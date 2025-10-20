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
  default     = ["t3.small", "m7i-flex.large"]
}

variable "gitlab_argo_repo" {
  type        = string
  description = "GitLab repository URL for ArgoCD"
}

variable "gitlab_argo_token" {
  type        = string
  description = "GitLab access token for ArgoCD"
  sensitive   = true
}

variable "argocd_chart_version" {
  type        = string
  description = "ArgoCD Helm chart version"
  default     = "7.6.12"
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

variable "state_prefix" {
  type        = string
  description = "State prefix path"
}

variable "home_ip" {
  type        = string
  description = "Home IP for API access"
}

variable "lab_ip" {
  type        = string
  description = "Lab IP for API access"
}

variable "base_domain" {
  type        = string
  description = "Base domain"
}

variable "create_oidc_provider" {
  description = "Create OIDC provider in this stack. Set to false if provider already exists."
  type        = bool
  default     = true
}

variable "cluster_alb_name" {
  description = "Optional explicit name for the shared ALB. If empty, skip AWS LB lookup."
  type        = string
  default     = ""
}

variable "enable_eks_data_lookup" {
  description = "Enable data.aws_eks_cluster lookups (set true after cluster exists)."
  type        = bool
  default     = false
}