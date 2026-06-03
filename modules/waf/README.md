# WAF Module Guide

This module creates an AWS WAFv2 Web ACL and associates it with your ALB.

## Purpose In This Project

WAF (Web Application Firewall) sits in front of the ALB (as shown in the architecture image). It inspects incoming requests and blocks bad traffic (SQL injection, XSS, bots, rate abuse) before it reaches your ECS app.

It is controlled by `waf_config` in the root (similar to `domain_config`).

## How It Fits the Flow

Users → Route53 → **WAF** → ALB (HTTPS) → ECS

## Resources Created

- `aws_wafv2_web_acl` – the firewall rules.
- `aws_wafv2_web_acl_association` – attaches the WAF to the ALB ARN.

## Example Usage (in root)

Add to `terraform.tfvars`:

```hcl
waf_config = {
  enabled     = true
  name        = "app-waf"
  rate_limit  = 2000   # requests per 5 min per IP
}
```

Then in a root file (e.g. `waf.tf` or `domain.tf`):

```hcl
module "waf" {
  count = var.waf_config.enabled ? 1 : 0

  source = "./modules/waf"

  name      = var.waf_config.name
  alb_arn   = module.alb["main"].alb_arn
  rate_limit = var.waf_config.rate_limit
  common_tags = var.common_tags
}
```

## Detailed Syntax Breakdown (Beginner)

### The Web ACL Resource

```hcl
resource "aws_wafv2_web_acl" "main" {
  name  = var.name
  scope = "REGIONAL"

  default_action {
    allow {}
  }

  # Rule 1: Common attacks
  rule { ... }

  visibility_config { ... }

  tags = ...
}
```

- `scope = "REGIONAL"` – because ALB is regional (not CloudFront global).
- `default_action { allow {} }` – by default let traffic through unless a rule blocks it.
- Each `rule` block has `priority` (order matters, lower = checked first).
- `managed_rule_group_statement` – uses AWS pre-built rules (you don't write the bad patterns yourself).
- `visibility_config` – enables CloudWatch metrics and sampling for debugging/monitoring.

### Rate Limit Rule (custom)

```hcl
rule {
  name     = "RateLimitRule"
  priority = 30

  action {
    block {}
  }

  statement {
    rate_based_statement {
      limit              = var.rate_limit
      aggregate_key_type = "IP"
    }
  }

  visibility_config { ... }
}
```

- This blocks an IP if it sends too many requests in 5 minutes.
- `aggregate_key_type = "IP"` – counts per source IP address.
- Change `rate_limit` in tfvars to tune (start with 1000-2000 for learning).

### Association

```hcl
resource "aws_wafv2_web_acl_association" "alb" {
  resource_arn = var.alb_arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```

This is the "glue". It tells AWS: "Put this WAF in front of this ALB".

You must pass the ALB ARN from the alb module output.

## Beginner Notes

- WAF is **not** a replacement for secure coding in your app. It is an extra layer.
- Managed rules are maintained by AWS – they update automatically.
- Rate limit is very useful against brute-force login or scraping.
- You can add more custom rules later (e.g. block certain countries).
- Cost: WAF has a base fee + per rule + per request. For learning with low traffic it's cheap.

## After Apply

- Go to AWS Console → WAF & Shield → Web ACLs → your name.
- You will see "Associated AWS resources" showing your ALB.
- Check CloudWatch metrics for the Web ACL to see blocked requests.
- Test: try sending many requests quickly from one IP – the rate limit should kick in.

## What to Remember

WAF protects at the edge. The code uses AWS Managed Rules (easy & effective) + one custom rate-based rule. Association is the step that actually puts the WAF in the traffic path of the ALB.

See also the root `waf_config` and how it is wired similarly to `domain_config`.
