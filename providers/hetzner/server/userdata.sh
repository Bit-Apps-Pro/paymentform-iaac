#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Starting Hetzner ${service_type} server setup"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

log "Logging into GHCR"
echo "${ghcr_token}" | docker login ghcr.io -u "${ghcr_username}" --password-stdin

log "Pulling container image: ${container_image}"
docker pull "${container_image}"

log "Writing container env file"
cat > /etc/container.env <<'ENVEOF'
%{ for key, value in container_env_vars ~}
%{ if value != null ~}
${key}=${value}
%{ endif ~}
%{ endfor ~}
ENVEOF

log "Starting Valkey"
docker stop valkey || true
docker rm valkey || true
docker run -d \
  --name valkey \
  --restart unless-stopped \
  -p 127.0.0.1:6379:6379 \
  valkey/valkey:latest \
  valkey-server \
  --requirepass "${valkey_password}" \
  --maxmemory "${valkey_memory_max}" \
  --maxmemory-policy allkeys-lru \
  --bind 0.0.0.0

log "Creating app systemd service"
cat > /etc/systemd/system/app.service <<'SVCEOF'
[Unit]
Description=Application Container
After=docker.service
Requires=docker.service

[Service]
Restart=always
RestartSec=10
ExecStartPre=-/usr/bin/docker stop app
ExecStartPre=-/usr/bin/docker rm app
ExecStart=/usr/bin/docker run --rm \
  --name app \
  --network host \
  --env-file /etc/container.env \
  -p 80:80 \
  -p 443:443 \
  ${container_image}
ExecStop=/usr/bin/docker stop app

[Install]
WantedBy=multi-user.target
SVCEOF

systemctl daemon-reload
systemctl enable app
systemctl start app

log "Hetzner ${service_type} setup complete"
