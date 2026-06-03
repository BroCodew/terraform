# Terraform Infrastructure Boilerplate

This repository manages an AWS DevOps platform with Terraform. The root module composes local modules for networking, EKS, EC2-based toolchain services, databases, DNS, load balancing, serverless integrations, IAM, and schedulers. Environment-specific values live under `environments/`.

## Project Structure

```text
.
|-- main.tf                    # Root module wiring and dependency graph
|-- variables.tf               # Root input contracts
|-- outputs.tf                 # Root outputs for consumers/operators
|-- provider.tf                # Terraform, AWS, Helm, and Kubernetes providers
|-- backend.tf                 # S3 backend block; values come from backend tfvars
|-- locals.tf                  # Common tags and static EKS identity configs
|-- environments/
|   |-- dev/                   # Complete dev environment inputs
|   |-- staging/               # Placeholder staging inputs/backend
|   `-- prod/                  # Placeholder production inputs/backend
|-- modules/                   # Local Terraform modules
`-- policies/                  # JSON IAM policy documents consumed by modules
```

## Terraform Syntax and Conventions

- Terraform version is constrained to `>= 1.10.0`.
- Provider versions are pinned in `provider.tf`; current lock file resolves AWS `6.23.0`, Helm `3.1.1`, Kubernetes `2.38.0`, TLS `4.2.1`, Archive `2.7.1`, and Random `3.8.1`.
- Root inputs use typed objects and maps heavily. Most resources are created with `for_each` from environment maps such as `security_groups`, `toolchain_config.services`, `rds_instances`, `lambda_config.functions`, and `sqs_config`.
- Tags are merged into resources using `merge(var.tags, ...)`. The root passes `local.common_tags` to modules and the AWS provider also applies the same default tags.
- Environment values are passed with `-var-file`; backend values are passed to `terraform init` with `-backend-config`.
- Module boundaries are mostly service-oriented: VPC, security groups, EKS, toolchain EC2, RDS, S3, DNS, load balancers, Lambda, SQS, WAF, KMS, and IAM roles.

## How to Run

Dev is the only fully populated environment at the moment.

```bash
terraform init -backend-config=environments/dev/backend.tfvars
terraform fmt -recursive
terraform validate
terraform plan -var-file=environments/dev/dev.tfvars
terraform apply -var-file=environments/dev/dev.tfvars
```

For staging or production, complete `environments/staging/stg.tfvars`, `environments/prod/prod.tfvars`, and their backend files before running the same workflow.

## System Design

### Network Layer

The `vpc` module creates one VPC, public subnets, private subnets, an internet gateway, private route tables, optional NAT gateway routing, S3 and DynamoDB gateway endpoints, and VPC flow logs. Private subnet behavior is driven by each subnet's `type` value, for example `eks`, `toolchain`, `database`, `bastion`, and `blue-green-application`.

The root config currently reserves `toolchain_subnet` for NAT instance routing by passing `nat_instance_subnet_keys = ["toolchain_subnet"]`. Other private route tables can use the NAT gateway path unless excluded.

### Security Layer

The `security-groups` module creates all security groups and rules from maps in tfvars. This keeps ingress and egress policy centralized, but it also means review discipline in the environment files is important because broad rules are easy to add.

KMS keys are created in `kms` for the primary platform key plus Vault and Boundary-specific keys. Several workloads use Secrets Manager and KMS access policies.

### EKS Layer

The `eks` module creates:

- EKS cluster and cluster IAM role
- OIDC provider for IRSA
- Managed node groups with launch templates
- EKS add-ons: VPC CNI, CoreDNS, kube-proxy, and pod identity agent
- AWS Load Balancer Controller IAM policy/role
- EKS access entry for the NAT instance role

The root also creates Karpenter resources through the public `terraform-aws-modules/eks/aws//modules/karpenter` module.

Workload IAM is split between:

- `eks-irsa-role` for web identity roles and Kubernetes service accounts
- `eks-pod-identity` for EKS Pod Identity associations

The role definitions are currently static in `locals.tf`.

### Toolchain Layer

The `toolchain` module creates EC2 instances for platform services such as Jenkins, Gitea, SonarQube, Keycloak, Nexus, NFS, CMDB, Boundary, and similar services configured in `toolchain_config.services`.

Each instance receives:

- A shared EC2 IAM instance profile
- SSM Session Manager access
- Encrypted gp3 root volume with `delete_on_termination = false`
- Service-specific security group
- Optional scheduling tags
- Optional internal ALB target group attachment

