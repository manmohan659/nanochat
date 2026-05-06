terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0

  name = var.domain_name
}

data "aws_route53_zone" "this" {
  count = var.create_zone ? 0 : 1

  name         = var.domain_name
  private_zone = false
}

locals {
  zone_id      = var.create_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.this[0].zone_id
  name_servers = var.create_zone ? aws_route53_zone.this[0].name_servers : data.aws_route53_zone.this[0].name_servers
}

# alb_dns_name / alb_zone_id come from the AWS Load Balancer Controller after the
# Ingress is created (look up via `kubectl get ingress` or a data source). Pass
# empty strings to skip A-record creation on the first apply, then re-apply.
resource "aws_route53_record" "apex" {
  count = var.alb_dns_name == "" ? 0 : 1

  zone_id = local.zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "subdomains" {
  for_each = var.alb_dns_name == "" ? toset([]) : toset(var.subdomains)

  zone_id = local.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}

# ACM DNS-validation CNAMEs. Pass the map exported by the ACM module.
resource "aws_route53_record" "acm_validation" {
  for_each = var.acm_validation_records

  zone_id         = local.zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  count = !var.validate_acm_certificate || var.acm_certificate_arn == "" || length(var.acm_validation_records) == 0 ? 0 : 1

  certificate_arn         = var.acm_certificate_arn
  validation_record_fqdns = [for record in aws_route53_record.acm_validation : record.fqdn]
}
