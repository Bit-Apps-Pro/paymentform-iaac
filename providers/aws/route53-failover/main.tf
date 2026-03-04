terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix = var.environment
}

# Health Check for Primary
resource "aws_route53_health_check" "primary" {
  fqdn              = var.primary_fqdn
  port              = var.health_check_port
  type              = var.health_check_type
  resource_path     = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-primary-health-check"
    }
  )
}

# Health Check for Secondary (DR)
resource "aws_route53_health_check" "secondary" {
  count             = var.enable_secondary_health_check ? 1 : 0
  fqdn              = var.secondary_fqdn
  port              = var.health_check_port
  type              = var.health_check_type
  resource_path     = var.health_check_path
  failure_threshold = var.failure_threshold
  request_interval  = var.request_interval

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-secondary-health-check"
    }
  )
}

# Primary Record (failover)
resource "aws_route53_record" "primary" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"

  failover_routing_policy {
    type = "PRIMARY"
  }

  set_identifier  = "primary"
  health_check_id = aws_route53_health_check.primary.id

  alias {
    name                   = var.primary_alb_dns_name
    zone_id                = var.primary_alb_zone_id
    evaluate_target_health = true
  }
}

# Secondary Record (failover)
resource "aws_route53_record" "secondary" {
  zone_id = var.zone_id
  name    = var.record_name
  type    = "A"

  failover_routing_policy {
    type = "SECONDARY"
  }

  set_identifier  = "secondary"
  health_check_id = var.enable_secondary_health_check ? aws_route53_health_check.secondary[0].id : null

  alias {
    name                   = var.secondary_alb_dns_name
    zone_id                = var.secondary_alb_zone_id
    evaluate_target_health = var.enable_secondary_health_check ? false : true
  }
}
