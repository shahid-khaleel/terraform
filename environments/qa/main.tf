###############################################################################
# DATA SOURCES
###############################################################################

# Fetch existing KMS ID
data "aws_kms_key" "app-data" {
  key_id = "alias/app-data"
}

# Get latest Amazon EKS Optimized AMI
data "aws_ami" "amazon_linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-standard-1.34-v*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = [" "] # Amazon EKS Optimized AMI owner
}

# AWS ACM Certificate
data "aws_acm_certificate" "acm_cert" {
  domain   = "*.test.com"
  statuses = ["ISSUED"]
}

###############################################################################
# EKS CLUSTER
###############################################################################

module "eks" {
  source                                   = "../../modules/eks"
  name                                     = var.cluster_name
  kubernetes_version                       = var.kubernetes_version
  endpoint_public_access                   = false
  bootstrap_self_managed_addons            = true
  enable_cluster_creator_admin_permissions = true
  enable_irsa                              = true

  vpc_id         = var.vpc_id
  create_kms_key = false

  encryption_config = {
    resources        = ["secrets"]
    provider_key_arn = data.aws_kms_key.app-data.arn
  }

  kms_key_arn              = data.aws_kms_key.app-data.arn
  control_plane_subnet_ids = [var.subnet_private_a, var.subnet_private_b]
  subnet_ids               = [var.subnet_private_a, var.subnet_private_b]
  deletion_protection      = false

  eks_managed_node_groups = {
    (var.name) = {
      #use_custom_launch_template = true
      create_launch_template = true
      block_device_mappings = {
        root = {
          device_name = "/dev/xvda"
          ebs = {
            volume_size           = 50
            volume_type           = "gp3"
            delete_on_termination = true
          }
        }
      }
      region                     = var.region
      ami_type                   = var.ami_type
      ami_id                     = data.aws_ami.amazon_linux.image_id
      vpc_id                     = var.vpc_id
      subnet_ids                 = [var.subnet_private_a, var.subnet_private_b]
      instance_types             = var.instance_type
      min_size                   = var.min_size
      max_size                   = var.max_size
      desired_size               = var.desired_size
      ami_id                     = data.aws_ami.amazon_linux.image_id
      enable_bootstrap_user_data = true
      key_name                   = var.keypair
      tags                       = var.global_tags
      launch_template_tags       = var.global_tags
      enable_monitoring          = true
    }
  }
}

###############################################################################
# CLUSTER AUTOSCALER - IAM
###############################################################################

# IAM Policy for Cluster Autoscaler
resource "aws_iam_policy" "cluster_autoscaler_iam_policy" {
  name        = "${local.name}-AmazonEKSClusterAutoscalerPolicy"
  path        = "/"
  description = "EKS Cluster Autoscaler Policy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:DescribeAutoScalingInstances",
          "autoscaling:DescribeInstances",
          "autoscaling:DescribeLaunchConfigurations",
          "autoscaling:DescribeTags",
          "autoscaling:SetDesiredCapacity",
          "autoscaling:TerminateInstanceInAutoScalingGroup",
          "ec2:DescribeLaunchTemplateVersions",
          "ec2:DescribeInstanceTypes"
        ]
      }
    ]
  })
}

# IAM Role for Cluster Autoscaler
resource "aws_iam_role" "cluster_autoscaler_iam_role" {
  name = "${local.name}-cluster-autoscaler"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Action    = "sts:AssumeRoleWithWebIdentity"
        Principal = { Federated = module.eks.oidc_provider_arn }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:kube-system:cluster-autoscaler"
          }
        }
      }
    ]
  })

  tags = {
    tag-key = "cluster-autoscaler"
  }
}

# Attach Cluster Autoscaler Policy
resource "aws_iam_role_policy_attachment" "cluster_autoscaler_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.cluster_autoscaler_iam_policy.arn
  role       = aws_iam_role.cluster_autoscaler_iam_role.name
}

###############################################################################
# AUTOSCALER POLICY DOCUMENT (EXTRA)
###############################################################################

data "aws_iam_policy_document" "default" {
  statement {
    sid    = "S3PolicyStmtNodeAutoscalingApiCalls"
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = [var.autoscaling_group_arn]
  }

  statement {
    sid       = "S3PolicyStmtNodeAutoscalingDescribe"
    effect    = "Allow"
    actions   = ["autoscaling:DescribeAutoScalingGroups"]
    resources = ["*"]
  }
}

###############################################################################
# KUBECONFIG SETUP
###############################################################################

resource "null_resource" "eks_kubeconfig" {
  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ap-south-1"
  }

  depends_on = [module.eks]
}

resource "null_resource" "enable_metric" {
  provisioner "local-exec" {
    command = "kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml"
  }
  depends_on = [module.eks]
}

