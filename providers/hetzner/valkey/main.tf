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
  location            = "ash"
  network_zone        = "us-east"
  network_cidr        = "10.1.0.0/24"
  valkey_private_ip   = cidrhost(local.network_cidr, 10)
  volume_name         = "${var.server_name}-${var.environment}-valkey-data"
  wg_listen_port      = try(var.wireguard_config.listen_port, 51820)
  wg_peer_public_ips  = length(try(var.wireguard_config.peer_public_ips, [])) > 0 ? var.wireguard_config.peer_public_ips : ["0.0.0.0/0"]
  wg_peer_allowed_ips = length(try(var.wireguard_config.peer_allowed_ips, [])) > 0 ? var.wireguard_config.peer_allowed_ips : [var.aws_vpc_cidr]
  wg_peer_endpoint    = trimspace(try(var.wireguard_config.peer_endpoint, ""))
  wg_preshared_key    = trimspace(try(var.wireguard_config.preshared_key, ""))

  wireguard_config_content = trimspace(join("\n", compact([
    "[Interface]",
    "Address = ${var.wireguard_config.address}",
    "ListenPort = ${local.wg_listen_port}",
    "PrivateKey = ${var.wireguard_config.private_key}",
    "",
    "[Peer]",
    "PublicKey = ${var.wireguard_config.peer_public_key}",
    local.wg_preshared_key != "" ? "PresharedKey = ${local.wg_preshared_key}" : "",
    local.wg_peer_endpoint != "" ? "Endpoint = ${local.wg_peer_endpoint}" : "",
    "AllowedIPs = ${join(", ", local.wg_peer_allowed_ips)}",
    "PersistentKeepalive = ${try(var.wireguard_config.persistent_keepalive, 25)}",
  ])))

  bootstrap_script = <<-SCRIPT
    #!/usr/bin/env bash
    set -euxo pipefail

    export DEBIAN_FRONTEND=noninteractive

    systemctl enable --now docker

    VOLUME_DEVICE=""
    for attempt in $(seq 1 60); do
      if [ -e "/dev/disk/by-id/scsi-0HC_Volume_${local.volume_name}" ]; then
        VOLUME_DEVICE="$(readlink -f "/dev/disk/by-id/scsi-0HC_Volume_${local.volume_name}")"
        break
      fi

      sleep 5
    done

    if [ -z "$VOLUME_DEVICE" ]; then
      echo "attached Hetzner volume not found" >&2
      exit 1
    fi

    if ! blkid "$VOLUME_DEVICE" >/dev/null 2>&1; then
      mkfs.ext4 -F "$VOLUME_DEVICE"
    fi

    mkdir -p /var/lib/valkey
    UUID="$(blkid -s UUID -o value "$VOLUME_DEVICE")"
    if ! grep -q "UUID=$UUID /var/lib/valkey ext4" /etc/fstab; then
      echo "UUID=$UUID /var/lib/valkey ext4 defaults,nofail 0 2" >> /etc/fstab
    fi
    mountpoint -q /var/lib/valkey || mount /var/lib/valkey
    mkdir -p /var/lib/valkey/data

    for attempt in $(seq 1 60); do
      if ip -4 addr show | grep -qw "${local.valkey_private_ip}"; then
        break
      fi

      sleep 5
    done

    if ! ip -4 addr show | grep -qw "${local.valkey_private_ip}"; then
      echo "Hetzner private IP ${local.valkey_private_ip} not present" >&2
      exit 1
    fi

    sysctl --system

    install -d -m 0700 /etc/wireguard
    systemctl enable wg-quick@wg0
    systemctl restart wg-quick@wg0

    iptables -C INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT || iptables -I INPUT 1 -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -C INPUT -i lo -j ACCEPT || iptables -I INPUT 2 -i lo -j ACCEPT
    iptables -C INPUT -i wg0 -s ${var.aws_vpc_cidr} -d ${local.valkey_private_ip} -p tcp --dport 6379 -j ACCEPT || iptables -I INPUT 3 -i wg0 -s ${var.aws_vpc_cidr} -d ${local.valkey_private_ip} -p tcp --dport 6379 -j ACCEPT
    iptables -C INPUT -d ${local.valkey_private_ip} -p tcp --dport 6379 -j DROP || iptables -A INPUT -d ${local.valkey_private_ip} -p tcp --dport 6379 -j DROP
    netfilter-persistent save

    VALKEY_PASSWORD="$(tr -d '\n' </etc/valkey/password)"

    docker pull valkey/valkey:7.2
    docker rm -f valkey || true
    docker run -d \
      --name valkey \
      --restart always \
      --network host \
      -v /var/lib/valkey/data:/data \
      valkey/valkey:7.2 \
      valkey-server \
      --bind 127.0.0.1 ${local.valkey_private_ip} \
      --port 6379 \
      --appendonly yes \
      --appendfsync everysec \
      --appendfilename appendonly.aof \
      --dir /data \
      --requirepass "$VALKEY_PASSWORD" \
      --protected-mode yes
  SCRIPT

  user_data = join("\n", [
    "#cloud-config",
    yamlencode({
      package_update = true
      packages = [
        "ca-certificates",
        "curl",
        "docker.io",
        "iptables-persistent",
        "wireguard",
      ]
      write_files = [
        {
          path        = "/etc/sysctl.d/99-valkey-wireguard.conf"
          owner       = "root:root"
          permissions = "0644"
          content     = <<-SYSCTL
            net.ipv4.ip_forward=1
            net.ipv4.conf.all.src_valid_mark=1
          SYSCTL
        },
        {
          path        = "/etc/wireguard/wg0.conf"
          owner       = "root:root"
          permissions = "0600"
          content     = local.wireguard_config_content
        },
        {
          path        = "/etc/valkey/password"
          owner       = "root:root"
          permissions = "0600"
          content     = var.valkey_password
        },
        {
          path        = "/usr/local/bin/bootstrap-valkey.sh"
          owner       = "root:root"
          permissions = "0755"
          content     = local.bootstrap_script
        },
      ]
      runcmd = [
        "/usr/local/bin/bootstrap-valkey.sh",
      ]
    }),
  ])
}

