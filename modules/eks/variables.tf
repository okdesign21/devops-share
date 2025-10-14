variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
}

variable "cluster_version" {
  description = "Kubernetes version"
  type        = string
  default     = "1.33"
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for EKS"
  type        = list(string)
}

variable "desired_size" {
  description = "Desired node count"
  type        = number
  default     = 2
}

variable "min_size" {
  description = "Min node count"
  type        = number
  default     = 2
}

variable "max_size" {
  description = "Max node count"
  type        = number
  default     = 4
}

variable "node_instance_types" {
  description = "Instance types for managed node group"
  type        = list(string)
  default     = ["m7i-flex.large"]
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default     = {}
}

variable "node_disk_size" {
  description = "EKS node disk size in GB"
  type        = number
  default     = 20
}

variable "endpoint_private_access" {
  description = "Whether to enable private access to the EKS endpoint"
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "List of CIDR blocks for public access to the EKS cluster"
  type        = list(string)
  default     = []
}

variable "endpoint_public_access" {
  description = "Whether to enable public access to the EKS endpoint"
  type        = bool
  default     = false
}
