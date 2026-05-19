data "aws_ami" "amazon_linux" {
  most_recent = true

  owners = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

resource "aws_security_group" "ssh_sg" {
  name        = "tr"
  description = "Allow SSH access"
  vpc_id      = var.vpc_id

  ingress {
    description = "SSH from my laptop"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "App port 3000"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "my_server" {
  ami                         = data.aws_ami.amazon_linux.id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [aws_security_group.ssh_sg.id]
  associate_public_ip_address = true
  tags = {
    Name = "my-terraform-server tr"
  }

  lifecycle {
    ignore_changes = [ami]
  }
}

resource "aws_ebs_volume" "app_data" {
  availability_zone = aws_instance.my_server.availability_zone
  size              = 20
  type              = "gp3"
  tags = {
    Name = "app-data-volume tr"
  }
}

resource "aws_volume_attachment" "app_data" {
  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.app_data.id
  instance_id = aws_instance.my_server.id
}

resource "aws_network_interface" "app_eni" {
  subnet_id       = var.public_subnet_id
  security_groups = [aws_security_group.ssh_sg.id]

  tags = {
    Name = "app-eni tr"
  }
}

resource "aws_eip" "app_eni" {
  domain = "vpc"

  tags = {
    Name = "app-eip tr"
  }
}

resource "aws_eip_association" "app_eip_assoc" {
  allocation_id        = aws_eip.app_eni.id
  network_interface_id = aws_network_interface.app_eni.id
}

resource "aws_network_interface_attachment" "app_eni_attach" {
  instance_id          = aws_instance.my_server.id
  network_interface_id = aws_network_interface.app_eni.id
  device_index         = 1
}
