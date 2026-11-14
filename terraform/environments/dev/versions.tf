terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # Configure after creating the state bucket with terraform/bootstrap/remote-state.
  # Copy backend.hcl.example to backend.hcl, replace the bucket name, then run:
  # terraform init -backend-config=backend.hcl
  backend "s3" {
    key          = "production-ready-eks/dev/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
