# Logs Module Guide

This folder contains a very small but important Terraform module that creates a CloudWatch Log Group for your application.

The main file is `main.tf`.

This module creates:

- One CloudWatch Logs Log Group (`aws_cloudwatch_log_group`)

## Purpose In This Project

When your containers write logs (using `console.log`, `print`, or any logging library), those logs need to go somewhere.

In this architecture, ECS is configured to send all container stdout/stderr to **AWS CloudWatch Logs**.

This module creates the destination (the Log Group) where those logs will be stored.

It is called from the root [app.tf](../../app.tf):

```hcl
module "logs" {
  for_each = var.app_stacks

  source = "./modules/logs"

  log_group_name     = each.value.log_group_name
  log_group_tag_name = each.value.log_group_tag_name
  retention_in_days  = each.value.log_retention_in_days
  common_tags        = var.common_tags
}
```

The output is passed to the ECS module:

```hcl
log_group_name = module.logs[each.key].app_log_group_name
```

Inside the ECS Task Definition, this log group name is used in the `logConfiguration` section.

## Big Picture: Why We Need CloudWatch Logs

When you run containers on Fargate:

- There is no EC2 instance for you to SSH into.
- You cannot run `docker logs`.
- The only practical way to see what your application is printing is through a centralized logging service.

**CloudWatch Logs** is AWS's built-in log storage and search service.

Benefits:
- Logs are stored durably (even if your tasks die).
- You can search and filter logs in the AWS Console.
- You can set up alarms on error patterns.
- Retention is configurable (you don't have to keep logs forever).

## The Resource Created

```hcl
resource "aws_cloudwatch_log_group" "app_logs" {
  name              = var.log_group_name
  retention_in_days = var.retention_in_days
  tags              = merge(var.common_tags, { Name = var.log_group_tag_name })
}
```

### Explanation of each argument

**`name`**

This is the full name of the log group.

Example from defaults:
```hcl
log_group_name = "/ecs/my-app-logs-tr"
```

**Naming convention note:**
AWS and many teams use a forward-slash prefix style for log groups:
- `/ecs/...` for ECS logs
- `/aws/lambda/...` for Lambda logs
- `/aws/rds/...` for RDS logs

This makes them easy to find and organize in the console.

**`retention_in_days`**

How long CloudWatch should keep the log events before automatically deleting them.

Common values:
- `1`, `3`, `5`, `7`, `14`, `30`, `60`, `90`, `120`, `150`, `180`, `365`, `400`, `545`, `731`, `1827`, `3653`

From the project default:
```hcl
log_retention_in_days = 7
```

This means logs older than 7 days are automatically deleted. This is a good default for development and cost control.

**`tags`**

Standard tagging using `merge()`, exactly like other modules in this project.

## How ECS Uses This Log Group

In the ECS Task Definition (`modules/ecs/main.tf`), you will see this block inside the container definition:

```hcl
logConfiguration = {
  logDriver = "awslogs"
  options = {
    awslogs-group         = var.log_group_name
    awslogs-region        = var.aws_region
    awslogs-stream-prefix = var.config.awslogs_stream_prefix
  }
}
```

### What each option does:

- `logDriver = "awslogs"` → Use the official AWS logs driver for ECS.
- `awslogs-group` → Which log group to send logs to (created by this module).
- `awslogs-region` → The region (must match where the log group lives).
- `awslogs-stream-prefix` → A prefix for the log streams inside the group.

**Log Stream example:**

After your task runs, you will see log streams with names like:

```
/ecs/my-app/1234567890abcdef
```

The `awslogs-stream-prefix` (`ecs` in the default) helps group streams by service.

## Example Values (from root variables)

```hcl
log_group_name        = "/ecs/my-app-logs-tr"
log_group_tag_name    = "my-app-logs-tr"
log_retention_in_days = 7
```

## Viewing Logs After Deployment

Once everything is running, you can view logs in two main ways:

### 1. AWS Console
1. Go to CloudWatch → Log groups
2. Find `/ecs/my-app-logs-tr`
3. Click on it → you will see log streams from your tasks

### 2. AWS CLI

```bash
# List log streams
aws logs describe-log-streams \
  --log-group-name "/ecs/my-app-logs-tr" \
  --order-by LastEventTime \
  --descending

# Tail logs live (very useful)
aws logs tail "/ecs/my-app-logs-tr" --follow
```

## Module Outputs

```hcl
output "app_log_group_name" {
  value = aws_cloudwatch_log_group.app_logs.name
}
```

Only the name is needed by the ECS module (not the ARN in this case).

## Beginner Notes

**Do I need to create the Log Group before the ECS service?**

Yes. If the log group does not exist when the task starts, the container will fail to start with a log driver error. Terraform handles this automatically because the ECS module references the output of this module.

**What happens to logs when I destroy the infrastructure?**

If you run `terraform destroy`, the log group will be deleted along with all the logs inside it. Be careful in production — you may want to set `skip_destroy = true` or manage log groups outside of the normal destroy cycle.

**Can I send logs to multiple places?**

Yes. In more advanced setups, people send logs to both CloudWatch **and** other systems (like Datadog, ELK, Grafana Loki, etc.) using sidecar containers or the AWS FireLens log driver.

For learning and most small-to-medium workloads, CloudWatch Logs + this module is perfectly sufficient.

**Cost consideration**

CloudWatch Logs charges for:
- Data ingested (per GB)
- Data stored (per GB-month)
- Requests (GetLogEvents, etc.)

With 7-day retention and low traffic, this is usually very cheap (often under $1/month for development use).

## Resource Address Cheat Sheet

```text
module.logs["main"].aws_cloudwatch_log_group.app_logs
```

Useful commands:

```bash
terraform state show module.logs["main"].aws_cloudwatch_log_group.app_logs

# Force recreation of the log group (deletes existing logs!)
terraform apply -replace=module.logs["main"].aws_cloudwatch_log_group.app_logs
```

---

Even though this is the smallest module in the application stack, centralized logging is one of the most important operational requirements when running containers. Without it, debugging production issues becomes extremely painful. This simple module gives you a solid foundation.