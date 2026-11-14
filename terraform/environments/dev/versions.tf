terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Create the S3 bucket with bootstrap/remote-state first.
  # Then run terraform init -backend-config=backend.hcl.
  backend "s3" {
    key          = "production-ready-eks/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
