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
  server_name = "${var.resource_prefix}-${var.region}-db-replica"
}

resource "hcloud_ssh_key" "db" {
  count      = var.ssh_public_key != "" ? 1 : 0
  name       = "${local.server_name}-key"
  public_key = var.ssh_public_key
}

resource "hcloud_volume" "data" {
  name     = "${local.server_name}-data"
  size     = var.volume_size_gb
  location = var.location
  format   = "ext4"

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "database"
  })
}

resource "hcloud_server" "db_replica" {
  name        = local.server_name
  server_type = var.server_type
  image       = var.server_image
  location    = var.location
  ssh_keys    = var.ssh_public_key != "" ? [hcloud_ssh_key.db[0].id] : []

  user_data = templatefile("${path.module}/userdata-replica.sh", {
    primary_host  = var.primary_host
    primary_port  = var.primary_port
    db_password   = var.db_password
  })

  labels = merge(var.standard_tags, {
    environment = var.environment
    region      = var.region
    service     = "database"
    role        = "replica"
  })
}

resource "hcloud_volume_attachment" "data" {
  volume_id = hcloud_volume.data.id
  server_id = hcloud_server.db_replica.id
  automount = true
}

resource "hcloud_server_network" "db_replica" {
  count      = var.network_id != "" ? 1 : 0
  server_id  = hcloud_server.db_replica.id
  network_id = tonumber(var.network_id)
}

resource "hcloud_firewall" "db" {
  name = "${local.server_name}-fw"

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "22"
    source_ips = ["0.0.0.0/0", "::/0"]
  }

  rule {
    direction  = "in"
    protocol   = "tcp"
    port       = "5432"
    source_ips = var.allowed_cidrs
  }

  labels = var.standard_tags
}

resource "hcloud_firewall_attachment" "db" {
  firewall_id = hcloud_firewall.db.id
  server_ids  = [hcloud_server.db_replica.id]
}
