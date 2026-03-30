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
