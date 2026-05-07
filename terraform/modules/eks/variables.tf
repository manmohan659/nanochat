variable "cluster_name" {
  description = "EKS cluster name."
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version for the EKS control plane."
  type        = string
  default     = "1.34"
}

variable "vpc_id" {
  description = "VPC the cluster lives in."
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnets for nodes and control-plane ENIs."
  type        = list(string)
}

variable "node_instance_type" {
  description = "EC2 instance type for the managed node group."
  type        = string
  default     = "t3.large"
}

variable "node_ami_type" {
  description = "EKS managed node group AMI type. AL2023 is required for Kubernetes 1.33+."
  type        = string
  default     = "AL2023_x86_64_STANDARD"
}

variable "node_min_size" {
  description = "Minimum nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum nodes in the managed node group."
  type        = number
  default     = 4
}

variable "node_desired_size" {
  description = "Desired nodes in the managed node group."
  type        = number
  default     = 2
}

variable "node_max_unavailable_percentage" {
  description = "Max percentage of nodes unavailable during rolling update."
  type        = number
  default     = 33
}

variable "enable_cluster_creator_admin_permissions" {
  description = "Grant the Terraform caller cluster-admin access through an EKS access entry."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to every resource."
  type        = map(string)
  default     = {}
}
