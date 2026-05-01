output "bucket_names" {
  description = "Map of region to R2 bucket name"
  value       = { for region, bucket in cloudflare_r2_bucket.application_storage : region => nonsensitive(bucket.name) }
}

output "bucket_jurisdictions" {
  description = "Map of region to R2 bucket jurisdiction"
  value       = { for region, bucket in cloudflare_r2_bucket.application_storage : region => bucket.jurisdiction }
}

output "bucket_ids" {
  description = "Map of region to R2 bucket id"
  value       = { for region, bucket in cloudflare_r2_bucket.application_storage : region => nonsensitive(bucket.id) }
}

output "bucket_endpoints" {
  description = "Map of region to R2 bucket public endpoint"
  value       = { for region, bucket in cloudflare_r2_bucket.application_storage : region => "${nonsensitive(bucket.name)}.r2.cloudflarestorage.com" }
}