output "worker_name" {
  description = "Name of the deployed Cloudflare Worker"
  value       = local.worker_name
}

output "status_url" {
  description = "URL of the status page"
  value       = "https://${var.status_subdomain}.${var.domain_name}"
}

output "status_json_url" {
  description = "URL of the JSON status endpoint"
  value       = "https://${var.status_subdomain}.${var.domain_name}/status"
}
