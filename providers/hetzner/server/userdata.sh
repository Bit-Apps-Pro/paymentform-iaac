#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Starting Hetzner server setup with Traefik reverse proxy"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

systemctl enable docker
systemctl start docker

log "Installing Docker Compose"
curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
chmod +x /usr/local/bin/docker-compose

log "Creating Docker network"
docker network create traefik-public 2>/dev/null || true

log "Logging into GHCR"
echo "${ghcr_token}" | docker login ghcr.io -u "${ghcr_username}" --password-stdin

log "Writing environment files"
cat > /etc/container.env <<'ENVEOF'
%{ for key, value in container_env_vars ~}
%{ if value != null ~}
${key}=${value}
%{ endif ~}
%{ endfor ~}
ENVEOF

# Renderer env file — disabled for initial deploy; uncomment when renderer is ready
# %{ if renderer_container_image != "" ~}
# cat > /etc/renderer.env <<'RENDEREOF'
# %{ for key, value in renderer_container_env_vars ~}
# %{ if value != null ~}
# ${key}=${value}
# %{ endif ~}
# %{ endfor ~}
# RENDEREOF
# %{ endif ~}

log "Creating Traefik configuration"
mkdir -p /opt/traefik
cat > /opt/traefik/traefik.yml <<'TRAEOF'
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
    network: traefik-public

log:
  level: ERROR
TRAEOF

log "Writing docker-compose.yml"
cat > /opt/docker-compose.yml <<'COMPOSEOF'
version: "3.8"

services:
  traefik:
    image: traefik:v3.0
    restart: unless-stopped
    networks:
      - traefik-public
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /opt/traefik/traefik.yml:/etc/traefik/traefik.yml:ro

  valkey:
    image: valkey/valkey:latest
    restart: unless-stopped
    networks:
      - traefik-public
    command: >
      valkey-server
      --requirepass "${valkey_password}"
      --maxmemory "${valkey_memory_max}"
      --maxmemory-policy allkeys-lru
      --bind 0.0.0.0

  backend:
    image: ${container_image}
    restart: unless-stopped
    networks:
      - traefik-public
    env_file:
      - /etc/container.env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.backend-http.rule=Host(\`api.paymentform.io\`)"
      - "traefik.http.routers.backend-http.entrypoints=web"
      - "traefik.http.services.backend-http.loadbalancer.server.port=80"
      - "traefik.tcp.routers.backend-tcp.rule=HostSNI(\`api.paymentform.io\`)"
      - "traefik.tcp.routers.backend-tcp.entrypoints=websecure"
      - "traefik.tcp.routers.backend-tcp.tls.passthrough=true"
      - "traefik.tcp.services.backend-tcp.loadbalancer.server.port=443"

%{ if renderer_container_image != "" ~}
  renderer:
    image: ${renderer_container_image}
    restart: unless-stopped
    networks:
      - traefik-public
    env_file:
      - /etc/renderer.env
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.renderer-http.rule=HostRegexp(\`{host:.+}\`) && !Host(\`api.paymentform.io\`)"
      - "traefik.http.routers.renderer-http.entrypoints=web"
      - "traefik.http.services.renderer-http.loadbalancer.server.port=80"
      - "traefik.http.routers.renderer-http.priority=1"
      - "traefik.tcp.routers.renderer-tcp.rule=HostSNI(\`*\`) && !HostSNI(\`api.paymentform.io\`)"
      - "traefik.tcp.routers.renderer-tcp.entrypoints=websecure"
      - "traefik.tcp.routers.renderer-tcp.tls.passthrough=true"
      - "traefik.tcp.services.renderer-tcp.loadbalancer.server.port=443"
      - "traefik.tcp.routers.renderer-tcp.priority=1"
%{ endif ~}

networks:
  traefik-public:
    external: true
COMPOSEOF

log "Starting services"
cd /opt && docker-compose up -d

log "Hetzner Traefik setup complete"