resource "hcloud_network" "valkey" {
  name     = "${var.server_name}-${var.environment}-valkey-net"
  ip_range = local.network_cidr

  labels = {
    environment = var.environment
    service     = "valkey"
  }
}

resource "hcloud_network_subnet" "valkey" {
  network_id   = hcloud_network.valkey.id
  type         = "cloud"
  network_zone = local.network_zone
  ip_range     = local.network_cidr
}

resource "hcloud_volume" "valkey" {
  name     = local.volume_name
  size     = var.volume_size_gb
  location = local.location
  format   = "ext4"

  labels = {
    environment = var.environment
    service     = "valkey"
  }
}

resource "hcloud_server" "valkey" {
  name        = var.server_name
  server_type = "cpx11"
  image       = var.server_image
  location    = local.location
  user_data   = local.user_data

  labels = {
    environment = var.environment
    service     = "valkey"
  }
}

resource "hcloud_server_network" "valkey" {
  server_id  = hcloud_server.valkey.id
  network_id = hcloud_network.valkey.id
  ip         = local.valkey_private_ip

  depends_on = [hcloud_network_subnet.valkey]
}

resource "hcloud_volume_attachment" "valkey" {
  volume_id = hcloud_volume.valkey.id
  server_id = hcloud_server.valkey.id
  automount = false
}

resource "hcloud_firewall" "valkey" {
  name = "${var.server_name}-${var.environment}-valkey-fw"

  rule {
    description     = "Allow WireGuard peers"
    direction       = "in"
    protocol        = "udp"
    port            = tostring(local.wg_listen_port)
    source_ips      = sort(distinct(local.wg_peer_public_ips))
    destination_ips = []
  }

  labels = {
    environment = var.environment
    service     = "valkey"
  }
}

resource "hcloud_firewall_attachment" "valkey" {
  firewall_id = hcloud_firewall.valkey.id
  server_ids  = [hcloud_server.valkey.id]
}
