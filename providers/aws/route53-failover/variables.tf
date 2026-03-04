variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "zone_id" {
  description = "Route53 Zone ID"
  type        = string
}

variable "record_name" {
  description = "Record name (e.g., api.example.com)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# Primary (US) Configuration
variable "primary_fqdn" {
  description = "FQDN to check health for primary region"
  type        = string
}

variable "primary_alb_dns_name" {
  description = "ALB DNS name for primary region"
  type        = string
}

variable "primary_alb_zone_id" {
  description = "ALB Zone ID for primary region"
  type        = string
}

# Secondary (DR) Configuration
variable "secondary_alb_dns_name" {
  description = "ALB DNS name for secondary region"
  type        = string
}

variable "secondary_alb_zone_id" {
  description = "ALB Zone ID for secondary region"
  type        = string
}

variable "enable_secondary_health_check" {
  description = "Enable health check for secondary region"
  type        = bool
  default     = false
}

variable "secondary_fqdn" {
  description = "FQDN to check health for secondary region"
  type        = string
  default     = ""
}

# Health Check Configuration
variable "health_check_port" {
  description = "Port for health check"
  type        = number
  default     = 80
}

variable "health_check_type" {
  description = "Type of health check (HTTP, HTTPS, TCP)"
  type        = string
  default     = "HTTPS"
}

variable "health_check_path" {
  description = "Path for health check"
  type        = string
  default     = "/health"
}

variable "failure_threshold" {
  description = "Number of consecutive failures before marking unhealthy"
  type        = number
  default     = 3
}

variable "request_interval" {
  description = "Interval between health checks (seconds)"
  type        = number
  default     = 30
}
