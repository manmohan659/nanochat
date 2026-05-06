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

variable "domain_name" {
  description = "Apex domain — must already have a Route53 hosted zone."
  type        = string
  default     = "samosachaat.art"
}

variable "create_route53_zone" {
  description = "Create the public Route53 hosted zone for domain_name. Set false if the hosted zone already exists in this AWS account."
  type        = bool
  default     = true
}

variable "alb_dns_name" {
  description = "ALB DNS name for Route53 alias records. Filled by the Day 1 deploy script after the Ingress creates the ALB."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB canonical hosted-zone ID for Route53 alias records. Filled by the Day 1 deploy script after the Ingress creates the ALB."
  type        = string
  default     = ""
}

variable "validate_acm_certificate" {
  description = "Wait for ACM DNS validation. Enable after the registrar delegates domain_name to the Route53 name servers."
  type        = bool
  default     = false
}

variable "github_repositories" {
  description = "GitHub repos that may assume the CI role."
  type        = list(string)
  default     = ["manmohan659/nanochat"]
}

variable "github_actions_role_arn" {
  description = "Existing GitHub Actions OIDC role ARN allowed to deploy to this EKS cluster. Use the dev environment github_actions_role_arn output."
  type        = string
  default     = ""
}
