# EC2 Module Explanation

This folder contains a Terraform module that creates EC2-related AWS resources.
The main file is `main.tf`.

This module creates:

- An Amazon Linux AMI lookup
- A security group for SSH and application traffic
- One EC2 instance
- One EBS data volume
- One EBS volume attachment
- One extra network interface
- One Elastic IP
- An Elastic IP association
- A network interface attachment

## Basic Terraform Syntax

Terraform files use blocks.

Example:

```hcl
resource "aws_instance" "my_server" {
  instance_type = var.instance_type
}
```

The general shape is:

```hcl
block_type "provider_resource_type" "local_name" {
  argument_name = argument_value
}
```

In this module:

- `data` means Terraform reads existing information from AWS.
- `resource` means Terraform creates or manages something in AWS.
- `var.something` means the value comes from `variables.tf` or from the parent module.
- `aws_instance.my_server.id` means Terraform reads the `id` value from the EC2 instance resource named `my_server`.

## Variables Used In This Module

The file uses values like:

```hcl
var.vpc_id
var.public_subnet_id
var.instance_type
var.key_name
var.common_tags
var.config.ssh_port
```

These are input variables.

For example:

```hcl
var.config.ssh_port
```

means:

- `var` = Terraform variable
- `config` = the object variable named `config`
- `ssh_port` = one field inside that object

The structure of `config` is defined in `variables.tf`.

## Data Source: Find Amazon Linux AMI

```hcl
data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = var.config.ami_owners

  filter {
    name   = "name"
    values = [var.config.ami_name_filter]
  }

  filter {
    name   = "architecture"
    values = [var.config.ami_architecture]
  }
}
```

This block does not create a new AMI.
It searches AWS for an existing AMI.

Important syntax:

- `data "aws_ami" "amazon_linux"` creates a local data source named `amazon_linux`.
- `most_recent = true` tells Terraform to pick the newest matching AMI.
- `owners = var.config.ami_owners` limits the search to AMIs owned by specific AWS accounts.
- `filter { ... }` narrows the search.
- `values = [var.config.ami_name_filter]` uses a list. Square brackets `[]` mean list.

### More Detail About filter Syntax

This part:

```hcl
filter {
  name   = "name"
  values = [var.config.ami_name_filter]
}
```

means:

```text
Find AMIs where the AMI name matches my configured AMI name pattern.
```

The `filter` block has two important arguments:

```hcl
name = "name"
```

This tells AWS which AMI field to check.
Here, `"name"` means the AMI name field.

```hcl
values = [var.config.ami_name_filter]
```

This tells AWS what value to search for.
The value comes from your `config` variable.

For example, if your root module passes this:

```hcl
config = {
  ami_name_filter  = "al2023-ami-*-x86_64"
  ami_architecture = "x86_64"
}
```

then Terraform reads this:

```hcl
var.config.ami_name_filter
```

as:

```hcl
"al2023-ami-*-x86_64"
```

So this code:

```hcl
values = [var.config.ami_name_filter]
```

becomes:

```hcl
values = ["al2023-ami-*-x86_64"]
```

The square brackets are important.
`values` must be a list, even when you only have one value.

This is valid:

```hcl
values = ["al2023-ami-*-x86_64"]
```

This is not valid for this argument:

```hcl
values = "al2023-ami-*-x86_64"
```

You can also give more than one possible value:

```hcl
values = [
  "al2023-ami-*-x86_64",
  "amzn2-ami-hvm-*-x86_64-gp2"
]
```

The second filter:

```hcl
filter {
  name   = "architecture"
  values = [var.config.ami_architecture]
}
```

means:

```text
Only find AMIs with the architecture I configured.
```

For example, if:

```hcl
ami_architecture = "x86_64"
```

then Terraform sends this filter to AWS:

```hcl
filter {
  name   = "architecture"
  values = ["x86_64"]
}
```

Together, the two filters mean:

