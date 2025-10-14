variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "state_bucket" {
  description = "Remote state S3 bucket"
  type        = string
}

variable "state_prefix" {
  description = "Remote state key prefix"
  type        = string
}

variable "project_name" {
  type = string
}

variable "jenkins_server_ami" {
  description = "AMI id for Jenkins server (ami-...) or empty to auto-select by tag 'type=jenkins'"
  type        = string
  default     = ""
}

variable "gitlab_ami" {
  description = "AMI id for GitLab server (ami-...) or empty to auto-select by tag 'type=gitlab'"
  type        = string
  default     = ""
}

variable "jenkins_server_instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t3.small"
}

variable "gitlab_server_instance_type" {
  description = "EC2 instance type for GitLab server"
  type        = string
  default     = "m7i-flex.large"
}

variable "jenkins_agent_instance_type" {
  description = "EC2 instance type for Jenkins agents"
  type        = string
  default     = "t3.small"
}

variable "jenkins_agent_volume_size_gb" {
  type    = number
  default = 8
}

variable "jenkins_server_volume_size_gb" {
  type    = number
  default = 8
}

variable "gitlab_volume_size_gb" {
  type    = number
  default = 20
}

variable "jenkins_agent_count" {
  type    = number
  default = 1
}

variable "ubuntu_ami" {
  description = "SSM parameter name for Ubuntu AMI (from common.tfvars) or empty"
  type        = string
  default     = ""
}

variable "ami_owner_ids" {
  description = "List of owner account IDs to filter AMI lookups (empty = no owner filter)."
  type        = list(string)
  default     = []
}

variable "zone_name" {
  description = "Base DNS zone"
  type        = string
}

variable "subdomain" {
  description = "Optional subdomain"
  type        = string
  default     = "infinity"
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  default     = ""
}