# Network Module Guide

This folder contains a Terraform module that creates the basic AWS network for the project.
The main file is `main.tf`.

This module creates:

- One VPC
- Two public subnets
- One Internet Gateway
- One public route table
- Public route table associations
- Two private subnets
- NAT Gateway(s) + EIP(s)   ← controlled by single_nat_gateway (Step 8)
- Private route table(s)    ← one shared or one per AZ depending on the flag

## Big Picture

The network looks like this (when single_nat_gateway = true, the default for learning):

```text
VPC
|
+-- Public subnet A (AZ-a)
|   |
|   +-- Route to Internet Gateway
|   |
|   +-- NAT Gateway (shared)
|
+-- Public subnet B (AZ-b)
|   |
|   +-- Route to Internet Gateway
|
+-- Private subnet A (AZ-a)
|   |
|   +-- Route to shared NAT Gateway
|
+-- Private subnet B (AZ-b)
    |
    +-- Route to shared NAT Gateway
```

When single_nat_gateway = false (HA mode):
- NAT Gateway in Public A for Private A only
- NAT Gateway in Public B for Private B only
- Separate private route tables

Public subnets can reach the internet through the Internet Gateway.
Private subnets can reach the internet through the NAT Gateway(s), but the internet cannot directly start connections to private subnet resources.

## Example Input Values

The module receives values from the root module through the `config` variable.

Example:

```hcl
module "network" {
  source = "./modules/network"

  config = {
    vpc_cidr = "10.0.0.0/16"
    vpc_name = "learning-vpc"

    public_subnet_a_cidr = "10.0.1.0/24"
    public_subnet_a_az   = "ap-southeast-1a"
    public_subnet_a_name = "public-a"

    public_subnet_b_cidr = "10.0.2.0/24"
    public_subnet_b_az   = "ap-southeast-1b"
    public_subnet_b_name = "public-b"

    private_subnet_a_cidr = "10.0.101.0/24"
    private_subnet_a_az   = "ap-southeast-1a"
    private_subnet_a_name = "private-a"

    private_subnet_b_cidr = "10.0.102.0/24"
    private_subnet_b_az   = "ap-southeast-1b"
    private_subnet_b_name = "private-b"

    internet_gateway_name    = "learning-igw"
    public_route_table_name  = "public-rt"
    private_route_table_name = "private-rt"
    nat_gateway_name         = "learning-nat"

    public_route_cidr_block  = "0.0.0.0/0"
    private_route_cidr_block = "0.0.0.0/0"

    map_public_ip_on_launch = true
  }

  common_tags = {
    Environment = "dev"
    Project     = "terraform-learning"
  }
}
```

## Basic Terraform Syntax

Terraform uses blocks.

Example:

```hcl
resource "aws_vpc" "main" {
  cidr_block = var.config.vpc_cidr
}
```

The general shape is:

```hcl
resource "aws_resource_type" "local_name" {
  argument_name = argument_value
}
```

In this module:

- `resource` means Terraform creates or manages something in AWS.
- `aws_vpc` is the AWS resource type.
- `main` is the local Terraform name.
- `var.config.vpc_cidr` means the value comes from the `config` input variable.
- `aws_vpc.main.id` means Terraform uses the ID of the VPC resource named `main`.

## VPC

```hcl
resource "aws_vpc" "main" {
  cidr_block = var.config.vpc_cidr
  tags       = merge(var.common_tags, { Name = var.config.vpc_name })
}
```

This creates the VPC.
A VPC is your private network inside AWS.

Important fields:

- `cidr_block` = IP range for the whole VPC.
- `tags` = labels added to the AWS resource.

Example:

```hcl
vpc_cidr = "10.0.0.0/16"
```

This gives the VPC IP addresses from the `10.0.x.x` range.

### About tags and merge()

```hcl
tags = merge(var.common_tags, { Name = var.config.vpc_name })
```

`merge()` combines maps.

Example:

```hcl
common_tags = {
  Environment = "dev"
  Project     = "terraform-learning"
}

vpc_name = "learning-vpc"
```

Terraform builds:

```hcl
tags = {
  Environment = "dev"
  Project     = "terraform-learning"
  Name        = "learning-vpc"
}
```

## Public Subnet A

```hcl
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.public_subnet_a_cidr
  availability_zone       = var.config.public_subnet_a_az
  map_public_ip_on_launch = var.config.map_public_ip_on_launch
  tags                    = merge(var.common_tags, { Name = var.config.public_subnet_a_name })
}
```

This creates the first public subnet.

Important fields:

- `vpc_id` = the VPC where the subnet is created.
- `cidr_block` = IP range for this subnet.
- `availability_zone` = AWS data center zone for this subnet.
- `map_public_ip_on_launch` = whether new instances get a public IP automatically.
- `tags` = AWS tags.

Example:

