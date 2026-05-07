variable "identifier" {
  description = "DB instance identifier."
  type        = string
}

variable "supporting_resource_name" {
  description = "Optional stable name prefix for RDS security group, subnet group, and parameter group. Use this when renaming an existing DB instance without replacing its supporting resources."
  type        = string
  default     = null
}

variable "vpc_id" {
  description = "VPC the database lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for the DB subnet group (>= 2 AZs)."
  type        = list(string)
}

variable "eks_node_security_group_id" {
  description = "Node SG that should be allowed inbound to PostgreSQL."
  type        = string
}

variable "instance_class" {
  description = "RDS instance class (e.g. db.t3.micro for non-prod, db.t3.medium for prod)."
  type        = string
  default     = "db.t3.micro"
}

variable "db_name" {
  description = "Initial database name."
  type        = string
  default     = "samosachaat"
}

variable "db_username" {
  description = "Master username."
  type        = string
  default     = "samosachaat_admin"
}

variable "allocated_storage" {
  description = "Initial storage (GB)."
  type        = number
  default     = 20
}

variable "max_allocated_storage" {
  description = "Storage autoscaling cap (GB)."
  type        = number
  default     = 100
}

variable "backup_retention_period" {
  description = "Backup retention in days. AWS Academy/Free Tier accounts may reject values above 1."
  type        = number
  default     = 1
}

variable "apply_immediately" {
  description = "Apply RDS changes immediately instead of waiting for the maintenance window. Useful for non-prod migration/rename work."
  type        = bool
  default     = false
}

variable "performance_insights_enabled" {
  description = "Enable RDS Performance Insights."
  type        = bool
  default     = false
}

variable "monitoring_interval" {
  description = "Enhanced monitoring interval in seconds. Use 0 to disable."
  type        = number
  default     = 0
}

variable "multi_az" {
  description = "Enable Multi-AZ (recommended for prod)."
  type        = bool
  default     = false
}

variable "skip_final_snapshot" {
  description = "Skip the final snapshot when destroying (true for dev)."
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "Block accidental deletion (recommended for prod)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
