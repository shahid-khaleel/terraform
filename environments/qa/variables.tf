#######################################
# EKS Cluster Core Configuration
#######################################

variable "cluster_name" {
  type        = string
  description = "EKS cluster name for any environment"
}

variable "kubernetes_version" {
  type        = string
  description = "EKS cluster version"
}

variable "region" {
  description = "Environment Region"
  type        = string
}

#######################################
# Networking Configuration
#######################################

variable "vpc_id" {
  type        = string
  description = "EKS cluster vpc id"
}

variable "subnet_private_a" {
  type        = string
  description = "EKS cluster private subnet A"
}

variable "subnet_private_b" {
  type        = string
  description = "EKS cluster private subnet B"
}

#######################################
# Node Group Identification
#######################################

variable "node_group_name" {
  type        = string
  description = "EKS cluster node node_group_name"
}

variable "name" {
  type        = string
  description = "name of worker nodes"
}

#######################################
# Node Group Scaling Configuration
#######################################

variable "min_size" {
  description = "Minimum number of nodes"
  type        = number
}

variable "max_size" {
  description = "Maximum number of nodes"
  type        = number
}

variable "desired_size" {
  description = "Desired number of nodes"
  type        = number
}

#######################################
# Node Group Compute Configuration
#######################################

variable "ami_type" {
  description = "AMI type for the EKS node group"
  type        = string
}

variable "instance_type" {
  description = "workers instance type"
  type        = list(string)
}

variable "keypair" {
  description = "Key pair for accessing EC2 instances in the node group."
  type        = string
}

variable "autoscaling_group_arn" {
  description = "ARN of the Auto Scaling group for worker nodes."
  type        = string
}

#######################################
# Add-ons & Bootstrap Configuration
#######################################

variable "bootstrap_self_managed_addons" {
  description = "Whether to bootstrap self-managed addons"
  type        = bool
  default     = false
}

#######################################
# Tagging & Ownership
#######################################

variable "sbu" {
  description = "Business division within the organization that owns the infrastructure."
  type        = string
}

variable "environment" {
  description = "Environment name used as a prefix (e.g., dev, prod)."
  type        = string
}


# variables.tf
variable "global_tags" {
  type    = map(string)
  default = {}
}


#######################################
# AZ's for Secondary CIDR Attachment
#######################################

variable "AZ1" {
  description = "Business division within the organization that owns the infrastructure."
  type        = string
}

variable "AZ2" {
  description = "Business division within the organization that owns the infrastructure."
  type        = string
}

variable "subnet-test-private-a-secondary" {
  description = "Secondary CIDR for private A subnet."
  type        = string
}

variable "subnet-test-private-b-secondary" {
  description = "Secondary CIDR for private B subnet."
  type        = string
}


#######################################
# HPA deployment
#######################################

variable "hpa_targets" {
  type = set(string)
  default = [
    "test-core-qa",
    "test2-core-qa",
    "test2-workflow-qa"
  ]
}
