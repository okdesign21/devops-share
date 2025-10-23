output "alb_controller_role_arn" {
  description = "IAM role ARN assigned to the AWS Load Balancer Controller"
  value       = aws_iam_role.alb_controller.arn
}

output "alb_controller_policy_arn" {
  description = "IAM policy ARN attached to the AWS Load Balancer Controller role"
  value       = aws_iam_policy.alb_controller.arn
}

output "argocd_namespace" {
  description = "ArgoCD namespace created by the add-ons stack"
  value       = try(kubernetes_namespace.argocd.metadata[0].name, "")
}

output "helm_aws_lb_controller_version" {
  description = "Version of the AWS Load Balancer Controller chart"
  value       = helm_release.aws_lb_controller.version
}

output "cluster_alb_dns_name" {
  description = "DNS name of the ALB created by the AWS Load Balancer Controller (available after ingress is provisioned)"
  value       = try(data.external.wait_for_alb.result.dns, "")
}

output "cluster_alb_zone_id" {
  description = "Zone ID of the ALB created by the AWS Load Balancer Controller (available after ingress is provisioned)"
  value       = try(data.external.wait_for_alb.result.zone_id, "")
}