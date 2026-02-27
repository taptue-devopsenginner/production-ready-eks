# Terraform Backend Configuration with State Locking and Versioning
# This configures S3 backend with DynamoDB for state locking

terraform {
  backend "s3" {
    # S3 bucket for state storage
    bucket = "my-terraform-state-bucket"
    key    = "kubernetes/production/terraform.tfstate"
    region = "us-east-1"

    # DynamoDB table for state locking
    dynamodb_table = "terraform-state-lock"

    # Enable encryption at rest
    encrypt = true

    # Enable versioning (must be enabled on S3 bucket)
    # versioning = true  # This is handled at bucket level

    # Use KMS for encryption (optional, recommended for production)
    # kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

    # Additional security options
    acl = "private"

    # Server-side encryption
    server_side_encryption_configuration {
      rule {
        apply_server_side_encryption_by_default {
          sse_algorithm = "AES256"
          # Or use KMS:
          # sse_algorithm     = "aws:kms"
          # kms_master_key_id = "arn:aws:kms:..."
        }
      }
    }
  }

  # Required provider versions
  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
