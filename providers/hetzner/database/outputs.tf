output "server_id" {
  value = var.enabled ? hcloud_server.db_replica[0].id : null
}

output "ipv4_address" {
  value = var.enabled ? hcloud_server.db_replica[0].ipv4_address : null
}

output "private_ipv4_address" {
  description = "Private IP on the attached Hetzner network (empty string if no network attached)"
  value       = var.enabled ? (var.network_id != "" ? hcloud_server_network.db_replica[0].ip : "") : ""
}

output "replica_endpoint" {
  description = "Postgres connection endpoint — private IP when network attached, public IP otherwise"
  value       = var.enabled ? (var.network_id != "" ? hcloud_server_network.db_replica[0].ip : hcloud_server.db_replica[0].ipv4_address) : null
}

output "enabled" {
  description = "Whether the replica is enabled"
  value       = var.enabled
}
