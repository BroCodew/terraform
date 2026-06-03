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

  # Allow HTTPS on the ALB when we have a certificate (plan: Step 4)
  dynamic "ingress" {
    for_each = var.config.enable_https ? [1] : []
    content {
      description = "Allow HTTPS traffic"
      from_port   = 443
      to_port     = 443
      protocol    = "tcp"
      cidr_blocks = var.config.alb_ingress_cidr_blocks
    }
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

# HTTP listener on the configured port (usually 80 from listener_port).
# We use count so that the original resource address "app" only exists when NOT using HTTPS.
# This keeps the current (no domain) behavior 100% unchanged until you enable domain_config.

# Forwarding version (used when HTTPS is disabled) — keeps exact same behavior as before.
resource "aws_lb_listener" "app" {
  count = var.config.enable_https ? 0 : 1

  load_balancer_arn = aws_lb.app.arn
  port              = var.config.listener_port
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(var.common_tags, { Name = var.config.listener_name })
}

# Redirect version on port 80 (used when HTTPS is enabled).
# All HTTP traffic will be redirected to HTTPS with 301.
resource "aws_lb_listener" "http_redirect" {
  count = var.config.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = var.config.listener_port
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }

  tags = merge(var.common_tags, { Name = var.config.listener_name })
}

# HTTPS listener on port 443. Only created when a certificate is provided and enabled.
resource "aws_lb_listener" "https" {
  count = var.config.enable_https ? 1 : 0

  load_balancer_arn = aws_lb.app.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-2016-08"
  certificate_arn   = var.config.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }

  tags = merge(var.common_tags, { Name = "${var.config.listener_name}-https" })
}
