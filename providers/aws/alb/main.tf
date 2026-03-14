terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix = var.name
}

# Security Group for ALB
resource "aws_security_group" "alb" {
  name_prefix = "${local.prefix}-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-security-group"
    }
  )
}

resource "aws_security_group_rule" "alb_ingress_http" {
  count = var.enable_http_listener ? 1 : 0

  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTP from anywhere"
}

resource "aws_security_group_rule" "alb_ingress_https" {
  count = var.enable_https_listener ? 1 : 0

  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow HTTPS from anywhere"
}

resource "aws_security_group_rule" "alb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.alb.id
  description       = "Allow all outbound"
}

# ALB
resource "aws_lb" "main" {
  name               = "${local.prefix}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-alb"
    }
  )
}

# Target Group for Backend
resource "aws_lb_target_group" "backend" {
  name     = "${local.prefix}-backend-tg"
  port     = var.target_port
  protocol = var.ssl_certificate_arn != "" ? "HTTP" : "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = var.health_check_path
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-backend-target-group"
    }
  )
}

# ALB Listener - HTTP (port 80)
resource "aws_lb_listener" "http" {
  count = var.enable_http_listener ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# ALB Listener - HTTPS (port 443) for backend
resource "aws_lb_listener" "https" {
  count = var.enable_https_listener ? 1 : 0

  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.ssl_certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }
}

# Route HTTPS traffic to backend based on hostname (if api_hostname specified)
resource "aws_lb_listener_rule" "api_host_rule" {
  count = var.api_hostname != "" && var.enable_https_listener ? 1 : 0

  listener_arn = aws_lb_listener.https[0].arn
  priority     = 100

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.backend.arn
  }

  condition {
    host_header {
      values = [var.api_hostname]
    }
  }
}
