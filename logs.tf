resource "aws_cloudwatch_log_group" "app_logs" {
  name              = "/ecs/my-app-logs-tr"
  retention_in_days = 7
  tags = {
  Name = "my-app-logs-tr" }
}