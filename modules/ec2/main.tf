resource "aws_instance" "this" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = var.sg_ids
  associate_public_ip_address = var.associate_public_ip
  user_data                   = var.user_data
  user_data_replace_on_change = true
  source_dest_check           = var.enable_source_dest_check
  iam_instance_profile        = var.iam_instance_profile

  root_block_device {
    volume_type = "gp3"
    volume_size = var.root_volume_size_gb
  }

  tags = { Name = var.name }
}

output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  value = aws_instance.this.public_ip
}

output "private_ip" {
  value = aws_instance.this.private_ip
}

output "primary_network_interface_id" {
  value = aws_instance.this.primary_network_interface_id
}