```text
Find AMIs where:

1. The AMI name matches "al2023-ami-*-x86_64"
2. The CPU architecture is "x86_64"
```

Because the data source also has:

```hcl
most_recent = true
```

Terraform picks the newest AMI from the matching results.

Later, the EC2 instance uses the result:

```hcl
ami = data.aws_ami.amazon_linux.id
```

This means:

- `data` = read from a data source
- `aws_ami` = data source type
- `amazon_linux` = local name
- `id` = AMI ID found by the search

## Security Group

```hcl
resource "aws_security_group" "ssh_sg" {
  name        = var.config.security_group_name
  description = "Allow SSH access"
  vpc_id      = var.vpc_id
}
```

This creates a security group in the VPC.
A security group works like a firewall for EC2.

Important syntax:

- `resource "aws_security_group" "ssh_sg"` creates an AWS security group.
- `ssh_sg` is the local Terraform name. You can reference it later.
- `vpc_id = var.vpc_id` places the security group inside the selected VPC.

### SSH Ingress Rule

```hcl
ingress {
  description = "SSH from my laptop"
  from_port   = var.config.ssh_port
  to_port     = var.config.ssh_port
  protocol    = "tcp"
  cidr_blocks = var.config.ssh_cidr_blocks
}
```

`ingress` means incoming traffic.

This rule allows SSH traffic.
Usually SSH uses port `22`.

Important fields:

- `from_port` = first allowed port
- `to_port` = last allowed port
- `protocol = "tcp"` = TCP traffic
- `cidr_blocks` = allowed source IP ranges

If `ssh_cidr_blocks` is your laptop IP only, only your laptop can SSH.
If it is `["0.0.0.0/0"]`, anyone on the internet can try to connect.

### Application Port Ingress Rule

```hcl
ingress {
  description = "App port ${var.config.app_port}"
  from_port   = var.config.app_port
  to_port     = var.config.app_port
  protocol    = "tcp"
  cidr_blocks = var.config.app_cidr_blocks
}
```

This allows incoming traffic to your application port.

Important syntax:

```hcl
"App port ${var.config.app_port}"
```

This is string interpolation.
Terraform replaces `${var.config.app_port}` with the actual port number.

Example:

```hcl
description = "App port 8080"
```

### Egress Rule

```hcl
egress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = var.config.egress_cidr_blocks
}
```

`egress` means outgoing traffic.

Important syntax:

- `protocol = "-1"` means all protocols.
- `from_port = 0` and `to_port = 0` are used with all protocols.
- `cidr_blocks` controls where the instance can connect.

Common value:

```hcl
egress_cidr_blocks = ["0.0.0.0/0"]
```

This allows outgoing traffic to the internet.

## EC2 Instance

```hcl
resource "aws_instance" "my_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh_sg.id]
  associate_public_ip_address = var.config.associate_public_ip
  tags                        = merge(var.common_tags, { Name = var.config.instance_name })
}
```

This creates the EC2 server.

Important fields:

- `ami` = image used to start the server
- `instance_type` = server size, for example `t2.micro` or `t3.micro`
- `key_name` = AWS key pair name for SSH
- `subnet_id` = subnet where the instance is created
- `vpc_security_group_ids` = security groups attached to the instance
- `associate_public_ip_address` = whether AWS gives the instance a public IP
- `tags` = AWS tags for organization

Important syntax:

```hcl
vpc_security_group_ids = [aws_security_group.ssh_sg.id]
```

This is a list with one item.
It references the security group created earlier.

Terraform understands this dependency automatically:

1. Create the security group.
2. Create the EC2 instance using that security group.

### More Detail About aws_instance Syntax

This line:

```hcl
resource "aws_instance" "my_server" {
```

means:

```text
Create one AWS EC2 instance, and inside Terraform call it my_server.
```

Breakdown:

- `resource` = Terraform will create or manage something.
- `aws_instance` = the AWS provider resource type for EC2 instances.
- `my_server` = your local Terraform name for this EC2 instance.

