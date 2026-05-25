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

resource "aws_security_group" "ssh_sg" {
  name        = var.config.security_group_name
  description = "Allow SSH access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from my laptop"
    from_port   = var.config.ssh_port
    to_port     = var.config.ssh_port
    protocol    = "tcp"
    cidr_blocks = var.config.ssh_cidr_blocks
  }

  ingress {
    description = "App port ${var.config.app_port}"
    from_port   = var.config.app_port
    to_port     = var.config.app_port
    protocol    = "tcp"
    cidr_blocks = var.config.app_cidr_blocks
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = var.config.egress_cidr_blocks
  }
}

resource "aws_instance" "my_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh_sg.id]
  associate_public_ip_address = var.config.associate_public_ip
  tags                        = merge(var.common_tags, { Name = var.config.instance_name })

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "app_data" {
  availability_zone = aws_instance.my_server.availability_zone
  size              = var.config.ebs_volume_size
  type              = var.config.ebs_volume_type
  tags              = merge(var.common_tags, { Name = var.config.ebs_volume_name })
}

resource "aws_volume_attachment" "app_data" {
  device_name = var.config.ebs_device_name
  volume_id   = aws_ebs_volume.app_data.id
  instance_id = aws_instance.my_server.id
}

resource "aws_network_interface" "app_eni" {
  subnet_id       = var.public_subnet_id
  security_groups = [aws_security_group.ssh_sg.id]

  tags = merge(var.common_tags, { Name = var.config.network_interface_name })
}

resource "aws_eip" "app_eip" {
  domain = "vpc"

  tags = merge(var.common_tags, { Name = var.config.elastic_ip_name })
}

resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = aws_eip.app_eip.id
  network_interface_id = aws_network_interface.app_eni.id
}

resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = aws_instance.my_server.id
  network_interface_id = aws_network_interface.app_eni.id
  device_index         = var.config.network_interface_device_index
}
