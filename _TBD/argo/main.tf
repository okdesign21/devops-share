locals {
  argo_repo = "http://gitlab.${var.env}.${var.base_domain}/${var.gitlab_argo_repo}"
}

# 1) Namespace
resource "kubernetes_namespace" "argocd" {
  metadata { name = "argocd" }
}

# 2) Argo CD via Helm
resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = kubernetes_namespace.argocd.metadata[0].name
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "9.0.5"

  # Optional hardening + service type
  values = [yamlencode({
    server = {
      service = { type = "LoadBalancer" }
    }
    configs = {
      params = {
        "application.namespaces" = "argocd"
      }
    }
  })]

  depends_on = [kubernetes_namespace.argocd]
}

# 3) (Optional) Repo credentials secret
resource "kubernetes_secret" "argocd_repo" {
  count      = var.gitlab_argo_repo != "" ? 1 : 0
  depends_on = [helm_release.argocd]

  metadata {
    name      = "repo-cred"
    namespace = "argocd"
    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = local.argo_repo
    username = var.repo_username
    password = var.repo_password
  }

  type = "Opaque"
}