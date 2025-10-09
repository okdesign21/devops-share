data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/dev/network/terraform.tfstate"
    region = var.region
  }
}

data "aws_ssm_parameter" "ubuntu_24" {
  name = var.ubuntu_ami
}

module "ud_jenkins_agent" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.module}/../../../modules/userdata/common/swap.sh",
    "${path.module}/../../../modules/userdata/common/ssm.sh",
    "${path.module}/../../../modules/userdata/common/docker.sh",
    "${path.module}/../../../modules/userdata/compose/jenkins_agent.sh",
  ]
}

# --- AMI lookup by tag "type" when explicit ami var is not provided ---
data "aws_ami" "jenkins_lookup" {
  count       = var.jenkins_server_ami == "" ? 1 : 0
  most_recent = true
  filter {
    name   = "tag:type"
    values = ["jenkins"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

data "aws_ami" "gitlab_lookup" {
  count       = var.gitlab_ami == "" ? 1 : 0
  most_recent = true
  filter {
    name   = "tag:type"
    values = ["gitlab"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

locals {
  jenkins_server_ami_resolved = var.jenkins_server_ami != "" ? var.jenkins_server_ami : (length(data.aws_ami.jenkins_lookup) > 0 ? data.aws_ami.jenkins_lookup[0].id : "")
  gitlab_ami_resolved         = var.gitlab_ami != "" ? var.gitlab_ami : (length(data.aws_ami.gitlab_lookup) > 0 ? data.aws_ami.gitlab_lookup[0].id : "")
  inst_subnets                = tolist(data.terraform_remote_state.network.outputs.private_subnet_ids)
  vpc_id                      = data.terraform_remote_state.network.outputs.vpc_id
  ssm_profile                 = data.terraform_remote_state.network.outputs.ssm_instance_profile_name
}

resource "null_resource" "require_amis" {
  count = (local.jenkins_server_ami_resolved == "" || local.gitlab_ami_resolved == "") ? 1 : 0
  provisioner "local-exec" {
    command = "echo 'ERROR: could not resolve jenkins/gitlab AMI(s)'; exit 1"
  }
}

# ALB SG (80 from anywhere, egress all)
resource "aws_security_group" "sg_alb" {
  name        = "${var.project_name}-cicd-alb-sg"
  description = "ALB ingress 80"
  vpc_id      = local.vpc_id

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

resource "aws_security_group" "sg_jenkins_srv" {
  name        = "${var.project_name}-jenkins-srv-sg"
  description = "Jenkins server"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_gitlab" {
  name        = "${var.project_name}-gitlab-sg"
  description = "GitLab server"
  vpc_id      = local.vpc_id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.sg_alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "sg_jenkins_agt" {
  name        = "${var.project_name}-jenkins-agt-sg"
  description = "Jenkins agents"
  vpc_id      = local.vpc_id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

module "alb" {
  source            = "../../../modules/alb"
  name              = "${var.project_name}-cicd-alb"
  vpc_id            = local.vpc_id
  subnets           = local.inst_subnets
  security_group_id = aws_security_group.sg_alb.id

  routes = concat(
    [
      { name = "jenkins", path = "/jenkins*", port = 8080, health_path = "/jenkins/login", priority = 10 },
      { name = "gitlab", path = "/gitlab*", port = 8080, health_path = "/gitlab/users/sign_in", priority = 20 }
    ]
  )
}

data "aws_ami" "gitlab_ami" {
  id = var.gitlab_ami
}

data "aws_ami" "jenkins_server_ami" {
  id = var.jenkins_server_ami
}

module "jenkins_server" {
  source               = "../../../modules/ec2"
  name                 = "${var.project_name}-jenkins-server"
  ami_id               = local.jenkins_server_ami_resolved
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 0)
  sg_ids               = [aws_security_group.sg_jenkins_srv.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_server_instance_type
  associate_public_ip  = false
  iam_instance_profile = null
}

module "gitlab" {
  source               = "../../../modules/ec2"
  name                 = "${var.project_name}-gitlab-server"
  ami_id               = local.gitlab_ami_resolved
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 1 % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids               = [aws_security_group.sg_gitlab.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.gitlab_server_instance_type
  associate_public_ip  = false
  user_data            = ""
  iam_instance_profile = null
}

module "jenkins_agent" {
  source               = "../../../modules/ec2"
  for_each             = { for i in range(var.jenkins_agent_count) : i => i }
  name                 = "${var.project_name}-jenkins-agent-${each.key}"
  ami_id               = data.aws_ssm_parameter.ubuntu_24.value
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, each.key % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids               = [aws_security_group.sg_jenkins_agt.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_agent_instance_type
  root_volume_size_gb  = var.jenkins_agent_volume_size_gb
  associate_public_ip  = false
  user_data            = module.ud_jenkins_agent.content
  iam_instance_profile = data.terraform_remote_state.network.outputs.ssm_instance_profile_name
}

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = module.alb.tg_arns["jenkins"]
  target_id        = module.jenkins_server.instance_id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "gitlab" {
  target_group_arn = module.alb.tg_arns["gitlab"]
  target_id        = module.gitlab.instance_id
  port             = 8080
}
