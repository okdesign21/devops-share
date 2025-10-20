data "terraform_remote_state" "network" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/${var.env}/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "cicd" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/${var.env}/cicd/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.state_prefix}/${var.env}/eks/terraform.tfstate"
    region = var.region
  }
}

data "cloudflare_zones" "this" {
  name = var.zone_name
}

locals {
  vpc_id             = data.terraform_remote_state.network.outputs.vpc_id
  private_subnet_ids = data.terraform_remote_state.network.outputs.private_subnet_ids
  zone_id            = one(data.cloudflare_zones.this.zones).id
  jenkins_host       = "jenkins.${var.env}.${var.base_domain}"
  gitlab_host        = "gitlab.${var.env}.${var.base_domain}"
  cicd_alb           = data.terraform_remote_state.cicd.outputs.cicd_alb_dns
  cluster_endpoint   = element(split("/", replace(replace(data.terraform_remote_state.eks.outputs.cluster_endpoint, "https://", ""), "http://", "")), 0)
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

resource "cloudflare_record" "jenkins" {
  zone_id = local.zone_id
  name    = local.jenkins_host
  type    = "CNAME"
  value   = local.cicd_alb
  proxied = false
}

resource "cloudflare_record" "gitlab" {
  zone_id = local.zone_id
  name    = local.gitlab_host
  type    = "CNAME"
  value   = local.cicd_alb
  proxied = false
}

resource "cloudflare_record" "weather_app" {
  zone_id = local.zone_id
  name    = "weather.${var.env}.${var.base_domain}"
  type    = "CNAME"
  ttl     = 300
  value   = local.cluster_endpoint
  proxied = false
}

resource "cloudflare_record" "argo_cd" {
  zone_id = local.zone_id
  name    = "argocd.${var.env}.${var.base_domain}"
  type    = "CNAME"
  ttl     = 300
  value   = local.cluster_endpoint
  proxied = false
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