```hcl
public_subnet_a_cidr = "10.0.1.0/24"
public_subnet_a_az   = "ap-southeast-1a"
```

This creates a subnet in Availability Zone `ap-southeast-1a` with IPs like `10.0.1.x`.

This line:

```hcl
vpc_id = aws_vpc.main.id
```

means:

```text
Create this subnet inside the VPC created earlier.
```

Terraform sees this reference and knows the VPC must be created before the subnet.

## Public Subnet B

```hcl
resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.public_subnet_b_cidr
  availability_zone       = var.config.public_subnet_b_az
  map_public_ip_on_launch = var.config.map_public_ip_on_launch
  tags                    = merge(var.common_tags, { Name = var.config.public_subnet_b_name })
}
```

This creates the second public subnet.
It is usually placed in a different Availability Zone for better availability.

Example:

```hcl
public_subnet_b_cidr = "10.0.2.0/24"
public_subnet_b_az   = "ap-southeast-1b"
```

## Internet Gateway

```hcl
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = var.config.internet_gateway_name })
}
```

This creates an Internet Gateway and attaches it to the VPC.

An Internet Gateway allows resources in public subnets to communicate with the internet, if the route table allows it.

Important syntax:

```hcl
vpc_id = aws_vpc.main.id
```

This attaches the Internet Gateway to the VPC created by this module.

## Public Route Table

```hcl
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.config.public_route_cidr_block
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, { Name = var.config.public_route_table_name })
}
```

This creates the route table for public subnets.
A route table controls where network traffic goes.

The nested `route` block is the important part:

```hcl
route {
  cidr_block = var.config.public_route_cidr_block
  gateway_id = aws_internet_gateway.igw.id
}
```

Example:

```hcl
public_route_cidr_block = "0.0.0.0/0"
```

Then Terraform understands the route like:

```hcl
route {
  cidr_block = "0.0.0.0/0"
  gateway_id = "igw-0123456789abcdef0"
}
```

`0.0.0.0/0` means all IPv4 destinations.

So this route means:

```text
For internet traffic, send it to the Internet Gateway.
```

This is what makes a subnet public when the subnet is associated with this route table.

## Public Route Table Associations

```hcl
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}
```

These blocks connect the public subnets to the public route table.

Important syntax:

```hcl
subnet_id = aws_subnet.public.id
```

means:

```text
Use public subnet A.
```

```hcl
route_table_id = aws_route_table.public.id
```

means:

```text
Use the public route table.
```

Result:

```text
public subnet A -> public route table -> Internet Gateway
public subnet B -> public route table -> Internet Gateway
```

## Private Subnets

```hcl
resource "aws_subnet" "private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.config.private_subnet_a_cidr
  availability_zone = var.config.private_subnet_a_az

  tags = merge(var.common_tags, { Name = var.config.private_subnet_a_name })
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.config.private_subnet_b_cidr
  availability_zone = var.config.private_subnet_b_az

  tags = merge(var.common_tags, { Name = var.config.private_subnet_b_name })
}
```

These create two private subnets.

Private subnets do not automatically receive public IP addresses in this module.
They also do not use the public route table.

Example:

```hcl
private_subnet_a_cidr = "10.0.101.0/24"
private_subnet_a_az   = "ap-southeast-1a"

private_subnet_b_cidr = "10.0.102.0/24"
private_subnet_b_az   = "ap-southeast-1b"
```

## Elastic IP For NAT Gateway

```hcl
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.common_tags, { Name = var.config.nat_gateway_name })
}
```

This creates a static public IPv4 address for the NAT Gateway.

Important syntax:

- `aws_eip` = Elastic IP resource.
- `nat` = local Terraform name.
- `domain = "vpc"` = this Elastic IP is for VPC use.

The NAT Gateway needs this Elastic IP so private subnet traffic can go out to the internet.

## NAT Gateway

```hcl
resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(var.common_tags, { Name = var.config.nat_gateway_name })

  depends_on = [aws_internet_gateway.igw]
}
```

This creates a NAT Gateway.

A NAT Gateway lets resources in private subnets start outbound internet connections.
For example, a private EC2 instance can download packages from the internet.

But the internet cannot directly start a connection to that private EC2 instance.

Important fields:

- `allocation_id` = Elastic IP used by the NAT Gateway.
- `subnet_id` = public subnet where the NAT Gateway is placed.
- `depends_on` = explicit dependency.

This line:

```hcl
allocation_id = aws_eip.nat.id
```

means:

```text
Use the Elastic IP created for the NAT Gateway.
```

This line:

```hcl
subnet_id = aws_subnet.public.id
```

means:

```text
Place the NAT Gateway in public subnet A.
```

The NAT Gateway must be in a public subnet because it needs access to the Internet Gateway.

### About depends_on

```hcl
depends_on = [aws_internet_gateway.igw]
```

