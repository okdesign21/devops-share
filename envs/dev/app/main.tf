data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/${var.env}/network/terraform.tfstate"
    region = var.region
  }
}

data "aws_ssm_parameter" "ubuntu" {
  name = var.ubuntu_ami
}

locals {
  alb_vars = <<-EOT
    #!/usr/bin/env bash
    export ALB_DNS="${module.alb.alb_dns_name}"
  EOT
}

module "ud_app" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.module}/../../../modules/userdata/common/swap.sh",
    "${path.module}/../../../modules/userdata/common/ssm.sh",
    "${path.module}/../../../modules/userdata/common/docker.sh",
    "${path.module}/../../../modules/userdata/compose/app.sh",
  ]
}

resource "aws_security_group" "alb" {
  name   = "${var.project_name}-alb-sg"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "app" {
  name   = "${var.project_name}-app-sg"
  vpc_id = data.terraform_remote_state.network.outputs.vpc_id
  ingress {
    from_port       = 8000
    to_port         = 8000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "alb" {
  source            = "../../../modules/alb"
  name              = var.project_name
  vpc_id            = data.terraform_remote_state.network.outputs.vpc_id
  subnets           = data.terraform_remote_state.network.outputs.public_subnet_ids
  security_group_id = aws_security_group.alb.id
  default_tg_name   = var.app_count > 0 ? "app" : null
  routes            = var.app_count > 0 ? [{ name = "app", path = "/", port = 8000, health_path = "/", priority = 5 }] : []
}

module "app" {
  source   = "../../../modules/ec2"
  for_each = { for i in range(var.app_count) : i => i }

  name                 = "${var.project_name}-app-${each.key}"
  ami_id               = data.aws_ssm_parameter.ubuntu.value
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, each.key % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids               = [aws_security_group.app.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.app_instance_type
  root_volume_size_gb  = var.app_disk_size_gb
  associate_public_ip  = false
  user_data            = module.ud_app.content
  iam_instance_profile = data.terraform_remote_state.network.outputs.ssm_instance_profile_name
}

resource "aws_lb_target_group_attachment" "app" {
  for_each         = module.app
  target_group_arn = module.alb.tg_arns["app"]
  target_id        = each.value.instance_id
  port             = 8000
}