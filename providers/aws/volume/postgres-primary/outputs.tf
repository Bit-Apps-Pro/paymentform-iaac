output "volume_id" {
  description = "PostgreSQL primary data volume ID"
  value       = aws_ebs_volume.this.id
}
