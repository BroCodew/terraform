# Implementation Plan From Reference Image

This file reviews the current Terraform project against the attached architecture image and lists the next sections to build.

The image shows a production-style path:

```text
GitLab CI
  -> build
  -> test
  -> build and scan image
  -> push image to ECR

Users
  -> Route 53
  -> AWS WAF
  -> Application Load Balancer
  -> ECS Fargate service in private subnets
  -> container
```

The current repository already implements the core ECS path, but it does not yet implement the full edge, security, secrets, and CI/CD parts from the image.

## Current Project Reality

The project has two layers:

- `vpc.tf` + `modules/network`: shared VPC, public subnets, private subnets, Internet Gateway, one NAT Gateway, and route tables.
- `main.tf` + `modules/ec2`: a standalone public EC2 instance. This is separate from the ECS application.
- `app.tf` + `modules/ecr`, `modules/iam`, `modules/logs`, `modules/alb`, `modules/ecs`: the modern container application stack.

Current request flow:

```text
User
  -> public ALB on HTTP port 80
  -> ALB target group
  -> ECS Fargate tasks in private subnets
  -> container port 3000
```

Current image/deploy flow:

```text
Manual Docker build/push
  -> ECR
  -> ECS task definition uses ECR image tag
```

## Diagram Mapping

| Diagram part | Current status | Current files/modules | Next action |
|---|---:|---|---|
| Region | Implemented | `providers.tf`, `variables.tf` | Keep using `var.aws_region` |
| VPC | Implemented | `modules/network` | No immediate change |
| Public subnets A/B | Implemented | `modules/network` | No immediate change |
| Private subnets A/B | Implemented | `modules/network` | No immediate change |
| Internet Gateway | Implemented | `modules/network` | No immediate change |
| NAT Gateway | Partially implemented | `modules/network` | Add optional one NAT per AZ |
| ECR | Implemented | `modules/ecr` | Add CI/CD push workflow |
| ECS cluster | Implemented | `modules/ecs` | No immediate change |
| ECS Fargate service/tasks | Implemented | `modules/ecs` | Add secrets support later |
| Application Load Balancer | Implemented | `modules/alb` | Add HTTPS listener |
| ALB target group | Implemented | `modules/alb` | No immediate change |
| CloudWatch logs | Implemented | `modules/logs` | No immediate change |
| ECS execution IAM role | Implemented | `modules/iam` | Add scoped Secrets Manager permission later |
| ALB ARN output | Implemented | `modules/alb/outputs.tf` | Already available for WAF |
| ALB zone ID output | Implemented | `modules/alb/outputs.tf` | Already available for Route 53 |
| Route 53 | Missing | none | Add `modules/route53` |
| ACM certificate | Missing | none | Add `modules/acm` |
| HTTPS | Missing | `modules/alb` only supports HTTP | Update ALB module |
| AWS WAF | Missing | none | Add `modules/waf` |
| Secrets Manager | Missing | none | Add `modules/secrets` and ECS wiring |
| GitLab CI/CD | Missing | none | Add `.gitlab-ci.yml` |

## What Is Missing From The Image

These are the main missing project sections:

1. **Custom domain section**
   - Route 53 hosted zone lookup or creation.
   - Route 53 alias record pointing to the ALB.

2. **HTTPS section**
   - ACM certificate.
   - DNS validation through Route 53.
   - ALB HTTPS listener on port `443`.
   - HTTP port `80` redirect to HTTPS.

3. **WAF security section**
   - WAFv2 Web ACL.
   - Managed rule groups.
   - Rate limiting rule.
   - Association with the ALB ARN.

4. **Secrets section**
   - Secrets Manager secret resources.
   - ECS task definition `secrets` support.
   - IAM permission for ECS to read only the required secret ARNs.

5. **High availability NAT section**
   - Current network has one NAT Gateway in public subnet A.
   - The image shows one NAT Gateway per public subnet/AZ.
   - Add this as an option because it increases monthly cost.

6. **CI/CD section**
   - GitLab pipeline that builds, tests, scans, pushes to ECR, and redeploys ECS.

## Recommended Build Order

Do not build every missing section at once. Use this order so each step has a clear test.

### Step 1: Prove The Current Core Works

Goal: confirm the existing ECS + ALB + ECR path works before adding new services.

Commands:

```bash
terraform fmt -recursive
terraform validate
terraform plan
terraform apply
```

