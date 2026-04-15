# Production Environment - Primary Region: us-east-1

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
    hcloud = {
      source  = "hetznercloud/hcloud"
      version = "~> 1.49"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-terraform-state"
    key            = "prod/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "paymentform-terraform-locks"
  }
}

provider "aws" {
  region = local.region
}

provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "hcloud" {
  token = var.hetzner_api_token
}

locals {
  resource_prefix = "paymentform-p-us"
  region          = "us-east-1"

  standard_tags = {
    Environment = "prod"
    Region      = "us-east-1"
    Project     = "paymentform"
    ManagedBy   = "opentofu"
  }
}

resource "aws_ssm_parameter" "ghcr_token" {
  name        = "/paymentform/prod/backend/GHCR_TOKEN"
  description = "GitHub Container Registry token for Docker image pull"
  type        = "SecureString"
  value       = var.ghcr_token
  overwrite   = true

  lifecycle {
    prevent_destroy = false
  }
}

# =============================================================================
# Networking
# =============================================================================
module "paymentform_networking" {
  source = "../../providers/aws/networking"

  environment         = "prod"
  region              = local.region
  vpc_cidr            = "10.0.0.0/16"
  availability_zones  = ["us-east-1a", "us-east-1b", "us-east-1c"]
  public_subnet_cidrs = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  standard_tags       = local.standard_tags
}

# =============================================================================
# Security
# =============================================================================
module "paymentform_security" {
  source = "../../providers/aws/security"

  environment            = "prod"
  vpc_id                 = module.paymentform_networking.vpc_id
  app_ports              = [80, 443]
  enable_strict_security = true
  standard_tags          = local.standard_tags
  nlb_security_group_ids = [
    module.paymentform_nlb_backend.security_group_id,
    module.paymentform_nlb_renderer.security_group_id,
  ]
  cross_region_vpc_cidrs = var.peer_vpc_cidrs
}

# =============================================================================
# PostgreSQL (Database)
# =============================================================================
module "postgres_primary_volume" {
  source = "../../providers/aws/volume/postgres-primary"

  environment       = "prod"
  name              = "${local.resource_prefix}-database-primary"
  availability_zone = "${local.region}a"
  size              = 30
  volume_type       = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125
  device_name       = "/dev/sdf"
  instance_id       = ""
  standard_tags     = local.standard_tags
}

module "postgres_replica_volume" {
  source = "../../providers/aws/volume/postgres-replica"

  environment       = "prod"
  name              = "${local.resource_prefix}-database-replica"
  availability_zone = "${local.region}b"
  size              = 30
  volume_type       = "gp3"
  encrypted         = true
  iops              = 3000
  throughput        = 125
  device_name       = "/dev/sdf"
  instance_id       = ""
  standard_tags     = local.standard_tags
}

# =============================================================================
# Cloudflare Tunnel — DB Primary (exposes Postgres 5432 to Hetzner replicas)
# =============================================================================
module "tunnel_db" {
  source = "../../providers/cloudflare/tunnel-db"

  cloudflare_account_id = var.cloudflare_account_id
  resource_prefix       = "${local.resource_prefix}-db"
}

module "postgres_database" {
  source = "../../providers/aws/database"

  depends_on = [
    module.postgres_primary_volume,
    module.postgres_replica_volume
  ]

  environment       = "prod"
  name              = "${local.resource_prefix}-database"
  ami_id            = var.postgres_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.postgresql_security_group_id

  primary_instance_type = "t4g.small"
  replica_instance_type = "t4g.micro"
  primary_volume_size   = 20
  replica_volume_size   = 20
  volume_type           = "gp3"

  enable_replica   = true
  postgres_version = "17"
  db_name          = var.db_database
  db_user          = var.db_username
  db_password      = var.db_password

  database_backup_bucket_endpoint      = "https://${var.backup_storage_bucket_name}.r2.cloudflarestorage.com"
  database_backup_bucket_name          = var.backup_storage_bucket_name
  database_backup_bucket_access_key_id = var.backup_storage_access_key_id
  database_backup_bucket_access_key    = var.backup_storage_access_key
  pgbackrest_cipher_pass               = var.pgbackrest_cipher_pass

  tunnel_token = module.tunnel_db.tunnel_token

  standard_tags = local.standard_tags
  region        = local.region
  assign_eip    = true

  peer_vpc_cidrs = var.peer_vpc_cidrs

  volumes = []
  volume_ids = {
    postgresql-primary-data = module.postgres_primary_volume.volume_id
    postgresql-replica-data = module.postgres_replica_volume.volume_id
  }
}

