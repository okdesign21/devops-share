data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/dev/network/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name       = "${var.project_name}-dev-eks"
  cluster_version    = var.cluster_version
  vpc_id             = local.vpc_id
  private_subnet_ids = local.private_subnet_ids

  desired_size            = var.desired_size
  min_size                = var.min_size
  max_size                = var.max_size
  node_instance_types     = var.node_instance_types
  endpoint_private_access = true
  endpoint_public_access  = true
  public_access_cidrs     = [var.home_ip, var.lab_ip]
  tags                    = var.tags
}

# Wire Kubernetes & Helm providers to the new cluster
data "aws_eks_cluster" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "this" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  token                  = data.aws_eks_cluster_auth.this.token
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
}

provider "helm" {
  kubernetes = {
    host                   = data.aws_eks_cluster.this.endpoint
    token                  = data.aws_eks_cluster_auth.this.token
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)
    load_config_file       = false
  }
}

# --- Argo CD install via Helm ---
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
    labels = {
      "app.kubernetes.io/name" = "argocd"
    }
  }
}

resource "helm_release" "argo_cd" {
  name       = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version

  # Minimal sane defaults; tweak as you like
  values = [
    yamlencode({
      server = {
        service = {
          type = "LoadBalancer"
        }
      }
      configs = {
        params = {
          "server.insecure" = true
        }
      }
    })
  ]

  # Wait until all resources are ready
  timeout = 600
  wait    = true

  depends_on = [module.eks]
}
