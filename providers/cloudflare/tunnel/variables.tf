variable "cloudflare_account_id" {
  description = "Cloudflare account ID"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "tunnel_name" {
  description = "Tunnel name suffix (e.g. 'backend-sg', 'backend-eu')"
  type        = string
}

variable "ingress_routes" {
  description = "List of hostname→service ingress rules for the tunnel"
  type = list(object({
    hostname = string
    service  = string
  }))
  default = []
}
