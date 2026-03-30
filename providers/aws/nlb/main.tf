terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  # AWS limits: NLB name ≤32 chars, target group name ≤32 chars.
  # Use a short env+label combo for TG names to stay well within limits.
  # e.g. environment="prod-us", service_label="bknd" → tg_prefix="prod-us-bknd"
  tg_prefix = "${var.environment}-${var.service_label}"
}

# Security Group for NLB
resource "aws_security_group" "nlb" {
  name_prefix = "${var.prefix}-nlb-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.prefix}-nlb-sg"
    }
  )
}

resource "aws_security_group_rule" "nlb_ingress_https" {
  type              = "ingress"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTPS from anywhere"
}

resource "aws_security_group_rule" "nlb_ingress_http" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow HTTP from anywhere"
}

resource "aws_security_group_rule" "nlb_egress_all" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.nlb.id
  description       = "Allow all outbound"
}

# NLB
resource "aws_lb" "main" {
  name               = "${var.prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.standard_tags,
    {
      Name = "${var.prefix}-nlb"
    }
  )
}

# Target Group - HTTPS (port 443) - TCP passthrough, Caddy handles TLS inside container
resource "aws_lb_target_group" "https" {
  name     = "${local.tg_prefix}-https-tg"
  port     = 443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    # Use HTTP/80 /health so the target is marked healthy as soon as Caddy is
    # serving HTTP — before the TLS cert is issued via DNS-01 challenge.
    # This prevents a chicken-and-egg deadlock where unhealthy targets block
    # the port 80 traffic that the ACME challenge needs.
    protocol            = "HTTP"
    port                = "80"
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.tg_prefix}-https-tg"
    }
  )
}

# Target Group - HTTP (port 80) - TCP passthrough
resource "aws_lb_target_group" "http" {
  name     = "${local.tg_prefix}-http-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
    protocol            = "HTTP"
    port                = "80"
    path                = "/health"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.tg_prefix}-http-tg"
    }
  )
}

# NLB Listener - TCP 443 → HTTPS target group
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.https.arn
  }
}

# NLB Listener - TCP 80 → HTTP target group
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.http.arn
  }
}
