variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with R2 permissions"
  type        = string
  sensitive   = true
}

variable "r2_bucket_name" {
  description = "Name of the R2 bucket for application storage (without environment prefix)"
  type        = string
}