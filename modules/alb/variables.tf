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
    path        = string
    port        = number
    health_path = string
    priority    = number
  }))
}

variable "enable_prometheus" {
  type    = bool
  default = false
}
