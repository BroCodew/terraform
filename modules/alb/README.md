# ALB Module Guide

This folder contains a Terraform module that creates an Application Load Balancer setup for ECS services.
The main file is `main.tf`.

This module creates:

- One security group for the ALB
- One security group for ECS tasks
- One internet-facing Application Load Balancer
- One target group
- One listener

## Purpose In This Project

This module is used in the root [app.tf](../../app.tf).

```hcl
module "alb" {
  for_each = var.app_stacks

  source = "./modules/alb"

  vpc_id            = module.network.vpc_id
  public_subnet_ids = module.network.public_subnet_ids
  ...
}
```

The ALB module uses values from the network module:

```hcl
vpc_id            = module.network.vpc_id
public_subnet_ids = module.network.public_subnet_ids
```

That means:

- The ALB is created inside the VPC from `module.network`.
- The ALB is placed in the public subnets from `module.network`.

The ECS module then uses outputs from this ALB module:

```hcl
security_group_ids = [module.alb[each.key].ecs_task_security_group_id]
target_group_arn   = module.alb[each.key].target_group_arn
```

That means:

- ECS tasks use the security group created by this ALB module.
- ECS service registers tasks into the target group created by this ALB module.

## Big Picture

The traffic flow looks like this:

```text
User browser
   |
   | HTTP
   v
Application Load Balancer
   |
   | forwards traffic
   v
Target Group
   |
   | sends traffic to healthy ECS task IPs
   v
ECS Tasks
```

Security group flow:

```text
Internet
   |
   v
ALB security group
   |
   v
ECS task security group
```

## Example Input Values

Example values for one app stack:

```hcl
config = {
  alb_security_group_name      = "app-alb-sg"
  ecs_task_security_group_name = "app-ecs-task-sg"

  alb_name          = "app-alb"
  target_group_name = "app-tg"
  listener_name     = "app-http-listener"

  listener_port     = 80
  target_group_port = 3000

  health_check_path                = "/"
  health_check_interval            = 30
  health_check_timeout             = 5
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2
  health_check_matcher             = "200"

  alb_ingress_cidr_blocks     = ["0.0.0.0/0"]
  alb_egress_cidr_blocks      = ["0.0.0.0/0"]
  ecs_task_egress_cidr_blocks = ["0.0.0.0/0"]
}
```

Example network values passed from the root module:

```hcl
vpc_id = "vpc-0123456789abcdef0"

public_subnet_ids = [
  "subnet-11111111111111111",
  "subnet-22222222222222222"
]
```

## Basic Terraform Syntax

Terraform resources look like this:

```hcl
resource "aws_lb" "app" {
  name = var.config.alb_name
}
```

The general shape is:

```hcl
resource "aws_resource_type" "local_name" {
  argument_name = argument_value
}
```

In this module:

- `resource` means Terraform creates or manages something.
- `aws_lb` is the AWS resource type for a load balancer.
- `app` is the local Terraform name.
- `var.config.alb_name` means the value comes from the `config` variable.
- `aws_lb.app.arn` means Terraform uses the ARN of the load balancer named `app`.

## ALB Security Group

```hcl
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
```

This creates the security group attached to the ALB.
A security group works like a firewall.

### Ingress

```hcl
ingress {
  description = "Allow HTTP traffic"
  from_port   = var.config.listener_port
  to_port     = var.config.listener_port
  protocol    = "tcp"
  cidr_blocks = var.config.alb_ingress_cidr_blocks
}
```

`ingress` means incoming traffic.

Example:

```hcl
listener_port           = 80
alb_ingress_cidr_blocks = ["0.0.0.0/0"]
```

Terraform understands it like:

```hcl
ingress {
  from_port   = 80
  to_port     = 80
  protocol    = "tcp"
  cidr_blocks = ["0.0.0.0/0"]
}
```

This means:

```text
Allow HTTP traffic on port 80 from anywhere on the internet.
```

### Egress

```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = var.config.alb_egress_cidr_blocks
}
```

`egress` means outgoing traffic.

Important syntax:

- `protocol = "-1"` means all protocols.
- `from_port = 0` and `to_port = 0` are used with all protocols.
- `cidr_blocks = ["0.0.0.0/0"]` means the ALB can send traffic anywhere.

In this project, the ALB needs outgoing traffic to send requests to ECS tasks.

## ECS Task Security Group

```hcl
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
```

This creates the security group used by ECS tasks.

The important part is:

```hcl
security_groups = [aws_security_group.alb.id]
```

This does not mean "allow traffic from an IP address".
It means:

```text
Allow traffic from resources that use the ALB security group.
```

That is safer than opening ECS tasks to the internet.
Only the ALB can reach the ECS tasks on the target port.

Example:

```hcl
target_group_port = 3000
```

Then Terraform understands the ECS task ingress rule like:

```hcl
ingress {
  from_port       = 3000
  to_port         = 3000
  protocol        = "tcp"
  security_groups = ["sg-alb-example"]
}
```

This means:

```text
Allow port 3000 only from the ALB security group.
```

## Application Load Balancer

```hcl
resource "aws_lb" "app" {
  name               = var.config.alb_name
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  tags               = merge(var.common_tags, { Name = var.config.alb_name })
}
```

This creates the Application Load Balancer.

Important fields:

- `name` = ALB name in AWS.
- `internal = false` = internet-facing ALB.
- `load_balancer_type = "application"` = layer 7 HTTP/HTTPS load balancer.
- `security_groups` = security group attached to the ALB.
- `subnets` = public subnets where the ALB is placed.

Example:

```hcl
internal = false
```

means:

```text
Users from the internet can reach this ALB, if the security group allows it.
```

This line:

```hcl
subnets = var.public_subnet_ids
```

usually becomes:

```hcl
subnets = [
  "subnet-11111111111111111",
  "subnet-22222222222222222"
]
```

An ALB should use at least two subnets in different Availability Zones for high availability.

## Target Group

```hcl
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
```

The target group is where the ALB sends traffic.
For ECS Fargate, targets are usually task private IP addresses.

Important fields:

- `port` = container/application port.
- `protocol = "HTTP"` = ALB forwards HTTP traffic.
- `target_type = "ip"` = targets are IP addresses, useful for ECS tasks.
- `vpc_id` = target group belongs to this VPC.

Example:

```hcl
target_group_port = 3000
target_type       = "ip"
```

This means:

```text
Forward requests to ECS task IPs on port 3000.
```

## Health Check

```hcl
health_check {
  path                = var.config.health_check_path
  interval            = var.config.health_check_interval
  timeout             = var.config.health_check_timeout
  healthy_threshold   = var.config.health_check_healthy_threshold
  unhealthy_threshold = var.config.health_check_unhealthy_threshold
  matcher             = var.config.health_check_matcher
}
```

The ALB uses health checks to decide which ECS tasks can receive traffic.

Example:

```hcl
health_check_path                = "/"
health_check_interval            = 30
health_check_timeout             = 5
health_check_healthy_threshold   = 2
health_check_unhealthy_threshold = 2
health_check_matcher             = "200"
```

This means:

```text
Every 30 seconds, call GET /
Wait up to 5 seconds for a response
If the task returns HTTP 200 enough times, mark it healthy
If it fails enough times, mark it unhealthy
```

Common examples:

```hcl
health_check_path    = "/"
health_check_matcher = "200"
```

or:

```hcl
health_check_path    = "/health"
health_check_matcher = "200-399"
```

Your application must return a matching HTTP status code on this path.

## Listener

```hcl
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
```

The listener waits for traffic on the ALB.

Important fields:

- `load_balancer_arn` = which ALB this listener belongs to.
- `port` = public port the ALB listens on.
- `protocol = "HTTP"` = listener accepts HTTP traffic.
- `default_action` = what to do with requests.

This line:

```hcl
load_balancer_arn = aws_lb.app.arn
```

means:

```text
Attach this listener to the ALB created earlier.
```

The default action:

```hcl
default_action {
  type             = "forward"
  target_group_arn = aws_lb_target_group.app.arn
}
```

means:

```text
Forward incoming requests to the target group.
```

Example:

```hcl
listener_port = 80
```

Then users access:

```text
http://ALB_DNS_NAME
```

The listener receives traffic on port `80` and forwards it to ECS tasks through the target group.

## Full Evaluated Example

Imagine Terraform receives:

```hcl
vpc_id = "vpc-0123456789abcdef0"

public_subnet_ids = [
  "subnet-11111111111111111",
  "subnet-22222222222222222"
]

config = {
  alb_security_group_name      = "app-alb-sg"
  ecs_task_security_group_name = "app-ecs-task-sg"
  alb_name                     = "app-alb"
  target_group_name            = "app-tg"
  listener_name                = "app-http-listener"
  listener_port                = 80
  target_group_port            = 3000
  health_check_path            = "/health"
  health_check_interval        = 30
  health_check_timeout         = 5
  health_check_healthy_threshold   = 2
  health_check_unhealthy_threshold = 2
  health_check_matcher             = "200"
  alb_ingress_cidr_blocks          = ["0.0.0.0/0"]
  alb_egress_cidr_blocks           = ["0.0.0.0/0"]
  ecs_task_egress_cidr_blocks      = ["0.0.0.0/0"]
}
```

After AWS creates resources, Terraform may have IDs like:

