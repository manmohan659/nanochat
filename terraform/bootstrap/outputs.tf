output "state_bucket_name" {
  description = "Terraform state S3 bucket."
  value       = aws_s3_bucket.state.id
}

output "lock_table_name" {
  description = "Terraform lock table."
  value       = aws_dynamodb_table.locks.name
}
