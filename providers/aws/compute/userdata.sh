#!/bin/bash
set -e

log() {
 echo "[ $(date '+%Y-%m-%d %H:%M:%S') ] $1"
}

authenticate_ghcr() {
  log "Authenticating with GHCR..."
  GHCR_TOKEN=$(aws ssm get-parameter \
    --name "/paymentform/${environment}/backend/GHCR_TOKEN" \
    --with-decryption \
    --region ${region} \
    --query Parameter.Value \
    --output text 2>/dev/null || echo "")
  
  if [ -n "$GHCR_TOKEN" ]; then
    echo "$GHCR_TOKEN" | docker login ghcr.io -u ${ghcr_username} --password-stdin || true
    log "GHCR authentication successful"
  else
    log "WARNING: GHCR_TOKEN not found; public images only"
  fi
}

log "Starting container deployment"

ENV_PATH="/etc/app.env"
> $ENV_PATH

echo "${container_env_vars}" >> $ENV_PATH
echo "AUTO_SSL=${auto_ssl}" >> $ENV_PATH

log "Pulling image ${IMAGE}"

authenticate_ghcr
docker pull ${IMAGE}

docker stop paymentform-${service_type} || true
docker rm paymentform-${service_type} || true

docker run -d \
  --name paymentform-${service_type} \
  --network=host \
  --restart unless-stopped \
  --env-file $ENV_PATH \
  -p 80:80 \
  -p 443:443 \
  -v /caddy/data:/data/caddy \
  -v /caddy/config:/config/caddy \
  ${IMAGE}

log "Container started successfully"
