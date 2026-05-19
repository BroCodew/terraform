output "ecs_task_security_group_id" {
  value = aws_security_group.ecs_task.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "listener_arn" {
  value = aws_lb_listener.app.arn
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}
