variable "name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnets" {
  type = list(string)
}

variable "security_group_id" {
  type = string
}

variable "default_tg_name" {
  type    = string
  default = null
}

variable "routes" {
  type = list(object({
    name        = string
    header      = optional(string)      # Single header (deprecated, use headers)
    headers     = optional(list(string)) # Multiple headers
    port        = number
    health_path = string
    priority    = number
  }))
  description = "List of routing rules. Use 'headers' for multiple host headers or 'header' for single header."
}

variable "enable_prometheus" {
  type    = bool
  default = false
}
