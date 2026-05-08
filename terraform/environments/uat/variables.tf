variable "region" {
  description = "AWS region."
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name (dev/uat/prod)."
  type        = string
  default     = "uat"
}
