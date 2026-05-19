resource "aws_ecs_cluster" "main" {
  name = var.config.cluster_name
  tags = merge(var.common_tags, { Name = var.config.cluster_name })
}

resource "aws_ecs_task_definition" "app" {
  family                   = var.config.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.config.task_cpu
  memory                   = var.config.task_memory
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = var.config.container_name
      image     = "${var.ecr_repository_url}:${var.config.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.config.container_port
          hostPort      = var.config.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = var.config.awslogs_stream_prefix
        }
      }
    }
  ])

  tags = merge(var.common_tags, { Name = var.config.task_family })
}

resource "aws_ecs_service" "app" {
  name            = var.config.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.config.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.config.container_name
    container_port   = var.config.container_port
  }

  tags = merge(var.common_tags, { Name = var.config.service_name })
}
