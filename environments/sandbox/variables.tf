# Sandbox Environment Variables

variable "cloudflare_api_email" {
  type      = string
  sensitive = true
}

variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "cloudflare_account_id" {
  type      = string
  sensitive = true
}

variable "cloudflare_zone_id" {
  type      = string
  sensitive = true
}

variable "ghcr_username" {
  type = string
}
variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "db_host" {
  description = "Database host IP/hostname"
  type        = string
  default     = "10.0.1.50"
}

variable "db_port" {
  description = "Database port"
  type        = number
  default     = 5432
}

variable "db_database" {
  description = "Database name"
  type        = string
  default     = "shopper_backend"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "redis_host" {
  description = "Redis host IP/hostname"
  type        = string
  default     = "10.0.1.51"
}

variable "redis_port" {
  description = "Redis port"
  type        = number
  default     = 6379
}

variable "client_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-client:dev-latest"
}

variable "renderer_container_image" {
  type    = string
  default = "ghcr.io/bit-apps-pro/paymentform-renderer:dev-latest"
}

variable "enable_containers" {
  type    = bool
  default = true
}

variable "stripe_public_key" {
  type    = string
  default = ""
}

variable "ssl_storage_access_key_id" {
  type      = string
  sensitive = true
}

variable "ssl_storage_secret_access_key" {
  type      = string
  sensitive = true
}

variable "kv_store_api_token" {
  type      = string
  sensitive = true
}

variable "neon_database_url" {
  type      = string
  sensitive = true
}

variable "turso_auth_token" {
  type      = string
  sensitive = true
}

variable "turso_api_token" {
  type      = string
  sensitive = true
}

variable "turso_org_slug" {
  type = string
}

variable "app_key" {
  type      = string
  sensitive = true
}

variable "redis_password" {
  type      = string
  sensitive = true
}

variable "db_password" {
  type      = string
  sensitive = true
}

variable "tenant_db_auth_token" {
  type      = string
  sensitive = true
}

variable "tenant_db_encryption_key" {
  type      = string
  sensitive = true
}

variable "mail_password" {
  type      = string
  sensitive = true
}

variable "upload_storage_access_key_id" {
  type      = string
  sensitive = true
}

variable "upload_storage_secret_access_key" {
  type      = string
  sensitive = true
}

variable "google_client_secret" {
  type      = string
  sensitive = true
}
variable "google_client_id" {
  type = string
}

variable "stripe_secret" {
  type      = string
  sensitive = true
}

variable "stripe_client_id" {
  type      = string
  sensitive = true
}

variable "stripe_connect_webhook_secret" {
  type      = string
  sensitive = true
}

variable "postgres_ami_id" {
  description = "AMI ID for PostgreSQL instances (Ubuntu with PostgreSQL)"
  type        = string
  default     = ""
}

variable "valkey_ami_id" {
  description = "AMI ID for Valkey instances"
  type        = string
  default     = ""
}

variable "backup_storage_access_key_id" {
  description = "R2 access key for pgbackrest backups"
  type        = string
  sensitive   = true
  default     = ""
}

variable "backup_storage_access_key" {
  description = "R2 secret key for pgbackrest backups"
  type        = string
  sensitive   = true
  default     = ""
}

variable "pgbackrest_cipher_pass" {
  description = "Encryption password for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}
