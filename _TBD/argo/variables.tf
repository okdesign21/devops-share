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

variable "base_domain" {
  type        = string
  description = "Base domain for ArgoCD repository URL"
}

variable "gitlab_argo_repo" {
  type        = string
  description = "GitLab ArgoCD repository path (owner/repo.git)"
}

variable "repo_username" {
  type        = string
  description = "ArgoCD Git repository username"
  default     = "git"
}

variable "repo_password" {
  type        = string
  description = "ArgoCD Git repository password/token"
  sensitive   = true
}