###############################################################################
# CLUSTER AUTOSCALER - HELM
###############################################################################

resource "helm_release" "cluster_autoscaler" {
  depends_on = [
    aws_iam_role.cluster_autoscaler_iam_role,
    null_resource.eks_kubeconfig
  ]

  name       = "aa-cluster-autoscaling"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "autoDiscovery.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.region
  }

  set {
    name  = "rbac.serviceAccount.create"
    value = "true"
  }

  set {
    name  = "rbac.serviceAccount.name"
    value = "cluster-autoscaler"
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.cluster_autoscaler_iam_role.arn
  }

  set {
    name  = "extraArgs.balance-similar-node-groups"
    value = "true"
  }

  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  set {
    name  = "extraArgs.scale-down-delay-after-add"
    value = "2m"
  }

  set {
    name  = "extraArgs.scale-down-unneeded-time"
    value = "2m"
  }
}

###############################################################################
# AWS LOAD BALANCER CONTROLLER
###############################################################################

# Fetch IAM policy from upstream repo
data "http" "lbc_iam_policy" {
  url = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/main/docs/install/iam_policy.json"

  request_headers = {
    Accept = "application/json"
  }
}

# IAM Policy
resource "aws_iam_policy" "lbc_iam_policy" {
  name        = "${local.name}-AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "AWS Load Balancer Controller IAM Policy"
  policy      = data.http.lbc_iam_policy.response_body
}

# IAM Role
resource "aws_iam_role" "lbc_iam_role" {
  name = "${local.name}-lbc-iam-role"

  # Terraform's "jsonencode" function converts a Terraform expression result to valid JSON syntax..
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRoleWithWebIdentity"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Federated = "${module.eks.oidc_provider_arn}"
        }
        Condition = {
          StringEquals = {
            "${module.eks.oidc_provider}:aud" : "sts.amazonaws.com",
            "${module.eks.oidc_provider}:sub" : "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      },
    ]
  })
  tags = {
    tag-key = "AWSLoadBalancerControllerIAMPolicy"
  }
}

# Attach LBC Policy
resource "aws_iam_role_policy_attachment" "lbc_iam_role_policy_attach" {
  policy_arn = aws_iam_policy.lbc_iam_policy.arn
  role       = aws_iam_role.lbc_iam_role.name
}

###############################################################################
# AWS LOAD BALANCER CONTROLLER - HELM
###############################################################################

resource "helm_release" "loadbalancer_controller" {
  depends_on = [
    aws_iam_role.lbc_iam_role,
    null_resource.eks_kubeconfig
  ]

  name       = "${local.name}-aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  version    = "1.12.0"
  namespace  = "kube-system"

  set {
    name  = "image.repository"
    value = "602401143452.dkr.ecr.ap-south-1.amazonaws.com/amazon/aws-load-balancer-controller"
  }

  set {
    name  = "vpcId"
    value = var.vpc_id
  }

  set {
    name  = "region"
    value = var.region
  }

  set {
    name  = "clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lbc_iam_role.arn
  }

  set {
    name  = "serviceAccount.create"
    value = true
  }

  set {
    name  = "serviceAccount.name"
    value = "aws-load-balancer-controller"
  }
}

###############################################################################
# INGRESS CONFIGURATION
###############################################################################

# Resource: Kubernetes Ingress Class
resource "kubernetes_ingress_class_v1" "ingress_class_default" {
  depends_on = [helm_release.loadbalancer_controller]
  metadata {
    name = "qa-test-qa-ingress-class"
    annotations = {
      "ingressclass.kubernetes.io/is-default-class" = "true"
    }
  }
  spec {
    controller = "ingress.k8s.aws/alb"
  }
}

## Additional Note
# 1. You can mark a particular IngressClass as the default for your cluster. 
# 2. Setting the ingressclass.kubernetes.io/is-default-class annotation to true on an IngressClass resource will ensure that new Ingresses without an ingressClassName field specified will be assigned this default IngressClass.  
# 3. Reference: https://kubernetes-sigs.github.io/aws-load-balancer-controller/v2.3/guide/ingress/ingress_class/

