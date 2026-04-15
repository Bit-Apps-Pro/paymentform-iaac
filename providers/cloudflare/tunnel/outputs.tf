output "tunnel_id" {
  description = "Cloudflare Tunnel ID"
  value       = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

output "tunnel_token" {
  description = "Cloudflare Tunnel token for cloudflared connector"
  value       = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel.token
  sensitive   = true
}

output "tunnel_cname" {
  description = "CNAME target for DNS records pointing at this tunnel"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
}