module "paymentform_cache" {
  source = "../../providers/aws/valkey"

  environment       = "prod"
  name              = "${local.resource_prefix}-cache"
  region            = local.region
  ami_id            = var.valkey_ami_id
  subnet_ids        = module.paymentform_networking.public_subnet_ids
  security_group_id = module.paymentform_security.valkey_security_group_id

  instance_type = "t4g.medium"
  node_count    = 1
  volume_size   = 20
  volume_type   = "gp3"

  cluster_password = var.redis_password
  memory_max       = "1gb"

  standard_tags = local.standard_tags
}

module "paymentform_backend" {
  source = "../../providers/aws/compute"

  depends_on = [
    module.paymentform_nlb_backend,
    module.paymentform_security
  ]

  environment                = "prod"
  instance_prefix            = "${local.resource_prefix}-backend"
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = "ami-06fdf1c06301d49be"
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 4
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 50
  root_volume_type           = "gp3"
  ecs_cluster_name           = "${local.resource_prefix}-cluster"
  ecs_security_group_id      = module.paymentform_security.ecs_security_group_id
  region                     = local.region
  bucket_name                = module.paymentform_storage_application.bucket_name
  service_type               = "backend"
  ghcr_username              = var.ghcr_username
  container_image            = var.backend_container_image
  alb_target_group_arns = [
    module.paymentform_nlb_backend.https_target_group_arn,
    module.paymentform_nlb_backend.http_target_group_arn,
  ]

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
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
    DB_HOST       = module.postgres_database.primary_endpoint
    DB_HOST_WRITE = module.postgres_database.primary_endpoint
    DB_HOST_READ  = module.postgres_database.replica_endpoint
    DB_PORT       = 5432
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = 120
    SESSION_ENCRYPT  = false
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = null

    BROADCAST_CONNECTION = "redis"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "redis"
    CACHE_STORE          = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = module.paymentform_cache.primary_endpoint
    REDIS_PORT     = 6379
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = module.paymentform_storage_application.bucket_name
    AWS_USE_PATH_STYLE_ENDPOINT = true
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".paymentform.io"
    SESSION_DOMAIN           = ".paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id

    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
  }
}

module "paymentform_renderer" {
  source = "../../providers/aws/compute"

  depends_on = [
    module.paymentform_nlb_renderer,
    module.paymentform_security
  ]

  environment                = "prod"
  instance_prefix            = "${local.resource_prefix}-renderer"
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  instance_type              = "t4g.small"
  ami_id                     = "ami-06fdf1c06301d49be"
  key_pair_name              = ""
  min_size                   = 1
  max_size                   = 4
  desired_capacity           = 1
  scaling_cpu_threshold      = 70
  scaling_down_cpu_threshold = 30
  standard_tags              = local.standard_tags
  detailed_monitoring        = true
  ebs_optimized              = true
  root_volume_size           = 20
  root_volume_type           = "gp3"
  ecs_cluster_name           = "${local.resource_prefix}-cluster"
  ecs_security_group_id      = module.paymentform_security.ecs_security_group_id
  region                     = local.region
  bucket_name                = module.paymentform_storage_application.bucket_name
  service_type               = "renderer"
  ghcr_username              = var.ghcr_username
  container_image            = var.renderer_container_image
  alb_target_group_arns = [
    module.paymentform_nlb_renderer.https_target_group_arn,
    module.paymentform_nlb_renderer.http_target_group_arn,
  ]

  container_env_vars = {
    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
    API_URL                          = "https://api.paymentform.io"
    DOMAIN                           = "paymentform.io"
    KV_STORE_BASE_URL                = "https://tenant-validator-prod.bitapps.workers.dev"
    ACME_EMAIL                       = "hello@paymentform.io"
    KV_STORE_NAMESPACE_ID            = module.paymentform_kv_store.namespace_id
    KV_STORE_API_TOKEN               = var.kv_store_api_token
    STRIPE_KEY                       = var.stripe_public_key
    RESERVED_SUBDOMAINS              = "www,admin,api,app,dev,test"
    NODE_ENV                         = "production"
  }
}

module "paymentform_storage_application" {
  source = "../../providers/cloudflare/r2/application-storage"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = "${local.resource_prefix}-uploads"
}

module "paymentform_storage_ssl_config" {
  source = "../../providers/cloudflare/r2/ssl-config"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  r2_bucket_name        = "${local.resource_prefix}-ssl-config"
  enabled               = true
}

module "paymentform_storage_cdn_worker" {
  source = "../../providers/cloudflare/r2/cdn-worker"

