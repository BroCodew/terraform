# Route53 Module Guide

This module creates an Alias A record in Route53 that points your custom domain (or subdomain) directly at the Application Load Balancer.

## Why an Alias Record (not a regular A or CNAME)?

- Regular CNAME cannot be used at the apex (root) of a domain (terraformaws.online).
- Alias records are a Route53-specific feature that understand AWS resources.
- Alias records are free and have better performance (Route53 can resolve them directly).
- `evaluate_target_health = true` means Route53 will only return the ALB IP addresses if the ALB is healthy.

## How It Fits Together

After you have:
- A working ALB (from modules/alb)
- An ACM certificate (from modules/acm) attached to the ALB on port 443

...then this module makes `https://app.terraformaws.online` (or the apex) resolve to your ALB.

## Example Call (from root domain.tf)

```hcl
module "route53" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/route53"

  zone_id      = var.domain_config.zone_id
  name         = var.domain_config.record_name     # "app" or ""
  alb_dns_name = module.alb["main"].alb_dns_name
  alb_zone_id  = module.alb["main"].alb_zone_id
}
```

## Important Values You Need

You get these from the ALB module outputs (already exposed via the root module after we add them, or directly via `module.alb["main"]...`):

- `alb_dns_name` → something like `app-alb-tr-123456789.ap-southeast-1.elb.amazonaws.com`
- `alb_zone_id` → something like `Z1GM3OXH4ZPM65` (this is the ALB's own zone ID, different from your domain's hosted zone ID)

## What the Record Looks Like in the Console

In Route53 you will see a record of type **A** with "Alias" set to "Yes", pointing at the ALB.

Value will look like:

`dualstack.app-alb-tr-....ap-southeast-1.elb.amazonaws.com.`

## Apex vs Subdomain

- For `terraformaws.online` (apex) → set `record_name = ""`
- For `app.terraformaws.online` → set `record_name = "app"`

You can create multiple records (apex + www + app) all pointing at the same ALB if you want.

## After Creating the Record

Propagation usually takes seconds to a couple of minutes.

Test with:

```bash
dig app.terraformaws.online
curl -I http://app.terraformaws.online   # or https once you have the cert + listener
```

## Remember

The real "magic" of a custom domain on ALB is the combination of three things:
1. ACM certificate (HTTPS)
2. ALB listener on 443 using that cert
3. Route53 Alias A record pointing the name at the ALB

This module only does #3. The other two are handled by the acm module + updates to the alb module.

## Detailed Syntax Breakdown (What We Added)

### The `aws_route53_record` with Alias (modules/route53/main.tf)

```hcl
resource "aws_route53_record" "app" {
  zone_id = var.zone_id
  name    = var.name
  type    = "A"

  alias {
    name                   = var.alb_dns_name
    zone_id                = var.alb_zone_id
    evaluate_target_health = true
  }
}
```

**Line-by-line beginner explanation:**

- `resource "aws_route53_record" "app"`  
  Block type = `resource`.  
  Resource type = `aws_route53_record` (from the AWS provider).  
  Local name = `"app"` (we use this name inside the module only).

- `zone_id = var.zone_id`  
  Argument. The ID of the hosted zone we are adding the record to (your `Z02237983SGZXT8DWH3PD` from the screenshot). This comes from the `domain_config` variable.

- `name = var.name`  
  The left-hand side of the DNS record.  
  - If you pass `name = "app"`, Terraform creates `app.terraformaws.online`.  
  - If you pass `name = ""` (empty string), it creates a record at the apex (root) of the zone: just `terraformaws.online`.

- `type = "A"`  
  Address record. For Alias records pointing at an ALB (or CloudFront, etc.), you almost always use type `A` (or `AAAA` for IPv6). Regular `CNAME` records cannot point at the root of a domain.

- `alias { ... }` — this is a **nested block** specific to Route53 Alias records.  
  It is **not** the same as a normal `CNAME`. Route53 treats Alias records specially (they are free and can point at AWS resources by their internal IDs).

  Inside the alias block:

  - `name = var.alb_dns_name`  
    The DNS name of the target (your ALB). Example: `app-alb-tr-63383853.ap-southeast-1.elb.amazonaws.com`.  
    This value comes from `module.alb["main"].alb_dns_name` (a reference to another module's output).

  - `zone_id = var.alb_zone_id`  
    **Critical and often confusing for beginners.**  
    This is **NOT** your domain's hosted zone ID (the Z02... one).  
    This is the **ALB's own canonical hosted zone ID** (something like `Z1LMS91P8CMLE5` or `Z1GM3OXH4ZPM65`).  
    Every AWS load balancer has its own "zone" for internal routing. You get this from the ALB module output `alb_zone_id` (which we exposed at the root).  
    If you put your domain zone ID here by mistake, the record will not work.

  - `evaluate_target_health = true`  
    Boolean. When true, Route53 will periodically check whether the ALB is healthy. If the ALB (or its target group) is unhealthy, Route53 will stop returning its IP addresses in DNS answers. This gives you automatic failover behavior at the DNS level.

**Cross-module references (the dependency magic):**

```hcl
alb_dns_name = module.alb["main"].alb_dns_name
alb_zone_id  = module.alb["main"].alb_zone_id
```

- `module.alb["main"]` — because the root calls the alb module with `for_each = var.app_stacks`, every alb resource lives under a key ("main" in our case).
- The dot `.alb_dns_name` reaches into the `outputs.tf` of that module instance.
- Terraform sees this reference and automatically knows: "I must finish creating (or updating) the ALB before I can create this Route53 record."

### Variables (modules/route53/variables.tf)

```hcl
variable "alb_zone_id" {
  description = "The canonical hosted zone ID of the ALB (from alb module output alb_zone_id). This is NOT the same as the Route53 zone ID."
  type        = string
}
```

We added a very clear description because mixing up the two zone IDs is the #1 mistake beginners make with ALB Alias records.

`name` has `default = ""` so you can omit it when you want an apex record.

### How It Is Wired at the Root (domain.tf)

```hcl
module "route53" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/route53"

  zone_id      = var.domain_config.zone_id
  name         = var.domain_config.record_name
  alb_dns_name = module.alb["main"].alb_dns_name
  alb_zone_id  = module.alb["main"].alb_zone_id
}
```

- `count = condition ? 1 : 0` — same pattern as the acm module. The whole module block is created or not created together.
- We hard-coded `["main"]` because we currently have only one app stack. If you add more stacks later you would make this more dynamic.
- Notice we do **not** pass `common_tags` into the record (we removed tags from the resource because some older provider behaviors made it awkward on Route53 records).

### Outputs (modules/route53/outputs.tf)

```hcl
output "fqdn" {
  value = aws_route53_record.app.fqdn
}
```

`fqdn` is the full name Terraform computed (e.g. `app.terraformaws.online.` with the trailing dot). Useful for debugging or feeding into other resources.

## Changes Made to Support This Module

- Added `alb_zone_id` and `alb_arn` as root outputs (see `outputs.tf`).
- The ALB module now always outputs `alb_zone_id` (it was already there in `modules/alb/outputs.tf`).
- We read it in `domain.tf` only when `domain_config.enabled = true`.

This keeps the old HTTP-only setup completely unchanged when the flag is false.
