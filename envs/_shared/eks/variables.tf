variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.34"
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
  default     = ["m7i-flex.large"]
}

variable "node_instance_size" {
  type    = number
  default = 20
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

# Infisical variables
variable "infisical_host" {
  type        = string
  description = "Infisical API host URL"
  default     = "https://eu.infisical.com"
}

variable "infisical_client_id" {
  type        = string
  description = "Infisical Machine Identity Client ID"
  sensitive   = true
  default     = ""
}

variable "infisical_client_secret" {
  type        = string
  description = "Infisical Machine Identity Client Secret"
  sensitive   = true
  default     = ""
}

variable "infisical_workspace_id" {
  type        = string
  description = "Infisical project/workspace ID"
  default     = ""
}

variable "enable_infisical" {
  type        = bool
  description = "Enable Infisical secret management integration"
  default     = true
}
