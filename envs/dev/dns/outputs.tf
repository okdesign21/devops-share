output "r53_subdomain" {
  value = try(aws_route53_zone.r53[0].name, "")
}

output "r53_name_servers" {
  value = try(aws_route53_zone.r53[0].name_servers, [])
}

output "external_dns_role_arn" {
  value = aws_iam_role.external_dns.arn
}