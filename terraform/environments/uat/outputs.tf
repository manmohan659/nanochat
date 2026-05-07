output "vpc_id" {
  description = "VPC identifier."
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet identifiers."
  value       = module.vpc.private_subnet_ids
}

output "public_subnet_ids" {
  description = "Public subnet identifiers."
  value       = module.vpc.public_subnet_ids
}

output "cluster_name" {
  description = "EKS cluster name."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint."
  value       = module.eks.cluster_endpoint
}

output "cluster_oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA bindings."
  value       = module.eks.oidc_provider_arn
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
  value       = "samosachaat-nonprod-pg"
}

output "uat_database_name" {
  description = "Logical UAT database hosted on the shared non-prod RDS instance."
  value       = "samosachaat_uat"
}

output "ecr_repository_urls" {
  description = "ECR repository URLs by name."
  value       = module.ecr.repository_urls
}

output "efs_file_system_id" {
  description = "EFS filesystem ID for model weights."
  value       = module.efs.file_system_id
}

output "acm_certificate_arn" {
  description = "ACM cert ARN for the ALB Ingress."
  value       = module.acm.certificate_arn
}

output "route53_zone_id" {
  description = "Route53 hosted zone ID."
  value       = module.route53.zone_id
}

output "route53_name_servers" {
  description = "Authoritative Route53 name servers to configure at the registrar."
  value       = module.route53.name_servers
}

output "alb_controller_role_arn" {
  description = "IRSA role ARN for the AWS Load Balancer Controller."
  value       = module.iam.alb_controller_role_arn
}

output "github_actions_role_arn" {
  description = "IAM role for GitHub Actions OIDC assumption."
  value       = module.iam.github_actions_role_arn
}