Then check outputs:

```bash
terraform output alb_dns_name
terraform output ecr_repository_url
terraform output ecs_cluster_name
terraform output ecs_service_name
```

Expected result:

```text
http://ALB_DNS_NAME reaches the ECS container.
```

If this fails, fix it before adding ACM, Route 53, WAF, or Secrets Manager.

### Step 2: Clean The Documentation

Goal: remove confusion between the real repo and old aspirational README content.

Current issue:

- `ARCHITECTURE.md` describes this repo accurately.
- Root `README.md` still describes a larger platform with EKS, RDS, Lambda, SQS, WAF, KMS, and environment folders that do not exist in this repo.

Recommended result:

```text
README.md = short project overview and quickstart
ARCHITECTURE.md = current architecture
README_PLAN.md = roadmap from the image
modules/*/README.md = beginner module notes
```

### Step 3: Add ACM Certificate

Goal: prepare HTTPS for the ALB.

Create:

```text
modules/acm
```

Resources:

```hcl
aws_acm_certificate
aws_route53_record
aws_acm_certificate_validation
```

Inputs:

```hcl
domain_name = "app.example.com"
zone_id     = "Z123456789"
```

Output:

```hcl
certificate_arn
```

Important:

- For an ALB, the ACM certificate must be in the same AWS region as the ALB.
- DNS validation is easiest when the domain is already managed in Route 53.

### Step 4: Add HTTPS Support To The ALB Module

Goal: change public traffic from plain HTTP to HTTPS.

Current ALB module:

```text
HTTP 80 -> target group
```

Target ALB module:

```text
HTTP 80  -> redirect to HTTPS 443
HTTPS 443 -> target group
```

Update `modules/alb`:

- Add input `certificate_arn`.
- Add input `enable_https`.
- Add HTTPS listener on port `443`.
- Change HTTP listener to redirect when HTTPS is enabled.
- Keep HTTP forwarding possible for learning/dev when no domain is configured.
- Add port `443` to ALB security group ingress when HTTPS is enabled.

### Step 5: Add Route 53 Alias Record

Goal: use a real domain instead of the raw ALB DNS name.

Create:

```text
modules/route53
```

Resources:

```hcl
data "aws_route53_zone" "selected"
aws_route53_record "app"
```

Inputs:

```hcl
zone_name    = "example.com"
record_name  = "app.example.com"
alb_dns_name = module.alb["main"].alb_dns_name
alb_zone_id  = module.alb["main"].alb_zone_id
```

Note:

- `modules/alb/outputs.tf` already has `alb_zone_id`.

Expected result:

```text
https://app.example.com -> ALB -> ECS
```

### Step 6: Add AWS WAF

Goal: protect public ALB traffic before requests reach ECS.

Create:

```text
modules/waf
```

Resources:

```hcl
aws_wafv2_web_acl
aws_wafv2_web_acl_association
```

Attach to:

```hcl
resource_arn = module.alb["main"].alb_arn
```

Note:

- `modules/alb/outputs.tf` already has `alb_arn`.

Starter rules:

- `AWSManagedRulesCommonRuleSet`
- `AWSManagedRulesKnownBadInputsRuleSet`
- Rate limit rule, for example 1000 to 2000 requests per 5 minutes per IP.

Expected result:

```text
Users -> Route 53 -> WAF -> ALB -> ECS
```

### Step 7: Add Secrets Manager Support

Goal: pass sensitive values to containers without hardcoding them in Terraform variables or source code.

Create:

```text
modules/secrets
```

Resources:

```hcl
aws_secretsmanager_secret
aws_secretsmanager_secret_version
```

Then update `modules/ecs`:

- Add input `container_secrets`.
- Add `secrets` to the ECS container definition.

Example ECS field:

```hcl
secrets = [
  {
    name      = "DATABASE_URL"
    valueFrom = "arn:aws:secretsmanager:ap-southeast-1:123456789012:secret:database-url"
  }
]
```

Update `modules/iam`:

- Add optional list of `secret_arns`.
- Add scoped `secretsmanager:GetSecretValue`.
- If secrets use a customer-managed KMS key, add scoped `kms:Decrypt`.

Avoid:

```hcl
Resource = "*"
```

Use only the secret ARNs required by the task.

### Step 8: Add Optional One NAT Gateway Per AZ

Goal: match the image more closely for production high availability.

