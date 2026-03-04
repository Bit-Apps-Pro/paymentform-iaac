variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "ami_id" {
  description = "AMI ID for PostgreSQL instances (e.g., Ubuntu with PostgreSQL)"
  type        = string
  default     = ""
}

variable "subnet_ids" {
  description = "Subnet IDs for PostgreSQL instances (primary and replica)"
  type        = list(string)
}

variable "security_group_id" {
  description = "Security group ID for PostgreSQL instances"
  type        = string
}

variable "primary_instance_type" {
  description = "Instance type for PostgreSQL primary"
  type        = string
  default     = "t4g.micro"
}

variable "replica_instance_type" {
  description = "Instance type for PostgreSQL replica"
  type        = string
  default     = "t4g.micro"
}

variable "primary_volume_size" {
  description = "Root volume size for primary (GB)"
  type        = number
  default     = 20
}

variable "replica_volume_size" {
  description = "Root volume size for replica (GB)"
  type        = number
  default     = 20
}

variable "volume_type" {
  description = "EBS volume type"
  type        = string
  default     = "gp3"
}

variable "enable_replica" {
  description = "Enable PostgreSQL replica"
  type        = bool
  default     = true
}

variable "postgres_version" {
  description = "PostgreSQL version"
  type        = string
  default     = "16"
}

variable "db_name" {
  description = "Database name"
  type        = string
  default     = "shopper_backend"
}

variable "db_user" {
  description = "PostgreSQL username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "PostgreSQL password"
  type        = string
  sensitive   = true
  default     = ""
}

variable "r2_endpoint" {
  description = "R2/S3 endpoint for pgbackrest backups"
  type        = string
  default     = "https://paymentform-backups.r2.cloudflarestorage.com"
}

variable "r2_bucket_name" {
  description = "R2/S3 bucket name for pgbackrest backups"
  type        = string
  default     = "paymentform-backups"
}

variable "r2_access_key" {
  description = "R2/S3 access key for pgbackrest"
  type        = string
  sensitive   = true
  default     = ""
}

variable "r2_secret_key" {
  description = "R2/S3 secret key for pgbackrest"
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

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "assign_eip" {
  description = "Assign EIP to PostgreSQL primary for stable IP"
  type        = bool
  default     = false
}
