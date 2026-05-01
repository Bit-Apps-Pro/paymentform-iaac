# DNS & Routing

## Overview

All DNS is managed via Cloudflare through `module.paymenform_dns` (source: `providers/cloudflare/dns/`). The module handles DNS records, WAF rules, rate limiting, and cache rules.

## DNS Records

| Record | Type | Target | Proxied | Purpose |
|--------|------|--------|---------|---------|
| `api.paymentform.io` | A or CNAME | NLB backend DNS name | Yes | Backend API |
| `app.paymentform.io` | A or CNAME | Container endpoint or IP | Yes | Client dashboard |
| `*.paymentform.io` | A or CNAME | NLB renderer DNS name | No | Wildcard renderer (Caddy handles TLS) |

The renderer wildcard record is DNS-only (`proxied = false`) because Caddy handles on-demand TLS directly via ACME DNS challenge.

## Regional API Records

When `enable_geo_routing = true`, additional regional DNS records are created:

| Record | Region | Target |
|--------|--------|--------|
| `api-eu.paymentform.io` | EU | Hetzner hel1 IP |
| `api-sg.paymentform.io` | AP | Hetzner sin1 IP |

These are configured via the `region_endpoints` and `region_hostnames` maps:

```hcl
region_endpoints = {
  eu = module.hetzner_backend_hel1.ipv4_address
  sg = module.hetzner_backend_sin1.ipv4_address
}
region_hostnames = {
  eu = "api-eu.paymentform.io"
  sg = "api-sg.paymentform.io"
}
```

Geo-steering to route users to the nearest regional API is handled outside Terraform (see Load Balancer section below).

## WAF

Controlled by `enable_waf` variable. When enabled, a custom ruleset blocks requests with `cf.threat_score > 50`.

```hcl
enable_waf = true   # or false
```

## Rate Limiting

Requires Cloudflare Business or Enterprise plan. When enabled, rate-limits POST requests on the API subdomain:

- Characteristic: `ip.src`
- Period: 60 seconds
- Requests per period: configurable via `rate_limit_requests` (default 100)
- Mitigation timeout: 600 seconds

```hcl
cloudflare_plan       = "business"    # required for rate limiting
enable_rate_limiting  = true
rate_limit_requests   = 100
```

## Cache Rules

Requires Business or Enterprise plan. Two rules:

1. **Static assets** (`.js`, `.css`, `.png`, `.jpg`, `.svg`, `.gif`, `.woff`, `.woff2`): edge TTL 7200s, browser TTL 3600s.
2. **HTML pages** (`.html`, `.php`): cache bypassed.

```hcl
cloudflare_plan = "business"   # required for cache rules
```

## Load Balancer

Not currently managed by Terraform. The module includes a placeholder comment for future implementation.

To set up geo-steering manually:

1. Cloudflare Dashboard → Load Balancing → Create Load Balancer
2. Create pools for each region (US, EU, AP)
3. Create health monitors pointing to `/health`
4. Configure country/pop pools for geo-steering

Alternatively, set `enable_load_balancer = true` and configure the variables once the Terraform provider syntax is verified.

## Cloudflare Tunnel (DB Access)

The `module.tunnel_db` (source: `providers/cloudflare/tunnel-db`) creates a Cloudflare Tunnel that exposes the PostgreSQL primary (port 5432) to Hetzner replicas without a public IP.

The tunnel token is passed to the primary database userdata, which installs `cloudflared` and configures it as a systemd service:

```bash
systemctl status cloudflared
journalctl -u cloudflared --no-pager -n 50
```

Hetzner replicas connect to the primary via the tunnel CNAME (`module.tunnel_db.tunnel_cname`).

## Updating DNS After Infrastructure Changes

```bash
cd environments/prod

# Update only DNS records
tofu apply -target=module.paymenform_dns

# Update DNS + CDN workers
tofu apply -target=module.paymenform_dns -target=module.paymentform_storage_cdn
```

DNS changes propagate based on TTL. Proxied records (orange cloud) have TTL=1 (auto). The renderer wildcard has TTL=120s.