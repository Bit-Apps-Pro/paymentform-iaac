output "server_ip" {
  description = "Public IPv4 address of the Hetzner Valkey server."
  value       = hcloud_server.valkey.ipv4_address
}

output "private_ip" {
  description = "Hetzner private network IP used by Valkey."
  value       = hcloud_server_network.valkey.ip
}

output "valkey_endpoint" {
  description = "Valkey endpoint reachable from AWS through WireGuard."
  value       = "${hcloud_server_network.valkey.ip}:6379"
}
