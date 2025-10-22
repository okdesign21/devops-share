locals {
  tags = {
    Environment = var.env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }

  alb_group_name   = "${var.env}-shared-alb"
  alb_role_name    = "${local.cluster_name}-alb-controller"
  oidc_provider_id = replace(local.cluster_oidc_issuer_url, "https://", "")
  argo_repo = "http://gitlab.${var.env}.${var.base_domain}/${var.gitlab_argo_repo}"
}

resource "aws_iam_policy" "alb_controller" {
  name        = "${local.alb_role_name}-policy"
  path        = "/"
  description = "IAM policy for AWS Load Balancer Controller"

  policy = file("${path.module}/iam-policy-alb.json")

  tags = local.tags
}

resource "aws_iam_role" "alb_controller" {
  name = local.alb_role_name

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
          "${local.oidc_provider_id}:sub" = "system:serviceaccount:kube-system:aws-load-balancer-controller"
          "${local.oidc_provider_id}:aud" = "sts.amazonaws.com"
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
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.8.1"

  set = [
    {
      name  = "clusterName"
      value = local.cluster_name
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

  depends_on = [aws_iam_role_policy_attachment.alb_controller]
}

resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argo_cd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  version    = var.argocd_chart_version

  values = [
    templatefile("${path.module}/kube-manifests/argocd-values.tpl", {
      base_domain      = var.base_domain
      env              = var.env
      cluster_alb_name = var.cluster_alb_name != "" ? var.cluster_alb_name : local.alb_group_name
    })
  ]

  depends_on = [
    kubernetes_namespace.argocd,
    helm_release.aws_lb_controller
  ]
}

resource "kubernetes_secret" "argocd_gitlab_repo" {
  metadata {
    name      = "gitlab-argo-repo"
    namespace = kubernetes_namespace.argocd.metadata[0].name
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = base64encode("git")
    url      = base64encode(local.argo_repo)
    password = base64encode(var.gitlab_argo_token)
    username = base64encode("git")
  }

  depends_on = [helm_release.argo_cd]
}

resource "kubernetes_manifest" "shared_alb_owner" {
  count = (var.cluster_alb_name != "") ? 1 : 0

  manifest = yamldecode(
    templatefile("${path.module}/kube-manifests/shared-alb-owner.yaml", {
      cluster_alb_name = var.cluster_alb_name
      alb_group_name   = local.alb_group_name
      env              = var.env
    })
  )

  depends_on = [helm_release.aws_lb_controller]
}
