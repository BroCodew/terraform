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
  execution_role_arn       = aws_iam_role.ecs_task_execution.arn

  container_definitions = jsonencode([
    {
      name      = "my-app"
      image     = "${aws_ecr_repository.app.repository_url}:latest"
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
          awslogs-group         = aws_cloudwatch_log_group.app_logs.name
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
    subnets          = [aws_subnet.private_a.id, aws_subnet.private_b.id]
    security_groups  = [aws_security_group.ecs_task.id]
    assign_public_ip = false

  }

  load_balancer {
    target_group_arn = aws_alb_target_group.app.arn
    container_name   = "my-app"
    container_port   = 3000
  }

  depends_on = [aws_lb_listener.app]

}