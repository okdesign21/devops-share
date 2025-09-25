variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "smart-pipeline"
}

variable "nat_instance_type" {
  type    = string
  default = "t3.nano"
}

variable "nat_disk_size_gb" {
  type    = number
  default = 8
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

variable "jenkins_controller_type" {
  type    = string
  default = "t3.medium"
}

variable "jenkins_controller_disk" {
  type    = number
  default = 8
}

variable "jenkins_agent_type" {
  type    = string
  default = "t3.small"
}

variable "jenkins_agent_disk" {
  type    = number
  default = 8
}

variable "gitlab_type" {
  type    = string
  default = "t3.large"
}

variable "gitlab_disk" {
  type    = number
  default = 20
}

variable "prometheus_type" {
  type    = string
  default = "t3.small"
}

variable "prometheus_disk" {
  type    = number
  default = 8
}

variable "enable_prometheus" {
  type    = bool
  default = false
}

variable "key_name" {
  description = "If null/empty, Terraform generates a new key pair"
  type        = string
  default     = null
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_cidrs" {
  description = "Public subnet CIDRs, one per AZ"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.3.0/24"]
}

variable "private_cidrs" {
  description = "Private subnet CIDRs, one per AZ"
  type        = list(string)
  default     = ["10.0.2.0/24", "10.0.4.0/24"]
}
