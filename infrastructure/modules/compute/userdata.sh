#!/bin/bash
echo ECS_CLUSTER=${ecs_cluster_name} >> /etc/ecs/ecs.config
yum update -y
yum install -y docker
service docker start
usermod -a -G docker ec2-user

# Authenticate with ECR if configured for this environment
if [ "${image_registry_type}" = "ecr" ]; then
  # Authenticate with ECR using IAM role
  aws ecr get-login-password --region ${ecr_region} | docker login --username AWS --password-stdin ${ecr_account_id}.dkr.ecr.${ecr_region}.amazonaws.com || true
fi

# Authenticate with ECR if configured for this environment
if [ "${image_registry_type}" = "ecr" ]; then
  # Authenticate with ECR using IAM role
  aws ecr get-login-password --region ${ecr_region} | docker login --username AWS --password-stdin ${ecr_account_id}.dkr.ecr.${ecr_region}.amazonaws.com || true
fi
