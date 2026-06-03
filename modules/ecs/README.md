# ECS Module Guide

This folder contains a Terraform module that creates the core AWS ECS (Elastic Container Service) resources to run containerized applications using **Fargate**.

The main file is `main.tf`.

This module creates:

- One ECS Cluster
- One ECS Task Definition (Fargate)
- One ECS Service (with load balancer integration)

## Purpose In This Project

This module is the **heart** of the modern application stack. It is called from the root [app.tf](../../app.tf) using `for_each`.

```hcl
module "ecs" {
  for_each = var.app_stacks

  source = "./modules/ecs"

  aws_region         = var.aws_region
  ecr_repository_url = module.ecr[each.key].repository_url
  execution_role_arn = module.iam[each.key].ecs_task_execution_role_arn
  log_group_name     = module.logs[each.key].app_log_group_name
  private_subnet_ids = module.network.private_subnet_ids
  security_group_ids = [module.alb[each.key].ecs_task_security_group_id]
  target_group_arn   = module.alb[each.key].target_group_arn

  config = {
    cluster_name          = each.value.cluster_name
    task_family           = each.value.task_family
    task_cpu              = each.value.task_cpu
    task_memory           = each.value.task_memory
    container_name        = each.value.container_name
    image_tag             = each.value.image_tag
    container_port        = each.value.container_port
    desired_count         = each.value.desired_count
    service_name          = each.value.service_name
    awslogs_stream_prefix = each.value.awslogs_stream_prefix
  }

  common_tags = var.common_tags

  depends_on = [module.alb]
}
```

This module depends on **five other modules**:
- `ecr` → to know which Docker image to run
- `iam` → to give ECS permission to pull images and write logs
- `logs` → CloudWatch log group for container output
- `alb` → Target Group + security group so the ALB can reach the tasks
- `network` → private subnets (tasks should not be directly on the internet)

## Big Picture: ECS Concepts

Before diving into the code, you need to understand these four concepts:

| Concept              | What it is                                      | Analogy                              |
|----------------------|--------------------------------------------------|--------------------------------------|
| **ECS Cluster**      | A logical group that holds your services         | A "parking lot" for your containers |
| **Task Definition**  | A blueprint that says "run this Docker image with these resources" | A recipe (CPU, memory, ports, logs, image) |
| **Task**             | A running copy of a Task Definition              | One actual cooking session from the recipe |
| **Service**          | Keeps the desired number of tasks running        | A manager that makes sure 2 cooks are always working |

This module uses **Fargate** (serverless). You do **not** manage EC2 instances. AWS runs your containers for you.

## The Three Resources Created

### 1. ECS Cluster

```hcl
resource "aws_ecs_cluster" "main" {
  name = var.config.cluster_name
  tags = merge(var.common_tags, { Name = var.config.cluster_name })
}
```

This is the simplest resource.

- `name` = the name of your cluster in the AWS console (example: `my-ecs-cluster-tr`)
- You can put many services inside one cluster. In this project we create one cluster per app stack.

### 2. ECS Task Definition (The Most Important Part)

```hcl
resource "aws_ecs_task_definition" "app" {
  family                   = var.config.task_family
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.config.task_cpu
  memory                   = var.config.task_memory
  execution_role_arn       = var.execution_role_arn

  container_definitions = jsonencode([
    {
      name      = var.config.container_name
      image     = "${var.ecr_repository_url}:${var.config.image_tag}"
      essential = true

      portMappings = [
        {
          containerPort = var.config.container_port
          hostPort      = var.config.container_port
          protocol      = "tcp"
        }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = var.log_group_name
          awslogs-region        = var.aws_region
          awslogs-stream_prefix = var.config.awslogs_stream_prefix
        }
      }
    }
  ])

  tags = merge(var.common_tags, { Name = var.config.task_family })
}
```

#### Breaking down the key arguments:

**`family`**
- A name for this task definition family.
- Every time you update the task definition, AWS creates a new **revision**.
- Example: `my-app-task-tr`

**`requires_compatibilities = ["FARGATE"]`**
- This task definition can **only** run on Fargate (not on EC2).

**`network_mode = "awsvpc"`**
- Required for Fargate.
- Every task gets its own Elastic Network Interface (ENI) with its own private IP.
- This is why we can attach the task directly to a Target Group.

**`cpu` and `memory`**
- These are **task-level** limits (not container level in this simple example).
- Values are in CPU units (1024 = 1 vCPU) and MiB.
- Common small values: `256` CPU + `512` memory (0.25 vCPU, 0.5 GB)

**`execution_role_arn`**
- This is the IAM role created by the `iam` module.
- It gives the task permission to:
  - Pull images from ECR
  - Write logs to CloudWatch
  - (The managed policy `AmazonECSTaskExecutionRolePolicy` covers the basics)

**`container_definitions` (the hardest part for beginners)**

This is a JSON array (written inside Terraform using `jsonencode()`).

Terraform code:
```hcl
container_definitions = jsonencode([
  {
    name  = "my-app"
    image = "501360634452.dkr.ecr...com/my-ecr-repo-tr:latest"
    ...
  }
])
```

After Terraform evaluates it, AWS receives valid JSON like:
```json
[
  {
    "name": "my-app",
    "image": "501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest",
    "essential": true,
    "portMappings": [
      { "containerPort": 3000, "hostPort": 3000, "protocol": "tcp" }
    ],
    "logConfiguration": { ... }
  }
]
```

