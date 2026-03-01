# Cloudflare KV Module Outputs

output "namespace_id" {
  description = "KV namespace ID"
  value       = try(cloudflare_workers_kv_namespace.this[0].id, null)
}

output "namespace_title" {
  description = "KV namespace title"
  value       = local.namespace_title
}

output "namespace_enabled" {
  description = "Whether the namespace is enabled"
  value       = var.namespace_enabled
}

output "api_endpoint" {
  description = "KV API endpoint URL"
  value       = "https://api.cloudflare.com/client/v4/accounts/${var.cloudflare_account_id}/storage/kv/namespaces"
}
