output "worker_name" {
  description = "Name of the Cloudflare Worker for public file serving (or null if disabled)"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? cloudflare_workers_script.cdn_worker[0].script_name : null
}

output "worker_url" {
  description = "URL pattern for accessing files via Worker (or null if disabled)"
  value       = var.worker_enabled && var.worker_route_pattern != "" ? "https://${replace(var.worker_route_pattern, "/*", "")}" : null
}