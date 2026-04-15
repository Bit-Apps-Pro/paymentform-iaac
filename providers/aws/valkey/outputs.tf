output "cluster_ips" {
  description = "List of private IPs for all Valkey nodes"
  value       = aws_instance.valkey[*].private_ip
}

output "instance_ids" {
  description = "List of instance IDs for all Valkey nodes"
  value       = aws_instance.valkey[*].id
}

output "primary_endpoint" {
  description = "Primary Valkey node endpoint"
  value       = aws_instance.valkey[0].private_ip
}

output "cluster_endpoints" {
  description = "All Valkey node endpoints (comma-separated)"
  value       = join(",", aws_instance.valkey[*].private_ip)
}

output "connection_string" {
  description = "Valkey connection string"
  sensitive   = true
  value       = "redis://:${var.cluster_password}@${aws_instance.valkey[0].private_ip}:6379"
}
