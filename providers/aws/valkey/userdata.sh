#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Installing Valkey on AL2023..."

dnf install -y valkey

mkdir -p /etc/valkey
cat > /etc/valkey/valkey.conf <<EOF
bind 0.0.0.0
protected-mode yes
port 6379
requirepass ${cluster_password}
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
supervised systemd
pidfile /var/run/valkey/valkey.pid
loglevel notice
logfile ""
databases 16
always-show-logo no

maxmemory ${memory_max}
maxmemory-policy allkeys-lru

cluster-enabled yes
cluster-config-file /etc/valkey/nodes.conf
cluster-node-timeout 5000
cluster-announce-ip $(hostname -I | awk '{print $1}')
cluster-announce-port 6379
cluster-announce-bus-port 16379

appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
EOF

mkdir -p /var/run/valkey
chown -R valkey:valkey /var/lib/valkey
chown -R valkey:valkey /etc/valkey

systemctl enable valkey
systemctl start valkey

log "Valkey node ${node_index} setup complete"
