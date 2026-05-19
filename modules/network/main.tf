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

resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = merge(var.common_tags, { Name = var.config.nat_gateway_name })
}

resource "aws_nat_gateway" "main" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id
  tags          = merge(var.common_tags, { Name = var.config.nat_gateway_name })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = var.config.private_route_cidr_block
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = merge(var.common_tags, { Name = var.config.private_route_table_name })
}

resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}
