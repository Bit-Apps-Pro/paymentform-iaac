#!/bin/bash
set -e

log() {
  echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

log "Starting Hetzner server setup with Traefik reverse proxy"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y docker.io curl

%{ if os_user_public_key != "" ~}
log "Creating OS user: ${os_username}"
id "${os_username}" &>/dev/null || useradd -m -s /bin/bash "${os_username}"

for grp in docker sudo; do
  if getent group "$grp" >/dev/null 2>&1; then
    usermod -aG "$grp" "${os_username}"
  fi
done

mkdir -p /home/${os_username}/.ssh
chmod 700 /home/${os_username}/.ssh
cat > /home/${os_username}/.ssh/authorized_keys <<'SSHEOF'
${os_user_public_key}
SSHEOF
chmod 600 /home/${os_username}/.ssh/authorized_keys
chown -R ${os_username}:${os_username} /home/${os_username}/.ssh

log "OS user ${os_username} created with SSH key"
%{ endif ~}

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

log "Writing deploy script"
cat > /usr/local/bin/deploy-hetzner.sh << 'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-hetzner.sh

log "Executing deploy script"
/usr/local/bin/deploy-hetzner.sh

log "Hetzner server setup complete"
