variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "region" {
  description = "AWS region (required for SSM cluster init command)"
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Instance name prefix for resources"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ami_id" {
  description = "AMI ID for Valkey instances (e.g., Ubuntu)"
  type        = string
  default     = ""
}

variable "instance_type" {
  description = "Instance type for Valkey nodes"
  type        = string
  default     = "t4g.micro"
}

variable "subnet_ids" {
  description = "Subnet IDs for Valkey nodes (should have at least 3 for HA)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for Valkey instances"
  type        = string
}

variable "node_count" {
  description = "Number of Valkey nodes. Use 1 for standalone, 3+ for cluster mode."
  type        = number
  default     = 1

  validation {
    condition     = var.node_count == 1 || var.node_count >= 3
    error_message = "node_count must be 1 (standalone) or >= 3 (cluster). Values 2 is not valid for Valkey cluster."
  }
}

variable "volume_size" {
  description = "Root volume size (GB)"
  type        = number
  default     = 20
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "cluster_password" {
  description = "Password for Valkey cluster"
  type        = string
  sensitive   = true
  default     = ""
}

variable "memory_max" {
  description = "Max memory for Valkey (e.g., 256mb, 1gb)"
  type        = string
  default     = "256mb"
}
