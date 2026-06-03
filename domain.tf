# Domain, ACM certificate, and Route53 records
# This is enabled when you set domain_config.enabled = true in terraform.tfvars
# and have created + delegated the Route53 hosted zone.

module "acm" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/acm"

  domain_name               = var.domain_config.domain_name
  subject_alternative_names = var.domain_config.subject_alternative_names
  zone_id                   = var.domain_config.zone_id
  common_tags               = var.common_tags
}

module "route53" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/route53"

  zone_id      = var.domain_config.zone_id
  name         = var.domain_config.record_name
  alb_dns_name = module.alb["main"].alb_dns_name
  alb_zone_id  = module.alb["main"].alb_zone_id
}
