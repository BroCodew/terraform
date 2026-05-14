# My AWS EC2 Infrastructure

This documents the AWS infrastructure I implemented using Terraform in the `ap-southeast-1` region.

## Architecture Overview

```
                      Internet
                          |
                  Internet Gateway
                          |
                   VPC (10.0.0.0/16)
                          |
          ---------------------------------
          |                               |
    Public Subnet A                Public Subnet B
    (10.0.1.0/24)                 (10.0.2.0/24)
    ap-southeast-1a               ap-southeast-1b
          |
     EC2 Instance
     (Amazon Linux 2023)
      |         |
 Primary ENI  Secondary ENI
      |              |
 Auto Public IP   Elastic IP
      |
  EBS Volume
  (20GB gp3)
```

## What I Built

### 1. VPC & Networking (`vpc.tf`)

| Resource | Details |
|----------|---------|
| VPC | CIDR `10.0.0.0/16` |
| Public Subnet A | `10.0.1.0/24` in `ap-southeast-1a`, auto-assign public IP |
| Public Subnet B | `10.0.2.0/24` in `ap-southeast-1b`, auto-assign public IP |
| Internet Gateway | Attached to VPC for internet access |
| Route Table | Routes `0.0.0.0/0` to Internet Gateway |
| Route Table Association | Links Public Subnet A to the route table |

### 2. Compute (`main.tf`)

| Resource | Details |
|----------|---------|
| AMI Data Source | Fetches latest Amazon Linux 2023 x86_64 AMI dynamically |
| Security Group | Allows inbound SSH (22) and app port (3000) from anywhere |
| EC2 Instance | Uses the fetched AMI, configurable instance type (default `t3.micro`) |

**Security Group Rules:**
- Ingress: TCP 22 (SSH) from `0.0.0.0/0`
- Ingress: TCP 3000 (App) from `0.0.0.0/0`
- Egress: All traffic to `0.0.0.0/0`

### 3. Storage (`storage-network.tf`)

| Resource | Details |
|----------|---------|
| EBS Volume | 20GB, GP3 type, same AZ as EC2 instance |
| Volume Attachment | Attached to EC2 as `/dev/sdf` |

### 4. Additional Networking (`storage-network.tf`)

| Resource | Details |
|----------|---------|
| Elastic Network Interface (ENI) | Secondary network interface in public subnet |
| Elastic IP | Static public IP address |
| EIP Association | Links Elastic IP to the ENI |
| ENI Attachment | Attaches ENI to EC2 as device index 1 |

### 5. Variables (`variables.tf`)

| Variable | Type | Default | Required |
|----------|------|---------|----------|
| `aws_region` | string | `ap-southeast-1` | No |
| `instance_type` | string | `t3.micro` | No |
| `key_name` | string | - | Yes |

### 6. Outputs (`main.tf`)

| Output | Description |
|--------|-------------|
| `public_ip` | Public IP of the EC2 instance |

## File Structure

```
.
├── main.tf              # Provider, AMI lookup, security group, EC2, output
├── vpc.tf               # VPC, subnets, IGW, route table
├── storage-network.tf   # EBS volume, ENI, Elastic IP
├── variables.tf         # Input variables
└── README.md            # Original boilerplate docs
```

## How to Deploy

```bash
# Initialize
terraform init

# Set your SSH key name
echo 'key_name = "your-key-pair"' > terraform.tfvars

# Plan and apply
terraform plan
terraform apply

# Get the public IP
terraform output public_ip
```

## Connect via SSH

```bash
ssh -i /path/to/your-key.pem ec2-user@$(terraform output -raw public_ip)
```

## Destroy

```bash
terraform destroy
```

## Resource Naming

All resources are tagged with `tr` suffix for identification:
- `my-terraform-server tr` (EC2)
- `app-data-volume tr` (EBS)
- `app-eni tr` (ENI)
- `app-eip tr` (EIP)
- `my-vpc tr`, `my-public-subnet tr`, etc.
