variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with Workers permissions"
  type        = string
  sensitive   = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare Zone ID for Worker route binding"
  type        = string
  default     = ""
}

variable "worker_enabled" {
  description = "Enable Cloudflare Workers for public file serving"
  type        = bool
  default     = false
}

variable "regional_buckets" {
  description = "Map of region to bucket names for binding to workers"
  type        = map(string)
  default     = {}
}

variable "domain_prefix" {
  description = "Prefix for CDN subdomains (e.g., 'cdn' creates cdn-us, cdn-eu, cdn-ap)"
  type        = string
  default     = "cdn"
}

variable "base_domain" {
  description = "Base domain for CDN (e.g., paymentform.io)"
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}
