output "name" {
  value = module.eks.cluster_name
}

output "cluster_arn" {
  value = try(data.aws_eks_cluster.this[0].arn, "")
}

output "cluster_certificate_authority_data" {
  value     = try(data.aws_eks_cluster.this[0].certificate_authority[0].data, "")
  sensitive = true
}

output "kubeconfig_command" {
  description = "CLI command to create a kubeconfig for this cluster (run locally)"
  value       = "aws eks update-kubeconfig --name ${module.eks.cluster_name} --region ${var.region}"
}

output "cluster_alb_dns_name" {
  description = "DNS name of the cluster shared ALB (or empty if not found)"
  value       = length(data.aws_lb.cluster_alb) > 0 ? data.aws_lb.cluster_alb[0].dns_name : ""
}

output "cluster_alb_zone_id" {
  description = "Zone ID for the cluster shared ALB (or empty if not found)"
  value       = length(data.aws_lb.cluster_alb) > 0 ? data.aws_lb.cluster_alb[0].zone_id : ""
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
  value       = try(kubernetes_namespace.argocd[0].metadata[0].name, "")
}

output "alb_controller_role_arn" {
  description = "ALB Controller IAM role ARN"
  value       = aws_iam_role.alb_controller.arn
}