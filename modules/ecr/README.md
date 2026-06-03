# ECR Module Guide

This folder contains a Terraform module that creates an Amazon ECR repository.
The main file is `main.tf`.

This module creates:

- One ECR repository (a private Docker image registry in AWS)

## Purpose In This Project

This module is used in the root [app.tf](../../app.tf) as part of an application stack.

```hcl
module "ecr" {
  for_each = var.app_stacks

  source = "./modules/ecr"

  repository_name      = each.value.ecr_repository_name
  image_tag_mutability = each.value.ecr_image_tag_mutability
  scan_on_push         = each.value.ecr_scan_on_push
  common_tags          = var.common_tags
}
```

The ECR repository URL is passed to the ECS module:

```hcl
module "ecs" {
  for_each = var.app_stacks

  source = "./modules/ecs"

  ecr_repository_url = module.ecr[each.key].repository_url
  ...
}
```

This means:

- You store your container images in this ECR repository.
- ECS tasks pull their Docker image from this exact repository URL.

## Big Picture

### What is ECR?

**ECR** = Elastic Container Registry.

It is AWS's managed private Docker registry. Think of it as a safe, private "photo album" for your container images.

### Why do we need it?

When you run containers with ECS (Elastic Container Service), AWS needs to download the container image somewhere.

You have two main choices:

1. Public Docker Hub (not recommended for private apps)
2. Private registry like ECR (what this module creates)

This project uses ECR so your container images stay private inside your AWS account.

### How it fits in the full picture

```
You (developer)
   |
   | docker push
   v
ECR Repository (this module)
   |
   | ECS pulls the image at deploy time
   v
ECS Task Definition (modules/ecs)
   |
   v
ECS Service runs containers on Fargate
```

## Example Input Values

From the default values in the root [variables.tf](../../variables.tf):

```hcl
main = {
  ecr_repository_name      = "my-ecr-repo-tr"
  ecr_image_tag_mutability = "MUTABLE"
  ecr_scan_on_push         = true
  ...
}
```

When the root module calls this ECR module, these values become:

| Variable                | Example Value         | Meaning |
|-------------------------|-----------------------|---------|
| `repository_name`       | `"my-ecr-repo-tr"`    | The name of your Docker repository in ECR |
| `image_tag_mutability`  | `"MUTABLE"`           | Allow overwriting the same tag (like `latest`) |
| `scan_on_push`          | `true`                | Automatically scan images for vulnerabilities when you push them |

## Basic Terraform Syntax

A Terraform resource looks like this:

```hcl
resource "aws_ecr_repository" "app" {
  name = var.repository_name
}
```

Breaking it down:

- `resource` = keyword that tells Terraform "I want to create or manage something"
- `"aws_ecr_repository"` = the AWS resource type (this one creates an ECR repo)
- `"app"` = local name inside Terraform (only used inside your code)
- `name = ...` = an argument (input) that controls what gets created in AWS

## The ECR Repository Resource

Here is the complete resource from [main.tf](main.tf):

```hcl
resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = var.image_tag_mutability

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = merge(var.common_tags, { Name = var.repository_name })
}
```

Let's explain every part.

### 1. `name`

```hcl
name = var.repository_name
```

- This becomes the repository name inside ECR.
- Example value: `"my-ecr-repo-tr"`
- After creation, the full repository URL will look like:
  `501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr`

The account ID and region are added automatically by AWS.

### 2. `image_tag_mutability`

```hcl
image_tag_mutability = var.image_tag_mutability
```

This controls whether you can push the same tag multiple times.

**Two possible values:**

| Value      | Meaning | When to use |
|------------|---------|-------------|
| `MUTABLE`  | You can push the same tag again and it will overwrite the old image | Good for development, `latest` tag, fast iteration |
| `IMMUTABLE`| Once a tag is pushed, you can never overwrite it | Recommended for production (safer, traceable) |

In this project the default is `"MUTABLE"` because it is a learning/dev environment.

### 3. `image_scanning_configuration` block

```hcl
image_scanning_configuration {
  scan_on_push = var.scan_on_push
}
```

This is a **nested block**.

