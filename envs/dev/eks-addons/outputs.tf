output "alb_controller_role_arn" {
  description = "IAM role ARN assigned to the AWS Load Balancer Controller"
  value       = var.deploy_addons ? aws_iam_role.alb_controller[0].arn : ""
}

output "alb_controller_policy_arn" {
  description = "IAM policy ARN attached to the AWS Load Balancer Controller role"
  value       = var.deploy_addons ? aws_iam_policy.alb_controller[0].arn : ""
}

output "argocd_namespace" {
  description = "ArgoCD namespace created by the add-ons stack"
  value       = try(kubernetes_namespace.argocd[0].metadata[0].name, "")
}

output "helm_aws_lb_controller_version" {
  description = "Version of the AWS Load Balancer Controller chart"
  value       = var.deploy_addons ? helm_release.aws_lb_controller[0].version : ""
}
