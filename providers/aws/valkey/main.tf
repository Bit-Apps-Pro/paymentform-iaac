terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix     = var.environment
  node_count = var.node_count
}

# EC2 Instances for Valkey Cluster
resource "aws_instance" "valkey" {
  count         = local.node_count
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_ids[count.index]

  vpc_security_group_ids = [
    var.security_group_id
  ]

  root_block_device {
    volume_size = var.volume_size
    volume_type = var.volume_type
    encrypted   = true
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-valkey-${count.index + 1}"
      Role = "valkey-node"
    }
  )

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    environment      = var.environment
    node_index       = count.index + 1
    cluster_password = var.cluster_password
    memory_max       = var.memory_max
  }))
}

# IAM Role for EC2
resource "aws_iam_role" "valkey_role" {
  name = "${local.prefix}-valkey-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_instance_profile" "valkey_profile" {
  name = "${local.prefix}-valkey-profile"
  role = aws_iam_role.valkey_role.name
}
