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

variable "routes" {
  description = "Path-based routes to backend ports"
  type = list(object({
    name        = string
    path        = string
    port        = number
    health_path = string
  }))
}

variable "enable_prometheus" {
  type    = bool
  default = false
}
