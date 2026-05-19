resource "aws_ecs_cluster" "main" {
  name = "my-ecs-cluster-tr"
  tags = {
    Name = "my-ecs-cluster-tr"
  }
}

resource "aws_ecs_task_definition" "app" {
  family                   = "my-app-task-tr"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 256
  memory                   = 512
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = "my-app"
      image     = "${var.ecr_repository_url}:latest"
      essential = true

      portMappings = [
        {
          containerPort = 3000
          hostPort      = 3000
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream-prefix = "ecs"
        }
      }
    }
  ])

  tags = {
    Name = "my-app-task-tr"
  }
}

resource "aws_ecs_service" "app" {
  name            = "my-app-service-tr"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = 2
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "my-app"
    container_port   = 3000
  }

  tags = {
    Name = "my-app-service-tr"
  }
}
