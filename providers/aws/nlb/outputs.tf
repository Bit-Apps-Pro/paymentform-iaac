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
  description = "Zone ID of the NLB"
  value       = aws_lb.main.zone_id
}

output "renderer_https_target_group_arn" {
  description = "ARN of the renderer HTTPS target group (port 443)"
  value       = aws_lb_target_group.renderer_https.arn
}

output "renderer_http_target_group_arn" {
  description = "ARN of the renderer HTTP target group (port 80)"
  value       = aws_lb_target_group.renderer_http.arn
}

output "backend_https_target_group_arn" {
  description = "ARN of the backend HTTPS target group (port 443)"
  value       = aws_lb_target_group.backend_https[0].arn
}

output "backend_http_target_group_arn" {
  description = "ARN of the backend HTTP target group (port 80)"
  value       = aws_lb_target_group.backend_http[0].arn
}

output "security_group_id" {
  description = "ID of the NLB security group"
  value       = aws_security_group.nlb.id
}
