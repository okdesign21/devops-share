variable "region" {
  type        = string
  description = "AWS region"
  default     = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = ""
}

variable "cluster_version" {
  type        = string
  description = "Kubernetes version"
  default     = "1.33"
}

variable "desired_size" {
  type    = number
  default = 2
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "node_instance_types" {
  type    = list(string)
  default = ["m7i-flex.large"]
}

# Helm chart versions (pin for reproducibility)
variable "argocd_chart_version" {
  type    = string
  default = "6.7.17"
}

variable "tags" {
  description = "A map of tags to assign to resources."
  type        = map(string)
  default     = {}
}

variable "ubuntu_ami" {
  description = "SSM parameter or AMI id for ubuntu fallback (provided via common.tfvars)"
  type        = string
  default     = ""
}

variable "state_bucket" {
  description = "State bucket name (present in common.tfvars)"
  type        = string
  default     = ""
}

variable "state_prefix" {
  description = "State prefix (present in common.tfvars)"
  type        = string
  default     = ""
}