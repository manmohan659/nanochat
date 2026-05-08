output "cluster_name" {
  description = "UAT runtime cluster name. UAT deploys as a namespace on shared non-prod EKS."
  value       = data.terraform_remote_state.nonprod.outputs.cluster_name
}

output "cluster_endpoint" {
  description = "UAT runtime EKS API endpoint."
  value       = data.terraform_remote_state.nonprod.outputs.cluster_endpoint
}

output "rds_endpoint" {
  description = "Shared non-prod RDS endpoint (host:port), owned by the dev/non-prod Terraform state."
  value       = data.terraform_remote_state.nonprod.outputs.rds_endpoint
}

output "rds_password" {
  description = "Shared non-prod RDS master password, owned by the dev/non-prod Terraform state."
  value       = data.terraform_remote_state.nonprod.outputs.rds_password
  sensitive   = true
}

output "rds_identifier" {
  description = "Shared non-prod RDS instance identifier."
  value       = data.terraform_remote_state.nonprod.outputs.rds_identifier
}

output "uat_database_name" {
  description = "Logical UAT database hosted on the shared non-prod RDS instance."
  value       = "samosachaat_uat"
}

output "acm_certificate_arn" {
  description = "Wildcard ACM cert ARN used by the shared non-prod ALB Ingress."
  value       = data.terraform_remote_state.nonprod.outputs.acm_certificate_arn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID from shared non-prod infrastructure."
  value       = data.terraform_remote_state.nonprod.outputs.route53_zone_id
}

output "github_actions_role_arn" {
  description = "IAM role for GitHub Actions OIDC assumption."
  value       = data.terraform_remote_state.nonprod.outputs.github_actions_role_arn
}
