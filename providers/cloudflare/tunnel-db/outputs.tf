output "tunnel_id" {
  value = cloudflare_zero_trust_tunnel_cloudflared.tunnel.id
}

output "tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.tunnel.token
  sensitive = true
}

output "tunnel_cname" {
  description = "CNAME hostname for the tunnel (use in pg_hba / replica primary_host)"
  value       = "${cloudflare_zero_trust_tunnel_cloudflared.tunnel.id}.cfargotunnel.com"
}
