output "alb_dns" {
  value = module.alb.alb_dns_name
}

output "sg_alb" {
  value = aws_security_group.alb.id
}

output "sg_app" {
  value = aws_security_group.app.id
}