# Sandbox Environment Configuration
# Calls provider modules directly

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.16.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-terraform-state"
    key            = "sandbox/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paymentform-terraform-locks"
  }
}

locals {
  resource_prefix = "paymentform-sandbox"

  standard_tags = {
    Environment = "sandbox"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

# ============================================================================
# AWS Infrastructure
# ============================================================================

module "aws_networking" {
  source = "../../providers/aws/networking"

  environment         = "sandbox"
  region              = "us-east-1"
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

module "aws_security" {
  source = "../../providers/aws/security"

  environment            = "sandbox"
  vpc_id                 = module.aws_networking.vpc_id
  app_ports              = [80, 443, 8000, 3000]
  enable_strict_security = false
  standard_tags          = local.standard_tags
}

module "aws_database" {
  source = "../../providers/aws/database"

  environment       = "sandbox"
  ami_id            = var.postgres_ami_id
  subnet_ids        = module.aws_networking.public_subnet_ids
  security_group_id = module.aws_security.postgresql_security_group_id

  primary_instance_type = "t4g.micro"
  replica_instance_type = "t4g.micro"
  primary_volume_size   = 20
  replica_volume_size   = 20
  volume_type           = "gp3"

  enable_replica   = true
  postgres_version = "16"
  db_name          = var.db_database
  db_user          = var.db_username
  db_password      = var.db_password

  r2_endpoint            = "https://paymentform-backups-sandbox.r2.cloudflarestorage.com"
  r2_bucket_name         = "paymentform-backups-sandbox"
  r2_access_key          = var.r2_backup_access_key
  r2_secret_key          = var.r2_backup_secret_key
  pgbackrest_cipher_pass = var.pgbackrest_cipher_pass

  standard_tags = local.standard_tags
  region        = "us-east-1"
  assign_eip    = true
}

module "aws_valkey" {
  source = "../../providers/aws/valkey"

  environment       = "sandbox"
  ami_id            = var.valkey_ami_id
  subnet_ids        = module.aws_networking.public_subnet_ids
  security_group_id = module.aws_security.valkey_security_group_id

  instance_type = "t4g.micro"
  node_count    = 2
  volume_size   = 20
  volume_type   = "gp3"

  cluster_password = var.redis_password
  memory_max       = "256mb"

  standard_tags = local.standard_tags
}

module "aws_compute_backend" {
  source = "../../providers/aws/compute"

  environment                = "sandbox"
  instance_prefix            = "sandbox-backend"
  subnet_ids                 = module.aws_networking.public_subnet_ids
  instance_type              = "t4g.micro"
  ami_id                     = ""
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 2
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 30
  root_volume_type           = "gp3"
  ecs_cluster_name           = "paymentform-cluster-sandbox"
  ecs_security_group_id      = module.aws_security.ecs_security_group_id
  region                     = "us-east-1"
  bucket_name                = module.cloudflare_r2.application_storage_bucket_name
  service_type               = "backend"

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.sandbox.paymentform.io"
    APP_BASE_DOMAIN   = "sandbox.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = 12

    LOG_CHANNEL              = "stack"
    LOG_STACK                = "single"
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.aws_database.primary_endpoint
    DB_PORT       = 5432
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"

    SESSION_DRIVER   = "database"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "log"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "database"
    CACHE_STORE          = "database"


    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.aws_valkey.primary_endpoint
    REDIS_PORT     = 6379
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = "smtp.mailgun.org"
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = "us-east-1"
    AWS_BUCKET                  = "paymentform-uploads-sandbox"
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://paymentform-uploads-sandbox.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://paymentform-uploads-sandbox.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.sandbox.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".sandbox.paymentform.io"
    SESSION_DOMAIN           = ".sandbox.paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.sandbox.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.sandbox.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.cloudflare_kv_tenants.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.cloudflare_kv_tenants.namespace_id
  }
}

module "aws_ssm" {
  source = "../../providers/aws/ssm"

  environment       = "sandbox"
  app_key           = var.app_key
  redis_password    = var.redis_password
  turso_auth_token  = var.turso_auth_token
  neon_database_url = var.neon_database_url
  kms_key_id        = ""

  db_password                   = var.db_password
  tenant_db_auth_token          = var.tenant_db_auth_token
  tenant_db_encryption_key      = var.tenant_db_encryption_key
  mail_password                 = var.mail_password
  aws_access_key_id             = var.aws_access_key_id
  aws_secret_access_key         = var.aws_secret_access_key
  google_client_secret          = var.google_client_secret
  stripe_secret                 = var.stripe_secret
  stripe_client_id              = var.stripe_client_id
  stripe_connect_webhook_secret = var.stripe_connect_webhook_secret
  kv_store_api_token            = var.kv_store_api_token
  ghcr_token                    = var.ghcr_token
}

# ============================================================================
# Cloudflare Infrastructure
# ============================================================================

module "cloudflare_r2" {
  source = "../../providers/cloudflare/r2"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  r2_bucket_name        = "paymentform-uploads-sandbox"
  r2_public_bucket_name = ""
  r2_ssl_bucket_name    = "paymentform-ssl-config"
  r2_backup_bucket_name = "paymentform-backups-sandbox"

  cors_allowed_origins    = ["*"]
  lifecycle_rules_enabled = true
  ssl_cert_retention_days = 30

  worker_enabled       = true
  worker_route_pattern = "cdn.sandbox.paymentform.io/*"
  cloudflare_zone_id   = var.cloudflare_zone_id
}

module "cloudflare_kv_tenants" {
  source = "../../providers/cloudflare/kv"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.kv_store_api_token

  namespace_name    = "tenants"
  namespace_enabled = true
}

module "cloudflare_container_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = true

  domain_name    = "app.sandbox.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    API_URL         = "https://api.sandbox.paymentform.io"
    DOMAIN          = "https://app.sandbox.paymentform.io"
    COOKIE_DOMAIN   = ".sandbox.paymentform.io"
    FORM_RENDER_URL = "https://renderer.sandbox.paymentform.io/"
    STRIPE_KEY      = var.stripe_public_key
    NODE_ENV        = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_container_renderer" {
  source = "../../providers/cloudflare/containers"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "renderer"
  container_image   = var.renderer_container_image
  container_enabled = true

  domain_name    = "*.sandbox.paymentform.io"
  domain_proxied = false

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    R2_SSL_BUCKET_NAME       = module.cloudflare_r2.ssl_config_bucket_name
    R2_SSL_ENDPOINT          = module.cloudflare_r2.r2_endpoint
    R2_SSL_ACCESS_KEY_ID     = var.r2_ssl_access_key_id
    R2_SSL_SECRET_ACCESS_KEY = var.r2_ssl_secret_access_key
    API_URL                  = "https://api.sandbox.paymentform.io"
    DOMAIN                   = "https://app.sandbox.paymentform.io"
    KV_STORE_BASE_URL        = module.cloudflare_kv_tenants.kv_store_endpoint
    KV_STORE_API_TOKEN       = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID    = module.cloudflare_kv_tenants.namespace_id
    STRIPE_KEY               = var.stripe_public_key
    RESERVED_SUBDOMAINS      = "www,admin,api,app,dev,test"
    NODE_ENV                 = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_container_backend" {
  source = "../../providers/cloudflare/containers"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "backend"
  container_image   = var.client_container_image
  container_enabled = true

  domain_name    = "api.sandbox.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.sandbox.paymentform.io"
    APP_BASE_DOMAIN   = "sandbox.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = 12

    LOG_CHANNEL              = "stack"
    LOG_STACK                = "single"
    LOG_DEPRECATIONS_CHANNEL = null
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.aws_database.primary_endpoint
    DB_PORT       = 5432
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"

    SESSION_DRIVER   = "database"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "log"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "database"
    CACHE_STORE          = "database"


    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.aws_valkey.primary_endpoint
    REDIS_PORT     = 6379
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = "smtp.mailgun.org"
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.aws_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.aws_secret_access_key
    AWS_DEFAULT_REGION          = "us-east-1"
    AWS_BUCKET                  = "paymentform-uploads-sandbox"
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://paymentform-uploads-sandbox.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://paymentform-uploads-sandbox.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.sandbox.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".sandbox.paymentform.io"
    SESSION_DOMAIN           = ".sandbox.paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.sandbox.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.sandbox.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.cloudflare_kv_tenants.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.cloudflare_kv_tenants.namespace_id
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

module "cloudflare_dns" {
  source = "../../providers/cloudflare/dns"

  environment           = "sandbox"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id

  domain_name        = "paymentform.io"
  api_subdomain      = "api.sandbox.paymentform.io"
  app_subdomain      = "app.sandbox.paymentform.io"
  renderer_subdomain = "*.sandbox.paymentform.io"

  api_origin_ips              = module.aws_compute_backend.instance_ips
  app_origin_ips              = []
  renderer_origin_ip          = ""
  app_container_endpoint      = module.cloudflare_container_client.container_endpoint
  renderer_container_endpoint = module.cloudflare_container_renderer.container_endpoint

  cloudflare_plan      = "free"
  enable_load_balancer = false
  enable_waf           = false
  enable_rate_limiting = false
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = ""
}

# ============================================================================
# Outputs
# ============================================================================

output "backend_instance_ips" {
  value = module.aws_compute_backend.instance_ips
}

output "client_container_endpoint" {
  value = module.cloudflare_container_client.container_endpoint
}

output "renderer_container_endpoint" {
  value = module.cloudflare_container_renderer.container_endpoint
}

output "api_hostname" {
  value = module.cloudflare_dns.api_hostname
}

output "app_hostname" {
  value = module.cloudflare_dns.app_hostname
}

output "renderer_hostname" {
  value = module.cloudflare_dns.renderer_hostname
}

output "r2_bucket_name" {
  value = module.cloudflare_r2.application_storage_bucket_name
}

output "ssl_config_bucket_name" {
  value = module.cloudflare_r2.ssl_config_bucket_name
}

output "postgresql_primary_endpoint" {
  description = "PostgreSQL primary endpoint"
  value       = module.aws_database.primary_endpoint
}

output "postgresql_replica_endpoint" {
  description = "PostgreSQL replica endpoint"
  value       = module.aws_database.replica_endpoint
}

output "valkey_cluster_endpoints" {
  description = "Valkey cluster endpoints"
  value       = module.aws_valkey.cluster_endpoints
}