```hcl
aws_security_group.alb.id       = "sg-alb-example"
aws_security_group.ecs_task.id  = "sg-ecs-task-example"
aws_lb.app.arn                  = "arn:aws:elasticloadbalancing:..."
aws_lb_target_group.app.arn     = "arn:aws:elasticloadbalancing:..."
aws_lb.app.dns_name             = "app-alb-123456.ap-southeast-1.elb.amazonaws.com"
```

The important relationship is:

```text
ALB listener port 80
  -> target group port 3000
  -> ECS task private IPs
```

## Terraform Creation Order

Terraform understands most order from references:

1. Create ALB security group.
2. Create ECS task security group that allows traffic from ALB security group.
3. Create ALB in public subnets.
4. Create target group in the VPC.
5. Create listener on the ALB.
6. Listener forwards traffic to the target group.

## Module Outputs

This module exposes these values in `outputs.tf`:

```hcl
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
```

Other modules use these outputs.

Example from ECS module usage in root `app.tf`:

```hcl
security_group_ids = [module.alb[each.key].ecs_task_security_group_id]
target_group_arn   = module.alb[each.key].target_group_arn
```

This means:

- ECS tasks receive the security group that only allows traffic from the ALB.
- ECS service registers itself into the ALB target group.

## Resource Address Cheat Sheet

These are the Terraform addresses in this module:

```text
aws_security_group.alb
aws_security_group.ecs_task
aws_lb.app
aws_lb_target_group.app
aws_lb_listener.app
```

Example command:

```bash
terraform state show module.alb["main"].aws_lb.app
```

Because the root module uses `for_each = var.app_stacks`, the full address may include the app stack key, for example:

```text
module.alb["main"].aws_lb.app
```

## Beginner Notes

- ALB means Application Load Balancer.
- ALB usually lives in public subnets.
- ECS tasks usually live in private subnets.
- The ALB receives internet traffic.
- The target group points to ECS task IPs.
- The listener connects the public ALB port to the target group.

## HTTPS + Custom Domain Support (Added for README_PLAN.md Steps 3–5)

Later we added support for HTTPS on port 443 + automatic HTTP→HTTPS redirect + ACM certificate attachment. This was required so you can use your real domain (`terraformaws.online` or `app.terraformaws.online`) securely.

The changes were made in three places:
1. `variables.tf` — extended the big `config` object type.
2. `main.tf` — security group + listeners.
3. `outputs.tf` — made `listener_arn` smart about which listener exists.

Everything is **conditional** so your existing HTTP-only deployment continues to work unchanged until you set `domain_config.enabled = true`.

### 1. New Fields in the Config Object (modules/alb/variables.tf)

We added these two lines inside the `config` object type:

```hcl
enable_https    = optional(bool, false)
certificate_arn = optional(string, null)
```

**Syntax explained:**

- `optional(bool, false)` — This is a Terraform 1.3+ feature. It means: "This field inside the object is not required. If the caller does not provide it, use `false`."
- `optional(string, null)` — Same idea. Default to `null` (nothing).
- Because the root passes a huge map for each app stack, using `optional()` lets us add new features without forcing every old `app_stacks` definition to be updated immediately.

In the root call (`app.tf`) we **inject** the real values from the top-level `domain_config`:

```hcl
enable_https    = var.domain_config.enabled
certificate_arn = var.domain_config.enabled && length(module.acm) > 0 ? module.acm[0].certificate_arn : null
```

We do **not** read `each.value.enable_https` from the stack map. We control it centrally from `domain_config`. This is simpler while you only have one app.

### 2. Conditional Ingress Rule for Port 443 (modules/alb/main.tf)

Old code only opened whatever `listener_port` was (usually 80).

New code:

```hcl
ingress {
  description = "Allow HTTP traffic"
  from_port   = var.config.listener_port
  ...
}

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
```

**Detailed syntax:**

- The first `ingress {}` block is static — it always exists.
- `dynamic "ingress" { ... }` — this is how you conditionally (or repeatedly) generate nested blocks of the same type.
  - `for_each = condition ? [1] : []` — when the condition is true we give the dynamic block a list with one item. The block runs once. When false we give it an empty list → the block is skipped entirely.
  - Inside `content { }` you write the actual ingress rule that will be created.
- We hard-coded port 443 because that is the standard HTTPS port. We still respect `listener_port` for the HTTP side (so it can stay 80 for the redirect).

Result:
- When `enable_https = false` → only port 80 (or your listener_port) is open in the ALB SG.
- When `enable_https = true` → both 80 and 443 are open.

### 3. The Listener Changes — Using `count` for Conditional Resources

We could not easily make one listener resource change from "forward" to "redirect" using dynamics without very ugly code. So we used the classic `count` pattern.

