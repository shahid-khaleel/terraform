cluster_name                  = ""
kubernetes_version            = ""
vpc_id                        = ""
subnet_private_a              = ""
subnet_private_b              = ""
node_group_name               = ""
ami_type                      = "AL2023_x86_64_STANDARD"
instance_type                 = ["m6i.xlarge"]
min_size                      = 1
max_size                      = 2
desired_size                  = 1
region                        = "ap-south-1"
bootstrap_self_managed_addons = false
keypair                       = ""

# Business Division
sbu = ""

# Environment Variable
environment = ""
name        = ""

#Az for Secondary CIDR

AZ1                             = ""
AZ2                             = ""
subnet-test-private-a-secondary = ""
subnet-test-private-b-secondary = ""


# Autoscaling Group ARN
autoscaling_group_arn = ""

global_tags = {
  Name = ""
}
