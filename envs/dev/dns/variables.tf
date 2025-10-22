variable "state_bucket" {
  type        = string
  description = "S3 bucket for remote state"
}

variable "region" {
  type        = string
  description = "AWS region"
}

variable "env" {
  type        = string
  description = "Environment name"
}

variable "base_domain" {
  type        = string
  description = "domain name"
}

variable "zone_name" {
  type        = string
  description = "Base DNS zone (Cloudflare)"
}

variable "cloudflare_api_token" {
  type        = string
  description = "Cloudflare API token (optional; will fallback to CLOUDFLARE_API_TOKEN env var)"
  default     = ""
}

variable "project_name" {
  type        = string
  description = "Project name"
}