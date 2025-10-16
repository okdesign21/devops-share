data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/dev/network/terraform.tfstate"
    region = var.region
  }
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

# caller identity so tag lookups can default to your account when ami_owner_ids is empty
data "aws_caller_identity" "me" {}

# Jenkins/GitLab tag-based lookups (only used when explicit AMI var empty)
data "aws_ami" "jenkins_lookup" {
  count       = var.jenkins_server_ami == "" ? 1 : 0
  most_recent = true
  owners      = length(var.ami_owner_ids) > 0 ? var.ami_owner_ids : [data.aws_caller_identity.me.account_id]

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
  owners      = length(var.ami_owner_ids) > 0 ? var.ami_owner_ids : [data.aws_caller_identity.me.account_id]

  filter {
    name   = "tag:type"
    values = ["gitlab"]
  }
  filter {
    name   = "state"
    values = ["available"]
  }
}

# If user provided explicit AMI ids, look them up safely (count = 0 when empty)
data "aws_ami" "gitlab_ami" {
  count       = var.gitlab_ami != "" ? 1 : 0
  most_recent = true
  filter {
    name   = "image-id"
    values = [var.gitlab_ami]
  }
}

data "aws_ami" "jenkins_server_ami" {
  count       = var.jenkins_server_ami != "" ? 1 : 0
  most_recent = true
  filter {
    name   = "image-id"
    values = [var.jenkins_server_ami]
  }
}

data "cloudflare_zones" "this" {
  filter { name = var.zone_name }
}

locals {
  gitlab_ami_resolved = var.gitlab_ami != "" ? var.gitlab_ami : (
    length(data.aws_ami.gitlab_ami) > 0 ? data.aws_ami.gitlab_ami[0].id : (
      length(data.aws_ami.gitlab_lookup) > 0 ? data.aws_ami.gitlab_lookup[0].id : ""
    )
  )

  jenkins_server_ami_resolved = var.jenkins_server_ami != "" ? var.jenkins_server_ami : (
    length(data.aws_ami.jenkins_server_ami) > 0 ? data.aws_ami.jenkins_server_ami[0].id :
    (length(data.aws_ami.jenkins_lookup) > 0 ? data.aws_ami.jenkins_lookup[0].id : "")
  )

  jenkins_agent_ami_resolved = length(data.aws_ssm_parameter.ubuntu_24) > 0 ? data.aws_ssm_parameter.ubuntu_24[0].value : ""
  inst_subnets               = tolist(data.terraform_remote_state.network.outputs.public_subnet_ids)
  vpc_id                     = data.terraform_remote_state.network.outputs.vpc_id
  ssm_profile                = data.terraform_remote_state.network.outputs.ssm_instance_profile_name
  zone_id                    = one(data.cloudflare_zones.this.zones).id
  base_domain                = var.subdomain != "" ? "${var.subdomain}.${var.zone_name}" : var.zone_name
  wildcard_domain            = "*.${local.base_domain}"
  jenkins_header             = var.subdomain != "" ? format("jenkins-dev.%s", var.subdomain) : "jenkins-dev"
  gitlab_header              = var.subdomain != "" ? format("gitlab-dev.%s", var.subdomain) : "gitlab-dev"

  gitlab_trusted_cidrs = (
    contains(keys(data.terraform_remote_state.network.outputs), "private_subnet_cidrs") && length(data.terraform_remote_state.network.outputs.private_subnet_cidrs) > 0 ?
    join(",", data.terraform_remote_state.network.outputs.private_subnet_cidrs) :
    ""
  )

  gitlab_trusted_array = (
    local.gitlab_trusted_cidrs != "" ? format("['%s']", join("','", split(",", local.gitlab_trusted_cidrs))) : "[]"
  )
}

