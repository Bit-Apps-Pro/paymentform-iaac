output "primary_health_check_id" {
  description = "Health check ID for primary region"
  value       = aws_route53_health_check.primary.id
}

output "secondary_health_check_id" {
  description = "Health check ID for secondary region"
  value       = var.enable_secondary_health_check ? aws_route53_health_check.secondary[0].id : null
}

output "primary_record_fqdn" {
  description = "Primary record FQDN"
  value       = aws_route53_record.primary.fqdn
}

output "secondary_record_fqdn" {
  description = "Secondary record FQDN"
  value       = aws_route53_record.secondary.fqdn
}