# Kubernetes Service Manifest (Type: Load Balancer)
resource "kubernetes_ingress_v1" "ingress" {
  depends_on = [data.aws_acm_certificate.acm_cert]
  metadata {
    name = " "
    annotations = {
      #kubernetes.io/ingress.class: "alb" (OLD INGRESS CLASS NOTATION - STILL WORKS BUT RECOMMENDED TO USE IngressClass Resource)
      # Ingress Core Settings
      "alb.ingress.kubernetes.io/load-balancer-name"   = "alb"
      "alb.ingress.kubernetes.io/certificate-arn"      = "${data.aws_acm_certificate.acm_cert.arn}"
      "alb.ingress.kubernetes.io/tags"                 = "Name=alb"
      "alb.ingress.kubernetes.io/scheme"               = "internal"
      "alb.ingress.kubernetes.io/healthcheck-protocol" = "HTTP"
      "alb.ingress.kubernetes.io/listen-ports"         = jsonencode([{ "HTTPS" : 443 }, { "HTTP" : 80 }])
      "alb.ingress.kubernetes.io/healthcheck-port"     = "traffic-port"
      #"alb.ingress.kubernetes.io/healthcheck-path"             = "/heartbeat"
      "alb.ingress.kubernetes.io/healthcheck-interval-seconds" = 15
      "alb.ingress.kubernetes.io/healthcheck-timeout-seconds"  = 5
      "alb.ingress.kubernetes.io/success-codes"                = 200
      "alb.ingress.kubernetes.io/healthy-threshold-count"      = 2
      "alb.ingress.kubernetes.io/unhealthy-threshold-count"    = 2
      # Ingress Groups	
      "alb.ingress.kubernetes.io/group.name"  = "test.app"
      "alb.ingress.kubernetes.io/group.order" = 10
      "alb.ingress.kubernetes.io/target-type" = "ip"
    }
  }
  spec {
    ingress_class_name = " "
    rule {
      http {
        path {
          backend {
            service {
              name = " "
              port {
                number = 80
              }
            }
          }
          path      = "/ "
          path_type = "Prefix"
        }
        path {
          backend {
            service {
              name = " "
              port {
                number = 80
              }
            }
          }
          path      = " "
          path_type = "Prefix"
        }
        path {
          backend {
            service {
              name = " "
              port {
                number = 80
              }
            }
          }
          path      = " "
          path_type = "Prefix"
        }
        path {
          backend {
            service {
              name = " "
              port {
                number = 80
              }
            }
          }
          path      = "/"
          path_type = "Prefix"
        }
      }
    }
  }
}

###############################################################################
# SecondaryCIDR Attachment
###############################################################################

#Here, we are only associating the secondary CIDR with existing subnets; no new resources are being created
#https://repost.aws/knowledge-center/eks-multiple-cidr-ranges

resource "null_resource" "enable_custom_networking" {
  provisioner "local-exec" {
    command = <<EOT
      kubectl describe daemonset aws-node --namespace kube-system | grep Image | cut -d "/" -f 2
      kubectl set env daemonset aws-node -n kube-system AWS_VPC_K8S_CNI_CUSTOM_NETWORK_CFG=true
      kubectl set env daemonset aws-node -n kube-system ENI_CONFIG_LABEL_DEF=failure-domain.beta.kubernetes.io/zone
    EOT
  }
}

data "aws_vpc" "vpc" {
  filter {
    name   = "tag:Name"
    values = ["vpc-test-79"]
  }
}

data "aws_eks_cluster" "cluster_name" {
  name = module.eks.cluster_name
}

resource "kubernetes_manifest" "eniconfig_a" {
  depends_on = [module.eks]
  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = var.AZ1
    }
    spec = {
      securityGroups = [
        module.eks.cluster_primary_security_group_id
      ]
      subnet = var.subnet-test-private-a-secondary
    }
  }
}

resource "kubernetes_manifest" "eniconfig_b" {
  depends_on = [module.eks]
  manifest = {
    apiVersion = "crd.k8s.amazonaws.com/v1alpha1"
    kind       = "ENIConfig"
    metadata = {
      name = var.AZ2
    }
    spec = {
      securityGroups = [
        module.eks.cluster_primary_security_group_id
      ]
      subnet = var.subnet-test-private-b-secondary
    }
  }
}


/*
resource "aws_vpc_ipv4_cidr_block_association" "secondary_cidr" {
  vpc_id     = data.aws_vpc.vpc.id
  cidr_block = " "
}

resource "aws_subnet" "subnet-test-79-private-a-secondary" {
  vpc_id            = data.aws_vpc.vpc.id
  cidr_block        = " "
  availability_zone = var.AZ1

  tags = {
    Name = "subnet-test-79-private-a-secondary"
  }

  depends_on = [
    aws_vpc_ipv4_cidr_block_association.secondary_cidr
  ]
}

resource "aws_subnet" "subnet-test-79-private-b-secondary" {
  vpc_id            = data.aws_vpc.vpc.id
  cidr_block        = " "
  availability_zone = var.AZ2

  tags = {
    Name = "subnet-test-79-private-b-secondary"
  }

  depends_on = [
    aws_vpc_ipv4_cidr_block_association.secondary_cidr
  ]
} 
*/

