terraform {
  required_version = ">= 1.8"

  required_providers {
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
  }
}

locals {
  server_name = "${var.resource_prefix}-${var.region}-backend"
}

resource "hcloud_ssh_key" "main" {
  count      = var.ssh_public_key != "" ? 1 : 0
  name       = "${local.server_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "backend" {
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_public_key != "" ? [hcloud_ssh_key.main[0].id] : []

  user_data = templatefile("${path.module}/userdata.sh", {
    ghcr_username      = var.ghcr_username
    ghcr_token         = var.ghcr_token
    container_image    = var.container_image
    container_env_vars = var.container_env_vars
    service_type       = var.service_type
    valkey_password    = var.valkey_password
    valkey_memory_max  = var.valkey_memory_max
  })

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "backend"
  })
}

resource "hcloud_server_network" "backend" {
  count     = var.network_id != "" ? 1 : 0
  server_id = hcloud_server.backend.id
  network_id = tonumber(var.network_id)
}

resource "hcloud_firewall" "backend" {
  name = "${local.server_name}-fw"

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "80"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction = "in"
    protocol  = "tcp"
    port      = "443"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  labels = var.standard_tags
}

resource "hcloud_firewall_attachment" "backend" {
  firewall_id = hcloud_firewall.backend.id
  server_ids  = [hcloud_server.backend.id]
}
