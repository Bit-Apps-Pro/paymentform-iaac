output "network_id" {
  value = hcloud_network.main.id
}

output "subnet_id" {
  value = hcloud_network_subnet.main.id
}

output "network_ip_range" {
  value = hcloud_network.main.ip_range
}
