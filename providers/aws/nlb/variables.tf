variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "prefix" {
  description = "Resource name prefix (e.g. paymentform-p-us-backend)"
  type        = string
}

variable "service_label" {
  description = "Short label for naming target groups (e.g. 'bknd' or 'rndr'). Max 4 chars recommended."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the NLB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for the NLB"
  type        = list(string)
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for the NLB"
  type        = bool
  default     = false
}

variable "alert_webhook_url" {
  description = "HTTP endpoint to POST to when all targets are unhealthy for alert_sustained_minutes"
  type        = string
  default     = ""
  sensitive   = true
}

variable "alert_sustained_minutes" {
  description = "Number of consecutive minutes all targets must be unhealthy before the webhook fires"
  type        = number
  default     = 5
}
