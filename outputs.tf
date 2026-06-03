output "alb_dns_name" {
  value = module.alb[local.default_app_stack].alb_dns_name
}

output "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB. Use this together with alb_dns_name when creating Route53 alias records."
  value       = module.alb[local.default_app_stack].alb_zone_id
}

output "alb_arn" {
  description = "ARN of the ALB (useful for WAF association later)."
  value       = module.alb[local.default_app_stack].alb_arn
}

output "ecr_repository_url" {
  value = module.ecr[local.default_app_stack].repository_url
}

output "ecs_cluster_name" {
  value = module.ecs[local.default_app_stack].cluster_name
}

output "ecs_service_name" {
  value = module.ecs[local.default_app_stack].service_name
}

output "acm_certificate_arn" {
  description = "ARN of the ACM certificate (when domain_config.enabled = true). Null otherwise."
  value       = var.domain_config.enabled && length(module.acm) > 0 ? module.acm[0].certificate_arn : null
}
