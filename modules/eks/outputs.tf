output "cluster_name" {
  value = module.eks_core.cluster_name
}

output "cluster_endpoint" {
  value = module.eks_core.cluster_endpoint
}

output "cluster_security_group_id" {
  value = module.eks_core.cluster_security_group_id
}

output "oidc_provider_arn" {
  value = module.eks_core.oidc_provider_arn
}

output "node_group_role_name" {
  value = module.eks_core.eks_managed_node_groups["default"].iam_role_name
}
