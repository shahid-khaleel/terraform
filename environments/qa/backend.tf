terraform {
  backend "local" {
    path = "terraform.tfstate"
  }

  # --- Enable when moving to remote state ---
  # backend "s3" {
  #   bucket         = ""
  #   key            = ""
  #   region         = "ap-south-1"
  #   dynamodb_table = "terraform-state-locks"
  #   encrypt        = true
  # }
}
