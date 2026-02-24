#!/bin/bash
set -e

# Configure ECS agent
echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config

# Install Docker (Ubuntu/Debian)
apt-get update -y
apt-get install -y ca-certificates curl awscli
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
  https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io
systemctl start docker
systemctl enable docker
usermod -a -G docker ubuntu

# Authenticate with ECR using IAM role
if [ "${image_registry_type}" = "ecr" ]; then
  aws ecr get-login-password --region ${ecr_region} \
    | docker login --username AWS \
      --password-stdin ${ecr_account_id}.dkr.ecr.${ecr_region}.amazonaws.com || true
fi

# Authenticate with GHCR using token stored in SSM
if [ "${image_registry_type}" = "ghcr" ]; then
  GHCR_TOKEN=$(aws ssm get-parameter \
    --name "/app/${environment}/backend/GHCR_TOKEN" \
    --with-decryption \
    --region ${region} \
    --query Parameter.Value \
    --output text 2>/dev/null || echo "")
  if [ -n "$GHCR_TOKEN" ]; then
    echo "$GHCR_TOKEN" | docker login ghcr.io -u x-access-token --password-stdin || true
  fi
fi
