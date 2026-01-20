# LocalStack-compatible version of the main Terraform configuration
# This version removes production-specific elements that won't work in LocalStack

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # For local development, use local file state instead of S3
  backend "local" {
    path = "./local/terraform.tfstate"
  }
}

# Provider configuration for LocalStack
provider "aws" {
  access_key                  = "test"
  secret_key                  = "test"
  region                      = "us-east-1"
  s3_force_path_style         = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_requesting_account_id  = true
  
  endpoints {
    apigateway     = "http://localhost:4566"
    apigatewayv2   = "http://localhost:4566"
    cloudformation = "http://localhost:4566"
    cloudwatch     = "http://localhost:4566"
    dynamodb       = "http://localhost:4566"
    es             = "http://localhost:4566"
    iam            = "http://localhost:4566"
    kinesis        = "http://localhost:4566"
    lambda         = "http://localhost:4566"
    route53        = "http://localhost:4566"
    redshift       = "http://localhost:4566"
    s3             = "http://localhost:4566"
    secretsmanager = "http://localhost:4566"
    ses            = "http://localhost:4566"
    sns            = "http://localhost:4566"
    sqs            = "http://localhost:4566"
    ssm            = "http://localhost:4566"
    stepfunctions  = "http://localhost:4566"
    sts            = "http://localhost:4566"
    ec2            = "http://localhost:4566"
    ecr            = "http://localhost:4566"
    ecs            = "http://localhost:4566"
    efs            = "http://localhost:4566"
    elb            = "http://localhost:4566"
    elbv2          = "http://localhost:4566"
    rds            = "http://localhost:4566"
    kms            = "http://localhost:4566"
    logs           = "http://localhost:4566"
  }

  default_tags {
    tags = {
      Project     = "paymentform-local"
      Environment = "local"
      ManagedBy   = "terraform-localstack"
    }
  }
}

# Simplified VPC for local testing
resource "aws_vpc" "local_backend" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "paymentform-local-backend-vpc"
    Environment = "local"
  }
}

resource "aws_subnet" "local_backend" {
  vpc_id            = aws_vpc.local_backend.id
  cidr_block        = "10.0.1.0/24"
  availability_zone = "us-east-1a"

  tags = {
    Name = "paymentform-local-backend-subnet"
    Environment = "local"
  }
}

# Local S3 bucket for storage
resource "aws_s3_bucket" "local_storage" {
  bucket = var.s3_bucket_name

  tags = {
    Name = var.s3_bucket_name
    Environment = "local"
  }
}

# Local RDS instance (simplified for LocalStack)
resource "aws_db_instance" "local_db" {
  identifier = "paymentform-local-db"
  
  allocated_storage    = 20
  storage_type         = "gp2"
  engine               = "postgres"
  engine_version       = "14.9"
  instance_class       = "db.t3.micro"
  db_name              = var.database_name
  username             = var.db_username
  password             = var.db_password
  parameter_group_name = "default.postgres14"
  
  db_subnet_group_name   = aws_db_subnet_group.local_db_subnet_group.name
  vpc_security_group_ids = [aws_security_group.local_db.id]
  
  skip_final_snapshot = true

  tags = {
    Name = "paymentform-local-db"
    Environment = "local"
  }
}

resource "aws_security_group" "local_db" {
  name_prefix = "paymentform-local-db-sg"
  description = "Security group for local database"
  vpc_id      = aws_vpc.local_backend.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paymentform-local-db-sg"
    Environment = "local"
  }
}

resource "aws_db_subnet_group" "local_db_subnet_group" {
  name       = "paymentform-local-db-subnet-group"
  subnet_ids = [aws_subnet.local_backend.id]

  tags = {
    Name = "paymentform-local-db-subnet-group"
    Environment = "local"
  }
}

# Local ALB for backend
resource "aws_lb" "local_backend" {
  name               = "paymentform-local-backend-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.local_alb.id]
  subnets            = [aws_subnet.local_backend.id]

  tags = {
    Name = "paymentform-local-backend-alb"
    Environment = "local"
  }
}

resource "aws_security_group" "local_alb" {
  name_prefix = "paymentform-local-alb-sg"
  description = "Security group for local ALB"
  vpc_id      = aws_vpc.local_backend.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "paymentform-local-alb-sg"
    Environment = "local"
  }
}

# Local target group and listener
resource "aws_lb_target_group" "local_backend" {
  name     = "paymentform-local-backend-tg"
  port     = 8000
  protocol = "HTTP"
  vpc_id   = aws_vpc.local_backend.id
  target_type = "ip"

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    path                = "/health"
    matcher             = "200"
  }

  tags = {
    Name = "paymentform-local-backend-tg"
    Environment = "local"
  }
}

resource "aws_lb_listener" "local_backend" {
  load_balancer_arn = aws_lb.local_backend.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Local backend placeholder - would connect to actual service in real deployment"
      status_code  = "200"
    }
  }
}

# Secrets manager equivalent for local
resource "aws_secretsmanager_secret" "local_app_key" {
  name = "paymentform/local/app-key"

  tags = {
    Environment = "local"
  }
}

resource "aws_secretsmanager_secret_version" "local_app_key" {
  secret_id     = aws_secretsmanager_secret.local_app_key.id
  secret_string = var.app_key
}

# Variables for local configuration
variable "database_name" {
  description = "Name of the database"
  type        = string
  default     = "shopper_backend_local"
}

variable "db_username" {
  description = "Database username"
  type        = string
  default     = "postgres"
}

variable "db_password" {
  description = "Database password"
  type        = string
  default     = "localpassword123"
  sensitive   = true
}

variable "app_key" {
  description = "Laravel application key"
  type        = string
  default     = "base64:abcdefghijklmnopqrstuvwxyz1234567890="
  sensitive   = true
}

variable "s3_bucket_name" {
  description = "Name for the S3 bucket"
  type        = string
  default     = "paymentform-local-storage"
}

# Outputs
output "local_db_endpoint" {
  description = "Endpoint for the local database"
  value       = aws_db_instance.local_db.endpoint
}

output "local_alb_dns" {
  description = "DNS name for the local ALB"
  value       = aws_lb.local_backend.dns_name
}

output "local_s3_bucket" {
  description = "Name of the local S3 bucket"
  value       = aws_s3_bucket.local_storage.bucket
}