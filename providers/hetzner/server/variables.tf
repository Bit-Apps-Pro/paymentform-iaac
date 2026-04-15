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
  description = "SSH public key content. Empty string disables SSH key resource creation."
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
