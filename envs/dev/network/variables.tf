variable "project_name" {
  description = "Project/cluster name prefix"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "cidr_base" {
  description = "Base first octet identifying the environment"
  type        = number
  default     = 10
}

variable "nat_instance_type" {
  description = "EC2 instance type for NAT instance"
  type        = string
  default     = "t3.micro"
}

variable "nat_disk_size_gb" {
  description = "Root volume size for NAT instance in GB"
  type        = number
  default     = 8
}

variable "key_name" {
  description = "SSH key pair name"
  type        = string
  default     = null
}