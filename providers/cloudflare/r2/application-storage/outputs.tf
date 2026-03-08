output "bucket_name" {
  description = "Name of the application storage R2 bucket"
  value       = cloudflare_r2_bucket.application_storage.name
}

output "bucket_id" {
  description = "ID of the application storage R2 bucket"
  value       = cloudflare_r2_bucket.application_storage.id
}

output "bucket_domain" {
  description = "R2 bucket domain"
  value       = "${cloudflare_r2_bucket.application_storage.name}.r2.cloudflarestorage.com"
}