The local name is not automatically the AWS instance name.
The AWS instance name comes from the `Name` tag:

```hcl
tags = merge(var.common_tags, { Name = var.config.instance_name })
```

### Line By Line Example

Imagine your variables have these values:

```hcl
instance_type = "t3.micro"
key_name      = "my-laptop-key"

public_subnet_id = "subnet-0123456789abcdef0"

config = {
  associate_public_ip = true
  instance_name       = "learning-server"
}

common_tags = {
  Environment = "dev"
  Project     = "terraform-learning"
}
```

Also imagine the AMI data source found this AMI:

```hcl
data.aws_ami.amazon_linux.id = "ami-0123456789abcdef0"
```

And the security group resource created this security group:

```hcl
aws_security_group.ssh_sg.id = "sg-0123456789abcdef0"
```

Then this original code:

```hcl
resource "aws_instance" "my_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh_sg.id]
  associate_public_ip_address = var.config.associate_public_ip
  tags                        = merge(var.common_tags, { Name = var.config.instance_name })
}
``` 

is understood by Terraform like this:

```hcl
resource "aws_instance" "my_server" {
  ami                         = "ami-0123456789abcdef0"
  instance_type               = "t3.micro"
  key_name                    = "my-laptop-key"
  subnet_id                   = "subnet-0123456789abcdef0"
  vpc_security_group_ids      = ["sg-0123456789abcdef0"]
  associate_public_ip_address = true
  tags = {
    Environment = "dev"
    Project     = "terraform-learning"
    Name        = "learning-server"
  }
}
```

This is not code you need to write.
It is an example of what Terraform calculates from your variables and references.

### About ami

```hcl
ami = data.aws_ami.amazon_linux.id
```

This means:

```text
Use the AMI ID found by the aws_ami data source.
```

The EC2 instance needs an AMI because an AMI is the operating system image.
For example, Amazon Linux, Ubuntu, or Windows Server.

### About instance_type

```hcl
instance_type = var.instance_type
```

This means:

```text
Use the EC2 size passed into this module.
```

Example values:

```hcl
instance_type = "t3.micro"
instance_type = "t3.small"
instance_type = "t2.micro"
```

For learning, `t2.micro` or `t3.micro` is common.

### About key_name

```hcl
key_name = var.key_name
```

This is the AWS key pair name used for SSH login.

Important: this is not the file path to your `.pem` file.
It is the key pair name already registered in AWS.

Example:

```hcl
key_name = "my-laptop-key"
```

Then you may SSH with a local private key file like:

```bash
ssh -i ~/.ssh/my-laptop-key.pem ec2-user@PUBLIC_IP
```

### About subnet_id

```hcl
subnet_id = var.public_subnet_id
```

This tells AWS which subnet to place the EC2 instance in.

In your module, the variable name is `public_subnet_id`, so the instance is expected to be in a public subnet.
A public subnet usually has a route to an Internet Gateway.

### About vpc_security_group_ids

```hcl
vpc_security_group_ids = [aws_security_group.ssh_sg.id]
```

This attaches the security group to the EC2 instance.

The value must be a list of security group IDs.
That is why the code uses square brackets:

```hcl
[aws_security_group.ssh_sg.id]
```

If the security group ID is:

```hcl
"sg-0123456789abcdef0"
```

then Terraform treats the line like:

```hcl
vpc_security_group_ids = ["sg-0123456789abcdef0"]
```

You can attach more than one security group:

```hcl
vpc_security_group_ids = [
  aws_security_group.ssh_sg.id,
  aws_security_group.web_sg.id
]
```

### About associate_public_ip_address

```hcl
associate_public_ip_address = var.config.associate_public_ip
```

This controls whether AWS gives the instance a public IP address at launch.

Example:

```hcl
associate_public_ip = true
```

means the instance can receive a public IP, if the subnet supports it.

```hcl
associate_public_ip = false
```

means AWS should not assign a public IP directly to this instance.

