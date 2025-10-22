locals {
  use_generated_key  = var.key_name == null || var.key_name == ""
  effective_key_name = local.use_generated_key ? "${var.project_name}-${var.env}-key" : var.key_name
}

resource "tls_private_key" "gen" {
  count     = local.use_generated_key ? 1 : 0
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "gen" {
  count      = local.use_generated_key ? 1 : 0
  key_name   = local.effective_key_name
  public_key = tls_private_key.gen[0].public_key_openssh
}

resource "local_file" "private_key_pem" {
  count           = local.use_generated_key ? 1 : 0
  content         = tls_private_key.gen[0].private_key_pem
  filename        = "${path.module}/${local.effective_key_name}.pem"
  file_permission = "0600"
}

output "ssh_private_key_path" {
  description = "Path to the generated private key (if created)"
  value       = local.use_generated_key ? local_file.private_key_pem[0].filename : null
  sensitive   = true
}

output "ssh_key_name" {
  value = local.effective_key_name
}
