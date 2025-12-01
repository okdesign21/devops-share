variable "project_name" {
  description = "Project/cluster name prefix"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
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

variable "ubuntu_ami" {
  description = "SSM parameter name or AMI id to use for Ubuntu images (defult 24.04 LTS)"
  type        = string
  default     = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

variable "state_bucket" {
  description = "S3 bucket for remote state (provided via common.tfvars)"
  type        = string
}

variable "env" {
  type = string
}