# fail early if any required AMI is unresolved
resource "null_resource" "require_amis" {
  count = (local.jenkins_server_ami_resolved == "" || local.gitlab_ami_resolved == "" || local.jenkins_agent_ami_resolved == "") ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: unresolved AMIs -> jenkins_server=${local.jenkins_server_ami_resolved} gitlab=${local.gitlab_ami_resolved} jenkins_agent=${local.jenkins_agent_ami_resolved}'; exit 1"
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
      { name = "jenkins", header = local.jenkins_header, port = 8080, health_path = "/jenkins/login", priority = 10 },
      { name = "gitlab", header = local.gitlab_header, port = 8080, health_path = "/gitlab/users/sign_in", priority = 20 }
    ]
  )
}

module "jenkins_server" {
  source               = "../../../modules/ec2"
  name                 = "${var.project_name}-jenkins-server"
  ami_id               = local.jenkins_server_ami_resolved
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 0)
  sg_ids               = [aws_security_group.sg_jenkins_srv.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_server_instance_type
  root_volume_size_gb  = var.jenkins_server_volume_size_gb
  associate_public_ip  = false
  iam_instance_profile = local.ssm_profile
  depends_on           = [null_resource.require_amis]

  user_data = templatefile("../../../modules/userdata/templates/jenkins_env.tpl", {
    public_hostname = "${local.jenkins_header}.${local.base_domain}"
    jenkins_url     = "http://${local.jenkins_header}.${local.base_domain}/"
    gitlab_url      = "http://${local.gitlab_header}.${local.base_domain}"
    agent_override  = "${local.jenkins_header}.${local.base_domain}"
  })
}

module "gitlab" {
  source              = "../../../modules/ec2"
  name                = "${var.project_name}-gitlab-server"
  ami_id              = local.gitlab_ami_resolved
  subnet_id           = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 1 % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids              = [aws_security_group.sg_gitlab.id]
  key_name            = data.terraform_remote_state.network.outputs.key_name
  instance_type       = var.gitlab_server_instance_type
  root_volume_size_gb = var.gitlab_volume_size_gb
  associate_public_ip = false

  user_data = templatefile("../../../modules/userdata/templates/gitlab_env.tpl", {
    external_url  = "http://${local.gitlab_header}.${local.base_domain}"
    trusted_cidrs = local.gitlab_trusted_cidrs
    trusted_array = local.gitlab_trusted_array
  })

  iam_instance_profile = local.ssm_profile
  depends_on           = [null_resource.require_amis]
}

module "jenkins_agent" {
  source               = "../../../modules/ec2"
  for_each             = { for i in range(var.jenkins_agent_count) : i => i }
  name                 = "${var.project_name}-jenkins-agent-${each.key}"
  ami_id               = local.jenkins_agent_ami_resolved
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, each.key % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids               = [aws_security_group.sg_jenkins_agt.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_agent_instance_type
  root_volume_size_gb  = var.jenkins_agent_volume_size_gb
  associate_public_ip  = false
  user_data            = module.ud_jenkins_agent.content
  iam_instance_profile = local.ssm_profile
  depends_on           = [null_resource.require_amis]
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

# Jenkins agent Ubuntu SSM (used when ubuntu_ami var is set to an SSM param name)
data "aws_ssm_parameter" "ubuntu_24" {
  count = var.ubuntu_ami != "" ? 1 : 0
  name  = var.ubuntu_ami
}

# Dev records (CNAME → ALB DNS). Set proxied=false while testing.
resource "cloudflare_record" "jenkins" {
  zone_id = local.zone_id
  name    = local.jenkins_header
  type    = "CNAME"
  value   = module.alb.alb_dns_name
  proxied = false
}

resource "cloudflare_record" "gitlab" {
  zone_id = local.zone_id
  name    = local.gitlab_header
  type    = "CNAME"
  value   = module.alb.alb_dns_name
  proxied = false
}

resource "aws_acm_certificate" "apps" {
  domain_name               = local.wildcard_domain
  validation_method         = "DNS"
  subject_alternative_names = [local.base_domain]

  lifecycle {
    create_before_destroy = true
  }
}
/*
resource "cloudflare_record" "acm_validations" {
  for_each = {
    for dvo in aws_acm_certificate.apps.domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  }

  zone_id = local.zone_id
  name    = each.value.name
  type    = each.value.type
  value   = each.value.value
  ttl     = 60
  proxied = false
}*/