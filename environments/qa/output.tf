###############################################################################
# CLUSTER IDENTIFICATION OUTPUTS
###############################################################################

output "cluster_name" {
  description = "EKS cluster name"
  value       = var.cluster_name
}

output "kubernetes_version" {
  description = "Kubernetes version of the EKS cluster"
  value       = var.kubernetes_version
}

output "region" {
  description = "AWS region for the deployment"
  value       = var.region
}

###############################################################################
# NETWORKING OUTPUTS
###############################################################################

output "vpc_id" {
  description = "VPC ID used by the EKS cluster"
  value       = var.vpc_id
}

output "private_subnets" {
  description = "Private subnets used by the EKS cluster"
  value = [
    var.subnet_private_a,
    var.subnet_private_b
  ]
}

###############################################################################
# NODE GROUP IDENTIFICATION
###############################################################################

output "node_group_name" {
  description = "EKS node group name"
  value       = var.node_group_name
}

###############################################################################
# NODE GROUP CONFIGURATION
###############################################################################

output "ami_type" {
  description = "AMI type used for the node group"
  value       = var.ami_type
}

output "instance_type" {
  description = "AWS instance_type for the deployment"
  value       = var.instance_type
}

output "node_group_scaling" {
  description = "Node group scaling configuration"
  value = {
    min     = var.min_size
    max     = var.max_size
    desired = var.desired_size
  }
}

###############################################################################
# SECURITY & CRYPTOGRAPHY
###############################################################################

output "aws_kms_key" {
  description = "KMS key ID resolved from alias"
  value       = data.aws_kms_key.test-qa-mt-app-data.id
}

###############################################################################
# AMI OUTPUTS
###############################################################################

output "ami_id" {
  description = "AMI ID for the ec2 worker nodes of k8"
  value       = data.aws_ami.amazon_linux.image_id
}

###############################################################################
# ACM CERTIFICATE OUTPUTS
###############################################################################

output "acm_certificate_id" {
  value = data.aws_acm_certificate.acm_cert.id
}

output "acm_certificate_arn" {
  value = data.aws_acm_certificate.acm_cert.arn
}

output "acm_certificate_status" {
  value = data.aws_acm_certificate.acm_cert.status
}
