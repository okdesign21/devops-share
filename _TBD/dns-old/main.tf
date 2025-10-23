data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "cicd" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/cicd/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks-addons" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/eks-addons/terraform.tfstate"
    region = var.region
  }
}

data "cloudflare_zones" "this" {
  name = var.zone_name
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  zone_id            = data.cloudflare_zones.this.result[0].id

  # CICD outputs - use try() to handle missing/empty state
  cicd_alb           = try(data.terraform_remote_state.cicd.outputs.cicd_alb_dns, "")
  jenkins_private_ip = try(data.terraform_remote_state.cicd.outputs.jenkins_private_ip, "")
  gitlab_private_ip  = try(data.terraform_remote_state.cicd.outputs.gitlab_private_ip, "")

  # Check if CICD resources exist
  has_cicd_resources = local.cicd_alb != "" && local.jenkins_private_ip != "" && local.gitlab_private_ip != ""

  jenkins_host = "jenkins.${var.env}.${var.base_domain}"
  gitlab_host  = "gitlab.${var.env}.${var.base_domain}"

  # EKS addons outputs - use try() to handle missing/empty state
  ingress_alb_dns  = try(data.terraform_remote_state.eks-addons.outputs.cluster_alb_dns_name, "")
  ingress_alb_zone = try(data.terraform_remote_state.eks-addons.outputs.cluster_alb_zone_id, "")

  # Check if EKS ingress exists
  has_eks_ingress = local.ingress_alb_dns != "" && local.ingress_alb_zone != ""

  weather_app_host = "weather.${var.env}.${var.base_domain}"
  argocd_host      = "argocd.${var.env}.${var.base_domain}"
}

resource "aws_route53_zone" "private" {
  name = "${var.env}.${var.base_domain}"
  vpc {
    vpc_id = local.vpc_id
  }
}

resource "aws_acm_certificate" "apps" {
  domain_name               = "*.${var.base_domain}"
  validation_method         = "DNS"
  subject_alternative_names = [var.base_domain]

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_dns_record" "jenkins" {
  count   = local.has_cicd_resources ? 1 : 0
  zone_id = local.zone_id
  name    = local.jenkins_host
  type    = "CNAME"
  content = local.cicd_alb
  proxied = false
  ttl     = 300
}

resource "aws_route53_record" "jenkins_private" {
  count   = local.has_cicd_resources ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "jenkins"
  type    = "A"
  ttl     = 60
  records = [local.jenkins_private_ip]
}


resource "cloudflare_dns_record" "gitlab" {
  count   = local.has_cicd_resources ? 1 : 0
  zone_id = local.zone_id
  name    = local.gitlab_host
  type    = "CNAME"
  content = local.cicd_alb
  proxied = false
  ttl     = 300
}

resource "aws_route53_record" "gitlab_private" {
  count   = local.has_cicd_resources ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "gitlab"
  type    = "A"
  ttl     = 60
  records = [local.gitlab_private_ip]
}

resource "cloudflare_dns_record" "weather_app" {
  count   = local.has_eks_ingress ? 1 : 0
  zone_id = local.zone_id
  name    = local.weather_app_host
  type    = "CNAME"
  ttl     = 300
  content = local.ingress_alb_dns
  proxied = false
}

resource "aws_route53_record" "weather" {
  count   = local.has_eks_ingress ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "weather"
  type    = "A"
  alias {
    name                   = local.ingress_alb_dns
    zone_id                = local.ingress_alb_zone
    evaluate_target_health = true
  }
}

resource "cloudflare_dns_record" "argo_cd" {
  count   = local.has_eks_ingress ? 1 : 0
  zone_id = local.zone_id
  name    = local.argocd_host
  type    = "CNAME"
  ttl     = 300
  content = local.ingress_alb_dns
  proxied = false
}

resource "aws_route53_record" "argocd" {
  count   = local.has_eks_ingress ? 1 : 0
  zone_id = aws_route53_zone.private.zone_id
  name    = "argocd"
  type    = "A"
  alias {
    name                   = local.ingress_alb_dns
    zone_id                = local.ingress_alb_zone
    evaluate_target_health = true
  }
}