Current state:

```text
Public subnet A -> NAT Gateway A
Private subnet A -> shared private route table -> NAT Gateway A
Private subnet B -> shared private route table -> NAT Gateway A
```

Target production state:

```text
Public subnet A -> NAT Gateway A
Private subnet A -> private route table A -> NAT Gateway A

Public subnet B -> NAT Gateway B
Private subnet B -> private route table B -> NAT Gateway B
```

Recommended implementation:

- Add `single_nat_gateway` to `network_config`.
- Default it to `true` for learning/dev cost control.
- When `false`, create one EIP/NAT/route table per AZ.

Tradeoff:

- More resilient.
- More expensive because each NAT Gateway has hourly and data processing cost.

### Step 9: Add GitLab CI/CD

Goal: implement the top pipeline in the image.

Create:

```text
.gitlab-ci.yml
```

Pipeline stages:

```yaml
stages:
  - test
  - docker-build
  - scan
  - push
  - deploy
```

Flow:

1. Run application tests.
2. Build Docker image.
3. Scan image.
4. Log in to ECR.
5. Push image to ECR with a commit SHA tag.
6. Register a new ECS task definition revision or force ECS deployment after updating the image tag.

Prefer immutable image tags:

```text
my-ecr-repo:<git-commit-sha>
```

Avoid relying only on:

```text
latest
```

Minimum deploy command if using the same tag:

```bash
aws ecs update-service \
  --cluster "$ECS_CLUSTER_NAME" \
  --service "$ECS_SERVICE_NAME" \
  --force-new-deployment
```

Better deploy path:

- Render a task definition with the new image tag.
- Register the task definition.
- Update the ECS service to that new revision.

### Step 10: Harden Production Defaults

Goal: reduce risk before using this outside learning/dev.

Recommended changes:

- Keep ECS tasks in private subnets.
- Keep `assign_public_ip = false` for ECS tasks.
- Keep ECS task ingress restricted to the ALB security group.
- Keep ALB public only on ports `80` and `443`.
- Put WAF in front of the ALB.
- Do not allow SSH from `0.0.0.0/0`.
- Prefer SSM Session Manager over SSH for EC2 access.
- Scope IAM permissions to exact ARNs.
- Store secrets in Secrets Manager, not plaintext tfvars.
- Consider remote Terraform state with S3 + DynamoDB locking before team use.

## Terraform Variables To Add Later

Add these only when implementing the related section.

```hcl
variable "domain_config" {
  type = object({
    enabled     = bool
    zone_name   = string
    domain_name = string
  })
}
```

```hcl
variable "waf_config" {
  type = object({
    enabled          = bool
    name             = string
    rate_limit       = number
    allowed_countries = optional(list(string), [])
  })
}
```

```hcl
variable "secrets_config" {
  type = map(object({
    name        = string
    description = optional(string)
    value       = string
  }))
  sensitive = true
}
```

Important:

- If Terraform creates `aws_secretsmanager_secret_version`, the secret value is stored in Terraform state.
- For real production secrets, prefer creating the secret container in Terraform and injecting secret values outside Terraform, or use a secure CI/CD secret process.

## Validation Checklist After Each Section

Run after every Terraform change:

```bash
terraform fmt -recursive
terraform validate
terraform plan
```

Functional checks:

```bash
terraform output alb_dns_name
terraform output ecr_repository_url
terraform output ecs_cluster_name
terraform output ecs_service_name
```

Expected checks by milestone:

| Milestone | Check |
|---|---|
| Current ECS core | `http://ALB_DNS_NAME` returns the app |
| HTTPS | `https://ALB_OR_DOMAIN` works |
| Route 53 | `https://app.example.com` resolves to ALB |
| WAF | WAF Web ACL is associated with ALB |
| Secrets | ECS task starts and app can read secret env vars |
| NAT HA | Private subnet A routes to NAT A, private subnet B routes to NAT B |
| CI/CD | New GitLab commit produces new ECR image and ECS deployment |

## Short Next Step

The best immediate next step is:

```text
1. Run terraform fmt/validate/plan.
2. Apply the current stack if the plan is acceptable.
3. Push one test Docker image to ECR.
4. Confirm the ALB reaches ECS.
5. Then implement ACM + HTTPS.
```

After HTTPS works, build Route 53, then WAF, then Secrets Manager, then NAT HA, then GitLab CI/CD.
