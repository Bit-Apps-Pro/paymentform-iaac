variable "environment" {
  description = "Environment name (dev, sandbox, prod)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID of the requester"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block of the requester VPC"
  type        = string
}

variable "peer_vpc_id" {
  description = "VPC ID of the peer (accepter)"
  type        = string
}

variable "peer_vpc_cidr" {
  description = "CIDR block of the peer VPC"
  type        = string
}

variable "peer_region" {
  description = "Region of the peer VPC"
  type        = string
}

variable "peer_account_id" {
  description = "Account ID of the peer VPC"
  type        = string
}

variable "requester_route_table_id" {
  description = "Route table ID in requester VPC to add route to peer"
  type        = string
}

variable "accepter_route_table_id" {
  description = "Route table ID in accepter VPC to add route to requester (optional)"
  type        = string
  default     = ""
}

variable "auto_accept" {
  description = "Auto accept the peering connection"
  type        = bool
  default     = true
}

variable "standard_tags" {
  description = "Standard tags to apply to all resources"
  type        = map(string)
  default     = {}
}
