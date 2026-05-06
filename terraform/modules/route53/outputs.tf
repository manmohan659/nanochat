output "zone_id" {
  description = "Hosted zone ID for the apex domain."
  value       = local.zone_id
}

output "name_servers" {
  description = "Authoritative name servers (configure these at the registrar)."
  value       = local.name_servers
}

output "apex_record_fqdn" {
  description = "FQDN of the apex A record (empty until alb_dns_name is supplied)."
  value       = try(aws_route53_record.apex[0].fqdn, "")
}

output "acm_validation_fqdns" {
  description = "FQDNs of ACM validation records managed in this zone."
  value       = [for record in aws_route53_record.acm_validation : record.fqdn]
}
