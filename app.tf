locals {
  default_app_stack = "main"
}

module "ecr" {
  for_each = var.app_stacks

  source = "./modules/ecr"

  repository_name      = each.value.ecr_repository_name
  image_tag_mutability = each.value.ecr_image_tag_mutability
  scan_on_push         = each.value.ecr_scan_on_push
  common_tags          = var.common_tags
}

module "iam" {
  for_each = var.app_stacks

  source = "./modules/iam"

  execution_role_name = each.value.iam_execution_role_name
}

module "logs" {
  for_each = var.app_stacks

  source = "./modules/logs"

  log_group_name     = each.value.log_group_name
  log_group_tag_name = each.value.log_group_tag_name
  retention_in_days  = each.value.log_retention_in_days
  common_tags        = var.common_tags
}

module "alb" {
  for_each = var.app_stacks

  source = "./modules/alb"

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  config = {
    alb_security_group_name          = each.value.alb_security_group_name
    ecs_task_security_group_name     = each.value.ecs_task_security_group_name
    alb_name                         = each.value.alb_name
    target_group_name                = each.value.target_group_name
    listener_name                    = each.value.listener_name
    listener_port                    = each.value.listener_port
    target_group_port                = each.value.target_group_port
    health_check_path                = each.value.health_check_path
    health_check_interval            = each.value.health_check_interval
    health_check_timeout             = each.value.health_check_timeout
    health_check_healthy_threshold   = each.value.health_check_healthy_threshold
    health_check_unhealthy_threshold = each.value.health_check_unhealthy_threshold
    health_check_matcher             = each.value.health_check_matcher
    alb_ingress_cidr_blocks          = each.value.alb_ingress_cidr_blocks
    alb_egress_cidr_blocks           = each.value.alb_egress_cidr_blocks
    ecs_task_egress_cidr_blocks      = each.value.ecs_task_egress_cidr_blocks

    # HTTPS / custom domain support (comes from top-level domain_config)
    enable_https    = var.domain_config.enabled
    certificate_arn = var.domain_config.enabled && length(module.acm) > 0 ? module.acm[0].certificate_arn : null
  }
  common_tags = var.common_tags
}

module "ecs" {
  for_each = var.app_stacks

  source = "./modules/ecs"

  aws_region         = var.aws_region
  ecr_repository_url = module.ecr[each.key].repository_url
  execution_role_arn = module.iam[each.key].ecs_task_execution_role_arn
  log_group_name     = module.logs[each.key].app_log_group_name
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [module.alb[each.key].ecs_task_security_group_id]
  target_group_arn   = module.alb[each.key].target_group_arn
  config = {
    cluster_name          = each.value.cluster_name
    task_family           = each.value.task_family
    task_cpu              = each.value.task_cpu
    task_memory           = each.value.task_memory
    container_name        = each.value.container_name
    image_tag             = each.value.image_tag
    container_port        = each.value.container_port
    desired_count         = each.value.desired_count
    service_name          = each.value.service_name
    awslogs_stream_prefix = each.value.awslogs_stream_prefix
  }
  common_tags = var.common_tags

  depends_on = [module.alb]
}
