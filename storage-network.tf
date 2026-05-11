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
  subnet_id       = aws_subnet.public.id
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

