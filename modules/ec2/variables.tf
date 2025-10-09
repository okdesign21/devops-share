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
  type    = list(string)
  default = []
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
  description = "Override root EBS size in GB. 0 => use AMI snapshot default (if EBS-backed). For instance-store, >0 requires root_snapshot_id to create EBS root."
  type        = number
  default     = 0
}

variable "root_snapshot_id" {
  description = "Optional snapshot id used to create an EBS root when AMI is instance-store and root_volume_size_gb > 0."
  type        = string
  default     = ""
}

variable "create_data_volume" {
  description = "When true, create and attach an additional EBS volume for data (useful with instance-store AMIs)."
  type        = bool
  default     = false
}

variable "data_volume_size_gb" {
  description = "Size for the additional data volume (only used if create_data_volume = true)."
  type        = number
  default     = 20
}

variable "data_device_name" {
  description = "Device name to attach additional data volume (example: /dev/sdf)."
  type        = string
  default     = "/dev/sdf"
}

variable "root_volume_type" {
  description = "Volume type used when overriding root volume (gp3/gp2/io1 etc)."
  type        = string
  default     = "gp3"
}

variable "enable_source_dest_check" {
  type    = bool
  default = true
}

variable "iam_instance_profile" {
  type    = string
  default = null
}

variable "tags" {
  description = "Additional tags to apply to the instance"
  type        = map(string)
  default     = {}
}