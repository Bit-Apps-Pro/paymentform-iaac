terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix     = var.name
  node_count = var.node_count

  # Cluster mode requires >= 3 nodes. A single node runs standalone.
  cluster_mode = local.node_count >= 3

  # Replicas per primary shard.
  # node_count >= 6 → 1 replica per primary (3 primaries + 3 replicas).
  # node_count 3–5  → 0 replicas (all primaries, no HA replicas).
  cluster_replicas = local.cluster_mode && local.node_count >= 6 ? 1 : 0
}

# EC2 Instances for Valkey
resource "aws_instance" "valkey" {
  count         = local.node_count
  ami           = var.ami_id
  instance_type = var.instance_type
  subnet_id     = var.subnet_ids[count.index % length(var.subnet_ids)]

  vpc_security_group_ids = [var.security_group_id]
  iam_instance_profile   = aws_iam_instance_profile.valkey_profile.name

  root_block_device {
    volume_size = var.volume_size
    volume_type = var.volume_type
    encrypted   = true
  }

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-valkey-${count.index + 1}"
      Role = local.cluster_mode ? "valkey-cluster-node" : "valkey-standalone"
    }
  )

  user_data = base64encode(templatefile("${path.module}/userdata.sh", {
    environment      = var.environment
    node_index       = count.index + 1
    cluster_password = var.cluster_password
    memory_max       = var.memory_max
    cluster_mode     = local.cluster_mode
    cluster_replicas = local.cluster_replicas
  }))
}

# ── Cluster initialisation (cluster mode only) ─────────────────────────────
# After all EC2 instances are up and Valkey is running, node 1 is instructed
# via SSM Run Command to form the cluster using the private IPs of all nodes.
# This sidesteps the chicken-and-egg problem of needing IPs inside user_data.
resource "null_resource" "cluster_init" {
  count = local.cluster_mode ? 1 : 0

  # Re-run if any node is replaced
  triggers = {
    instance_ids = join(",", aws_instance.valkey[*].id)
  }

  depends_on = [aws_instance.valkey]

  provisioner "local-exec" {
    command = <<-EOT
      set -e

      ALL_IPS="${join(" ", aws_instance.valkey[*].private_ip)}"
      CLUSTER_ARGS=$(echo $ALL_IPS | tr ' ' '\n' | sed 's/$/:6379/' | tr '\n' ' ')
      NODE1_ID="${aws_instance.valkey[0].id}"
      REGION="${var.region}"
      PASSWORD="${var.cluster_password}"

      echo "Waiting 90s for Valkey to start on all nodes..."
      sleep 90

      echo "Sending CLUSTER CREATE command via SSM to node 1 ($NODE1_ID)..."

      aws ssm send-command \
        --region "$REGION" \
        --instance-ids "$NODE1_ID" \
        --document-name "AWS-RunShellScript" \
        --parameters "commands=[\"valkey-cli -a '$PASSWORD' --no-auth-warning --cluster create $CLUSTER_ARGS --cluster-replicas ${local.cluster_replicas} --cluster-yes\"]" \
        --output text \
        --query "Command.CommandId"
    EOT
  }
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

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.valkey_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
