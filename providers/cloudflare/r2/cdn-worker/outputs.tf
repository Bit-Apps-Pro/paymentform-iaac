output "worker_names" {
  description = "Map of region to Cloudflare Worker names (or empty if disabled)"
  value       = var.worker_enabled ? { for region, worker in cloudflare_workers_script.cdn_worker : region => worker.script_name } : {}
}

output "worker_urls" {
  description = "Map of region to CDN URLs (or empty if disabled)"
  value       = var.worker_enabled ? { for region, config in local.worker_configs : region => "https://${replace(config.pattern, "/*", "")}" } : {}
}
