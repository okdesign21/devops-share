variable "base_domain" {
  type = string
}

variable "env" {
  type = string
}

variable "zone_name" {
  description = "Base DNS zone"
  type        = string
}

variable "cloudflare_api_token" {
  description = "Cloudflare API token with DNS edit permissions"
  type        = string
  default     = ""
}

variable "region" {
  type    = string
  default = "eu-central-1"
}