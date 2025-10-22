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
    volume_type           = "gp3"
    volume_size           = var.root_volume_size_gb
    delete_on_termination = true
  }

  tags = { Name = var.name, Environment = var.env, Project = var.project_name }
}
