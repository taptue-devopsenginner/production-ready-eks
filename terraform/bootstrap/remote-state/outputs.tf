output "state_bucket_name" {
  description = "S3 bucket name to place in the dev backend configuration."
  value       = aws_s3_bucket.terraform_state.id
}

output "state_bucket_arn" {
  value = aws_s3_bucket.terraform_state.arn
}
