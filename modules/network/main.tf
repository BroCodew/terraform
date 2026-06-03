# State migration for NAT when we introduced count for HA support (Step 8)
# This helps Terraform understand the old single NAT resource is now the [0] instance.
moved {
  from = aws_nat_gateway.main
  to   = aws_nat_gateway.main[0]
}

moved {
  from = aws_eip.nat
  to   = aws_eip.nat[0]
}

moved {
  from = aws_route_table.private
  to   = aws_route_table.private[0]
}

resource "aws_vpc" "main" {
  cidr_block = var.config.vpc_cidr
  tags       = merge(var.common_tags, { Name = var.config.vpc_name })
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.public_subnet_a_cidr
  availability_zone       = var.config.public_subnet_a_az
  map_public_ip_on_launch = var.config.map_public_ip_on_launch
  tags                    = merge(var.common_tags, { Name = var.config.public_subnet_a_name })
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.config.public_subnet_b_cidr
  availability_zone       = var.config.public_subnet_b_az
  map_public_ip_on_launch = var.config.map_public_ip_on_launch
  tags                    = merge(var.common_tags, { Name = var.config.public_subnet_b_name })
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = merge(var.common_tags, { Name = var.config.internet_gateway_name })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = var.config.public_route_cidr_block
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, { Name = var.config.public_route_table_name })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

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

# NAT Gateway logic for Step 8 (optional HA)
# single_nat_gateway = true  → 1 NAT in public A, shared by both private subnets (current cheap setup)
# single_nat_gateway = false → 1 NAT per AZ (public A for private A, public B for private B)

locals {
  nat_count = var.config.single_nat_gateway ? 1 : 2
}

resource "aws_eip" "nat" {
  count  = local.nat_count
  domain = "vpc"
  tags = merge(var.common_tags, {
    Name = var.config.single_nat_gateway ? var.config.nat_gateway_name : "${var.config.nat_gateway_name}-${count.index}"
  })
}

resource "aws_nat_gateway" "main" {
  count         = local.nat_count
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = count.index == 0 ? aws_subnet.public.id : aws_subnet.public_b.id
  tags = merge(var.common_tags, {
    Name = var.config.single_nat_gateway ? var.config.nat_gateway_name : "${var.config.nat_gateway_name}-${count.index}"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  count  = local.nat_count
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = var.config.private_route_cidr_block
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }

  tags = merge(var.common_tags, {
    Name = var.config.single_nat_gateway ? var.config.private_route_table_name : "${var.config.private_route_table_name}-${count.index}"
  })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private[0].id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = var.config.single_nat_gateway ? aws_route_table.private[0].id : aws_route_table.private[1].id
}
