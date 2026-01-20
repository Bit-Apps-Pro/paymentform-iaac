variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Primary domain name for the application"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "app_key" {
  description = "Laravel application key"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket"
  type        = string
}

variable "allow_origin_hosts" {
  description = "Allowed origin hosts for CORS"
  type        = string
  default     = "renderer.paymentform.btcd-test.io,*.renderer.paymentform.btcd-test.io"
}