In this module, you also create an Elastic IP and attach it to an extra network interface.
That is separate from the instance's automatically assigned public IP.

### Tags And merge()

```hcl
tags = merge(var.common_tags, { Name = var.config.instance_name })
```

`merge()` combines maps.

`var.common_tags` may contain shared tags like:

```hcl
{
  Environment = "dev"
  Project     = "learning"
}
```

`{ Name = var.config.instance_name }` adds the AWS `Name` tag.

The final result may look like:

```hcl
{
  Environment = "dev"
  Project     = "learning"
  Name        = "my-server"
}
```

### Lifecycle Ignore Changes

```hcl
lifecycle {
  ignore_changes = [ami]
}
```

This tells Terraform to ignore future AMI changes.

Why this matters:

- The AMI data source uses `most_recent = true`.
- A newer AMI may appear later.
- Without `ignore_changes`, Terraform may want to replace the EC2 instance.
- With `ignore_changes = [ami]`, Terraform keeps the existing instance AMI.

## EBS Volume

```hcl
resource "aws_ebs_volume" "app_data" {
  availability_zone = aws_instance.my_server.availability_zone
  size              = var.config.ebs_volume_size
  type              = var.config.ebs_volume_type
  tags              = merge(var.common_tags, { Name = var.config.ebs_volume_name })
}
```

This creates an EBS volume.
An EBS volume is like a disk for EC2.

Important fields:

- `availability_zone` = where the disk is created
- `size` = disk size in GB
- `type` = disk type, for example `gp3`
- `tags` = AWS tags

Important syntax:

```hcl
availability_zone = aws_instance.my_server.availability_zone
```

This makes the EBS volume use the same Availability Zone as the EC2 instance.
This is required because an EBS volume can only attach to an instance in the same Availability Zone.

## EBS Volume Attachment

```hcl
resource "aws_volume_attachment" "app_data" {
  device_name = var.config.ebs_device_name
  volume_id   = aws_ebs_volume.app_data.id
  instance_id = aws_instance.my_server.id
}
```

This attaches the EBS volume to the EC2 instance.

Important fields:

- `device_name` = Linux device path, for example `/dev/sdf`
- `volume_id` = the EBS volume to attach
- `instance_id` = the EC2 instance to attach it to

Terraform sees these references and creates resources in the correct order:

1. Create EC2 instance.
2. Create EBS volume.
3. Attach EBS volume to EC2 instance.

## Network Interface

```hcl
resource "aws_network_interface" "app_eni" {
  subnet_id       = var.public_subnet_id
  security_groups = [aws_security_group.ssh_sg.id]

  tags = merge(var.common_tags, { Name = var.config.network_interface_name })
}
```

This creates an Elastic Network Interface, also called an ENI.
An ENI is a virtual network card.

Important fields:

- `subnet_id` = subnet where the ENI is created
- `security_groups` = security groups attached to the ENI
- `tags` = AWS tags

### More Detail About Network Interfaces

An ENI is like an extra network card for your EC2 instance.

Your EC2 instance already has a primary network interface when it is created.
This block creates another one:

```hcl
resource "aws_network_interface" "app_eni" {
```

Breakdown:

- `resource` = Terraform creates or manages something.
- `aws_network_interface` = AWS resource type for an ENI.
- `app_eni` = local Terraform name for this ENI.

This line:

```hcl
subnet_id = var.public_subnet_id
```

means:

```text
Create this ENI inside the public subnet.
```

This line:

```hcl
security_groups = [aws_security_group.ssh_sg.id]
```

means:

```text
Attach the security group named ssh_sg to this ENI.
```

The value is inside square brackets because `security_groups` expects a list.

Example:

```hcl
security_groups = ["sg-0123456789abcdef0"]
```

You can attach more than one security group:

```hcl
security_groups = [
  aws_security_group.ssh_sg.id,
  aws_security_group.web_sg.id
]
```

## Elastic IP

