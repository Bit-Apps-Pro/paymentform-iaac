output "volume_id" {
  description = "PostgreSQL replica data volume ID"
  value       = aws_ebs_volume.this.id
}
