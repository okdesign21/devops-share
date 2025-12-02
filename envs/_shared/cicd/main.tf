data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/eks/terraform.tfstate"
    region = var.region
  }
}

# caller identity so tag lookups can default to your account when ami_owner_ids is empty
data "aws_caller_identity" "me" {}

# Jenkins/GitLab tag-based lookups (only used when explicit AMI var empty)
data "aws_ami" "jenkins_lookup" {
  count       = var.jenkins_server_ami == "" ? 1 : 0
  most_recent = true
  owners      = length(var.ami_owner_ids) > 0 ? var.ami_owner_ids : [data.aws_caller_identity.me.account_id]

  filter {
    name   = "tag:Type"
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
    name   = "tag:Type"
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

  # SSM-only access configuration (localhost-based)
  # Users access via: aws ssm start-session --target <instance-id> --document AWS-StartPortForwardingSession

  # Localhost communication variables
  # GitLab uses internal DNS for clone URLs (Jenkins/EKS can reach it)
  gitlab_self_url      = "http://gitlab-server.vpc.internal"       # GitLab self-reference (for clone URLs)
  jenkins_self_url     = "http://jenkins-server.vpc.internal:8080" # Jenkins self-reference (internal DNS)
  gitlab_for_jenkins   = "http://gitlab-server.vpc.internal"       # How Jenkins reaches GitLab
  jenkins_for_agents   = "http://jenkins-server.vpc.internal:8080" # How agents reach Jenkins
  gitlab_external_url  = "https://localhost:8443"                  # User access via SSM port-forward
  jenkins_external_url = "https://localhost:8080"                  # User access via SSM port-forward

  gitlab_trusted_cidrs = (
    contains(keys(data.terraform_remote_state.network.outputs), "private_subnet_cidrs") && length(data.terraform_remote_state.network.outputs.private_subnet_cidrs) > 0 ?
    join(",", data.terraform_remote_state.network.outputs.private_subnet_cidrs) :
    ""
  )

  gitlab_trusted_array = (
    local.gitlab_trusted_cidrs != "" ? format("['%s']", join("','", split(",", local.gitlab_trusted_cidrs))) : "[]"
  )

  inst_subnets = tolist(data.terraform_remote_state.network.outputs.public_subnet_ids)
  vpc_id       = data.terraform_remote_state.network.outputs.vpc_id
  ssm_profile  = data.terraform_remote_state.network.outputs.ssm_instance_profile_name

  tags = {
    Environment = var.env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# fail early if any required AMI is unresolved
resource "null_resource" "require_amis" {
  count = (local.jenkins_server_ami_resolved == "" || local.gitlab_ami_resolved == "") ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'ERROR: unresolved AMIs -> jenkins_server=${local.jenkins_server_ami_resolved} gitlab=${local.gitlab_ami_resolved}'; exit 1"
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

  tags = merge(local.tags, { Name = "${var.project_name}-jenkins-agt-sg" })
}

module "ud_jenkins_server" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.module}/../../../modules/userdata/common/kubectl.sh",
    "${path.module}/../../../modules/userdata/compose/jenkins_server.sh",
    templatefile("../../../modules/userdata/templates/jenkins_env.tpl", {
      public_hostname  = "jenkins-server.vpc.internal" # Internal FQDN
      jenkins_url      = local.jenkins_self_url        # http://jenkins-server.vpc.internal:8080
      gitlab_url       = local.gitlab_for_jenkins      # http://gitlab-server.vpc.internal (cross-service)
      agent_override   = "jenkins-server.vpc.internal" # Internal FQDN
      eks_cluster_name = data.terraform_remote_state.eks.outputs.cluster_name
      aws_region       = var.region
    })
  ]
}

module "jenkins_server" {
  source               = "../../../modules/ec2"
  name                 = "${var.project_name}-jenkins-server"
  ami_id               = local.jenkins_server_ami_resolved
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 0)
  sg_ids               = [data.terraform_remote_state.network.outputs.ssm_only_sg_id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_server_instance_type
  root_volume_size_gb  = var.jenkins_server_volume_size_gb
  associate_public_ip  = false
  iam_instance_profile = local.ssm_profile
  project_name         = var.project_name
  env                  = var.env
  ssm_access           = "devs" # Allow "Devs" group SSM access
  depends_on           = [null_resource.require_amis]

  user_data = module.ud_jenkins_server.content
}

module "ud_gitlab" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.module}/../../../modules/userdata/compose/gitlab.sh",
    templatefile("../../../modules/userdata/templates/gitlab_env.tpl", {
      external_url  = local.gitlab_self_url        # http://localhost (self-reference)
      trusted_cidrs = local.gitlab_trusted_cidrs   # Private subnet CIDRs
      trusted_array = local.gitlab_trusted_array   # Private subnet array
      gitlab_host   = "gitlab-server.vpc.internal" # Internal FQDN
    })
  ]
}


module "gitlab" {
  source              = "../../../modules/ec2"
  name                = "${var.project_name}-gitlab-server"
  ami_id              = local.gitlab_ami_resolved
  subnet_id           = element(data.terraform_remote_state.network.outputs.private_subnet_ids, 1 % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids              = [data.terraform_remote_state.network.outputs.ssm_only_sg_id]
  key_name            = data.terraform_remote_state.network.outputs.key_name
  instance_type       = var.gitlab_server_instance_type
  root_volume_size_gb = var.gitlab_volume_size_gb
  associate_public_ip = false
  project_name        = var.project_name
  env                 = var.env
  ssm_access          = "devs" # Allow "Devs" group SSM access
  user_data           = module.ud_gitlab.content

  iam_instance_profile = local.ssm_profile
  depends_on           = [null_resource.require_amis]
}

module "ud_jenkins_agent" {
  source = "../../../modules/userdata"
  scripts = [
    "${path.module}/../../../modules/userdata/common/swap.sh",
    "${path.module}/../../../modules/userdata/common/ssm.sh",
    "${path.module}/../../../modules/userdata/common/docker.sh",
    "${path.module}/../../../modules/userdata/compose/jenkins_agent.sh",
    templatefile("../../../modules/userdata/templates/jenkins_agnt_env.tpl",
      {
        jenkins_url = local.jenkins_for_agents # http://jenkins-server.vpc.internal:8080
    })
  ]
}

module "jenkins_agent" {
  source               = "../../../modules/ec2"
  for_each             = { for i in range(var.jenkins_agent_count) : i => i }
  name                 = "${var.project_name}-jenkins-agent-${each.key}"
  ami_id               = data.terraform_remote_state.network.outputs.ubuntu_ami_id
  subnet_id            = element(data.terraform_remote_state.network.outputs.private_subnet_ids, each.key % length(data.terraform_remote_state.network.outputs.private_subnet_ids))
  sg_ids               = [aws_security_group.sg_jenkins_agt.id]
  key_name             = data.terraform_remote_state.network.outputs.key_name
  instance_type        = var.jenkins_agent_instance_type
  root_volume_size_gb  = var.jenkins_agent_volume_size_gb
  associate_public_ip  = false
  user_data            = module.ud_jenkins_agent.content
  iam_instance_profile = local.ssm_profile
  depends_on           = [null_resource.require_amis]
  project_name         = var.project_name
  env                  = var.env
}
