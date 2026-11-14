variable "aws_region" {
  description = "AWS region for the Terraform state bucket."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "production-ready-eks"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name for Terraform state."
  type        = string
}

variable "force_destroy" {
  description = "Allow bucket deletion when non-empty. Keep false outside disposable labs."
  type        = bool
  default     = false
}
