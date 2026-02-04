# Define Local Values in Terraform
locals {
  name = "${var.sbu}-${var.environment}"
  common_tags = {
    owners      = var.sbu
    environment = var.environment
  }
}
