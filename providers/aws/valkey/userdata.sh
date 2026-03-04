#!/bin/bash
set -e

export DEBIAN_FRONTEND=noninteractive

# Update and install Valkey (Redis fork)
apt-get update
apt-get install -y valkey

# Configure Valkey
mkdir -p /etc/valkey
cat > /etc/valkey/valkey.conf <<EOF
bind 0.0.0.0
protected-mode no
port 6379
tcp-backlog 511
timeout 0
tcp-keepalive 300
daemonize no
supervised systemd
pidfile /var/run/valkey_6379.pid
loglevel notice
logfile ""
databases 16
always-show-logo no

# Memory management
maxmemory ${memory_max}
maxmemory-policy allkeys-lru

# Cluster configuration
cluster-enabled yes
cluster-config-file /etc/valkey/nodes.conf
cluster-node-timeout 5000
cluster-announce-ip $(hostname -I | awk '{print $1}')
cluster-announce-port 6379
cluster-announce-bus-port 16379

# Append only file for persistence
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no

# Security
# Password will be set by cluster init script
EOF

# Create valkey user if not exists
id valkey &>/dev/null || useradd -r -s /sbin/nologin valkey
chown -R valkey:valkey /var/lib/valkey
chown -R valkey:valkey /etc/valkey

# Enable and start Valkey
systemctl enable valkey
systemctl start valkey

echo "Valkey node ${node_index} setup complete"
