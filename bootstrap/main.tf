# Bootstrap Terraform Configuration
# Creates AWS backend resources (S3 bucket and DynamoDB table)
# for remote state management and locking

terraform {
  required_version = ">= 1.8"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# S3 Bucket for Terraform State
resource "aws_s3_bucket" "terraform_state" {
  bucket = var.state_bucket_name

  tags = {
    Name        = var.state_bucket_name
    Purpose     = "terraform-state"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

# Enable versioning on state bucket
resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

# Enable server-side encryption on state bucket
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block all public access to state bucket
resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Enable logging on state bucket (optional)
resource "aws_s3_bucket_logging" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  target_bucket = aws_s3_bucket.terraform_logs.id
  target_prefix = "state-bucket-logs/"
}

# S3 Bucket for storing logs
resource "aws_s3_bucket" "terraform_logs" {
  bucket = "${var.state_bucket_name}-logs"

  tags = {
    Name        = "${var.state_bucket_name}-logs"
    Purpose     = "terraform-state-logs"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

# Block all public access to logs bucket
resource "aws_s3_bucket_public_access_block" "terraform_logs" {
  bucket = aws_s3_bucket.terraform_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB Table for Terraform State Locking
resource "aws_dynamodb_table" "terraform_locks" {
  name         = var.locks_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name        = var.locks_table_name
    Purpose     = "terraform-state-lock"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

# CloudTrail logging (optional - for audit trail of state changes)
resource "aws_cloudtrail" "terraform_state_audit" {
  count = var.enable_audit_logging ? 1 : 0

  name                          = "${var.state_bucket_name}-audit"
  s3_bucket_name                = aws_s3_bucket.terraform_logs.id
  include_global_service_events = true
  is_multi_region_trail         = true
  enable_log_file_validation    = true
  depends_on                    = [aws_s3_bucket_policy.terraform_audit_logs]

  tags = {
    Name        = "${var.state_bucket_name}-audit"
    Purpose     = "terraform-audit-trail"
    Environment = "shared"
    ManagedBy   = "terraform"
  }
}

# S3 bucket policy for CloudTrail
resource "aws_s3_bucket_policy" "terraform_audit_logs" {
  bucket = aws_s3_bucket.terraform_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AWSCloudTrailAclCheck"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:GetBucketAcl"
        Resource = aws_s3_bucket.terraform_logs.arn
      },
      {
        Sid    = "AWSCloudTrailWrite"
        Effect = "Allow"
        Principal = {
          Service = "cloudtrail.amazonaws.com"
        }
        Action   = "s3:PutObject"
        Resource = "${aws_s3_bucket.terraform_logs.arn}/*"
      }
    ]
  })
}
