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

authenticate_ghcr

log "Writing deploy script"
cat > /usr/local/bin/deploy-ec2.sh << 'DEPLOYEOF'
${deploy_script_content}
DEPLOYEOF
chmod +x /usr/local/bin/deploy-ec2.sh

log "Executing deploy script"
/usr/local/bin/deploy-ec2.sh

log "Container started successfully"

%{ if tunnel_token != "" ~}
log "Starting cloudflared tunnel connector"
docker stop cloudflared || true
docker rm cloudflared || true
docker run -d \
  --name cloudflared \
  --restart unless-stopped \
  --network=host \
  cloudflare/cloudflared:latest tunnel --no-autoupdate run \
  --token ${tunnel_token}
log "cloudflared started"
%{ endif ~}