The `instance-scheduler` module uses SSM Automation and EventBridge rules to start/stop these EC2 instances.

### Database and Storage Layer

The `rds` module creates database subnet groups, DB parameter groups, RDS instances, generated master passwords, and Secrets Manager records. The `rds-scheduler` module can schedule RDS stop/start with EventBridge Scheduler.

The `s3` module creates S3 buckets with versioning, encryption, lifecycle rules, CORS, and public access block settings from tfvars.

The `dlm` module creates an EC2 volume backup lifecycle policy based on tags.

### Ingress, DNS, and Certificates

The `route53-zones` module creates a private zone and a private split-horizon zone for the public domain, while reading the existing public hosted zone. The `acm` module creates a DNS-validated ACM certificate in the public zone.

The `internal-alb` module creates an internal ALB, HTTP/HTTPS listeners, target groups, and many host-header listener rules for toolchain services. The `nlb` module creates a public NLB with static EIPs and forwards selected public TCP services to either the internal ALB or EC2 instances.

The `route53-records` module creates private, split-horizon, and public alias records for services.

### Serverless and Messaging Layer

The `sqs` module creates queues and optional DLQs. The `lambda` module creates IAM roles, Secrets Manager entries, Lambda layers, functions from S3 artifacts, optional function URLs, optional ALB target groups, and SQS event source mappings. The `API-Gateway` module creates HTTP APIs and Lambda integrations.

## Environment Status

- `dev`: complete environment file with real CIDRs, services, DNS, RDS, Lambda, SQS, IAM users, and backend.
- `staging`: currently only `environment = "staging"` and empty `aws_region`; backend values are placeholders.
- `prod`: currently only `environment = "prod"` and empty `aws_region`; backend values are placeholders.

## Outputs

The root module exposes important IDs and endpoints including:

- VPC ID and private subnet IDs
- EKS cluster name, endpoint, OIDC provider ARN/URL, and certificate authority data
- Internal ALB DNS name/listener ARN
- Security group IDs for EKS nodes, internal ALB, and EC2 app workloads
- NLB DNS name and zone ID
- Route53 public/private hosted zone IDs
- API Gateway endpoint URLs

## Design Review and Better Ideas

### 1. Split state by domain or environment component

Current design puts network, EKS, EC2 toolchain, RDS, DNS, Lambda, SQS, and IAM into one large root state. This increases blast radius and makes plans slower and riskier.

Better design:

- `network`: VPC, subnets, route tables, endpoints, flow logs
- `security`: security groups, KMS, shared IAM policies
- `cluster`: EKS, node groups, Karpenter, workload identity
- `platform-services`: toolchain EC2, internal ALB, NLB, DNS records
- `data`: RDS, S3, backup policies
- `serverless`: Lambda, SQS, API Gateway

Use remote state outputs or a small parameter contract between stacks.

### 2. Avoid Kubernetes and Helm providers in the same apply that creates EKS

`provider.tf` reads `data.aws_eks_cluster.cluster` and configures Kubernetes/Helm providers at root provider initialization time. This can fail on a first apply when the EKS cluster does not exist yet.

Better design: keep EKS infrastructure in one stack, then apply Kubernetes/Helm resources from a second stack after the cluster exists.

### 3. Make environment data truly environment-specific

`locals.tf` currently hardcodes `environment = "dev"` and an owner email in `common_tags`. Several naming and policy blocks also include fixed platform naming.

Better design: derive tags from variables:

```hcl
common_tags = merge(var.common_tags, {
  environment = var.environment
  system      = local.system_name
})
```

This prevents staging/prod resources from receiving dev tags.

### 4. Remove or wire unused root variables

The root declares variables that are currently not consumed, including `aws_account_id`, `common_tags`, `secrets_config`, `enable_nat_gateway`, `single_nat_gateway`, `enable_s3_endpoint`, `ssm_parameters`, and `eks_irsa_config`.

Better design: either remove unused variables or wire them into modules. Unused inputs make the interface misleading and can cause operators to believe a setting is active when it is not.

### 5. Parameterize region-specific IAM conditions

Some IAM policies hardcode `secretsmanager.ap-northeast-2.amazonaws.com` as the KMS `ViaService` condition.

Better design: use `data.aws_region.current.region` or pass `var.aws_region` into the module so the same module works in any region.

### 6. Reduce broad IAM permissions