```hcl
resource "aws_eip" "app_eip" {
  domain = "vpc"

  tags = merge(var.common_tags, { Name = var.config.elastic_ip_name })
}
```

This creates an Elastic IP.
An Elastic IP is a static public IPv4 address.

Important syntax:

- `domain = "vpc"` means this Elastic IP is for use in a VPC.

### More Detail About Elastic IP

Normally, an EC2 public IP can change when the instance is stopped and started.
An Elastic IP is different because it is a static public IP address.

This block:

```hcl
resource "aws_eip" "app_eip" {
  domain = "vpc"
}
```

means:

```text
Create one static public IPv4 address for use inside a VPC.
```

The local Terraform name is `app_eip`:

```hcl
resource "aws_eip" "app_eip"
```

This name is clearer than `app_eni` because this resource is an Elastic IP.

These two addresses are different Terraform resources:

```text
aws_network_interface.app_eni
aws_eip.app_eip
```

The ENI uses the local name `app_eni`.
The Elastic IP uses the local name `app_eip`.

## Elastic IP Association

```hcl
resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = aws_eip.app_eip.id
  network_interface_id = aws_network_interface.app_eni.id
}
```

This associates the Elastic IP with the network interface.

Important fields:

- `allocation_id` = the Elastic IP allocation ID
- `network_interface_id` = the ENI ID

Important syntax:

```hcl
aws_eip.app_eip.id
```

This references the Elastic IP resource.

```hcl
aws_network_interface.app_eni.id
```

This references the network interface resource.

### More Detail About Elastic IP Association

Creating an Elastic IP alone is not enough.
AWS gives you the static IP, but you still need to attach it to something.

This block attaches the Elastic IP to the ENI:

```hcl
resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = aws_eip.app_eip.id
  network_interface_id = aws_network_interface.app_eni.id
}
```

This line:

```hcl
allocation_id = aws_eip.app_eip.id
```

means:

```text
Use the Elastic IP created by aws_eip.app_eip.
```

This line:

```hcl
network_interface_id = aws_network_interface.app_eni.id
```

means:

```text
Attach that Elastic IP to the network interface created by aws_network_interface.app_eni.
```

Example after Terraform evaluates the references:

```hcl
resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = "eipalloc-0123456789abcdef0"
  network_interface_id = "eni-0123456789abcdef0"
}
```

This is not code you write manually.
It shows what Terraform calculates after AWS creates the resources.

## Network Interface Attachment

```hcl
resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = aws_instance.my_server.id
  network_interface_id = aws_network_interface.app_eni.id
  device_index         = var.config.network_interface_device_index
}
```

This attaches the ENI to the EC2 instance.

Important fields:

- `instance_id` = EC2 instance ID
- `network_interface_id` = ENI ID
- `device_index` = network device number on the instance

Important note:

- `device_index = 0` is usually the primary network interface.
- A second network interface usually uses `device_index = 1`.

### More Detail About Network Interface Attachment

Creating an ENI does not automatically attach it to the EC2 instance.
This block attaches it:

```hcl
resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = aws_instance.my_server.id
  network_interface_id = aws_network_interface.app_eni.id
  device_index         = var.config.network_interface_device_index
}
```

This line:

```hcl
instance_id = aws_instance.my_server.id
```

means:

```text
Attach the ENI to the EC2 instance named my_server.
```

This line:

```hcl
network_interface_id = aws_network_interface.app_eni.id
```

means:

```text
Use the ENI created earlier.
```

This line:

```hcl
device_index = var.config.network_interface_device_index
```

means:

```text
Choose which network card number this ENI becomes on the instance.
```

Example:

```hcl
network_interface_device_index = 1
```

Then Terraform treats the attachment like:

```hcl
resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = "i-0123456789abcdef0"
  network_interface_id = "eni-0123456789abcdef0"
  device_index         = 1
}
```

For most beginner cases:

- `device_index = 0` means primary network interface.
- `device_index = 1` means second network interface.

