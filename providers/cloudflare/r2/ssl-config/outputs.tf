output "bucket_name" {
  description = "Name of the SSL config R2 bucket (or null if disabled)"
  value       = var.enabled ? cloudflare_r2_bucket.ssl_config[0].name : null
}

output "bucket_id" {
  description = "ID of the SSL config R2 bucket (or null if disabled)"
  value       = var.enabled ? cloudflare_r2_bucket.ssl_config[0].id : null
}

output "bucket_domain" {
  description = "R2 bucket domain for SSL config"
  value       = var.enabled ? "${var.cloudflare_account_id}.r2.cloudflarestorage.com" : null
}
