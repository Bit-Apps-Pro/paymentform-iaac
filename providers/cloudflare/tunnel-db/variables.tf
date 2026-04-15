variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "resource_prefix" {
  type = string
}

variable "db_port" {
  description = "Local Postgres port to expose via the tunnel"
  type        = number
  default     = 5432
}
