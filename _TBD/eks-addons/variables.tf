variable "region" {
  description = "AWS region"
  type        = string
}

variable "state_bucket" {
  description = "S3 bucket containing remote state"
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
  description = "GitLab repository Name for ArgoCD"
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

variable "alb_wait_timeout" {
  description = "Seconds to wait for ALB creation"
  type        = number
  default     = 600
}

variable "alb_wait_interval" {
  description = "Polling interval seconds for ALB creation"
  type        = number
  default     = 5
}