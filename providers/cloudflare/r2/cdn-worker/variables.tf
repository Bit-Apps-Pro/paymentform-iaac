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
  description = "Enable Cloudflare Worker for public file serving"
  type        = bool
  default     = false
}

variable "worker_route_pattern" {
  description = "Route pattern for the Worker (e.g., cdn.example.com/*)"
  type        = string
  default     = ""
}

variable "cors_allowed_origins" {
  description = "List of allowed origins for CORS configuration"
  type        = list(string)
  default     = ["*"]
}

variable "application_bucket_name" {
  description = "Optional: Name of the application R2 bucket to bind to the Worker"
  type        = string
  default     = ""
}