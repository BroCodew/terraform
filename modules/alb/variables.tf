variable "vpc_id" {
  description = "VPC ID for ALB resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB"
  type        = list(string)
}

variable "config" {
  description = "ALB, target group, listener, and security group settings."
  type = object({
    alb_security_group_name          = string
    alb_ingress_cidr_blocks          = list(string)
    alb_egress_cidr_blocks           = list(string)
    ecs_task_security_group_name     = string
    ecs_task_egress_cidr_blocks      = list(string)
    alb_name                         = string
    target_group_name                = string
    listener_name                    = string
    listener_port                    = number
    target_group_port                = number
    health_check_path                = string
    health_check_interval            = number
    health_check_timeout             = number
    health_check_healthy_threshold   = number
    health_check_unhealthy_threshold = number
    health_check_matcher             = string

    # HTTPS and custom domain support (optional)
    enable_https    = optional(bool, false)
    certificate_arn = optional(string, null)
  })
}

variable "common_tags" {
  description = "Tags applied to ALB resources."
  type        = map(string)
  default     = {}
}
