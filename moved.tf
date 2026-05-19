moved {
  from = aws_vpc.main
  to   = module.network.aws_vpc.main
}

moved {
  from = aws_subnet.public
  to   = module.network.aws_subnet.public
}

moved {
  from = aws_subnet.public_b
  to   = module.network.aws_subnet.public_b
}

moved {
  from = aws_internet_gateway.igw
  to   = module.network.aws_internet_gateway.igw
}

moved {
  from = aws_route_table.public
  to   = module.network.aws_route_table.public
}

moved {
  from = aws_route_table_association.public
  to   = module.network.aws_route_table_association.public
}

moved {
  from = aws_route_table_association.public_b
  to   = module.network.aws_route_table_association.public_b
}

moved {
  from = aws_subnet.private_a
  to   = module.network.aws_subnet.private_a
}

moved {
  from = aws_subnet.private_b
  to   = module.network.aws_subnet.private_b
}

moved {
  from = aws_eip.nat
  to   = module.network.aws_eip.nat
}

moved {
  from = aws_nat_gateway.main
  to   = module.network.aws_nat_gateway.main
}

moved {
  from = aws_route_table.private
  to   = module.network.aws_route_table.private
}

moved {
  from = aws_route_table_association.private_a
  to   = module.network.aws_route_table_association.private_a
}

moved {
  from = aws_route_table_association.private_b
  to   = module.network.aws_route_table_association.private_b
}

moved {
  from = aws_security_group.ssh_sg
  to   = module.ec2.aws_security_group.ssh_sg
}

moved {
  from = aws_instance.my_server
  to   = module.ec2.aws_instance.my_server
}

moved {
  from = aws_ebs_volume.app_data
  to   = module.ec2.aws_ebs_volume.app_data
}

moved {
  from = aws_volume_attachment.app_data
  to   = module.ec2.aws_volume_attachment.app_data
}

moved {
  from = aws_network_interface.app_eni
  to   = module.ec2.aws_network_interface.app_eni
}

moved {
  from = aws_eip.app_eni
  to   = module.ec2.aws_eip.app_eni
}

moved {
  from = aws_eip_association.app_eip_assoc
  to   = module.ec2.aws_eip_association.app_eip_assoc
}

moved {
  from = aws_network_interface_attachment.app_eni_attach
  to   = module.ec2.aws_network_interface_attachment.app_eni_attach
}

moved {
  from = aws_ecr_repository.app
  to   = module.ecr.aws_ecr_repository.app
}

moved {
  from = aws_iam_role.ecs_task_execution
  to   = module.iam.aws_iam_role.ecs_task_execution
}

moved {
  from = aws_iam_role_policy_attachment.ecs_task_execution
  to   = module.iam.aws_iam_role_policy_attachment.ecs_task_execution
}

moved {
  from = aws_cloudwatch_log_group.app_logs
  to   = module.logs.aws_cloudwatch_log_group.app_logs
}

moved {
  from = aws_security_group.alb
  to   = module.alb.aws_security_group.alb
}

moved {
  from = aws_security_group.ecs_task
  to   = module.alb.aws_security_group.ecs_task
}

moved {
  from = aws_lb.app
  to   = module.alb.aws_lb.app
}

moved {
  from = aws_lb_target_group.app
  to   = module.alb.aws_lb_target_group.app
}

moved {
  from = aws_lb_listener.app
  to   = module.alb.aws_lb_listener.app
}

moved {
  from = aws_ecs_cluster.main
  to   = module.ecs.aws_ecs_cluster.main
}

moved {
  from = aws_ecs_task_definition.app
  to   = module.ecs.aws_ecs_task_definition.app
}

moved {
  from = aws_ecs_service.app
  to   = module.ecs.aws_ecs_service.app
}

moved {
  from = module.ecr
  to   = module.ecr["main"]
}

moved {
  from = module.iam
  to   = module.iam["main"]
}

moved {
  from = module.logs
  to   = module.logs["main"]
}

moved {
  from = module.alb
  to   = module.alb["main"]
}

moved {
  from = module.ecs
  to   = module.ecs["main"]
}
