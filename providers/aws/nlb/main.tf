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

# Security Group for NLB
resource "aws_security_group" "nlb" {
  name_prefix = "${local.prefix}-nlb-sg"
  vpc_id      = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-nlb-security-group"
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
  name               = "${local.prefix}-nlb"
  internal           = false
  load_balancer_type = "network"
  security_groups    = [aws_security_group.nlb.id]
  subnets            = var.subnet_ids

  enable_deletion_protection = var.enable_deletion_protection

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-nlb"
    }
  )
}

# Target Group for Renderer (HTTPS - port 443)
resource "aws_lb_target_group" "renderer_https" {
  name     = "${local.prefix}-rndrs-tg"
  port     = 443
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    port                = "443"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-rndr-s-tg"
    }
  )
}

# Target Group for Renderer (HTTP - port 80)
resource "aws_lb_target_group" "renderer_http" {
  name     = "${local.prefix}-rndr-tg"
  port     = 80
  protocol = "TCP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 10
    interval            = 30
    port                = "80"
    matcher             = "200"
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-rndr-tg"
    }
  )
}

# NLB Listener - TCP 443 (HTTPS passthrough)
resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.main.arn
  port              = "443"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.renderer_https.arn
  }
}

# NLB Listener - TCP 80 (HTTP passthrough)
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.renderer_http.arn
  }
}
