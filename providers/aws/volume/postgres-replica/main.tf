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

resource "aws_ebs_volume" "this" {
  availability_zone = var.availability_zone
  size              = var.size
  type              = var.volume_type
  encrypted         = var.encrypted
  iops              = var.iops
  throughput        = var.throughput

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-${var.name}"
    }
  )

  lifecycle {
    prevent_destroy = true # HARDCODED for data protection
  }
}

resource "aws_volume_attachment" "this" {
  count       = var.instance_id != "" ? 1 : 0
  device_name = var.device_name
  volume_id   = aws_ebs_volume.this.id
  instance_id = var.instance_id
}
