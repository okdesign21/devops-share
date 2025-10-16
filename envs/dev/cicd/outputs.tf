output "sg_jenkins_srv" {
  value = aws_security_group.sg_jenkins_srv.id
}

output "sg_jenkins_agt" {
  value = aws_security_group.sg_jenkins_agt.id
}

output "sg_gitlab" {
  value = aws_security_group.sg_gitlab.id
}

output "sg_cicd-alb" {
  value = aws_security_group.sg_alb.id
}

output "jenkins_server_id" {
  value = module.jenkins_server.instance_id
}

output "gitlab_server_id" {
  value = module.gitlab.instance_id
}

output "cicd_alb_dns" {
  value = module.alb.alb_dns_name
}

output "jenkins_ami_used" {
  value = local.jenkins_server_ami_resolved
}

output "gitlab_ami_used" {
  value = local.gitlab_ami_resolved
}

output "gitlab_url" {
  value = local.gitlab_url
}

output "jenkins_url" {
  value = local.jenkins_url
}

output "zone_id" {
  value = local.zone_id
}