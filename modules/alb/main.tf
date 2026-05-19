resource "aws_security_group" "alb" {
  name        = var.config.alb_security_group_name
  description = "Allow HTTP and HTTPS traffic to ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "Allow HTTP traffic"
    from_port   = var.config.listener_port
    to_port     = var.config.listener_port
    protocol    = "tcp"
    cidr_blocks = var.config.alb_ingress_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.config.alb_egress_cidr_blocks
  }

  tags = merge(var.common_tags, { Name = var.config.alb_security_group_name })
}

resource "aws_security_group" "ecs_task" {
  name        = var.config.ecs_task_security_group_name
  description = "Allow traffic from ALB to ECS tasks"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Allow traffic from ALB"
    from_port       = var.config.target_group_port
    to_port         = var.config.target_group_port
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.config.ecs_task_egress_cidr_blocks
  }

  tags = merge(var.common_tags, { Name = var.config.ecs_task_security_group_name })
}

resource "aws_lb" "app" {
  name               = var.config.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  tags               = merge(var.common_tags, { Name = var.config.alb_name })
}

resource "aws_lb_target_group" "app" {
  name        = var.config.target_group_name
  port        = var.config.target_group_port
  protocol    = "HTTP"
  target_type = "ip"
  vpc_id      = var.vpc_id
  health_check {
    path                = var.config.health_check_path
    interval            = var.config.health_check_interval
    timeout             = var.config.health_check_timeout
    healthy_threshold   = var.config.health_check_healthy_threshold
    unhealthy_threshold = var.config.health_check_unhealthy_threshold
    matcher             = var.config.health_check_matcher
  }
  tags = merge(var.common_tags, { Name = var.config.target_group_name })
}

resource "aws_lb_listener" "app" {
  load_balancer_arn = aws_lb.app.arn
  port              = var.config.listener_port
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  tags = merge(var.common_tags, { Name = var.config.listener_name })
}
