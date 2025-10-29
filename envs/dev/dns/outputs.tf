output "r53_subdomain" {
  value = try(aws_route53_zone.r53[0].name, "")
}

output "r53_name_servers" {
  value = try(aws_route53_zone.r53[0].name_servers, [])
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}

output "r53_zone_id" {
  description = "Route53 hosted zone ID for certificate validation"
  value       = try(aws_route53_zone.r53[0].zone_id, "")
}

output "app_certificate_arn" {
  description = "ACM certificate ARN for public app HTTPS (use in Kubernetes Ingress)"
  value       = try(aws_acm_certificate_validation.app[0].certificate_arn, "")
}

output "app_domain_name" {
  description = "Public app domain name"
  value       = var.env == "dev" ? "app.${var.env}.r53.${var.base_domain}" : ""
}

output "weather_domain_name" {
  description = "Weather app domain name (SAN on certificate)"
  value       = var.env == "dev" ? "weather.${var.env}.r53.${var.base_domain}" : ""
}

output "internal_zone_id" {
  description = "Private Route53 zone ID for internal service discovery"
  value       = aws_route53_zone.internal.zone_id
}

output "internal_zone_name" {
  description = "Private zone domain name (internal.local)"
  value       = aws_route53_zone.internal.name
}

output "gitlab_internal_fqdn" {
  description = "GitLab internal fully qualified domain name"
  value       = aws_route53_record.gitlab_server.fqdn
}

output "jenkins_internal_fqdn" {
  description = "Jenkins internal fully qualified domain name"
  value       = aws_route53_record.jenkins_server.fqdn
}