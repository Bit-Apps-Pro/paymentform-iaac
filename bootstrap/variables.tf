variable "aws_region" {
  description = "AWS region for backend resources"
  type        = string
  default     = "us-east-1"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket for storing Terraform state"
  type        = string
  default     = "paymentform-terraform-state"
}

variable "locks_table_name" {
  description = "Name of the DynamoDB table for state locking"
  type        = string
  default     = "paymentform-terraform-locks"
}

variable "enable_audit_logging" {
  description = "Enable CloudTrail logging for audit trail"
  type        = bool
  default     = true
}
