output "bucket_name" {
  description = "Name of the public files R2 bucket (or null if disabled)"
  value       = var.enabled ? cloudflare_r2_bucket.public_files[0].name : null
}

output "bucket_id" {
  description = "ID of the public files R2 bucket (or null if disabled)"
  value       = var.enabled ? cloudflare_r2_bucket.public_files[0].id : null
}

output "bucket_domain" {
  description = "R2 bucket domain for public files"
  value       = var.enabled ? "${cloudflare_r2_bucket.public_files[0].name}.r2.cloudflarestorage.com" : null
}