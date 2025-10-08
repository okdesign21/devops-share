# AMI: Ubuntu 24.04 LTS
data "aws_ssm_parameter" "ubuntu_24" {
  name = "/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id"
}

# SSM role & instance profile for Session Manager
resource "aws_iam_role" "ssm_ec2" {
  name = "${var.project_name}-ssm-ec2-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect    = "Allow",
      Principal = { Service = "ec2.amazonaws.com" },
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ssm_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ssm" {
  name = "${var.project_name}-ssm-instance-profile"
  role = aws_iam_role.ssm_ec2.name
}

module "vpc" {
  source        = "./modules/vpc"
  name          = var.project_name
  cidr_block    = var.vpc_cidr
  azs           = ["${var.region}a", "${var.region}b"]
  public_cidrs  = var.public_cidrs
  private_cidrs = var.private_cidrs
}

module "sg" {
  source                   = "./modules/sg"
  vpc_id                   = module.vpc.vpc_id
  allowed_nat_ingress_cidr = var.vpc_cidr
}

# ---------- user-data bundles ----------
locals {
  alb_vars = <<-EOT
    #!/usr/bin/env bash
    export ALB_DNS="${module.alb.alb_dns_name}"
  EOT

  vpc_vars = <<-EOT
    #!/usr/bin/env bash
    export VPC_ID="${module.vpc.vpc_id}"
    export SUBNET_PUBLIC_A="${module.vpc.public_subnet_ids[0]}"
    export SUBNET_PUBLIC_B="${module.vpc.public_subnet_ids[1]}"
    export VPC_CIDR="${var.vpc_cidr}"
  EOT

  nat_vars = <<-EOT
    #!/usr/bin/env bash
    export PRIVATE_CIDRS="${var.vpc_cidr}" 
  EOT
}

module "ud_app" {
  source = "./modules/userdata"
  scripts = [
    "${path.module}/modules/userdata/common/swap.sh",
    "${path.module}/modules/userdata/common/docker.sh",
    "${path.module}/modules/userdata/common/ssm.sh",
    "${path.module}/modules/userdata/compose/app.sh"
  ]
}

module "ud_jenkins" {
  source = "./modules/userdata"
  scripts = [
    "${path.root}/modules/userdata/common/swap.sh",
    "${path.root}/modules/userdata/common/docker.sh",
    "${path.root}/modules/userdata/common/ssm.sh",
    "${path.root}/modules/userdata/compose/jenkins_server.sh",
  ]
  inline_snippets = [local.alb_vars]
}

module "ud_jenkins_agent" {
  source = "./modules/userdata"
  scripts = [
    "${path.root}/modules/userdata/common/swap.sh",
    "${path.root}/modules/userdata/common/docker.sh",
    "${path.root}/modules/userdata/common/ssm.sh",
    "${path.root}/modules/userdata/compose/jenkins_agent.sh",
  ]
  inline_snippets = [local.alb_vars]
}

module "ud_gitlab" {
  source = "./modules/userdata"
  scripts = [
    "${path.root}/modules/userdata/common/swap.sh",
    "${path.root}/modules/userdata/common/docker.sh",
    "${path.root}/modules/userdata/common/ssm.sh",
    "${path.root}/modules/userdata/compose/gitlab.sh",
  ]
  inline_snippets = [local.alb_vars, local.vpc_vars]
}

module "ud_prom" {
  source = "./modules/userdata"
  scripts = [
    "${path.module}/modules/userdata/common/swap.sh",
    "${path.module}/modules/userdata/common/docker.sh",
    "${path.module}/modules/userdata/common/ssm.sh",
    "${path.module}/modules/userdata/compose/prometheus.sh"
  ]
}

module "ud_nat" {
  source = "./modules/userdata"
  scripts = [
    "${path.root}/modules/userdata/common/ssm.sh",
    "${path.root}/modules/userdata/common/nat.sh",
  ]
  inline_snippets = [local.nat_vars]
}

# ---------- compute ----------
# NAT Instance for egress from private subnets
module "nat_instance" {
  source                   = "./modules/ec2"
  name                     = "${var.project_name}-nat"
  ami_id                   = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id                = module.vpc.public_subnet_ids[0]
  sg_ids                   = [module.sg.sg_nat]
  key_name                 = local.effective_key_name
  instance_type            = var.nat_instance_type
  associate_public_ip      = true
  user_data                = module.ud_nat.content
  enable_source_dest_check = false
  root_volume_size_gb      = var.nat_disk_size_gb
  iam_instance_profile     = aws_iam_instance_profile.ssm.name

}

resource "aws_route" "private_nat" {
  for_each = {
    az1 = module.vpc.private_route_table_ids[0]
    az2 = module.vpc.private_route_table_ids[1]
  }

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  network_interface_id   = module.nat_instance.primary_network_interface_id
}

