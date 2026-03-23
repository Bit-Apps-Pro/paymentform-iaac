output "application_storage_bucket_name" {
  description = "Name of the application storage R2 bucket"
  value       = module.application-storage.bucket_name
}

output "application_storage_bucket_domain" {
  description = "Domain of the application storage R2 bucket"
  value       = module.application-storage.bucket_domain
}

output "ssl_config_bucket_name" {
  description = "Name of the SSL config R2 bucket"
  value       = module.ssl-config.bucket_name
}

output "ssl_config_bucket_domain" {
  description = "Domain of the SSL config R2 bucket"
  value       = module.ssl-config.bucket_domain
}

output "r2_endpoint" {
  description = "R2 endpoint URL for SSL config bucket"
  value       = "https://${module.ssl-config.bucket_name}.r2.cloudflarestorage.com"
}

output "public_files_bucket_name" {
  description = "Name of the public files R2 bucket"
  value       = length(module.public-files) > 0 ? module.public-files[0].bucket_name : ""
}

output "public_files_bucket_domain" {
  description = "Domain of the public files R2 bucket"
  value       = length(module.public-files) > 0 ? module.public-files[0].bucket_domain : ""
}

output "cdn_worker_endpoint" {
  description = "Endpoint of the CDN worker"
  value       = length(module.cdn-worker) > 0 ? "https://${var.worker_route_pattern}" : ""
}
