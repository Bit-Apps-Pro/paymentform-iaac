terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

locals {
  prefix = "${var.environment}-peering"
}

# VPC Peering Connection
resource "aws_vpc_peering_connection" "main" {
  peer_vpc_id   = var.peer_vpc_id
  peer_region   = var.peer_region
  peer_owner_id = var.peer_account_id
  vpc_id        = var.vpc_id

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-connection"
    }
  )
}

# Accept VPC Peering Connection (if this is the accepter)
resource "aws_vpc_peering_connection_accepter" "main" {
  count                     = var.auto_accept ? 1 : 0
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id

  tags = merge(
    var.standard_tags,
    {
      Name = "${local.prefix}-accepter"
    }
  )
}

# Route table updates for requester VPC
resource "aws_route" "requester_to_peer" {
  route_table_id            = var.requester_route_table_id
  destination_cidr_block    = var.peer_vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}

# Route table updates for accepter VPC (if auto_accept is true)
resource "aws_route" "accepter_to_requester" {
  count                     = var.auto_accept && var.accepter_route_table_id != "" ? 1 : 0
  route_table_id            = var.accepter_route_table_id
  destination_cidr_block    = var.vpc_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.main.id
}