**Important fields inside the container definition:**

- `image` — Full ECR URL + tag (comes from the `ecr` module output + `image_tag`)
- `essential = true` — If this container crashes, the whole task is considered failed
- `portMappings` — Tells ECS which port inside the container should receive traffic
- `logConfiguration` — Sends stdout/stderr to CloudWatch Logs

### 3. ECS Service

```hcl
resource "aws_ecs_service" "app" {
  name            = var.config.service_name
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.app.arn
  desired_count   = var.config.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = var.security_group_ids
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = var.config.container_name
    container_port   = var.config.container_port
  }

  tags = merge(var.common_tags, { Name = var.config.service_name })
}
```

#### Critical sections explained:

**`desired_count`**
- How many copies of your task should be running at all times.
- Example: `2` means ECS will try to keep exactly 2 tasks healthy.

**`launch_type = "FARGATE"`**
- Run on Fargate (serverless). No EC2 management needed.

**`network_configuration` block**

```hcl
network_configuration {
  subnets          = var.private_subnet_ids
  security_groups  = var.security_group_ids
  assign_public_ip = false
}
```

- `subnets` = private subnets (from the network module). Your tasks should not be publicly reachable.
- `security_groups` = usually the ECS task security group created by the ALB module.
- `assign_public_ip = false` — **Very important**. Tasks get private IPs only.

**`load_balancer` block**

```hcl
load_balancer {
  target_group_arn = var.target_group_arn
  container_name   = var.config.container_name
  container_port   = var.config.container_port
}
```

This connects the ECS service to the Application Load Balancer:

- When the ALB receives traffic, it sends it to the Target Group.
- The Target Group knows about the private IPs of the ECS tasks.
- `container_name` + `container_port` must match exactly what is inside the task definition.

## Example Input Values (from root)

From the default in [variables.tf](../../variables.tf) under `app_stacks.main`:

```hcl
cluster_name          = "my-ecs-cluster-tr"
task_family           = "my-app-task-tr"
task_cpu              = 256
task_memory           = 512
container_name        = "my-app"
image_tag             = "latest"
container_port        = 3000
desired_count         = 2
service_name          = "my-app-service-tr"
awslogs_stream_prefix = "ecs"
```

Passed from other modules (in `app.tf`):

```hcl
ecr_repository_url = "501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr"
execution_role_arn = "arn:aws:iam::501360634452:role/ecs-task-execution-role-tr"
log_group_name     = "/ecs/my-app-logs-tr"
private_subnet_ids = ["subnet-xxx", "subnet-yyy"]
security_group_ids = ["sg-ecs-task-sg-tr"]
target_group_arn   = "arn:aws:elasticloadbalancing:...:targetgroup/app-tg-tr/xxx"
```

## How This Module Connects to Everything

```
ECR Repository (modules/ecr)
        │
        │ image URL
        ▼
ECS Task Definition
        │
        │ uses execution role
        ▼
IAM Role (modules/iam)
        │
        │ writes logs to
        ▼
CloudWatch Log Group (modules/logs)

        ▲
        │ traffic comes from
Target Group ← ALB (modules/alb)
        │
        │ runs tasks in
Private Subnets + Security Group (from modules/network + modules/alb)
```

The ECS service is the "glue" that brings all the other modules together into a running application.

## Resource Address Cheat Sheet

```text
module.ecs["main"].aws_ecs_cluster.main
module.ecs["main"].aws_ecs_task_definition.app
module.ecs["main"].aws_ecs_service.app
```

Useful commands:

```bash
terraform state show module.ecs["main"].aws_ecs_service.app

# Force ECS to use the latest task definition revision
terraform apply -replace=module.ecs["main"].aws_ecs_task_definition.app
```

## Beginner Notes & Common Questions

**Why is `container_definitions` written with `jsonencode()`?**

Terraform cannot directly write complex nested JSON easily in HCL for this field. `jsonencode()` lets you write normal HCL objects and Terraform converts them to valid JSON that the AWS API expects.

**Why `assign_public_ip = false`?**

Because the tasks live in private subnets. Only the ALB (in public subnets) should be reachable from the internet. This is a security best practice.

**What happens if I change the Docker image tag?**

You must update `image_tag` in your `app_stacks` variable, then run `terraform apply`. This creates a new task definition revision. The ECS service will gradually replace old tasks with new ones (blue/green style by default).

**Why do I need both a Target Group and the `load_balancer` block in the service?**

- Target Group = "where the ALB should send traffic"
- The `load_balancer` block in the service = "register these tasks into that Target Group"

Both sides are needed.

**Fargate vs EC2 launch type**

Fargate = AWS manages the underlying servers (easier, more expensive for high load).  
EC2 = You manage a cluster of EC2 instances (more control, cheaper at scale).

This module uses Fargate only.

## Cost Note

Fargate charges per vCPU and memory used **per second**, while tasks are running.

Small example (256 CPU + 512 MiB, 2 tasks, running 24/7) can cost roughly $15–25 USD per month in `ap-southeast-1` (check current pricing).

When learning, remember to `terraform destroy` when you no longer need the environment.

---

This module is the final piece that actually runs your application code. All the other modules (network, ALB, ECR, IAM, logs) exist to support a healthy, secure, observable ECS service.