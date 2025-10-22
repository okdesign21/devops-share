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
  cluster_ca_data         = try(data.terraform_remote_state.eks.outputs.cluster_certificate_authority_data, "")
  cluster_oidc_issuer_url = try(data.terraform_remote_state.eks.outputs.cluster_oidc_issuer_url, "")
  oidc_provider_arn       = try(data.terraform_remote_state.eks.outputs.oidc_provider_arn, "")
}

data "aws_eks_cluster_auth" "this" {
  count = var.deploy_addons ? 1 : 0
  name  = local.cluster_name
}

provider "kubernetes" {
  host                   = var.deploy_addons ? local.cluster_endpoint : ""
  cluster_ca_certificate = var.deploy_addons ? base64decode(local.cluster_ca_data) : ""
  token                  = var.deploy_addons ? data.aws_eks_cluster_auth.this[0].token : ""
}

provider "helm" {
  kubernetes = {
    host                   = var.deploy_addons ? local.cluster_endpoint : ""
    cluster_ca_certificate = var.deploy_addons ? base64decode(local.cluster_ca_data) : ""
    token                  = var.deploy_addons ? data.aws_eks_cluster_auth.this[0].token : ""
  }
}