Several EC2 and EKS policies grant `Resource = "*"`, including access to RDS, Secrets Manager, KMS decrypt, SSM document management, EventBridge, and `iam:PassRole`.

Better design: scope permissions to specific secret ARNs, KMS key ARNs, RDS resources, and allowed role ARNs. Keep broad read-only AWS describe permissions where needed, but narrow write and credential access paths.

### 7. Review public ingress rules before production

The dev tfvars includes many `0.0.0.0/0` CIDR rules and an EKS public endpoint CIDR of `0.0.0.0/0`. This may be acceptable for development, but it is not a good production default.

Better design: use office/VPN CIDRs, CloudFront/WAF entry points, or private-only access through VPN/SSM/Bastion. For EKS, restrict public endpoint CIDRs or disable public access.

### 8. Move hardcoded ALB listener rules into data-driven maps

The `internal-alb` module has many explicit listener rule resources by service name. This makes every new service a code change.

Better design: model listener rules as a map and create them with `for_each`, the same way this project already handles security groups, toolchain services, Lambda functions, SQS queues, and RDS instances.

### 9. Complete staging and production before using them

Staging and production tfvars are placeholders and cannot run the current root module because many required variables have no values.

Better design: either create complete tfvars for each environment or split shared defaults into `.auto.tfvars`/composition files and keep only environment overrides in each environment folder.

## Validation Performed

The current configuration passed:

```bash
terraform fmt -check -recursive
terraform validate
```

## Recent Addition: Custom Domain + HTTPS (ACM + Route53 + ALB Listeners)

We implemented the next major pieces from `README_PLAN.md` (Steps 3, 4, 5) so you can use your real domain (`terraformaws.online`) with a proper certificate.

### New / Changed Files

- `domain.tf` (new) — contains the conditional `module "acm"` and `module "route53"` calls using `count`.
- `variables.tf` — added the `domain_config` object variable (with `enabled`, `zone_id`, `domain_name`, `record_name`, etc.).
- `app.tf` — injects `enable_https` + `certificate_arn` into the ALB config map.
- `outputs.tf` — now also exports `alb_zone_id`, `alb_arn`, and `acm_certificate_arn`.
- `modules/acm/` (completely new module)
- `modules/route53/` (completely new module)
- `modules/alb/` — updated to support HTTPS listeners, redirect, conditional security group rule, and smarter outputs.

### How to Activate

See the commented example at the bottom of `terraform.tfvars.example`, or add this to your `terraform.tfvars`:

```hcl
domain_config = {
  enabled     = true
  zone_id     = "Z02237983SGZXT8DWH3PD"     # from your Route53 hosted zone
  domain_name = "app.terraformaws.online"
  record_name = "app"
}
```

Then run the normal `fmt / validate / plan / apply`.

### Detailed Syntax Teaching

The best place to learn the exact Terraform syntax we added is inside the per-module README files (they contain long beginner-friendly line-by-line breakdowns):

- [modules/acm/README.md](modules/acm/README.md) — full explanation of `aws_acm_certificate`, the `for` expression + `for_each` for validation records, `aws_acm_certificate_validation`, `count` on modules, safe ternary access to `module.acm[0]`, etc.
- [modules/route53/README.md](modules/route53/README.md) — detailed breakdown of the `alias {}` block, why you need the ALB's zone ID (not your domain zone ID), cross-module references with `module.alb["main"]`, `count` pattern again.
- [modules/alb/README.md](modules/alb/README.md) — new long section "HTTPS + Custom Domain Support" explaining `optional()` in object types, `dynamic "ingress"`, the `count` trick for listeners (why we have both `app` and `http_redirect` resources), redirect action syntax, `ssl_policy`, and how the output ternary with `[0]` indexing works.

These READMEs were written in the Adam teaching style (small steps, define every keyword, show before/after mental models, and explicit syntax tables where helpful).

### Important Notes for This Feature

- The feature is fully **opt-in** via `domain_config.enabled`. When false, the plan should only do the ongoing state "moved" work from the earlier refactoring and add the new root outputs.
- You **must** have delegated the nameservers at your domain registrar before ACM validation or the Route53 alias will do anything useful on the public internet.
- When you first flip `enabled = true`, Terraform will replace the listener on port 80 (forward → redirect) and add the 443 listener. This is expected and low-risk for the ALB itself.
- After apply, visit `https://your-chosen-name` — the padlock should appear and your ECS app should load.

See also `ARCHITECTURE.md` (current reality) and `README_PLAN.md` (the original roadmap we are following).
