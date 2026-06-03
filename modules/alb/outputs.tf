output "ecs_task_security_group_id" {
  value = aws_security_group.ecs_task.id
}

output "target_group_arn" {
  value = aws_lb_target_group.app.arn
}

output "listener_arn" {
  description = "ARN of the primary listener (HTTPS if enabled, otherwise the HTTP one)."
  value       = var.config.enable_https ? aws_lb_listener.https[0].arn : aws_lb_listener.app[0].arn
}

output "alb_dns_name" {
  value = aws_lb.app.dns_name
}

output "alb_arn" {
  value = aws_lb.app.arn
}

output "alb_zone_id" {
  value = aws_lb.app.zone_id
}
