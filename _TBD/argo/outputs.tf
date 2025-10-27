output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_helm_status" {
  description = "ArgoCD Helm release status"
  value       = helm_release.argocd.status
}

output "argocd_chart_version" {
  description = "ArgoCD Helm chart version deployed"
  value       = helm_release.argocd.version
}
