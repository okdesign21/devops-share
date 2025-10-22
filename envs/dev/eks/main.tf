data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/network/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  cluster_name       = "${var.project_name}-${var.env}-cluster"

  tags = {
    Environment = var.env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.4"

  name               = local.cluster_name
  kubernetes_version = var.cluster_version

  enable_irsa = true

  vpc_id                  = local.vpc_id
  subnet_ids              = local.private_subnet_ids
  endpoint_private_access = true
  endpoint_public_access  = true
  endpoint_public_access_cidrs = [
    var.home_ip,
    var.lab_ip,
  ]

  enable_cluster_creator_admin_permissions = true

  addons = {
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
  }

  eks_managed_node_groups = {
    main = {
      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      instance_types = var.node_instance_types
      capacity_type  = "ON_DEMAND"

      labels = {
        role = "general"
      }

      tags = local.tags
    }
  }

  tags = local.tags
}
