variable "region" {
  description = "AWS region"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket containing remote state"
  type        = string
}

variable "state_prefix" {
  description = "Prefix within the state bucket"
  type        = string
}

variable "env" {
  description = "Environment name"
  type        = string
}

variable "project_name" {
  description = "Project name"
  type        = string
}

variable "base_domain" {
  description = "Base domain for rendered templates"
  type        = string
}

variable "gitlab_argo_repo" {
  description = "GitLab repository URL for ArgoCD"
  type        = string
}

variable "gitlab_argo_token" {
  description = "GitLab token for ArgoCD"
  type        = string
  sensitive   = true
}

variable "argocd_chart_version" {
  description = "ArgoCD Helm chart version"
  type        = string
  default     = "7.6.12"
}

variable "cluster_alb_name" {
  description = "Optional shared ALB name for ownership manifest"
  type        = string
  default     = ""
}

variable "deploy_addons" {
  description = "Set true to deploy Helm/Kubernetes add-ons once the cluster exists"
  type        = bool
  default     = false
}
