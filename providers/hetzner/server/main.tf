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
  server_name      = "${var.resource_prefix}-${var.region}-backend"
  admin_source_ips = sort(distinct(length(var.admin_cidr_blocks) > 0 ? var.admin_cidr_blocks : ["0.0.0.0/0"]))
  edge_source_ips  = sort(distinct(var.cloudflare_cidrs))
}

resource "hcloud_ssh_key" "main" {
  count      = var.ssh_key_id == "" && var.ssh_public_key != "" ? 1 : 0
  name       = "${local.server_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_server" "backend" {
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_key_id != "" ? [var.ssh_key_id] : (var.ssh_public_key != "" ? [hcloud_ssh_key.main[0].id] : [])

user_data = templatefile("${path.module}/userdata.sh", {
    ghcr_username               = var.ghcr_username
    ghcr_token                  = var.ghcr_token
    container_image             = var.container_image
    container_env_vars          = var.container_env_vars
    service_type                = var.service_type
    valkey_password             = var.valkey_password
    valkey_memory_max           = var.valkey_memory_max
    renderer_container_image    = var.renderer_container_image
    renderer_container_env_vars = var.renderer_container_env_vars
    os_username                 = var.os_username
    os_user_public_key          = var.os_user_public_key
    deploy_script_content       = var.deploy_script_content
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
    description     = "Allow SSH admin access"
    direction       = "in"
    protocol        = "tcp"
    port            = "22"
    source_ips      = local.admin_source_ips
    destination_ips = []
  }

  rule {
    description     = "Allow HTTP from Cloudflare"
    direction       = "in"
    protocol        = "tcp"
    port            = "80"
    source_ips      = local.edge_source_ips
    destination_ips = []
  }

  rule {
    description     = "Allow HTTPS from Cloudflare"
    direction       = "in"
    protocol        = "tcp"
    port            = "443"
    source_ips      = local.edge_source_ips
    destination_ips = []
  }

  labels = var.standard_tags
}

resource "hcloud_firewall_attachment" "backend" {
  firewall_id = hcloud_firewall.backend.id
  server_ids  = [hcloud_server.backend.id]
}
