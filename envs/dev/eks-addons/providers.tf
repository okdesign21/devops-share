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
  }
}

provider "aws" {
  region = var.region
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/eks/terraform.tfstate"
    region = var.region
  }
}

locals {
  cluster_name            = data.terraform_remote_state.eks.outputs.cluster_name
  cluster_endpoint        = data.terraform_remote_state.eks.outputs.cluster_endpoint
  cluster_ca_data         = data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data
  cluster_oidc_issuer_url = data.terraform_remote_state.eks.outputs.cluster_oidc_issuer_url
  oidc_provider_arn       = data.terraform_remote_state.eks.outputs.oidc_provider_arn
}

data "aws_eks_cluster_auth" "this" {
  name = local.cluster_name
}

provider "kubernetes" {
  host                   = local.cluster_endpoint
  cluster_ca_certificate = base64decode(local.cluster_ca_data)
  token                  = data.aws_eks_cluster_auth.this.token
}

provider "helm" {
  kubernetes = {
    host                   = local.cluster_endpoint
    cluster_ca_certificate = base64decode(local.cluster_ca_data)
    token                  = data.aws_eks_cluster_auth.this.token
  }
}
