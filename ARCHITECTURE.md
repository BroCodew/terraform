# Project Architecture & Flow

This document describes **how this Terraform project actually works today** (as of the current code).

> **Important Note for Beginners**
>
> The root `README.md` describes a much larger, more advanced platform (EKS, Karpenter, Lambda, SQS, etc.).  
> The **actual code** in this repository is smaller and focused on two things:
> - A basic VPC + EC2 setup (older layer)
> - A complete containerized application stack using ECS Fargate + ALB + ECR (newer layer)
>
> This document describes **reality**, not the aspirational design.

---

## High-Level Architecture

```
                        Internet
                            │
                    ┌───────▼───────┐
                    │  Public ALB   │  ← modules/alb
                    │  (port 80)    │
                    └───────┬───────┘
                            │ forwards to
                    ┌───────▼───────┐
                    │  Target Group │
                    └───────┬───────┘
                            │
            ┌───────────────┴───────────────┐
            ▼                               ▼
    ┌───────────────┐               ┌───────────────┐
    │  ECS Service  │               │  EC2 Instance │  ← modules/ec2 (separate)
    │  (Fargate)    │               │  (standalone) │
    └───────┬───────┘               └───────────────┘
            │
    ┌───────▼───────┐
    │ ECS Cluster   │  ← modules/ecs
    │ Task Definition│
    └───────┬───────┘
            │ pulls image from
    ┌───────▼───────┐
    │  ECR Repo     │  ← modules/ecr
    └───────────────┘

Network Foundation (shared by both)
┌─────────────────────────────────────────────┐
│  VPC (10.0.0.0/16)          modules/network │
│    ├── Public Subnets (A + B)               │
│    ├── Private Subnets (A + B)              │
│    ├── Internet Gateway                     │
│    └── NAT Gateway                          │
└─────────────────────────────────────────────┘
```

**Key Reality Check:**
- The **EC2 instance** and the **ECS Fargate service** are two completely separate workloads.
- They happen to share the same VPC (created by `modules/network`).
- The ECS tasks run in **private subnets** (no public IP).
- The ALB is the only thing directly reachable from the internet for the containerized app.

---

## The Two Layers

This project contains **two architectural layers** that were built at different times.

### Layer 1: Foundational Network + Legacy EC2 (`vpc.tf` + `main.tf`)

| File       | What it does                              | Modules used      |
|------------|-------------------------------------------|-------------------|
| `vpc.tf`   | Creates the entire network                | `modules/network` |
| `main.tf`  | Creates one EC2 instance + storage + extra networking | `modules/ec2`     |

**What gets created:**
- 1 VPC
- 2 public subnets + 2 private subnets
- Internet Gateway + NAT Gateway
- 1 EC2 instance (Amazon Linux 2023) in a public subnet
- Security group allowing SSH (22) and app port (3000)
- Extra EBS volume attached to the EC2
- Secondary ENI + Elastic IP attached to the EC2

This layer is mostly self-contained. It was the original focus of the project (see `MY-INFRASTRUCTURE.md`).

### Layer 2: Modern Container Application Stack (`app.tf`)

This is the more sophisticated part. It lives almost entirely in [app.tf](app.tf) and uses a `for_each` pattern over the `app_stacks` variable.

It creates a full production-style container deployment:

| Module       | Responsibility                                      | Key Resources Created |
|--------------|-----------------------------------------------------|-----------------------|
| `ecr`        | Private Docker image storage                        | `aws_ecr_repository` |
| `iam`        | Permission for ECS to pull images + write logs      | IAM Role + Policy Attachment |
| `logs`       | Centralized logging                                 | CloudWatch Log Group |
| `alb`        | Public entry point + traffic routing                | ALB + 2 Security Groups + Target Group + Listener |
| `ecs`        | Run the actual containers                           | ECS Cluster + Task Definition + Service (Fargate) |

All five modules are called with `for_each = var.app_stacks`. This design makes it possible to deploy multiple different applications later by just adding more keys to the map.

---

## Request Flow (The Most Important Part)

Here is exactly what happens when someone accesses your application:

```
1. User types http://<alb-dns-name> in browser
          │
2. DNS resolves to the public ALB (in public subnets)
          │
3. ALB receives request on port 80
          │
4. ALB checks Target Group health
          │
5. ALB forwards request to a healthy ECS task
   (private IP in private subnet, port 3000)
          │
6. ECS task (your container) processes the request
          │
7. Response goes back: Container → ALB → User
```

**Critical security design:**
- ECS tasks have **no public IP** (`assign_public_ip = false`)
- The only way to reach them is through the ALB
- The ECS task security group only allows traffic from the ALB security group (not from the whole internet)

This is a classic and correct pattern.

---

## Terraform Composition Flow (File by File)

When you run `terraform apply`, Terraform processes files in this order of dependency:

1. **providers.tf**  
   → Tells Terraform we will use the AWS provider in `ap-southeast-1`.

2. **variables.tf** + **terraform.tfvars**  
   → All input values are loaded (network CIDRs, app stack settings, SSH key name, etc.).

