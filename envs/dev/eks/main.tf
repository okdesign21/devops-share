data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/${var.env}/network/terraform.tfstate"
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

# --- OIDC Provider for IRSA ---
data "tls_certificate" "eks_oidc" {
  url = module.eks.cluster_oidc_issuer_url
}

resource "aws_iam_openid_connect_provider" "eks" {
  count = (var.create_oidc_provider && var.enable_eks_data_lookup) ? 1 : 0

  url             = data.aws_eks_cluster.this[0].identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc.certificates[0].sha1_fingerprint]
}

locals {
  oidc_provider_arn = coalesce(
    module.eks.oidc_provider_arn,
    try(aws_iam_openid_connect_provider.eks[0].arn, "")
  )
}

# --- AWS Load Balancer Controller IAM Policy ---
data "aws_caller_identity" "current" {}

resource "aws_iam_policy" "alb_controller" {
  name        = "AWSLoadBalancerControllerIAMPolicy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"

  # load policy JSON from external file
  policy = file("${path.module}/iam-policy-alb.json")

  tags = local.tags
}

resource "aws_iam_role" "alb_controller" {
  name = "${local.cluster_name}-alb-controller"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = local.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${replace(module.eks.cluster_oidc_issuer_url, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy_attachment" "alb_controller" {
  role       = aws_iam_role.alb_controller.name
  policy_arn = aws_iam_policy.alb_controller.arn
}

resource "helm_release" "aws_lb_controller" {
  count = var.enable_eks_data_lookup ? 1 : 0

  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set = [
    {
      name  = "clusterName"
      value = module.eks.cluster_name
    },
    {
      name  = "serviceAccount.create"
      value = "true"
    },
    {
      name  = "serviceAccount.name"
      value = "aws-load-balancer-controller"
    },
    {
      name  = "serviceAccount.annotations.eks.amazonaws.com/role-arn"
      value = aws_iam_role.alb_controller.arn
    }
  ]

  depends_on = [module.eks]
}

# --- ArgoCD Installation ---
resource "kubernetes_namespace" "argocd" {
  count = var.enable_eks_data_lookup ? 1 : 0

  metadata {
    name = "argocd"
  }

  depends_on = [module.eks]
}

resource "helm_release" "argo_cd" {
  count = var.enable_eks_data_lookup ? 1 : 0

  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd[count.index].metadata[0].name
  version    = var.argocd_chart_version

  values = [
    templatefile("${path.module}/kube-manifests/argocd-values.tpl", {
      base_domain = var.base_domain
      env         = var.env
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.aws_lb_controller
  ]
}

# ArgoCD GitLab Repository Secret
resource "kubernetes_secret" "argocd_gitlab_repo" {
  count = var.enable_eks_data_lookup ? 1 : 0

  metadata {
    name      = "gitlab-argo-repo"
    namespace = kubernetes_namespace.argocd[count.index].metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = base64encode("git")
    url      = base64encode(var.gitlab_argo_repo)
    password = base64encode(var.gitlab_argo_token)
    username = base64encode("git")
  }

  depends_on = [helm_release.argo_cd]
}

# ArgoCD ConfigMap for resource exclusions
resource "kubernetes_config_map_v1_data" "argocd_defaults" {
  count = var.enable_eks_data_lookup ? 1 : 0

  metadata {
    name      = "argocd-cm"
    namespace = kubernetes_namespace.argocd[count.index].metadata[0].name
  }

  data = {
    "resource.exclusions"                = <<-EOT
      - apiGroups:
        - cilium.io
        kinds:
        - CiliumIdentity
        clusters:
        - "*"
    EOT
    "application.resourceTrackingMethod" = "annotation"
  }

  force = true

  depends_on = [helm_release.argo_cd]
}

# Update kubeconfig for local access
resource "null_resource" "update_kubeconfig" {
  count = var.enable_eks_data_lookup ? 1 : 0

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
  }

  depends_on = [module.eks]

  triggers = {
    cluster_name = module.eks.cluster_name
  }
}

resource "kubernetes_manifest" "shared_alb_owner" {
  count = (var.enable_eks_data_lookup && var.cluster_alb_name != "") ? 1 : 0

  manifest = yamldecode(
    templatefile("${path.module}/kube-manifests/shared-alb-owner.yaml", {
      cluster_alb_name = var.cluster_alb_name
    })
  )

  depends_on = [helm_release.aws_lb_controller]
}

data "aws_lb" "cluster_alb" {
  count = var.cluster_alb_name != "" ? 1 : 0
  name  = var.cluster_alb_name
}
