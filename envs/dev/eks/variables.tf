variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.33"
}

variable "min_size" {
  type        = number
  description = "Minimum number of nodes"
  default     = 2
}

variable "max_size" {
  type        = number
  description = "Maximum number of nodes"
  default     = 4
}

variable "desired_size" {
  type        = number
  description = "Desired number of nodes"
  default     = 2
}

variable "node_instance_types" {
  type        = list(string)
  description = "EC2 instance types for nodes"
  default     = ["t3.small", "m7i-flex.large"]
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "project_name" {
  type        = string
  description = "Project name"
}

variable "env" {
  type        = string
  description = "Environment (dev/prod)"
}

variable "state_bucket" {
  type        = string
  description = "S3 bucket for Terraform state"
}

variable "home_ip" {
  type        = string
  description = "Home IP for API access"
}

variable "lab_ip" {
  type        = string
  description = "Lab IP for API access"
}
