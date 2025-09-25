variable "vpc_id" {
  type = string
}

variable "allowed_nat_ingress_cidr" {
  description = "CIDR allowed to reach the NAT (typically the VPC CIDR)"
  type        = string
}

