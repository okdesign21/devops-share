# ## IMPORT GARD: only after eks creation

# # providers: configure kubernetes & helm to point at DEV cluster
# provider "kubernetes" {
#   host                   = module.eks.cluster_endpoint
#   cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#   token                  = data.aws_eks_cluster_auth.this.token
# }

# provider "helm" {
#   kubernetes {
#     host                   = module.eks.cluster_endpoint
#     cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
#     token                  = data.aws_eks_cluster_auth.this.token
#   }
# }

# # 1) Namespace
# resource "kubernetes_namespace" "argocd" {
#   metadata { name = "argocd" }
# }

# # 2) Argo CD via Helm
# resource "helm_release" "argocd" {
#   name       = "argocd"
#   namespace  = kubernetes_namespace.argocd.metadata[0].name
#   repository = "https://argoproj.github.io/argo-helm"
#   chart      = "argo-cd"
#   version    = "6.7.18" # pin a version you’re happy with

#   # Optional hardening + service type
#   values = [yamlencode({
#     server = {
#       service = { type = "LoadBalancer" } # or ClusterIP if you expose via Ingress later
#     }
#     configs = {
#       params = {
#         "application.namespaces" = "argocd" # reduce scope if you want
#       }
#     }
#   })]
# }

# # 3) (Optional) Repo credentials secret (if the repo is private HTTP/S)
# # Create a Kubernetes secret that Argo reads as a repo cred.
# # Skip if you’ll add credentials via UI/CLI once.
# resource "kubernetes_secret" "argocd_repo" {
#   depends_on = [helm_release.argocd]
#   metadata {
#     name      = "repo-cred"
#     namespace = "argocd"
#     labels = {
#       "argocd.argoproj.io/secret-type" = "repository"
#     }
#   }
#   data = {
#     type     = "git"
#     url      = "https://<your-git-host>/<org>/<repo>.git"
#     username = "<user>"
#     password = "<token_or_password>"
#   }
#   type = "Opaque"
# }

# # 4) Bootstrap "app-of-apps" (your platform project + ApplicationSets)
# # Use the kubernetes_manifest resource if available, else kubectl_file_documents via null_resource.
# resource "kubernetes_manifest" "appproject_platform" {
#   depends_on = [helm_release.argocd]
#   manifest = yamldecode(file("${path.module}/bootstrap/platform-project-app.yaml"))
# }

# # Example: an ApplicationSet that installs platform addons to all clusters with env=dev
# resource "kubernetes_manifest" "apps_platform_dev" {
#   depends_on = [helm_release.argocd]
#   manifest   = yamldecode(file("${path.module}/applicationsets/platform-dev.yaml"))
# }