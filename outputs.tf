output "alb_dns_name" {
  value = module.alb.alb_dns_name
}

output "app_url" {
  value = "http://${module.alb.alb_dns_name}/"
}

output "jenkins_url" {
  value = "http://${module.alb.alb_dns_name}/jenkins"
}

output "gitlab_url" {
  value = "http://${module.alb.alb_dns_name}/gitlab"
}

output "prometheus_url" {
  value = var.enable_prometheus ? "http://${module.alb.alb_dns_name}/prom" : null
}

output "gitlab_private_ip" {
  value = module.gitlab.private_ip
}

output "jenkins_controller_ip" {
  value = module.jenkins_server.private_ip
}
