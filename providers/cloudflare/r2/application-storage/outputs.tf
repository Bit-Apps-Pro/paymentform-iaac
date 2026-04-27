output "bucket_names" {
  description = "Map of region to bucket names"
  value = {
    for region, bucket in cloudflare_r2_bucket.application_storage : region => bucket.name
  }
}

output "bucket_ids" {
  description = "Map of region to bucket IDs"
  value = {
    for region, bucket in cloudflare_r2_bucket.application_storage : region => bucket.id
  }
}

output "bucket_domains" {
  description = "Map of region to bucket domains"
  value = {
    for region, bucket in cloudflare_r2_bucket.application_storage : region => "${bucket.name}.r2.cloudflarestorage.com"
  }
}
