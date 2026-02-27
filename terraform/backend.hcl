# Backend configuration file for Terraform
# Use this with: terraform init -backend-config=backend.hcl

# S3 backend configuration
bucket         = "my-terraform-state-bucket"
key            = "kubernetes/production/terraform.tfstate"
region         = "us-east-1"
dynamodb_table = "terraform-state-lock"
encrypt        = true

# Optional: Use KMS encryption
# kms_key_id = "arn:aws:kms:us-east-1:123456789012:key/12345678-1234-1234-1234-123456789012"

# Workspace configuration (optional)
# workspace_key_prefix = "workspaces"
