data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/eks/terraform.tfstate"
    region = var.region
  }
}

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

data "cloudflare_zones" "this" {
  name = var.zone_name
}

locals {
  eks_oidc_provider_arn = data.terraform_remote_state.eks.outputs.oidc_provider_arn
  eks_oidc_issuer_url   = data.terraform_remote_state.eks.outputs.cluster_oidc_issuer_url

  # Cloudflare root zone id
  cf_zone_id = data.cloudflare_zones.this.result[0].id

  # r53 subdomain we delegate to AWS
  r53_subdomain = "r53.${var.base_domain}"

  # convenience
  env_fqdn_base     = "${var.env}.${var.base_domain}"
  env_fqdn_r53_base = "${var.env}.r53.${var.base_domain}"
}

################## ONE TIME R53 REG ONLY WHEN ENV=DEV ########################
resource "aws_route53_zone" "r53" {
  count   = var.env == "dev" ? 1 : 0
  name    = local.r53_subdomain
  comment = "Delegated to Route53 for ExternalDNS-managed records"
}

# Delegate the subdomain from Cloudflare → Route53 (creates 4 NS records in CF)
resource "cloudflare_dns_record" "delegate_r53_subdomain" {
  # Route53 returns 4 NS records for a hosted zone; create 4 CF records when env=dev
  count   = var.env == "dev" ? 4 : 0
  zone_id = local.cf_zone_id
  name    = local.r53_subdomain
  type    = "NS"
  # index into name_servers; use try() to avoid errors if list is not yet available during plan
  content = try(aws_route53_zone.r53[0].name_servers[count.index], "")
  ttl     = 3600
  proxied = false
}

#########################################################
# ACM Certificate for Public App (HTTPS)
#########################################################

# ACM Certificate for the public app
resource "aws_acm_certificate" "app" {
  count             = var.env == "dev" ? 1 : 0
  domain_name       = "app.${var.env}.r53.${var.base_domain}"
  validation_method = "DNS"

  # Optional: Add SAN for wildcard or additional domains
  subject_alternative_names = [
    "*.${var.env}.r53.${var.base_domain}",      # Wildcard for subpaths
    "weather.${var.env}.r53.${var.base_domain}" # Weather app specifically
  ]

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name        = "app-${var.env}-cert"
    Purpose     = "Public app HTTPS"
    Environment = var.env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# Route53 Records for ACM DNS validation
resource "aws_route53_record" "app_validation" {
  for_each = var.env == "dev" ? {
    for dvo in aws_acm_certificate.app[0].domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
    # Ensure consistent ordering by filtering to unique domain names
    if dvo.domain_name != ""
  } : {}

  allow_overwrite = true
  zone_id         = aws_route53_zone.r53[0].zone_id
  name            = each.value.name
  type            = each.value.type
  records         = [each.value.record]
  ttl             = 60
}

# ACM Certificate validation
resource "aws_acm_certificate_validation" "app" {
  count                   = var.env == "dev" ? 1 : 0
  certificate_arn         = aws_acm_certificate.app[0].arn
  validation_record_fqdns = [for record in aws_route53_record.app_validation : record.fqdn]

  timeouts {
    create = "10m"
  }
}

#########################################################
# IAM Role and Policy for ExternalDNS (IRSA)
data "aws_iam_policy_document" "oidc_trust" {
  statement {
    effect = "Allow"
    principals {
      type        = "Federated"
      identifiers = [local.eks_oidc_provider_arn] #
    }
    actions = ["sts:AssumeRoleWithWebIdentity"]
    condition {
      test     = "StringEquals"
      variable = "${replace(local.eks_oidc_issuer_url, "https://", "")}:sub"
      values   = ["system:serviceaccount:external-dns:external-dns"]
    }
    condition {
      test     = "StringEquals"
      variable = "${replace(local.eks_oidc_issuer_url, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

#IAM policy for ExternalDNS (Route53)
data "aws_iam_policy_document" "external_dns" {
  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [
      try(aws_route53_zone.r53[0].arn, ""),
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ListResourceRecordSets",
    ]
    resources = [
      try(aws_route53_zone.r53[0].arn, ""),
    ]
  }
  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
      "route53:ListTagsForResource",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "external_dns" {
  name        = "external-dns-${var.env}"
  description = "ExternalDNS Route53 permissions (${var.env})"
  policy      = data.aws_iam_policy_document.external_dns.json
}

#IAM role for ExternalDNS (assumed via IRSA)
resource "aws_iam_role" "external_dns" {
  name               = "irsa-external-dns-${var.env}"
  assume_role_policy = data.aws_iam_policy_document.oidc_trust.json
}

resource "aws_iam_role_policy_attachment" "external_dns_attach" {
  role       = aws_iam_role.external_dns.name
  policy_arn = aws_iam_policy.external_dns.arn
}

#########################################################
# Private DNS Zone for Internal Service Discovery
#########################################################

# Private Route53 zone for internal service discovery
resource "aws_route53_zone" "internal" {
  name    = "vpc.internal"
  comment = "Private zone for VPC internal service discovery"

  vpc {
    vpc_id = data.terraform_remote_state.network.outputs.vpc_id
  }

  tags = {
    Name        = "${var.project_name}-${var.env}-internal-zone"
    Purpose     = "Internal service discovery"
    Environment = var.env
    Project     = var.project_name
    ManagedBy   = "Terraform"
  }
}

# DNS A records for CICD services
resource "aws_route53_record" "gitlab_server" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "gitlab-server.vpc.internal"
  type    = "A"
  ttl     = 300
  records = [data.terraform_remote_state.cicd.outputs.gitlab_private_ip]

  depends_on = [aws_route53_zone.internal]
}

resource "aws_route53_record" "jenkins_server" {
  zone_id = aws_route53_zone.internal.zone_id
  name    = "jenkins-server.vpc.internal"
  type    = "A"
  ttl     = 300
  records = [data.terraform_remote_state.cicd.outputs.jenkins_private_ip]

  depends_on = [aws_route53_zone.internal]
}
