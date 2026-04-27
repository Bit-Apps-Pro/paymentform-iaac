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

variable "bucket_name_prefix" {
  description = "Prefix for bucket names (e.g., paymentform-uploads)"
  type        = string
}

variable "regional_config" {
  description = "Map of region suffix to R2 location and jurisdiction"
  type = map(object({
    location     = string
    jurisdiction = optional(string, "default")
  }))
  default = {
    "us" = { location = "wnam", jurisdiction = "default" }
    "eu" = { location = "weur", jurisdiction = "eu" }
    "ap" = { location = "apac", jurisdiction = "default" }
  }
}