- `scan_on_push = true` tells AWS: "Every time someone pushes a new image, automatically scan it for known security vulnerabilities."
- The scan results appear in the ECR console.
- This is a security best practice.

When `scan_on_push = true`, AWS will tell you if your image contains packages with known CVEs (security problems).

### 4. `tags` and `merge()`

```hcl
tags = merge(var.common_tags, { Name = var.repository_name })
```

- Every AWS resource can have tags (key-value labels).
- `merge()` is a Terraform function that combines two maps.
- `var.common_tags` usually contains project-wide tags like `Environment`, `Owner`, `Project`.
- `{ Name = var.repository_name }` adds one extra tag called `Name`.

Result example:

```hcl
tags = {
  Environment = "dev"
  Owner       = "team-platform"
  Name        = "my-ecr-repo-tr"
}
```

Tags help you find resources and manage costs in the AWS console.

## Module Outputs

The file [outputs.tf](outputs.tf) exposes one value:

```hcl
output "repository_url" {
  value = aws_ecr_repository.app.repository_url
}
```

This output gives you the full URL that other tools (Docker, ECS, etc.) need to push or pull images.

Example value after creation:

```
501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr
```

## How This Module Connects to Other Modules

In [app.tf](../../app.tf), the ECS module receives the URL like this:

```hcl
ecr_repository_url = module.ecr[each.key].repository_url
```

Inside the ECS module ([modules/ecs/main.tf](../ecs/main.tf)), it is used here:

```hcl
image = "${var.ecr_repository_url}:${var.config.image_tag}"
```

If you pass:
- `ecr_repository_url` = `501360634452.dkr.ecr...com/my-ecr-repo-tr`
- `image_tag` = `latest`

Then the final image string becomes:

```
501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest
```

This is the exact string ECS uses to download your container.

## Resource Address Cheat Sheet

Terraform address for the resource created by this module:

```
aws_ecr_repository.app
```

Because the root uses `for_each = var.app_stacks`, the full address when you run commands is usually:

```
module.ecr["main"].aws_ecr_repository.app
```

Useful commands:

```bash
# See everything Terraform knows about this repository
terraform state show module.ecr["main"].aws_ecr_repository.app

# Plan only changes to the ECR module
terraform plan -target=module.ecr
```

## Common ECR Workflow (for Beginners)

After you run `terraform apply` and the repository exists, here is how you normally use it:

### 1. Authenticate Docker to ECR

```bash
aws ecr get-login-password --region ap-southeast-1 | \
  docker login --username AWS --password-stdin \
  501360634452.dkr.ecr.ap-southeast-1.amazonaws.com
```

### 2. Build your Docker image locally

```bash
docker build -t my-ecr-repo-tr .
```

### 3. Tag the image with the ECR URL

```bash
docker tag my-ecr-repo-tr:latest \
  501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest
```

### 4. Push the image

```bash
docker push 501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest
```

### 5. (Optional) Pull it back to test

```bash
docker pull 501360634452.dkr.ecr.ap-southeast-1.amazonaws.com/my-ecr-repo-tr:latest
```

After pushing, ECS can use this image when you deploy your service.

## Beginner Notes

- ECR is **private by default** — only your AWS account (and accounts you explicitly allow) can pull images.
- The repository name in Terraform (`repository_name`) must be unique **inside your AWS account** in that region.
- Changing `repository_name` after creation usually forces Terraform to destroy the old repo and create a new one (you will lose all images).
- `scan_on_push = true` costs a small amount of money per scan. For learning it is fine.
- `MUTABLE` is convenient for development. Switch to `IMMUTABLE` before production.
- The ECR repository itself does **not** run your containers. It only stores the images. ECS does the running.

## Cost Note

ECR charges for:

- Storage of your container images (GB-months)
- Data transfer out when ECS pulls images

While learning, keep only the images you actually need. You can delete old images from the ECR console or using the AWS CLI.

When you no longer need the repository:

```bash
terraform destroy -target=module.ecr
```

Be careful: destroying the ECR repository will delete all images stored inside it.

---

This module is intentionally small. Its only job is to create a safe place for your Docker images. The real work of running containers happens in the ECS module that consumes the `repository_url` output.
