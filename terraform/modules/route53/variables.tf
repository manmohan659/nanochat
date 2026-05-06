variable "domain_name" {
  description = "Apex domain (e.g. samosachaat.art)."
  type        = string
}

variable "create_zone" {
  description = "Create the public hosted zone. Set false to use an existing Route53 hosted zone."
  type        = bool
  default     = true
}

variable "subdomains" {
  description = "Subdomains to alias to the ALB (e.g. [\"grafana\", \"api\"])."
  type        = list(string)
  default     = ["grafana"]
}

variable "alb_dns_name" {
  description = "ALB DNS name from the AWS Load Balancer Controller. Empty string skips A-record creation (first-apply bootstrap)."
  type        = string
  default     = ""
}

variable "alb_zone_id" {
  description = "ALB hosted-zone ID (region-specific)."
  type        = string
  default     = ""
}

variable "acm_validation_records" {
  description = "Map keyed by domain → { name, type, record } — pass module.acm.validation_records here."
  type = map(object({
    name   = string
    type   = string
    record = string
  }))
  default = {}
}

variable "acm_certificate_arn" {
  description = "ACM certificate ARN to validate after DNS validation records are created. Empty skips validation."
  type        = string
  default     = ""
}

variable "validate_acm_certificate" {
  description = "Wait for ACM DNS validation. Enable only after the domain is delegated to this Route53 zone."
  type        = bool
  default     = false
}
