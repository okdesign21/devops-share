locals {
  name = var.cluster_name
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.name
  cluster_version = var.cluster_version

  vpc_id                                   = var.vpc_id
  subnet_ids                               = var.private_subnet_ids
  cluster_endpoint_private_access          = var.endpoint_private_access
  cluster_endpoint_public_access_cidrs     = var.public_access_cidrs
  cluster_endpoint_public_access           = var.endpoint_public_access
  enable_cluster_creator_admin_permissions = true

  # Core addons (managed by AWS)
  cluster_addons = {
    coredns    = { most_recent = true }
    kube-proxy = { most_recent = true }
    vpc-cni    = { most_recent = true }
  }

  # One default managed node group across private subnets
  eks_managed_node_groups = {
    default = {
      ami_type               = "BOTTLEROCKET_x86_64"
      instance_types         = var.node_instance_types
      min_size               = var.min_size
      max_size               = var.max_size
      desired_size           = var.desired_size
      subnet_ids             = var.private_subnet_ids
      capacity_type          = "ON_DEMAND"
      disk_size              = var.node_disk_size
      create_launch_template = true
      launch_template_tags   = var.tags
      tags                   = var.tags
    }
  }

  tags = var.tags
}