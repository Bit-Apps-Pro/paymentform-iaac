output "server_id" {
  value = hcloud_server.db_replica.id
}

output "ipv4_address" {
  value = hcloud_server.db_replica.ipv4_address
}

output "private_ipv4_address" {
  description = "Private IP on the attached Hetzner network (empty string if no network attached)"
  value       = var.network_id != "" ? hcloud_server_network.db_replica[0].ip : ""
}

output "replica_endpoint" {
  description = "Postgres connection endpoint — private IP when network attached, public IP otherwise"
  value       = var.network_id != "" ? hcloud_server_network.db_replica[0].ip : hcloud_server.db_replica.ipv4_address
}
