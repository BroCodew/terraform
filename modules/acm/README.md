# ACM Module Guide

This folder contains a Terraform module that creates an AWS Certificate Manager (ACM) certificate with DNS validation using Route53.

## Purpose In This Project

Used to get a free public TLS certificate so the ALB can serve traffic over HTTPS (port 443) with a custom domain like `app.terraformaws.online`.

The module is called from the root when `domain_config.enabled = true`.

It creates:
- `aws_acm_certificate` (the certificate request)
- `aws_route53_record` (one or more DNS records for validation, e.g. `_acme-challenge...`)
- `aws_acm_certificate_validation` (waits for AWS to verify the DNS records and issue the cert)

## How DNS Validation Works (Important for Beginners)

1. You request a certificate for `app.terraformaws.online`.
2. ACM gives you a special DNS record you must create (a CNAME like `_acme-challenge.app.terraformaws.online`).
3. This module automatically creates that record in your Route53 hosted zone.
4. AWS checks the record (usually within a few minutes).
5. Once verified, the certificate status becomes `ISSUED`.
6. You can then attach the certificate ARN to the ALB HTTPS listener.

This is why your Route53 hosted zone **must be delegated** (nameservers updated at your registrar) before validation can succeed.

## Basic Usage (in root)

```hcl
module "acm" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/acm"

  domain_name               = var.domain_config.domain_name
  subject_alternative_names = var.domain_config.subject_alternative_names
  zone_id                   = var.domain_config.zone_id
  common_tags               = var.common_tags
}
```

Then pass the output to the ALB module:

```hcl
certificate_arn = var.domain_config.enabled ? module.acm[0].certificate_arn : null
enable_https    = var.domain_config.enabled
```

## Example Inputs

```hcl
domain_config = {
  enabled     = true
  zone_id     = "Z02237983SGZXT8DWH3PD"   # from your Route53 hosted zone
  domain_name = "app.terraformaws.online"
  # Optional: also cover the apex or other names
  # subject_alternative_names = ["terraformaws.online"]
  record_name = "app"   # for the Route53 alias record ("" for apex)
}
```

## Terraform Syntax Highlights in This Module

- `aws_acm_certificate` with `validation_method = "DNS"`
- `for_each` over `domain_validation_options` — this is a set of objects that ACM returns after you request the cert. Each entry tells you exactly which DNS record to create for that name.
- `aws_acm_certificate_validation` — this resource does not create anything in AWS. Its only job is to block until validation finishes. It makes `terraform apply` wait nicely.

## Detailed Syntax Breakdown (What We Added)

This section explains the exact Terraform code in `main.tf`, `variables.tf`, and `outputs.tf` line by line, for beginners.

### 1. The `aws_acm_certificate` Resource (modules/acm/main.tf)

```hcl
resource "aws_acm_certificate" "this" {
  domain_name               = var.domain_name
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"

  tags = merge(var.common_tags, { Name = var.domain_name })
}
```

**Syntax explanation:**

- `resource` — the Terraform block type. It tells Terraform "I want to manage something in the real world (AWS)".
- `"aws_acm_certificate"` — the **resource type** (provided by the AWS provider). This specific type creates a certificate request in AWS Certificate Manager.
- `"this"` — the **local name** (label) inside your Terraform code. You use `aws_acm_certificate.this` later to refer to it. We chose "this" because the module only creates one certificate.
- `domain_name = var.domain_name` — an **argument**. The value comes from the variable we pass in (e.g. "app.terraformaws.online"). This becomes the main name on the certificate.
- `subject_alternative_names = var.subject_alternative_names` — another argument. A list of extra names (SANs). Example: `["terraformaws.online"]`. This lets one certificate cover both the apex and a subdomain.
- `validation_method = "DNS"` — tells AWS: "I will prove I own the domain by creating DNS records" (instead of email validation).
- `tags = merge(var.common_tags, { Name = var.domain_name })` — `merge()` is a Terraform function that combines two maps. We always add a `Name` tag for easy finding in the AWS console.

This resource creates the certificate in **PENDING_VALIDATION** state immediately.

### 2. The Complex `for_each` + `aws_route53_record` for Validation (the clever part)

```hcl
resource "aws_route53_record" "validation" {
  for_each = {
    for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = var.zone_id
}
```

**Step-by-step syntax breakdown:**

- `resource "aws_route53_record" "validation"` — we are creating Route53 DNS records. Local name "validation".
- `for_each = { ... }` — This is the key feature. `for_each` makes Terraform create **one resource instance per item** in the map/set. Without `for_each` you would need to write the block multiple times manually.

Inside the `for_each`:

```hcl
for_each = {
  for dvo in aws_acm_certificate.this.domain_validation_options : dvo.domain_name => {
    name   = dvo.resource_record_name
    record = dvo.resource_record_value
    type   = dvo.resource_record_type
  }
}
```

