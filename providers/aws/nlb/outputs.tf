output "nlb_id" {
  description = "ID of the NLB"
  value       = aws_lb.main.id
}

output "nlb_arn" {
  description = "ARN of the NLB"
  value       = aws_lb.main.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.main.dns_name
}

output "nlb_zone_id" {
  description = "Zone ID of the NLB (for Route53 alias records)"
  value       = aws_lb.main.zone_id
}

output "https_target_group_arn" {
  description = "ARN of the HTTPS target group (port 443)"
  value       = aws_lb_target_group.https.arn
}

output "http_target_group_arn" {
  description = "ARN of the HTTP target group (port 80)"
  value       = aws_lb_target_group.http.arn
}

output "security_group_id" {
  description = "ID of the NLB security group"
  value       = aws_security_group.nlb.id
}