```hcl
# Forwarding version (the original behavior)
resource "aws_lb_listener" "app" {
  count = var.config.enable_https ? 0 : 1
  ...
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  ...
}

# Redirect version (new)
resource "aws_lb_listener" "http_redirect" {
  count = var.config.enable_https ? 1 : 0
  ...
  default_action {
    type = "redirect"
    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
  ...
}

# HTTPS listener (new)
resource "aws_lb_listener" "https" {
  count = var.config.enable_https ? 1 : 0
  ...
  protocol        = "HTTPS"
  ssl_policy      = "ELBSecurityPolicy-2016-08"
  certificate_arn = var.config.certificate_arn
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
  ...
}
```

**Syntax & concepts explained:**

- `count = condition ? 0 : 1` — another very common conditional resource pattern.
  - When the expression evaluates to 0, Terraform creates **zero** instances of that resource. The address `aws_lb_listener.app` does not exist in the graph.
  - When it is 1, it creates exactly one instance, addressable as `aws_lb_listener.app[0]`.

- Why two different resources for port 80 (`app` vs `http_redirect`)?
  - A single `aws_lb_listener` resource on the same port cannot easily flip between a `forward` action and a `redirect` action without destroying and recreating the listener.
  - By using count we make the "which listener exists on port 80" decision clean.

- Inside the redirect action:
  ```hcl
  redirect {
    port        = "443"
    protocol    = "HTTPS"
    status_code = "HTTP_301"
  }
  ```
  - `status_code = "HTTP_301"` = permanent redirect (browsers and search engines will remember this).
  - This listener still listens on `var.config.listener_port` (80). All traffic that hits port 80 gets told "go to port 443 instead".

- The https listener:
  - `protocol = "HTTPS"`
  - `ssl_policy = "ELBSecurityPolicy-2016-08"` — a named policy that controls which TLS versions and ciphers are allowed. This one is a reasonable default that works with most clients.
  - `certificate_arn = var.config.certificate_arn` — this is the ARN we got from the ACM module. This is what makes the ALB present a certificate to browsers.

- `target_group_arn` still points at the same target group. The backend (ECS on port 3000) stays plain HTTP. The ALB terminates TLS for us.

### 4. Updated Output (modules/alb/outputs.tf)

```hcl
output "listener_arn" {
  value = var.config.enable_https ? aws_lb_listener.https[0].arn : aws_lb_listener.app[0].arn
}
```

Because of `count`, we must use `[0]` indexing when we know the resource exists.

The ternary chooses:
- the https listener ARN when we are in HTTPS mode
- the original app listener when we are still in HTTP-only mode

Other outputs (`alb_dns_name`, `alb_zone_id`, `alb_arn`, `target_group_arn`) did not need changes — they are always useful.

### 5. Root Wiring Summary (for completeness)

- `variables.tf` added the `domain_config` object (with `enabled`, `zone_id`, `domain_name`, `record_name`, etc.).
- `domain.tf` (new file) contains the `module "acm"` and `module "route53"` blocks using `count`.
- `app.tf` passes the certificate and the `enable_https` flag into the alb module's config map.
- `outputs.tf` (root) now also exports `alb_zone_id`, `alb_arn`, and `acm_certificate_arn`.

All of these changes are documented with comments in the code.

## Resource Address Changes When You Enable HTTPS

When `domain_config.enabled` goes from false → true, Terraform will:
- Destroy the old `module.alb["main"].aws_lb_listener.app[0]` (the forward listener)
- Create `module.alb["main"].aws_lb_listener.http_redirect[0]` (port 80 redirect)
- Create `module.alb["main"].aws_lb_listener.https[0]` (port 443 with cert)

This is expected. The ALB itself stays running the whole time — only the listener configuration on it changes.

## What the ALB Now Does (Traffic Flow After HTTPS Is Enabled)

```
User → http://app.terraformaws.online
         │
         v
Route53 Alias record
         │
         v
ALB port 80 listener  →  redirect (301) to https://...
         │
         v
ALB port 443 listener (with ACM cert)
         │
         v
Target Group (health checks on /)
         │
         v
ECS tasks on port 3000 (private IPs)
```

This is the flow the original architecture image wanted.

## Beginner Takeaways from the ALB HTTPS Work

- `count` and `dynamic` are the two main tools for making resources appear/disappear or repeat based on variables.
- You almost never want to manage TLS certificates yourself — let ACM + DNS validation do it.
- The ALB is a "reverse proxy" that terminates HTTPS for you. Your containers can stay simple HTTP.
- Always keep port 80 open if you want automatic redirects (users typing the name without https still get sent to the secure version).
- `security_groups = [aws_security_group.alb.id]` means allow traffic from the ALB security group.
- `target_type = "ip"` is commonly used for ECS Fargate.
- `health_check_path` must be a real route in your application.
- `alb_dns_name` is the URL hostname you can open in the browser.

## Cost Note

Application Load Balancers can cost money while running.
When learning, destroy resources you do not need:

```bash
terraform destroy
```
