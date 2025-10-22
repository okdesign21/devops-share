variable "name" {
  type = string
}

variable "ami_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "sg_ids" {
  type = list(string)
}

variable "key_name" {
  type    = string
  default = null
}

variable "instance_type" {
  type = string
}

variable "associate_public_ip" {
  type    = bool
  default = false
}

variable "user_data" {
  type    = string
  default = ""
}

variable "root_volume_size_gb" {
  type    = number
  default = 8
}

variable "enable_source_dest_check" {
  type    = bool
  default = true
}

variable "iam_instance_profile" {
  type    = string
  default = null
}

variable "env" {
  type        = string
  description = "Environment (dev/prod)"
}

variable "project_name" {
  type        = string
  description = "Project name"
}