This is a **for expression** (Terraform's way of transforming collections).

- `for dvo in ...` — loop over every item in the set called `domain_validation_options` that the certificate resource outputs after it is created.
- `dvo` is a temporary variable name (short for "domain validation option").
- `dvo.domain_name => { ... }` — the key of the resulting map will be the domain name. The value is a small object/map we build.
- We extract the three pieces AWS tells us we must create: the record name (usually `_acme-challenge.app.terraformaws.online.`), the value (a long random string), and the type (usually `CNAME`).

Then, inside the resource body (this runs once **per key** in the map):

- `each.value.name` — `each` is a special keyword available inside `for_each` resources. `each.value` is the right-hand side object we built. `each.key` would be the domain_name.
- `name = each.value.name` — the DNS record name to create.
- `records = [each.value.record]` — list with one value (the CNAME target).
- `ttl = 60` — Time To Live in seconds. Short because this is temporary validation.
- `type = each.value.type`
- `zone_id = var.zone_id` — reference to the **input variable**. This is the ID of your manually created hosted zone (Z02237983SGZXT8DWH3PD).
- `allow_overwrite = true` — if the record already exists, just replace it (useful during testing).

**Reference & dependency:**  
`aws_acm_certificate.this.domain_validation_options` — because we write `aws_acm_certificate.this...`, Terraform automatically knows: "create the certificate first, then look at what it outputs, then create these DNS records."

### 3. The `aws_acm_certificate_validation` Resource

```hcl
resource "aws_acm_certificate_validation" "this" {
  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]
}
```

- `aws_acm_certificate_validation` — special resource type whose **only job is to wait**.
- It does not create anything new in AWS. It just tells Terraform: "Do not finish until the certificate status is ISSUED".
- `certificate_arn = aws_acm_certificate.this.arn` — we pass the ARN of the cert we are waiting for.
- `validation_record_fqdns = [for record in aws_route53_record.validation : record.fqdn]` — another small `for` expression. It collects the full domain names (`fqdn`) of all the validation records we just created. AWS uses these to know "these records were created by Terraform".

This resource creates a **dependency** on both the certificate and all the Route53 records.

### 4. Variables (modules/acm/variables.tf)

```hcl
variable "domain_name" {
  description = "..."
  type        = string
}
```

- `variable "domain_name"` — declares an input.
- `type = string` — must be a single text value.
- We use `var.domain_name` inside the module.

The `subject_alternative_names` uses `type = list(string)` and `default = []`.

`zone_id` is `type = string` because we pass the raw ID from the screenshot.

### 5. Outputs (modules/acm/outputs.tf)

```hcl
output "certificate_arn" {
  value = aws_acm_certificate.this.arn
}
```

- `output "certificate_arn"` — makes a value available to the root module and other modules.
- We return the ARN (Amazon Resource Name) so the ALB listener can use it with `certificate_arn = ...`.

We also output `certificate_status` for debugging.

## How the Module Is Called from the Root (domain.tf + app.tf)

See `domain.tf`:

```hcl
module "acm" {
  count = var.domain_config.enabled ? 1 : 0

  source = "./modules/acm"
  ...
}
```

- `count = ... ? 1 : 0` — a common Terraform pattern for "create this module only if a flag is true". When count = 0 the module does not exist. When count = 1 it exists as `module.acm[0]`.
- We use `count` (not `for_each`) here because we treat domain_config as a single top-level setting for now.

Then in `app.tf` (inside the alb module call) we pass the result safely:

```hcl
enable_https    = var.domain_config.enabled
certificate_arn = var.domain_config.enabled && length(module.acm) > 0 ? module.acm[0].certificate_arn : null
```

- `length(module.acm) > 0` protects us from errors when the module is not created (count = 0).
- The ternary `condition ? value_if_true : value_if_false` chooses what to pass.

This pattern lets you keep your old HTTP-only setup working while the new HTTPS code exists in the same files.

## After Apply

- Run `terraform output` or check the AWS Console → Certificate Manager.
- The certificate will first show "Pending validation".
- After a few minutes (and after nameservers are delegated), it becomes "Issued".
- Then re-run `terraform apply` (or the validation resource finishes) and the ALB will be updated with the HTTPS listener.

## Cost

ACM public certificates are **free**. You only pay for the resources that use them (ALB hours, data transfer).

## Common Issues

- Validation never completes → nameservers at your domain registrar are not yet pointing to the AWS Route53 nameservers.
- "Domain not found" or validation record not created → wrong `zone_id` passed (must be the ID of the hosted zone that owns the domain).
- Certificate ARN not usable yet → you tried to use it before the validation resource finished.

## What to Remember

The ACM module's main job is **not** just creating a cert — it also creates the exact DNS records needed to prove you own the domain, using your existing Route53 zone.