3. **vpc.tf**  
   → Calls `module "network"`.  
   → Creates VPC, subnets, IGW, NAT, route tables.  
   → **This must exist first** because almost everything else needs subnet IDs and VPC ID.

4. **main.tf**  
   → Calls `module "ec2"`, passing outputs from the network module.  
   → Creates the standalone EC2 instance + EBS + ENI + EIP.

5. **app.tf** (the heart of the modern stack)
   - `locals { default_app_stack = "main" }`
   - `module "ecr"` (for_each)
   - `module "iam"` (for_each)
   - `module "logs"` (for_each)
   - `module "alb"` (for_each) — depends on `module.network`
   - `module "ecs"` (for_each) — depends on ecr + iam + logs + alb + network

   Terraform automatically figures out most ordering using references (e.g. `module.ecr[each.key].repository_url`).

6. **outputs.tf**  
   → Exposes useful values after apply (ALB DNS name, ECR URL, ECS cluster/service names).

---

## Module Dependency Graph (Simplified)

```
                    ┌─────────────┐
                    │  variables  │
                    └──────┬──────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
   modules/network    modules/ec2     modules/ecr
          │                │                │
          │                │                ▼
          │                │          modules/iam
          │                │                │
          │                │                ▼
          │                │          modules/logs
          │                │                │
          └──────┬─────────┴──────┬─────────┘
                 │                │
                 ▼                ▼
            modules/alb      modules/ecs
                 │                │
                 └────────┬───────┘
                          ▼
                     (outputs)
```

**Real dependency notes:**
- `alb` and `ecs` both need `module.network.*`
- `ecs` needs outputs from **all four** sibling modules (`ecr`, `iam`, `logs`, `alb`)
- The `depends_on = [module.alb]` in `app.tf` is an explicit safety net (Terraform usually doesn't need it).

---

## How Images Get Into ECS (The ECR → ECS Flow)

This is the part beginners often find confusing.

1. You build a Docker image locally.
2. You `docker login` to ECR (using AWS credentials).
3. You `docker tag` and `docker push` the image into the ECR repository created by `modules/ecr`.
4. When ECS starts a task, it uses this string (constructed in `modules/ecs/main.tf`):

```hcl
image = "${var.ecr_repository_url}:${var.config.image_tag}"
```

Example value:
```
501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest
```

AWS automatically pulls this image when launching the Fargate task (using the IAM role from `modules/iam`).

---

## Current State & Observations

### What Works Well
- Clean separation of concerns using modules.
- Good use of `for_each` on `app_stacks` (future-proof).
- Proper private subnet + ALB pattern for ECS Fargate.
- Explicit `moved` blocks show the project was carefully refactored.

### Areas That Deserve Attention
- The EC2 layer and the ECS layer are **two different worlds** sharing one VPC. This can be confusing.
- Many security groups still allow `0.0.0.0/0` (very open). Fine for learning, dangerous for real use.
- No remote backend configured (state lives locally in `terraform.tfstate`).
- `environments/` folder structure documented in root README does not exist yet.
- The old EC2 setup (with secondary ENI + EBS + EIP) is quite complex for what it does. Most people would just use one ENI.

---

## How to Actually Use This Project (Practical Flow)

```bash
# 1. Provide required values
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars and set your key_name

# 2. Initialize
terraform init

# 3. See what will be created
terraform plan

# 4. Deploy everything
terraform apply

# 5. Get useful addresses
terraform output alb_dns_name
terraform output ecr_repository_url
```

After apply you will have:
- A working ALB you can reach from the internet
- An ECS service running your container (once you push an image)
- A completely separate EC2 instance you can SSH into

---

## Summary for Beginners

| Concept                    | Where it lives                  | Why it matters |
|---------------------------|----------------------------------|--------------|
| Network foundation        | `vpc.tf` → `modules/network`    | Everything else needs subnets and VPC |
| Old school VM             | `main.tf` → `modules/ec2`       | Standalone EC2 (not connected to ECS) |
| Container registry        | `app.tf` → `modules/ecr`        | Where you push your Docker images |
| Permissions               | `app.tf` → `modules/iam`        | Lets ECS pull images from ECR |
| Logging                   | `app.tf` → `modules/logs`       | CloudWatch logs from containers |
| Public entry point        | `app.tf` → `modules/alb`        | The only thing with a public IP for the app |
| The actual app            | `app.tf` → `modules/ecs`        | Runs your containers on Fargate |

This project is a great learning example because it shows both the "old way" (EC2) and the "modern way" (ECS Fargate + ALB + ECR) living side by side in the same Terraform codebase.

If you want a cleaner version in the future, the recommended path would be to either:
- Remove the EC2 layer entirely, or
- Split into separate Terraform states (network vs application).

---

**Next step recommendation:** Read the individual module READMEs (especially [modules/ecr/README.md](modules/ecr/README.md) and [modules/alb/README.md](modules/alb/README.md)) after reading this document. They explain the syntax in much more detail.