  environment           = "prod"
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  worker_enabled          = false
  worker_route_pattern    = "cdn.paymentform.io/*"
  cors_allowed_origins    = ["https://app.paymentform.io"]
  application_bucket_name = module.paymentform_storage_application.bucket_name
}

module "paymentform_kv_store" {
  source = "../../providers/cloudflare/kv"

  environment           = "paymenform"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token

  namespace_name     = "tenants"
  namespace_enabled  = true
  deploy_worker      = true
  worker_path        = "${path.root}/../../../kv-store"
  kv_store_api_token = var.kv_store_api_token
}

# NLB for backend API - api.paymentform.io → port 80/443 → backend containers
module "paymentform_nlb_backend" {
  source = "../../providers/aws/nlb"

  environment                = "prod"
  prefix                     = "${local.resource_prefix}-backend"
  service_label              = "bknd"
  vpc_id                     = module.paymentform_networking.vpc_id
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  enable_deletion_protection = true
  standard_tags              = local.standard_tags
  alert_webhook_url          = var.alert_webhook_url
}

# NLB for renderer - *.paymentform.io → port 80/443 → renderer containers
module "paymentform_nlb_renderer" {
  source = "../../providers/aws/nlb"

  environment                = "prod"
  prefix                     = "${local.resource_prefix}-renderer"
  service_label              = "rndr"
  vpc_id                     = module.paymentform_networking.vpc_id
  subnet_ids                 = module.paymentform_networking.public_subnet_ids
  enable_deletion_protection = true
  standard_tags              = local.standard_tags
  alert_webhook_url          = var.alert_webhook_url
}

module "paymentform_client" {
  source = "../../providers/cloudflare/containers"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id

  container_name    = "client"
  container_image   = var.client_container_image
  container_enabled = false

  domain_name    = "app.paymentform.io"
  domain_proxied = true

  deployment_cpu       = "0.5"
  deployment_memory_mb = 512
  instance_min_count   = 1

  container_env_vars = {
    API_URL         = "https://api.paymentform.io"
    DOMAIN          = "https://app.paymentform.io"
    COOKIE_DOMAIN   = ".paymentform.io"
    FORM_RENDER_URL = "https://renderer.paymentform.io/"
    STRIPE_KEY      = var.stripe_public_key
    NODE_ENV        = "production"
  }

  registry_url      = "ghcr.io"
  registry_username = var.ghcr_username
  registry_password = var.ghcr_token
}

# =============================================================================
# Hetzner Networks (private networking per zone)
# =============================================================================
module "hetzner_network_eu" {
  source = "../../providers/hetzner/network"

  environment     = "prod"
  resource_prefix = "paymentform-p-eu"
  network_zone    = "eu-central"
  ip_range        = "10.10.0.0/16"
  subnet_ip_range = "10.10.1.0/24"
  standard_tags   = local.standard_tags
}

module "hetzner_network_ap" {
  source = "../../providers/hetzner/network"

  environment     = "prod"
  resource_prefix = "paymentform-p-sg"
  network_zone    = "ap-southeast"
  ip_range        = "10.20.0.0/16"
  subnet_ip_range = "10.20.1.0/24"
  standard_tags   = local.standard_tags
}

# =============================================================================
# Hetzner — EU (HEL1 Helsinki)
# =============================================================================
module "hetzner_backend_hel1" {
  source = "../../providers/hetzner/server"

  environment     = "prod"
  resource_prefix = "paymentform-p-eu"
  region          = "eu-hel1"
  location        = "hel1"
  server_type     = var.hetzner_server_type
  server_image    = "ubuntu-24.04"
  ssh_public_key  = var.hetzner_ssh_public_key
  ghcr_username   = var.ghcr_username
  ghcr_token      = var.ghcr_token
  container_image = var.backend_container_image
  service_type    = "backend"
  valkey_password = var.redis_password
  network_id      = tostring(module.hetzner_network_eu.network_id)

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = "12"

    LOG_CHANNEL              = "stack"
    LOG_STACK                = "single"
    LOG_DEPRECATIONS_CHANNEL = ""
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.hetzner_db_hel1.replica_endpoint
    DB_HOST_WRITE = module.postgres_database.primary_endpoint
    DB_HOST_READ  = module.hetzner_db_hel1.replica_endpoint
    DB_PORT       = "5432"
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = "120"
    SESSION_ENCRYPT  = "false"
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = ""

    BROADCAST_CONNECTION = "redis"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "redis"
    CACHE_STORE          = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = "127.0.0.1"
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = module.paymentform_storage_application.bucket_name
    AWS_USE_PATH_STYLE_ENDPOINT = "true"
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id

    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
  }

  standard_tags = local.standard_tags
}

