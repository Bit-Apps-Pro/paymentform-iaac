# Main OpenTofu configuration at root level
# This file sources the infrastructure modules from the infrastructure/ directory

terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
    neon = {
      source  = "kislerdm/neon"
      version = "0.13.0"
    }
    turso = {
      source  = "celest-dev/turso"
      version = "0.2.3"
    }
  }

  # S3 backend configuration
  # Use -backend-config to specify environment-specific values
  backend "s3" {}
}

# Import infrastructure configurations
module "infrastructure" {
  source                = "./infrastructure"
  neon_api_key          = var.neon_api_key
  turso_api_token       = var.turso_api_token
  turso_organization    = var.turso_organization
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id
  desired_capacity      = var.desired_capacity
  region                = var.region
  environment           = var.environment
  # Image registry
  image_registry_type = var.image_registry_type
  enable_ecr          = var.enable_ecr
  ghcr_token          = var.ghcr_token
  # Two-instance sizing
  backend_instance_type     = var.backend_instance_type
  renderer_instance_type    = var.renderer_instance_type
  backend_desired_capacity  = var.backend_desired_capacity
  renderer_desired_capacity = var.renderer_desired_capacity
  backend_ami_id            = var.backend_ami_id
  renderer_ami_id           = var.renderer_ami_id
  key_pair_name             = var.key_pair_name
  # Secrets
  google_client_secret           = var.google_client_secret
  tenant_db_encryption_key       = var.tenant_db_encryption_key
  stripe_secret                  = var.stripe_secret
  aws_secret_access_key          = var.aws_secret_access_key
  db_password                    = var.db_password
  stripe_client_id               = var.stripe_client_id
  pgadmin_default_password       = var.pgadmin_default_password
  tenant_db_auth_token           = var.tenant_db_auth_token
  aws_access_key_id              = var.aws_access_key_id
  turso_auth_token               = var.turso_auth_token
  mail_password                  = var.mail_password
  kv_store_api_token             = var.kv_store_api_token
  stripe_connect_webhook_secret  = var.stripe_connect_webhook_secret
}

# Re-export all infrastructure outputs
output "resource_prefix" {
  description = "Standard prefix used for resource naming"
  value       = module.infrastructure.resource_prefix
}

output "standard_tags" {
  description = "Standard tags applied to all resources"
  value       = module.infrastructure.standard_tags
}

output "environment" {
  description = "Current deployment environment"
  value       = module.infrastructure.environment
}

output "region" {
  description = "Deployed region"
  value       = module.infrastructure.region
}

output "project_name" {
  description = "Project name"
  value       = module.infrastructure.project_name
}
output "database_host" {
  description = "Neon database host"
  value       = module.infrastructure.database_host
}

output "database_name" {
  description = "Neon database name"
  value       = module.infrastructure.database_name
}

output "database_app_role" {
  description = "Database application role"
  value       = module.infrastructure.database_app_role
}

output "neon_project_id" {
  description = "Neon project ID"
  value       = module.infrastructure.neon_project_id
}

output "neon_connection_string" {
  description = "Neon connection string (replace <password> with actual password)"
  value       = module.infrastructure.neon_connection_string
  sensitive   = true
}
output "tenant_db_url" {
  description = "Turso tenant database SSM parameter path"
  value       = module.infrastructure.tenant_db_ssm_path
  sensitive   = true
}

output "tenant_db_name" {
  description = "Turso tenant database name"
  value       = module.infrastructure.tenant_db_name
}

output "analytics_db_url" {
  description = "Turso analytics database SSM parameter path"
  value       = module.infrastructure.analytics_db_ssm_path
  sensitive   = true
}

output "analytics_db_name" {
  description = "Turso analytics database name"
  value       = module.infrastructure.analytics_db_name
}

output "backup_db_url" {
  description = "Turso backup database SSM parameter path"
  value       = module.infrastructure.backup_db_ssm_path
  sensitive   = true
}

output "backup_db_name" {
  description = "Turso backup database name"
  value       = module.infrastructure.backup_db_name
}

output "tenants_kv_namespace_id" {
  description = "Cloudflare KV namespace ID for tenant storage"
  value       = module.infrastructure.tenants_kv_namespace_id
}

output "tenants_kv_namespace_title" {
  description = "Cloudflare KV namespace title"
  value       = module.infrastructure.tenants_kv_namespace_title
}
