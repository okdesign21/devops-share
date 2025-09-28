variable "name" {
  description = "Base name/prefix (e.g., project_name)"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where the cluster will live"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for control plane and nodes"
  type        = list(string)
}

variable "cluster_version" {
  description = "EKS version (e.g., 1.33)."
  type        = string
  default     = "1.33"
}

# Node group variables
variable "node_instance_type" {
  description = "EC2 instance type for worker nodes"
  type        = string
  default     = "t3.small"
}

variable "node_desired_size" {
  description = "Desired number of worker nodes"
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Minimum number of worker nodes"
  type        = number
  default     = 2
}

variable "node_max_size" {
  description = "Maximum number of worker nodes"
  type        = number
  default     = 4
}

variable "node_capacity_type" {
  description = "Capacity type for worker nodes (ON_DEMAND or SPOT)"
  type        = string
  default     = "ON_DEMAND"
}

variable "tags" {
  description = "Common tags to apply"
  type        = map(string)
  default     = {}
}

# Node labels / taints as variables
variable "node_labels" {
  description = "Labels applied to the managed node group"
  type        = map(string)
  default     = { role = "general" }
}

# Additional IAM policies to attach to the node role
variable "node_iam_additional_policies" {
  description = "Map of name=>policy ARN to attach to node IAM role"
  type        = map(string)
  default = {
    ssm = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }
}

# Use an existing IAM role for the node group (prevents recreation)
# If provided, Terraform will NOT create a role and will use this ARN.
variable "node_iam_role_arn" {
  description = "Existing IAM role ARN for the managed node group (optional)"
  type        = string
  default     = null
}