module "hetzner_db_hel1" {
  source = "../../providers/hetzner/database"

  environment     = "prod"
  resource_prefix = "paymentform-p-eu"
  region          = "eu-hel1"
  location        = "hel1"
  server_type     = var.hetzner_db_server_type
  server_image    = "ubuntu-24.04"
  ssh_public_key  = var.hetzner_ssh_public_key
  volume_size_gb  = 30
  primary_host    = module.tunnel_db.tunnel_cname
  db_password     = var.db_password
  network_id      = tostring(module.hetzner_network_eu.network_id)
  standard_tags   = local.standard_tags
}

# =============================================================================
# Hetzner — Asia (SIN1 Singapore)
# =============================================================================
module "hetzner_backend_sin1" {
  source = "../../providers/hetzner/server"

  environment     = "prod"
  resource_prefix = "paymentform-p-sg"
  region          = "ap-sin1"
  location        = "sin1"
  server_type     = var.hetzner_server_type
  server_image    = "ubuntu-24.04"
  ssh_public_key  = var.hetzner_ssh_public_key
  ghcr_username   = var.ghcr_username
  ghcr_token      = var.ghcr_token
  container_image = var.backend_container_image
  service_type    = "backend"
  valkey_password = var.redis_password
  network_id      = tostring(module.hetzner_network_ap.network_id)

  container_env_vars = {
    APP_NAME          = "Payment Form"
    APP_ENV           = "production"
    APP_URL           = "https://api.paymentform.io"
    APP_BASE_DOMAIN   = "paymentform.io"
    APP_DOMAIN        = "api.paymentform.io"
    FRONTEND_URL      = "https://app.paymentform.io"
    FRONTEND_DASH_URL = "https://app.paymentform.io/myforms"
    APP_KEY           = var.app_key
    APP_DEBUG         = "false"

    APP_LOCALE          = "en"
    APP_FALLBACK_LOCALE = "en"

    BCRYPT_ROUNDS = "12"

    LOG_CHANNEL              = "stack"
    LOG_STACK                = "single"
    LOG_DEPRECATIONS_CHANNEL = ""
    LOG_LEVEL                = "error"

    DB_CONNECTION = "pgsql"
    DB_HOST       = module.hetzner_db_sin1.replica_endpoint
    DB_HOST_WRITE = module.postgres_database.primary_endpoint
    DB_HOST_READ  = module.hetzner_db_sin1.replica_endpoint
    DB_PORT       = "5432"
    DB_DATABASE   = var.db_database
    DB_USERNAME   = var.db_username
    DB_PASSWORD   = var.db_password

    TENANT_DB_SYNC_URL          = ""
    TENANT_DB_API_URL           = "https://api.turso.tech"
    TENANT_TURSO_ORG_SLUG       = var.turso_org_slug
    TENANT_TURSO_DEFAULT_REGION = "aws-ap-northeast-1"
    TENANT_DB_AUTH_TOKEN        = var.tenant_db_auth_token

    SESSION_DRIVER   = "redis"
    SESSION_LIFETIME = "120"
    SESSION_ENCRYPT  = "false"
    SESSION_PATH     = "/"
    SESSION_DOMAIN   = ""

    BROADCAST_CONNECTION = "redis"
    FILESYSTEM_DISK      = "local"
    QUEUE_CONNECTION     = "redis"
    CACHE_STORE          = "redis"

    REDIS_CLIENT   = "phpredis"
    REDIS_HOST     = "127.0.0.1"
    REDIS_PORT     = "6379"
    REDIS_PASSWORD = var.redis_password

    MAIL_MAILER       = "smtp"
    MAIL_HOST         = var.mail_host
    MAIL_USERNAME     = var.mail_username
    MAIL_PASSWORD     = var.mail_password
    MAIL_PORT         = "587"
    MAIL_FROM_ADDRESS = "hello@paymentform.io"
    MAIL_FROM_NAME    = "Payment Form"

    AWS_ACCESS_KEY_ID           = var.upload_storage_access_key_id
    AWS_SECRET_ACCESS_KEY       = var.upload_storage_secret_access_key
    AWS_DEFAULT_REGION          = local.region
    AWS_BUCKET                  = module.paymentform_storage_application.bucket_name
    AWS_USE_PATH_STYLE_ENDPOINT = "true"
    AWS_ENDPOINT                = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
    AWS_CLOUDFRONT_URL          = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"

    CORS_ALLOWED_ORIGINS = "https://app.paymentform.io"
    CORS_ALLOWED_METHODS = "POST, GET, OPTIONS, PUT, DELETE"
    CORS_ALLOWED_HEADERS = "Content-Type,X-Requested-With,Authorization,X-CSRF-Token, X-XSRF-TOKEN,Accept,Origin, X-Tenant"
    CORS_EXPOSED_HEADERS = "Content-Disposition"

    SANCTUM_STATEFUL_DOMAINS = ".paymentform.io"

    GOOGLE_CLIENT_ID     = var.google_client_id
    GOOGLE_CLIENT_SECRET = var.google_client_secret
    GOOGLE_REDIRECT_URI  = "https://api.paymentform.io/auth/google/callback"

    STRIPE_PUBLIC                 = var.stripe_public_key
    STRIPE_SECRET                 = var.stripe_secret
    STRIPE_CLIENT_ID              = var.stripe_client_id
    STRIPE_REDIRECT_URI           = "https://api.paymentform.io/stripe/callback"
    STRIPE_CONNECT_WEBHOOK_SECRET = var.stripe_connect_webhook_secret

    KV_STORE_API_URL      = module.paymentform_kv_store.kv_store_endpoint
    KV_STORE_API_TOKEN    = var.kv_store_api_token
    KV_STORE_NAMESPACE_ID = module.paymentform_kv_store.namespace_id

    SSL_STORAGE_BUCKET_NAME          = module.paymentform_storage_ssl_config.bucket_name
    SSL_STORAGE_BUCKET_HOST          = module.paymentform_storage_ssl_config.bucket_domain
    SSL_STORAGE_BUCKET_ACCESS_KEY_ID = var.ssl_storage_access_key_id
    SSL_STORAGE_BUCKET_ACCESS_KEY    = var.ssl_storage_secret_access_key
    CLOUDFLARE_API_TOKEN             = var.cloudflare_api_token_wildcard_dns
  }