# Public ALB with path routing to app/jenkins/prom/gitlab
module "alb" {
  source            = "./modules/alb"
  name              = var.project_name
  vpc_id            = module.vpc.vpc_id
  subnets           = module.vpc.public_subnet_ids
  security_group_id = module.sg.sg_alb
  default_tg_name   = var.app_count > 0 ? "app" : null
  routes = concat(
    var.app_count > 0 ? [
      { name = "app", path = "/", port = 8000, health_path = "/", priority = 5 }
    ] : [],
    [
      { name = "jenkins", path = "/jenkins*", port = 8080, health_path = "/jenkins/login", priority = 10 },
      { name = "gitlab", path = "/gitlab*", port = 8080, health_path = "/gitlab/users/sign_in", priority = 15 }
    ],
    var.enable_prometheus ? [
      { name = "prometheus", path = "/prom*", port = 9090, health_path = "/-/healthy", priority = 30 }
    ] : []
  )
}

# ----- app EC2s -----
module "app" {
  source   = "./modules/ec2"
  for_each = { for i in range(var.app_count) : i => i }

  name                 = "${var.project_name}-app-${each.key}"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = element(module.vpc.private_subnet_ids, each.key % length(module.vpc.private_subnet_ids))
  sg_ids               = [module.sg.sg_app]
  key_name             = local.effective_key_name
  instance_type        = var.app_instance_type
  root_volume_size_gb  = var.app_disk_size_gb
  associate_public_ip  = false
  user_data            = module.ud_app.content
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  depends_on           = [module.nat_instance, aws_route.private_nat]
}

resource "aws_lb_target_group_attachment" "app" {
  for_each         = module.app
  target_group_arn = module.alb.tg_arns["app"]
  target_id        = each.value.instance_id
  port             = 8000
}

# ----- jenkins -----
module "jenkins_server" {
  source               = "./modules/ec2"
  name                 = "${var.project_name}-jenkins-controller"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = module.vpc.private_subnet_ids[0]
  sg_ids               = [module.sg.sg_jenkins_srv]
  key_name             = local.effective_key_name
  instance_type        = var.jenkins_controller_type
  associate_public_ip  = false
  user_data            = module.ud_jenkins.content
  root_volume_size_gb  = var.jenkins_controller_disk
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  depends_on           = [module.nat_instance, aws_route.private_nat]
}

module "jenkins_agent" {
  source               = "./modules/ec2"
  name                 = "${var.project_name}-jenkins-agent"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = module.vpc.private_subnet_ids[0]
  sg_ids               = [module.sg.sg_jenkins_agt]
  key_name             = local.effective_key_name
  instance_type        = var.jenkins_agent_type
  associate_public_ip  = false
  user_data            = module.ud_jenkins_agent.content
  root_volume_size_gb  = var.jenkins_agent_disk
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  depends_on           = [module.nat_instance, aws_route.private_nat]
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = module.alb.tg_arns["jenkins"]
  target_id        = module.jenkins_server.instance_id
  port             = 8080
}

# ----- gitlab -----
module "gitlab" {
  source               = "./modules/ec2"
  name                 = "${var.project_name}-gitlab"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = module.vpc.private_subnet_ids[0]
  sg_ids               = [module.sg.sg_gitlab]
  key_name             = local.effective_key_name
  instance_type        = var.gitlab_type
  associate_public_ip  = false
  user_data            = module.ud_gitlab.content
  root_volume_size_gb  = var.gitlab_disk
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  depends_on           = [module.nat_instance, aws_route.private_nat]
}

resource "aws_lb_target_group_attachment" "gitlab" {
  target_group_arn = module.alb.tg_arns["gitlab"]
  target_id        = module.gitlab.instance_id
  port             = 8080
}

# ----- prometheus (optional) -----
module "prometheus" {
  count                = var.enable_prometheus ? 1 : 0
  source               = "./modules/ec2"
  name                 = "${var.project_name}-prometheus"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = module.vpc.private_subnet_ids[0]
  sg_ids               = [module.sg.sg_prom]
  key_name             = local.effective_key_name
  instance_type        = var.prometheus_type
  associate_public_ip  = false
  user_data            = module.ud_prom.content
  root_volume_size_gb  = var.prometheus_disk
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  depends_on           = [module.nat_instance, aws_route.private_nat]
}

resource "aws_lb_target_group_attachment" "prometheus" {
  count            = var.enable_prometheus ? 1 : 0
  target_group_arn = module.alb.tg_arns["prometheus"]
  target_id        = module.prometheus[0].instance_id
  port             = 9090
}

module "eks" {
  source             = "./modules/eks"
  name               = var.project_name
  vpc_id             = module.vpc.vpc_id
  private_subnet_ids = module.vpc.private_subnet_ids
  #create_kms_key     = ture
  #cluster_encryption_config = []
}

output "alb_dns" { value = module.alb.alb_dns_name }
output "jenkins_ip" { value = module.jenkins_server.private_ip }
output "gitlab_ip" { value = module.gitlab.private_ip }
