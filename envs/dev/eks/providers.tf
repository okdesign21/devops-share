terraform {
  backend "s3" {}
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.17"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.38.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0.2"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0.0"
    }
  }
}

provider "aws" {
  region = var.region
}

# Data sources for EKS cluster info
data "aws_eks_cluster" "this" {
  count = var.enable_eks_data_lookup ? 1 : 0
  name  = module.eks.cluster_name
}

data "aws_eks_cluster_auth" "this" {
  count = var.enable_eks_data_lookup ? 1 : 0
  name  = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = length(data.aws_eks_cluster.this) > 0 ? data.aws_eks_cluster.this[0].endpoint : ""
  cluster_ca_certificate = length(data.aws_eks_cluster.this) > 0 ? base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data) : ""
  token                  = length(data.aws_eks_cluster_auth.this) > 0 ? data.aws_eks_cluster_auth.this[0].token : ""
}

provider "helm" {
  kubernetes = {
    host                   = length(data.aws_eks_cluster.this) > 0 ? data.aws_eks_cluster.this[0].endpoint : ""
    cluster_ca_certificate = length(data.aws_eks_cluster.this) > 0 ? base64decode(data.aws_eks_cluster.this[0].certificate_authority[0].data) : ""
    token                  = length(data.aws_eks_cluster_auth.this) > 0 ? data.aws_eks_cluster_auth.this[0].token : ""
  }
}
