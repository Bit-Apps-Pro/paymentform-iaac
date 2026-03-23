variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "name" {
  description = "Instance name prefix for resources"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where NLB will be created"
  type        = string
}

variable "subnet_ids" {
  description = "Subnet IDs for NLB"
  type        = list(string)
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "health_check_path" {
  description = "Health check path for target group"
  type        = string
  default     = "/health"
}

variable "enable_deletion_protection" {
  description = "Enable deletion protection for NLB"
  type        = bool
  default     = false
}

variable "enable_backend" {
  description = "Enable backend target groups (for API backend behind NLB)"
  type        = bool
  default     = false
}
