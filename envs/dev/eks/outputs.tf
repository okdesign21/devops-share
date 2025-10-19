output "name" {
  value = module.eks.cluster_name
}

output "cluster_arn" {
  description = "EKS cluster ARN"
  value       = data.aws_eks_cluster.this.arn
}

output "cluster_certificate_authority_data" {
  description = "Base64 CA certificate for the cluster (as provided by AWS)"
  value       = data.aws_eks_cluster.this.certificate_authority[0].data
  sensitive   = true
}

output "kubeconfig_command" {
  description = "CLI command to create a kubeconfig for this cluster (run locally)"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "cluster_alb_hostname" {
  value       = try(data.kubernetes_ingress_v1.argocd.status[0].load_balancer[0].ingress[0].hostname, "")
  description = "ALB hostname created by AWS LB Controller for the ArgoCD ingress (empty until created)"
}

output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "EKS cluster version"
  value       = module.eks.cluster_version
}

output "argocd_namespace" {
  description = "ArgoCD namespace"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "alb_controller_role_arn" {
  description = "ALB Controller IAM role ARN"
  value       = aws_iam_role.alb_controller.arn
}