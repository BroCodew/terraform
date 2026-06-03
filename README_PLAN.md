# Implementation Plan From Reference Image

This file reviews the current Terraform project against the attached architecture image and lists the next sections to build.

> **Progress Update (latest session)**
> 
> **Completed (Steps 3, 4, 5):**
> - Step 3: `modules/acm` fully implemented (aws_acm_certificate + DNS validation records via for_each + aws_acm_certificate_validation).
> - Step 4: `modules/alb` updated with full HTTPS support (conditional listeners, HTTP→HTTPS redirect on port 80, HTTPS listener on 443, dynamic SG ingress for 443, `enable_https` + `certificate_arn` inputs).
> - Step 5: `modules/route53` implemented (Alias A record using `alias {}` block). New `domain.tf` wires conditional ACM + Route53 via `count` on `domain_config.enabled`.
> - Added `domain_config` variable (supports subdomain or apex via `record_name`, SANs).
> - Root integration: `app.tf`, `outputs.tf`, `variables.tf` updated. ALB outputs (zone_id, arn) exposed.
> - Current live config (in `terraform.tfvars`): Subdomain `app.terraformaws.online` (record_name="app"), `enabled=true`. HTTPS + Alias record active.
> - Detailed beginner-friendly README.md added/expanded for acm, route53, alb (syntax breakdowns, examples).
> 
> **Still missing from plan:** WAF, Secrets Manager, NAT HA, GitLab CI/CD, full doc cleanup (root README still has old EKS content).
> 
> **Current request flow:** Users → Route53 (Alias for subdomain) → ALB (HTTPS 443 + HTTP 80 redirect) → ECS Fargate (when domain_config.enabled = true).

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
- `domain.tf` + `modules/acm` + `modules/route53`: custom domain + ACM + Route53 Alias support (new in this session). Controlled by `domain_config`.

Current request flow (updated):

```text
User
  -> Route53 (Alias record for subdomain or apex)
  -> (optional WAF later)
  -> ALB (HTTPS 443 with redirect from HTTP 80 when domain_config.enabled=true)
  -> ALB target group
  -> ECS Fargate tasks in private subnets
  -> container port 3000
```

When `domain_config.enabled = false`: falls back to plain HTTP on the ALB DNS name (backward compatible).

Current image/deploy flow:

```text
Manual Docker build/push (or future GitLab CI)
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
| Route 53 | **Implemented** (subdomain) | `modules/route53` + `domain.tf` | Done. Supports `record_name` for subdomain (e.g. "app") or apex (""). Uses Alias A record + ALB outputs. |
| ACM certificate | **Implemented** | `modules/acm` | Done. Creates cert + auto DNS validation records in the provided zone_id. Supports SANs. |
| HTTPS | **Implemented** | `modules/alb` (updated) + `domain_config` | Done. Conditional listeners (HTTP redirect + HTTPS 443), dynamic SG rule, `enable_https` + `certificate_arn`. Works with/without domain_config. |
| AWS WAF | Missing | none | Add `modules/waf` |
| Secrets Manager | Missing | none | Add `modules/secrets` and ECS wiring |
| GitLab CI/CD | Missing | none | Add `.gitlab-ci.yml` |

## What Is Missing From The Image

These are the main missing project sections (updated after latest session):

**Completed in this session:**
- Custom domain + Route 53 alias (Step 5)
- ACM certificate + DNS validation (Step 3)
- HTTPS on ALB with redirect (Step 4)

**Still missing:**

1. **WAF security section**
   - WAFv2 Web ACL.
   - Managed rule groups.
   - Rate limiting rule.
   - Association with the ALB ARN.

2. **Secrets section**
   - Secrets Manager secret resources.
   - ECS task definition `secrets` support.
   - IAM permission for ECS to read only the required secret ARNs.

3. **High availability NAT section**
   - Current network has one NAT Gateway in public subnet A.
   - The image shows one NAT Gateway per public subnet/AZ.
   - Add this as an option because it increases monthly cost.

4. **CI/CD section**
   - GitLab pipeline that builds, tests, scans, pushes to ECR, and redeploys ECS.

5. **Documentation cleanup (Step 2)**
   - Root `README.md` still contains a lot of outdated EKS/RDS/Lambda content from the larger aspirational platform. `ARCHITECTURE.md` is accurate. Module READMEs are now excellent for beginners.

## Recommended Build Order

Do not build every missing section at once. Use this order so each step has a clear test.

### Step 1: Prove The Current Core Works

**Status: Completed (before this session)**

Goal: confirm the existing ECS + ALB + ECR path works before adding new services.

(Original commands and checks remain valid.)

### Step 2: Clean The Documentation

**Status: Partially done**

Goal: remove confusion between the real repo and old aspirational README content.

**Progress:**
- `ARCHITECTURE.md` is accurate and excellent.
- Added detailed `modules/*/README.md` (especially acm, route53, alb) with syntax explanations for beginners.
- Added progress note + current reality section to root `README.md`.
- **Still needed:** Root `README.md` still has large outdated sections describing EKS, RDS, Lambda, environments/ folder structure, etc. Should be cleaned to match actual slim ECS + ALB project.

### Step 3: Add ACM Certificate

**Status: Completed**

Implemented in `modules/acm` (with validation records inside the module using for_each on `domain_validation_options`).

### Step 4: Add HTTPS Support To The ALB Module

**Status: Completed**

`modules/alb` fully updated:
- `enable_https` + `certificate_arn` (optional in config object)
- Dynamic ingress for port 443
- Conditional listeners (HTTP redirect vs forward using count)
- HTTPS listener (443) with certificate + ssl_policy
- Updated listener_arn output

Works transparently when `domain_config.enabled = false` (pure HTTP mode preserved).

### Step 5: Add Route 53 Alias Record

**Status: Completed**

- New `modules/route53` (uses `type = "A"` + `alias {}` block + `evaluate_target_health`).
- New `domain.tf` at root (conditional `count` on `domain_config.enabled`).
- Supports both subdomain (`record_name = "app"`) and apex (`record_name = ""`).
- Integrated with ALB outputs.
- Currently live with `app.terraformaws.online` (see `terraform.tfvars`).

Note: We used direct `zone_id` + `record_name` (more flexible) instead of the plan's suggested `data "aws_route53_zone"` + `zone_name`.

### Step 6: Add AWS WAF

**Status: Not started**

(Create `modules/waf` ... original content unchanged)

### Step 7: Add Secrets Manager Support

**Status: Not started**

(Original content unchanged)

### Step 8: Add Optional One NAT Gateway Per AZ

**Status: Not started**

- Still single NAT Gateway (in public subnet A).
- `network_config` in variables.tf and `modules/network` do not yet expose `single_nat_gateway` toggle.
- Original recommendation still applies.

### Step 9: Add GitLab CI/CD

**Status: Not started**

(No `.gitlab-ci.yml` yet. Manual Docker push still used.)

### Step 10: Harden Production Defaults

**Status: Partially addressed via new features**

HTTPS + WAF (when implemented) + scoped IAM (future secrets) will help.
Many 0.0.0.0/0 rules, local state, and the separate EC2 layer remain.
See original recommendations.

## Terraform Variables To Add Later

**Already implemented (this session):**

```hcl
variable "domain_config" {
  type = object({
    enabled                   = bool
    zone_id                   = string
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    record_name               = optional(string, "")
  })
}
```
(Improved over original plan suggestion: uses `zone_id` + `record_name` for flexible apex/subdomain, plus SANs support.)

**Still to add when implementing related sections:**

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
| HTTPS + Route 53 (subdomain) | `https://app.terraformaws.online` resolves to ALB + has valid cert (when `domain_config.enabled = true`) |
| WAF | WAF Web ACL is associated with ALB |
| Secrets | ECS task starts and app can read secret env vars |
| NAT HA | Private subnet A routes to NAT A, private subnet B routes to NAT B |
| CI/CD | New GitLab commit produces new ECR image and ECS deployment |

## Short Next Step (Updated)

**What has been completed in this session:**
- Core + ECR + ALB (HTTP) was already working.
- **Steps 3 + 4 + 5 fully delivered**: ACM + HTTPS on ALB + Route53 Alias for subdomain (`app.terraformaws.online`).
- Live with `enabled = true` in `terraform.tfvars`.
- Excellent beginner documentation added.

**Recommended immediate next priorities (in suggested order):**

1. **Clean the root documentation (Step 2)**  
   The root `README.md` is still very misleading (talks about EKS, environments/ folders, etc.). Prioritize making it match the actual slim ECS+ALB project. `ARCHITECTURE.md` + module READMEs + this `README_PLAN.md` are already good.

2. **Add GitLab CI/CD (Step 9)**  
   This was the top of the original image. High value for the "image/deploy flow".

3. **Add AWS WAF (Step 6)**  
   Security layer in front of the ALB. Relatively self-contained.

4. **Add Secrets Manager (Step 7)**  
   For real apps you will need this.

5. **NAT HA + production hardening (Steps 8 + 10)**

**Current recommended commands for the user:**

```bash
# Verify current subdomain + HTTPS setup
terraform fmt -recursive
terraform validate
terraform plan
terraform output

# Check the live DNS record
dig app.terraformaws.online
```

After the above, the next big win is cleaning docs + adding the CI/CD pipeline. 

(Old "Short Next Step" text below kept for historical reference.)

---

**Historical Short Next Step (original plan):**

The best immediate next step (at the time of writing the plan) was:

```text
1. Run terraform fmt/validate/plan.
2. Apply the current stack if the plan is acceptable.
3. Push one test Docker image to ECR.
4. Confirm the ALB reaches ECS.
5. Then implement ACM + HTTPS.
```

After HTTPS works, build Route 53, then WAF, then Secrets Manager, then NAT HA, then GitLab CI/CD.