Because your EC2 instance already has a primary network interface, this extra ENI should usually use `1`.

### Full Example Of This Section

Imagine Terraform has these values:

```hcl
public_subnet_id = "subnet-0123456789abcdef0"

config = {
  network_interface_name         = "app-extra-eni"
  elastic_ip_name                = "app-static-ip"
  network_interface_device_index = 1
}

common_tags = {
  Environment = "dev"
  Project     = "terraform-learning"
}
```

And imagine AWS created these IDs:

```hcl
aws_security_group.ssh_sg.id      = "sg-0123456789abcdef0"
aws_network_interface.app_eni.id  = "eni-0123456789abcdef0"
aws_eip.app_eip.id                = "eipalloc-0123456789abcdef0"
aws_instance.my_server.id         = "i-0123456789abcdef0"
```

Then Terraform understands this section like:

```hcl
resource "aws_network_interface" "app_eni" {
  subnet_id       = "subnet-0123456789abcdef0"
  security_groups = ["sg-0123456789abcdef0"]

  tags = {
    Environment = "dev"
    Project     = "terraform-learning"
    Name        = "app-extra-eni"
  }
}

resource "aws_eip" "app_eip" {
  domain = "vpc"

  tags = {
    Environment = "dev"
    Project     = "terraform-learning"
    Name        = "app-static-ip"
  }
}

resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = "eipalloc-0123456789abcdef0"
  network_interface_id = "eni-0123456789abcdef0"
}

resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = "i-0123456789abcdef0"
  network_interface_id = "eni-0123456789abcdef0"
  device_index         = 1
}
```

### What This Section Does In Order

Terraform will understand the dependencies like this:

1. Create the EC2 instance.
2. Create the security group.
3. Create the extra ENI in the public subnet.
4. Create the Elastic IP.
5. Associate the Elastic IP with the ENI.
6. Attach the ENI to the EC2 instance as device index `1`.

The final result is:

```text
Internet
   |
Elastic IP
   |
Extra network interface
   |
EC2 instance
```

## Terraform Automatically Builds A Dependency Graph

Terraform uses references to understand order.

Example:

```hcl
instance_id = aws_instance.my_server.id
```

Because this attachment needs `aws_instance.my_server.id`, Terraform knows the EC2 instance must exist first.

You usually do not need to manually say "create this first".
Terraform can understand it from references.

## Resource Address Cheat Sheet

These are the local Terraform addresses in this file:

```text
data.aws_ami.amazon_linux
aws_security_group.ssh_sg
aws_instance.my_server
aws_ebs_volume.app_data
aws_volume_attachment.app_data
aws_network_interface.app_eni
aws_eip.app_eip
aws_eip_association.app_eip_assoc
aws_network_interface_attachment.app_eni_attach
```

You can use addresses like these with Terraform commands.

Example:

```bash
terraform state show aws_instance.my_server
```

## Beginner Notes

- Strings use quotes: `"tcp"`.
- Numbers do not use quotes: `22`.
- Booleans are `true` or `false`.
- Lists use square brackets: `["0.0.0.0/0"]`.
- Maps and objects use curly braces: `{ Name = "my-server" }`.
- Nested blocks use braces, for example `ingress { ... }`.
- References connect resources together, for example `aws_instance.my_server.id`.

## What Happens When You Apply This Module

When you run Terraform from the root module, Terraform will roughly do this:

1. Search for the newest matching Amazon Linux AMI.
2. Create the security group.
3. Create the EC2 instance.
4. Create the EBS volume in the same Availability Zone as the instance.
5. Attach the EBS volume to the instance.
6. Create the extra network interface.
7. Create the Elastic IP.
8. Associate the Elastic IP with the network interface.
9. Attach the network interface to the EC2 instance.

## Important AWS Cost Note

Some resources in this file can cost money:

- EC2 instance
- EBS volume
- Elastic IP, especially if unused

When learning, remember to destroy resources you do not need:

```bash
terraform destroy
```
