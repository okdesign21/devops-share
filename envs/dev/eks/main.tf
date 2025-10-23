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

# EKS cluster
resource "aws_eks_cluster" "main" {
  name     = local.cluster_name
  version  = var.cluster_version
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    subnet_ids              = local.private_subnet_ids
    endpoint_private_access = true
    endpoint_public_access  = true
    public_access_cidrs     = [var.home_ip, var.lab_ip]
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  tags = merge(local.tags, { Name = local.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.cluster_vpc_resource_controller
  ]
}

# Cluster IAM role
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project_name}-${var.env}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "cluster_vpc_resource_controller" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# OIDC provider for IRSA
data "tls_certificate" "cluster" {
  url = aws_eks_cluster.main.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster.certificates[0].sha1_fingerprint]
  url             = aws_eks_cluster.main.identity[0].oidc[0].issuer

  tags = merge(local.tags, { Name = "${local.cluster_name}-oidc" })
}

# Node IAM role and profile
data "aws_iam_policy" "eks_worker_node" {
  arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

data "aws_iam_policy" "eks_cni" {
  arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

data "aws_iam_policy" "ecr_read" {
  arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project_name}-${var.env}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json
  tags               = local.tags
}

resource "aws_iam_role_policy_attachment" "node_worker_attach" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.eks_worker_node.arn
}

resource "aws_iam_role_policy_attachment" "node_cni_attach" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.eks_cni.arn
}

resource "aws_iam_role_policy_attachment" "node_ecr_attach" {
  role       = aws_iam_role.node.name
  policy_arn = data.aws_iam_policy.ecr_read.arn
}

resource "aws_iam_instance_profile" "node_profile" {
  name = "${var.project_name}-${var.env}-eks-node-profile"
  role = aws_iam_role.node.name
}

# Managed node group
resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${local.cluster_name}-main"
  node_role_arn   = aws_iam_role.node.arn
  subnet_ids      = local.private_subnet_ids
  version         = var.cluster_version

  scaling_config {
    desired_size = var.desired_size
    min_size     = var.min_size
    max_size     = var.max_size
  }

  update_config {
    max_unavailable = 1
  }

  instance_types = var.node_instance_types
  capacity_type  = "ON_DEMAND"

  disk_size = var.node_instance_size

  labels = {
    role = "general"
  }

  tags = merge(local.tags, { Name = "${local.cluster_name}-main" })

  lifecycle {
    create_before_destroy = true
    ignore_changes        = [scaling_config[0].desired_size]
  }

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.node_worker_attach,
    aws_iam_role_policy_attachment.node_cni_attach,
    aws_iam_role_policy_attachment.node_ecr_attach
  ]
}

# Add-ons
resource "aws_eks_addon" "vpc_cni" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "vpc-cni"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags

  depends_on = [
    aws_eks_cluster.main,
    aws_iam_role_policy_attachment.node_cni_attach
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags

  depends_on = [aws_eks_addon.vpc_cni]
}

resource "aws_eks_addon" "coredns" {
  cluster_name                = aws_eks_cluster.main.name
  addon_name                  = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "PRESERVE"
  tags                        = local.tags

  depends_on = [
    aws_eks_node_group.main,
    aws_eks_addon.vpc_cni
  ]
}

locals {
  all_subnet_ids = concat(
    data.terraform_remote_state.network.outputs.public_subnet_ids,
    data.terraform_remote_state.network.outputs.private_subnet_ids
  )
}

# Tag all subnets for cluster discovery
resource "aws_ec2_tag" "cluster_subnets" {
  for_each = toset(local.all_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/cluster/${aws_eks_cluster.main.name}"
  value       = "shared"
}

# Tag only public subnets for internet-facing ALBs
resource "aws_ec2_tag" "public_elb" {
  for_each = toset(data.terraform_remote_state.network.outputs.public_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

# Tag only private subnets for internal ALBs
resource "aws_ec2_tag" "private_elb" {
  for_each = toset(data.terraform_remote_state.network.outputs.private_subnet_ids)

  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}