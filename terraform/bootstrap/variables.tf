variable "region" {
  description = "AWS region for the Terraform state backend."
  type        = string
  default     = "us-west-2"
}

variable "state_bucket_name" {
  description = "S3 bucket that stores Terraform state."
  type        = string
  default     = "samosachaat-terraform-state"
}

variable "lock_table_name" {
  description = "DynamoDB table used for Terraform state locking."
  type        = string
  default     = "samosachaat-terraform-locks"
}
