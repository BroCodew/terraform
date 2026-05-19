variable "aws_region" {
  description = "AWS region used by the awslogs driver"
  type        = string
}

variable "ecr_repository_url" {
  description = "ECR repository URL for the application image"
  type        = string
}

variable "execution_role_arn" {
  description = "ECS task execution role ARN"
  type        = string
}

variable "log_group_name" {
  description = "CloudWatch log group name for ECS logs"
  type        = string
}

variable "private_subnet_ids" {
  description = "Private subnet IDs for ECS tasks"
  type        = list(string)
}

variable "security_group_ids" {
  description = "Security group IDs for ECS tasks"
  type        = list(string)
}

variable "target_group_arn" {
  description = "ALB target group ARN"
  type        = string
}
