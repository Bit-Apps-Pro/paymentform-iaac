variable "environment" {
  description = "Deployment environment label applied to Hetzner resources. Required."
  type        = string
}

variable "server_name" {
  description = "Hetzner server name for the Valkey host. Required."
  type        = string

  validation {
    condition     = length(trimspace(var.server_name)) > 0
    error_message = "server_name must not be empty."
  }
}

variable "aws_vpc_cidr" {
  description = "AWS VPC CIDR routed through WireGuard to reach Valkey, for example 10.0.0.0/16. Required."
  type        = string
}

variable "wireguard_config" {
  description = <<-DESC
    WireGuard site-to-site settings. Required fields:
    - address: Hetzner WireGuard interface CIDR, example 172.27.0.2/32
    - private_key: private key for the Hetzner peer
    - peer_public_key: public key for the AWS peer

    Optional fields:
    - listen_port: UDP port on the Hetzner VM, default 51820
    - peer_endpoint: AWS peer public endpoint host:port when Hetzner should initiate
    - preshared_key: optional WireGuard preshared key
    - peer_allowed_ips: overrides default allowed IPs; defaults to aws_vpc_cidr
    - peer_public_ips: public source CIDRs allowed to hit the WireGuard UDP port; defaults to 0.0.0.0/0 when unknown
    - persistent_keepalive: default 25
  DESC
  type = object({
    address              = string
    private_key          = string
    peer_public_key      = string
    listen_port          = optional(number, 51820)
    peer_endpoint        = optional(string, "")
    preshared_key        = optional(string, "")
    peer_allowed_ips     = optional(list(string), [])
    peer_public_ips      = optional(list(string), [])
    persistent_keepalive = optional(number, 25)
  })
  sensitive = true
}

variable "valkey_password" {
  description = "Password required by Valkey AUTH. Required."
  type        = string
  sensitive   = true

  validation {
    condition     = length(trimspace(var.valkey_password)) > 0
    error_message = "valkey_password must not be empty."
  }
}

variable "server_image" {
  description = "Hetzner OS image used for the VM. Optional."
  type        = string
  default     = "ubuntu-24.04"
}

variable "volume_size_gb" {
  description = "Persistent Hetzner volume size in GB used for Valkey AOF data. Optional."
  type        = number
  default     = 20
}
