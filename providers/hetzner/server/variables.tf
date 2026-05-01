variable "environment" {
  type = string
}

variable "resource_prefix" {
  type = string
}

variable "region" {
  type = string
}

variable "location" {
  description = "Hetzner datacenter location (e.g. hel1, sin1, fsn1)"
  type        = string
}

variable "server_type" {
  description = "Hetzner server type (e.g. cx22, cx32, cpx21)"
  type        = string
  default     = "cx22"
}

variable "server_image" {
  description = "Hetzner OS image (e.g. ubuntu-24.04)"
  type        = string
  default     = "ubuntu-24.04"
}

variable "ssh_public_key" {
  description = "SSH public key content. Empty string disables SSH key resource creation. Deprecated: use ssh_key_id instead."
  type        = string
  default     = ""
}

variable "ssh_key_id" {
  description = "Hetzner SSH key ID to attach to server. Takes precedence over ssh_public_key."
  type        = string
  default     = ""
}

variable "ghcr_username" {
  type = string
}

variable "ghcr_token" {
  type      = string
  sensitive = true
}

variable "container_image" {
  type = string
}

variable "service_type" {
  description = "Service type label (backend, renderer)"
  type        = string
  default     = "backend"
}

variable "container_env_vars" {
  description = "Environment variables passed to the container"
  type        = map(string)
  default     = {}
}

variable "valkey_password" {
  description = "Password for the local Valkey instance"
  type        = string
  sensitive   = true
  default     = ""
}

variable "valkey_memory_max" {
  description = "Valkey maxmemory (e.g. 512mb, 1gb)"
  type        = string
  default     = "512mb"
}

variable "network_id" {
  description = "Hetzner private network ID to attach this server to. Empty string disables attachment."
  type        = string
  default     = ""
}

variable "standard_tags" {
  type    = map(string)
  default = {}
}

variable "admin_cidr_blocks" {
  description = "CIDR blocks allowed for SSH access (admin IPs only)"
  type        = list(string)
  default     = []
}

variable "cloudflare_cidrs" {
  description = "Cloudflare IP ranges for HTTP/HTTPS access"
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}

variable "renderer_container_image" {
  description = "Container image for renderer service (optional, enables renderer if provided)"
  type        = string
  default     = ""
}

variable "renderer_container_env_vars" {
  description = "Environment variables for renderer container"
  type        = map(string)
  default     = {}
}
