output "name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API server endpoint"
  value       = data.aws_eks_cluster.this.endpoint
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