  standard_tags = local.standard_tags
}

module "hetzner_db_sin1" {
  source = "../../providers/hetzner/database"

  environment     = "prod"
  resource_prefix = "paymentform-p-sg"
  region          = "ap-sin1"
  location        = "sin1"
  server_type     = var.hetzner_db_server_type
  server_image    = "ubuntu-24.04"
  ssh_public_key  = var.hetzner_ssh_public_key
  volume_size_gb  = 30
  primary_host    = module.tunnel_db.tunnel_cname
  db_password     = var.db_password
  network_id      = tostring(module.hetzner_network_ap.network_id)
  standard_tags   = local.standard_tags
}

module "paymenform_dns" {
  source = "../../providers/cloudflare/dns"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_api_email  = var.cloudflare_api_email
  cloudflare_zone_id    = var.cloudflare_zone_id
  cloudflare_account_id = var.cloudflare_account_id

  domain_name        = "paymentform.io"
  api_subdomain      = "api.paymentform.io"
  app_subdomain      = "app.paymentform.io"
  renderer_subdomain = "*.paymentform.io"

  api_cname                   = module.paymentform_nlb_backend.nlb_dns_name
  app_origin_ips              = []
  renderer_container_endpoint = module.paymentform_nlb_renderer.nlb_dns_name

  enable_geo_routing = true
  region_endpoints = {
    us = module.paymentform_nlb_backend.nlb_dns_name
    eu = module.hetzner_backend_hel1.ipv4_address
    sg = module.hetzner_backend_sin1.ipv4_address
  }

  cloudflare_plan      = "free"
  enable_load_balancer = false
  enable_waf           = false
  enable_rate_limiting = false
  rate_limit_requests  = 100
  health_check_path    = "/health"
  notification_email   = ""
}

# =============================================================================
# Status Page (Cloudflare Worker)
# =============================================================================
module "paymentform_status" {
  source = "../../providers/cloudflare/status"

  environment           = "prod"
  resource_prefix       = local.resource_prefix
  standard_tags         = local.standard_tags
  cloudflare_account_id = var.cloudflare_account_id
  cloudflare_api_token  = var.cloudflare_api_token
  cloudflare_zone_id    = var.cloudflare_zone_id
  domain_name           = "paymentform.io"
  status_subdomain      = "status"
  kv_namespace_id       = module.paymentform_kv_store.namespace_id

  services = [
    {
      name       = "API (Backend)"
      health_url = "https://api.paymentform.io/up"
    },
    {
      name       = "Renderer"
      health_url = "https://renderer.paymentform.io/api/health"
    },
    {
      name       = "Client"
      health_url = "https://app.paymentform.io/api/health"
    },
  ]
}
