data "terraform_remote_state" "eks" {
  backend = "s3"
  config = {
    bucket = var.state_bucket
    key    = "${var.project_name}/${var.env}/eks/terraform.tfstate"
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
#######################################################

variable "app_hosts" {
  type    = list(string)
  default = ["app", "gitlab", "jenkins"]
}

resource "cloudflare_dns_record" "apps_env_cnames" {
  for_each = toset(var.app_hosts)

  zone_id = local.cf_zone_id
  name    = "${each.key}.${var.env}.${var.base_domain}"
  type    = "CNAME"
  content = "${each.key}.${local.env_fqdn_r53_base}"
  ttl     = 120
  proxied = false
}

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
      values   = ["system:serviceaccount:kube-system:external-dns"]
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
