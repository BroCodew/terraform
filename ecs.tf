module "ecs" {
  source = "./modules/ecs"

  aws_region         = var.aws_region
  ecr_repository_url = module.ecr.repository_url
  execution_role_arn = module.iam.ecs_task_execution_role_arn
  log_group_name     = module.logs.app_log_group_name
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [module.alb.ecs_task_security_group_id]
  target_group_arn   = module.alb.target_group_arn

  depends_on = [module.alb]
}
