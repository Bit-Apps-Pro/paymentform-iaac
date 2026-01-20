# Main Terraform configuration to tie all regions together

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "paymentform-main-state"
    key            = "main/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "paymentform-terraform-lock"
    encrypt        = true
  }
}

# Provider configurations for each region
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

provider "aws" {
  alias  = "eu_west_1"
  region = "eu-west-1"
}

provider "aws" {
  alias  = "ap_southeast_1"
  region = "ap-southeast-1"
}

# Module calls for each region
module "backend_infrastructure" {
  source = "./backend/us-east-1"

  providers = {
    aws = aws.us_east_1
  }

  # Pass required variables
  primary_db_endpoint    = module.database_cluster.cluster_endpoint
  db_username           = var.db_username
  db_password           = var.db_password
  s3_bucket_name        = module.storage_bucket.bucket_id
  ssl_certificate_arn   = module.global_networking.backend_ssl_cert_arn
  app_key_secret_arn    = aws_secretsmanager_secret.app_key.arn
}

module "client_infrastructure" {
  source = "./client/eu-west-1"

  providers = {
    aws = aws.eu_west_1
  }

  # Pass required variables
  api_url              = "https://api.${var.domain_name}"
  frontend_domain      = "https://app.${var.domain_name}"
  ssl_certificate_arn = module.global_networking.client_ssl_cert_arn
}

module "renderer_infrastructure" {
  source = "./renderer/ap-southeast-1"

  providers = {
    aws = aws.ap_southeast_1
  }

  # Pass required variables
  api_url              = "https://api.${var.domain_name}"
  frontend_domain      = "https://renderer.${var.domain_name}"
  allow_origin_hosts   = var.allow_origin_hosts
  ssl_certificate_arn = module.global_networking.renderer_ssl_cert_arn
}

module "database_cluster" {
  source = "./databases/primary"

  providers = {
    aws = aws.us_east_1
  }

  cluster_identifier = "paymentform-primary-db"
  master_username   = var.db_username
  master_password   = var.db_password
  vpc_id            = module.backend_infrastructure.vpc_id
  subnet_ids        = module.backend_infrastructure.private_subnets
  security_group_ids = [module.database_security_group.security_group_id]
}

module "database_security_group" {
  source = "./modules/security-group"

  providers = {
    aws = aws.us_east_1
  }

  name        = "database-sg"
  description = "Security group for database access"
  vpc_id      = module.backend_infrastructure.vpc_id
  inbound_rules = [
    {
      from_port   = 5432
      to_port     = 5432
      protocol    = "tcp"
      cidr_blocks = [module.backend_infrastructure.vpc_cidr]
    }
  ]
}

module "storage_bucket" {
  source = "./modules/s3-bucket"

  providers = {
    aws = aws.us_east_1
  }

  bucket_name   = var.s3_bucket_name
  region        = "us-east-1"
  environment   = var.environment
}

module "global_networking" {
  source = "./networking/global"

  providers = {
    aws = aws.us_east_1
  }

  domain_name                = var.domain_name
  backend_load_balancer_dns  = module.backend_infrastructure.lb_dns_name
  client_load_balancer_dns   = module.client_infrastructure.lb_dns_name
  renderer_load_balancer_dns = module.renderer_infrastructure.lb_dns_name
}

# Secrets for application configuration
resource "aws_secretsmanager_secret" "app_key" {
  name = "paymentform/${var.environment}/app-key"

  tags = {
    Environment = var.environment
  }
}

resource "aws_secretsmanager_secret_version" "app_key" {
  secret_id     = aws_secretsmanager_secret.app_key.id
  secret_string = var.app_key
}

# Variables
variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Primary domain name for the application"
  type        = string
}

variable "db_username" {
  description = "Database username"
  type        = string
}

variable "db_password" {
  description = "Database password"
  type        = string
  sensitive   = true
}

variable "app_key" {
  description = "Laravel application key"
  type        = string
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket"
  type        = string
}

variable "allow_origin_hosts" {
  description = "Allowed origin hosts for CORS"
  type        = string
  default     = "renderer.paymentform.btcd-test.io,*.renderer.paymentform.btcd-test.io"
}

# Outputs
output "backend_api_url" {
  description = "URL for the backend API"
  value       = "https://api.${var.domain_name}"
}

output "client_dashboard_url" {
  description = "URL for the client dashboard"
  value       = "https://app.${var.domain_name}"
}

output "renderer_url" {
  description = "URL for the renderer"
  value       = "https://renderer.${var.domain_name}"
}

output "database_endpoint" {
  description = "Primary database endpoint"
  value       = module.database_cluster.cluster_endpoint
}