# Cloudflare KV Module Variables
# Reusable module for a single KV namespace

variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "resource_prefix" {
  description = "Prefix for resource naming"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to resources"
  type        = map(string)
  default     = {}
}

variable "cloudflare_account_id" {
  description = "Cloudflare Account ID"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with KV permissions"
  type        = string
  sensitive   = true
}

# KV Namespace Configuration
variable "namespace_name" {
  description = "Name of the KV namespace (e.g., tenants, analytics, sessions)"
  type        = string
}

variable "namespace_enabled" {
  description = "Enable this KV namespace"
  type        = bool
  default     = true
}

variable "deploy_worker" {
  description = "Deploy the kv-store worker using wrangler"
  type        = bool
  default     = false
}

variable "worker_path" {
  description = "Path to the kv-store worker code (containing wrangler.toml)"
  type        = string
  default     = ""
}

variable "kv_store_api_token" {
  description = "API token for KV store worker operations"
  type        = string
  sensitive   = true
  default     = ""
}
