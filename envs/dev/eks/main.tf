data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/dev/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "cicd" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/dev/cicd/terraform.tfstate"
    region = var.region
  }
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  zone_id            = data.terraform_remote_state.cicd.outputs.zone_id
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

data "aws_ssm_parameter" "argo_key" {
  name = "/cicd/argo_gitlab_private_key"
}

resource "kubernetes_secret" "argocd_gitlab_repo" {
  metadata {
    name      = "gitlab-argo-repo"
    namespace = "argocd"
    labels    = { "argocd.argoproj.io/secret-type" = "repository" }
  }

  data = {
    url           = var.gitlab_argo_repo
    sshPrivateKey = data.aws_ssm_parameter.argo_key.value
  }

  depends_on = [kubernetes_namespace.argocd]
}

# add cname record in cloudflare for app (weather app)
resource "cloudflare_record" "weather_app" {
  zone_id = local.zone_id
  name    = "dev-weather.${var.base_domain}"
  value   = module.eks.cluster_endpoint
  type    = "CNAME"
  ttl     = 300
}

resource "null_resource" "update_kubeconfig" {
  triggers = {
    cluster = module.eks.cluster_name
    region  = var.region
  }

  depends_on = [module.eks]

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${self.triggers.cluster} --region ${self.triggers.region}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
kubectl config delete-context ${self.triggers.cluster} || true
kubectl config delete-cluster ${self.triggers.cluster} || true
kubectl config unset users.${self.triggers.cluster}-aws || true
EOT
  }
}