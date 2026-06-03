# AWS WAF (Web Application Firewall) in front of the ALB
# Controlled by waf_config.enabled in terraform.tfvars

module "waf" {
  count = var.waf_config.enabled ? 1 : 0

  source = "./modules/waf"

  name        = var.waf_config.name
  alb_arn     = module.alb["main"].alb_arn
  rate_limit  = var.waf_config.rate_limit
  common_tags = var.common_tags
}
