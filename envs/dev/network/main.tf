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
  source        = "../../../modules/vpc"
  name          = var.project_name
  cidr_block    = local.vpc_cidr
  azs           = local.availability_zones
  public_cidrs  = local.public_cidrs
  private_cidrs = local.private_cidrs
}

module "sg" {
  source                   = "../../../modules/sg"
  vpc_id                   = module.vpc.vpc_id
  allowed_nat_ingress_cidr = local.vpc_cidr
}

locals {
  availability_zones = ["${var.region}a", "${var.region}b"]
  vpc_cidr            = format("%d.10.0.0/16", var.cidr_base)
  public_cidrs        = [
    format("%d.10.1.0/24", var.cidr_base),
    format("%d.10.2.0/24", var.cidr_base),
  ]
  private_cidrs = [
    format("%d.10.11.0/24", var.cidr_base),
    format("%d.10.12.0/24", var.cidr_base),
  ]

  vpc_vars = <<-EOT
    #!/usr/bin/env bash
    export VPC_ID="${module.vpc.vpc_id}"
    export SUBNET_PUBLIC_A="${local.public_cidrs[0]}"
    export SUBNET_PUBLIC_B="${local.public_cidrs[1]}"
    export VPC_CIDR="${local.vpc_cidr}"
  EOT

  nat_vars = <<-EOT
    #!/usr/bin/env bash
    export PRIVATE_CIDRS="${local.vpc_cidr}" 
  EOT
}

module "ud_nat" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.root}/modules/userdata/common/ssm.sh",
    "${path.root}/modules/userdata/common/nat.sh",
  ]
  inline_snippets = [local.nat_vars]
}

module "nat_instance" {
  source                   = "../../../modules/ec2"
  name                     = "${var.project_name}-nat"
  ami_id                   = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id                = module.vpc.public_subnet_ids[0]
  sg_ids                   = [module.sg.sg_nat]
  key_name                 = var.key_name
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
