variable "project_name" {
  description = "Project/cluster name prefix"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "app_count" {
  type    = number
  default = 2
}

variable "app_instance_type" {
  type    = string
  default = "t3.micro"
}

variable "app_disk_size_gb" {
  type    = number
  default = 8
}

variable "state_bucket" {
  description = "S3 bucket for terraform remote state"
  type        = string
}

variable "ubuntu_ami" {
  description = "SSM parameter name or AMI id for Ubuntu (provided via common.tfvars)"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}