Terraform usually understands dependency order from references.
Here, the NAT Gateway does not directly reference `aws_internet_gateway.igw`.

The explicit `depends_on` tells Terraform:

```text
Create the Internet Gateway before creating the NAT Gateway.
```

This is useful because the NAT Gateway needs public internet connectivity to work correctly.

## Private Route Table

```hcl
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = var.config.private_route_cidr_block
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = var.config.private_route_table_name })
}
```

This creates the route table for private subnets.

The route block:

```hcl
route {
  cidr_block     = var.config.private_route_cidr_block
  nat_gateway_id = aws_nat_gateway.main.id
}
```

Example:

```hcl
private_route_cidr_block = "0.0.0.0/0"
```

Then Terraform understands:

```hcl
route {
  cidr_block     = "0.0.0.0/0"
  nat_gateway_id = "nat-0123456789abcdef0"
}
```

This route means:

```text
For internet traffic from private subnets, send it to the NAT Gateway.
```

## Private Route Table Associations

```hcl
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
```

These blocks connect the private subnets to the private route table.

Result:

```text
private subnet A -> private route table -> NAT Gateway -> Internet Gateway
private subnet B -> private route table -> NAT Gateway -> Internet Gateway
```

## Full Evaluated Example

Imagine Terraform receives these inputs:

```hcl
vpc_cidr = "10.0.0.0/16"

public_subnet_a_cidr = "10.0.1.0/24"
public_subnet_b_cidr = "10.0.2.0/24"

private_subnet_a_cidr = "10.0.101.0/24"
private_subnet_b_cidr = "10.0.102.0/24"

public_route_cidr_block  = "0.0.0.0/0"
private_route_cidr_block = "0.0.0.0/0"
```

After AWS creates resources, Terraform may have IDs like:

```hcl
aws_vpc.main.id            = "vpc-0123456789abcdef0"
aws_subnet.public.id       = "subnet-11111111111111111"
aws_subnet.public_b.id     = "subnet-22222222222222222"
aws_subnet.private_a.id    = "subnet-33333333333333333"
aws_subnet.private_b.id    = "subnet-44444444444444444"
aws_internet_gateway.igw.id = "igw-0123456789abcdef0"
aws_eip.nat.id             = "eipalloc-0123456789abcdef0"
aws_nat_gateway.main.id    = "nat-0123456789abcdef0"
```

Then the important relationships become:

```text
public subnet A uses public route table
public subnet B uses public route table
public route table sends 0.0.0.0/0 to Internet Gateway

private subnet A uses private route table
private subnet B uses private route table
private route table sends 0.0.0.0/0 to NAT Gateway
```

## Terraform Creation Order

Terraform uses references to understand order.
The order is roughly:

1. Create the VPC.
2. Create public and private subnets inside the VPC.
3. Create the Internet Gateway and attach it to the VPC.
4. Create the public route table.
5. Associate public subnets with the public route table.
6. Create the Elastic IP for NAT.
7. Create the NAT Gateway in public subnet A.
8. Create the private route table.
9. Associate private subnets with the private route table.

## Module Outputs

The module exposes these values in `outputs.tf`:

```hcl
output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "public_subnet_ids" {
  value = [aws_subnet.public.id, aws_subnet.public_b.id]
}

output "private_subnet_ids" {
  value = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}
```

Other modules can use these outputs.

Example:

```hcl
module "ec2" {
  source = "./modules/ec2"

  vpc_id           = module.network.vpc_id
  public_subnet_id = module.network.public_subnet_id
}
```

This means the EC2 module can create an instance inside the VPC and public subnet created by this network module.

## Resource Address Cheat Sheet

These are the Terraform addresses in this module:

```text
aws_vpc.main
aws_subnet.public
aws_subnet.public_b
aws_internet_gateway.igw
aws_route_table.public
aws_route_table_association.public
aws_route_table_association.public_b
aws_subnet.private_a
aws_subnet.private_b
aws_eip.nat
aws_nat_gateway.main
aws_route_table.private
aws_route_table_association.private_a
aws_route_table_association.private_b
```

Example command:

```bash
terraform state show aws_vpc.main
```

## Beginner Notes

- VPC CIDR should be bigger, for example `/16`.
- Subnet CIDRs should be smaller parts inside the VPC, for example `/24`.
- Public subnets need a route to an Internet Gateway.
- Private subnets usually use a route to a NAT Gateway for outbound internet.
- NAT Gateway must live in a public subnet.
- `0.0.0.0/0` means all IPv4 destinations.
- `aws_vpc.main.id` is a reference to the VPC ID.
- `[]` means list.
- `{}` means map or object.
- `merge()` combines maps, usually for tags.

## Cost Note

Some resources in this module can cost money:

- NAT Gateway
- Elastic IP, especially if unused

When learning, destroy resources you do not need:

```bash
terraform destroy
```
