output "server_id" {
  value = hcloud_server.backend.id
}

output "ipv4_address" {
  value = hcloud_server.backend.ipv4_address
}

output "ipv6_address" {
  value = hcloud_server.backend.ipv6_address
}

output "server_name" {
  value = hcloud_server.backend.name
}

output "private_ipv4_address" {
  description = "Private IP on the attached Hetzner network (empty string if no network attached)"
  value       = var.network_id != "" ? hcloud_server_network.backend[0].ip : ""
}
