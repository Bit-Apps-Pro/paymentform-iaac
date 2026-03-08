variable "environment" {
  description = "Deployment environment (e.g., prod-us)"
  type        = string
}

variable "name" {
  description = "Logical name for the volume"
  type        = string
}

variable "availability_zone" {
  description = "AWS availability zone (e.g., us-east-1a)"
  type        = string
}

variable "size" {
  description = "Volume size in GB"
  type        = number
}

variable "volume_type" {
  description = "EBS volume type (gp3, gp2, io1, etc.)"
  type        = string
}

variable "encrypted" {
  description = "Whether the volume is encrypted"
  type        = bool
}

variable "iops" {
  description = "IOPS for the volume (when applicable)"
  type        = number
  default     = null
}

variable "throughput" {
  description = "Throughput for gp3 volumes (MB/s)"
  type        = number
  default     = null
}

variable "device_name" {
  description = "Device name to attach (e.g., /dev/sdf)"
  type        = string
}

variable "instance_id" {
  description = "Instance ID to attach the volume to (optional)"
  type        = string
  default     = ""
}

variable "standard_tags" {
  description = "Map of standard tags to apply"
  type        = map(any)
  default     = {}
}
