output "sg_jenkins_agt" {
  value = aws_security_group.sg_jenkins_agt.id
}

output "jenkins_server_id" {
  value = module.jenkins_server.instance_id
}

output "gitlab_server_id" {
  value = module.gitlab.instance_id
}

output "ssm_access_policy_arn" {
  description = "IAM policy ARN to attach to 'Devs' group for SSM access (from network stack)"
  value       = data.terraform_remote_state.network.outputs.ssm_access_policy_arn
}

output "jenkins_ami_used" {
  value = local.jenkins_server_ami_resolved
}

output "gitlab_ami_used" {
  value = local.gitlab_ami_resolved
}

output "gitlab_url" {
  description = "GitLab self-reference URL (accessed via SSM port-forward on :8443)"
  value       = local.gitlab_self_url
}

output "jenkins_url" {
  description = "Jenkins self-reference URL (accessed via SSM port-forward on :8080)"
  value       = local.jenkins_self_url
}

output "jenkins_private_ip" {
  value = module.jenkins_server.private_ip
}

output "gitlab_private_ip" {
  value = module.gitlab.private_ip
}
