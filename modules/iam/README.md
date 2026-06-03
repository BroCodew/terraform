# IAM Module Guide

This folder contains a Terraform module that creates the IAM role required for ECS tasks to run properly.

The main file is `main.tf`.

This module creates:

- One IAM Role (`aws_iam_role`)
- One IAM Role Policy Attachment (attaches a managed policy)

## Purpose In This Project

ECS tasks need permissions to do certain things, such as:

- Pulling Docker images from ECR
- Writing logs to CloudWatch Logs
- (In bigger systems) reading secrets, accessing S3, etc.

You cannot give permissions directly to a task. Instead, you create an **IAM Role** and attach it to the Task Definition. AWS then gives temporary credentials to every running task using this role.

This module is called from the root [app.tf](../../app.tf):

```hcl
module "iam" {
  for_each = var.app_stacks

  source = "./modules/iam"

  execution_role_name = each.value.iam_execution_role_name
}
```

The output (`ecs_task_execution_role_arn`) is then passed to the ECS module:

```hcl
execution_role_arn = module.iam[each.key].ecs_task_execution_role_arn
```

## Big Picture: Why ECS Needs an IAM Role

When your container starts on Fargate, it needs to talk to AWS services (ECR, CloudWatch, etc.).

AWS uses **IAM Roles for Tasks** (also called Task Execution Role) to give temporary credentials to the container without putting AWS access keys inside your Docker image.

This is much safer than hardcoding credentials.

The role created by this module is specifically the **Task Execution Role** (not the Task Role).

| Role Type              | Purpose                                      | Used By                  |
|------------------------|----------------------------------------------|--------------------------|
| Task Execution Role    | Pull image from ECR, write logs to CloudWatch | The ECS agent / Fargate  |
| Task Role              | What your application code is allowed to do (S3, DynamoDB, Secrets Manager, etc.) | Your application inside the container |

This module only creates the **Task Execution Role**.

## The Two Resources Created

### 1. The IAM Role + Trust Policy

```hcl
resource "aws_iam_role" "ecs_task_execution" {
  name = var.execution_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
```

#### Detailed Explanation

**`name`**
- The name of the IAM role in AWS (example: `ecs-task-execution-role-tr`)

**`assume_role_policy` (The Trust Policy)**

This is the most important part for beginners to understand.

A **Trust Policy** answers the question:

> "Who is allowed to assume (use) this role?"

In this case:

```json
{
  "Effect": "Allow",
  "Principal": {
    "Service": "ecs-tasks.amazonaws.com"
  },
  "Action": "sts:AssumeRole"
}
```

This means:

> "The ECS service (ecs-tasks.amazonaws.com) is allowed to assume this role and receive temporary credentials."

Without this trust policy, ECS would not be allowed to use the role.

`jsonencode()` is used here for the same reason as in the ECS module — it converts nice HCL syntax into valid JSON that the AWS IAM API expects.

### 2. Attaching the Managed Policy

```hcl
resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  role       = aws_iam_role.ecs_task_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```

This attaches a pre-built AWS managed policy to our role.

**What does `AmazonECSTaskExecutionRolePolicy` allow?**

It gives permission to:
- Pull images from ECR (`ecr:GetAuthorizationToken`, `ecr:BatchGetImage`, etc.)
- Write logs to CloudWatch Logs (`logs:CreateLogStream`, `logs:PutLogEvents`)
- Some other basic actions needed by Fargate

This is the standard, recommended policy for ECS Task Execution Roles.

## Example Values

From the default in root [variables.tf](../../variables.tf):

```hcl
iam_execution_role_name = "ecs-task-execution-role-tr"
```

After creation, the full ARN looks like:

```
arn:aws:iam::501360634452:role/ecs-task-execution-role-tr
```

This ARN is what gets passed into the Task Definition.

## How This Role Is Used

Inside the ECS Task Definition (`modules/ecs/main.tf`):

```hcl
resource "aws_ecs_task_definition" "app" {
  ...
  execution_role_arn = var.execution_role_arn
  ...
}
```

When Fargate starts your task, it does the following:

1. Uses the trust policy to assume the IAM role.
2. Receives temporary AWS credentials.
3. Uses those credentials to pull your image from ECR.
4. Uses those credentials to send logs to CloudWatch.

All of this happens automatically — your container code does not need to know anything about AWS credentials.

## Module Outputs

```hcl
output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_task_execution.arn
}
```

This is the only output. It is required by the ECS module.

## Beginner Notes

**Why can't I just use my own IAM user credentials?**

You could during development, but it is a very bad practice for these reasons:

- Your long-lived access keys would be embedded in the task (insecure).
- You would give the container far more permissions than it needs.
- It breaks when you rotate your keys.

IAM Roles for Tasks solve all of these problems.

**Can I add more permissions later?**

Yes. In real projects you often create a second role called the **Task Role** (different from Task Execution Role) and give it permissions for whatever your application needs (reading S3 buckets, calling other APIs, etc.).

This module only handles the minimum required for ECS + Fargate to work.

**What if I change the role name?**

Terraform will destroy the old role and create a new one. Any running tasks will continue using the old role until they are replaced.

**Is attaching a managed policy good practice?**

For the Task Execution Role, using the official `AmazonECSTaskExecutionRolePolicy` is the recommended approach by AWS. For your own application permissions, you should usually create custom policies with least privilege.

## Resource Address Cheat Sheet

```text
module.iam["main"].aws_iam_role.ecs_task_execution
module.iam["main"].aws_iam_role_policy_attachment.ecs_task_execution
```

Useful command:

```bash
terraform state show module.iam["main"].aws_iam_role.ecs_task_execution
```

---

This is one of the smallest modules in the project, but it is **critical for security and functionality**. Without this role, your ECS tasks would not be able to start (they would fail with permission errors when trying to pull the image or write logs).