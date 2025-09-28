locals {
  cluster_name = "${var.name}-eks"
}

module "eks_core" {
  source             = "terraform-aws-modules/eks/aws"
  version            = "21.3.1"
  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  vpc_id                   = var.vpc_id
  subnet_ids               = var.private_subnet_ids
  control_plane_subnet_ids = var.private_subnet_ids

  endpoint_private_access = true
  endpoint_public_access  = false

  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  create_security_group      = true
  create_node_security_group = true
  create_kms_key             = true
  #cluster_encryption_config  = []

  addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = { before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      name           = "${local.cluster_name}-mng"
      instance_types = [var.node_instance_type]
      desired_size   = var.node_desired_size
      min_size       = var.node_min_size
      max_size       = var.node_max_size
      capacity_type  = var.node_capacity_type
      subnet_ids     = var.private_subnet_ids

      create_iam_role = var.node_iam_role_arn == null ? true : false
      iam_role_arn    = var.node_iam_role_arn

      iam_role_additional_policies = var.node_iam_additional_policies
      labels                       = var.node_labels
    }
  }

  tags = merge({ Project = var.name, Stack = "eks" }, var.tags)
}
