variable "aws_region" {
  description = "AWS region to deploy to"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  description = "Name of your ssh key"
  type        = string
}

variable "common_tags" {
  description = "Tags applied to supported resources."
  type        = map(string)
  default     = {}
}

variable "network_config" {
  description = "Network CIDR blocks, availability zones, and resource names."
  type = object({
    vpc_cidr                 = string
    vpc_name                 = string
    public_subnet_a_cidr     = string
    public_subnet_a_az       = string
    public_subnet_a_name     = string
    public_subnet_b_cidr     = string
    public_subnet_b_az       = string
    public_subnet_b_name     = string
    private_subnet_a_cidr    = string
    private_subnet_a_az      = string
    private_subnet_a_name    = string
    private_subnet_b_cidr    = string
    private_subnet_b_az      = string
    private_subnet_b_name    = string
    internet_gateway_name    = string
    public_route_table_name  = string
    private_route_table_name = string
    nat_gateway_name         = string
    public_route_cidr_block  = string
    private_route_cidr_block = string
    map_public_ip_on_launch  = bool
  })
  default = {
    vpc_cidr                 = "10.0.0.0/16"
    vpc_name                 = "my-vpc tr"
    public_subnet_a_cidr     = "10.0.1.0/24"
    public_subnet_a_az       = "ap-southeast-1a"
    public_subnet_a_name     = "my-public-subnet tr"
    public_subnet_b_cidr     = "10.0.2.0/24"
    public_subnet_b_az       = "ap-southeast-1b"
    public_subnet_b_name     = "my-public-subnet-2 tr"
    private_subnet_a_cidr    = "10.0.11.0/24"
    private_subnet_a_az      = "ap-southeast-1a"
    private_subnet_a_name    = "my-private-subnet-a tr"
    private_subnet_b_cidr    = "10.0.12.0/24"
    private_subnet_b_az      = "ap-southeast-1b"
    private_subnet_b_name    = "my-private-subnet-b tr"
    internet_gateway_name    = "igw tr"
    public_route_table_name  = "my-route-table tr"
    private_route_table_name = "private-route-table-tr"
    nat_gateway_name         = "my-nat-gateway tr"
    public_route_cidr_block  = "0.0.0.0/0"
    private_route_cidr_block = "0.0.0.0/0"
    map_public_ip_on_launch  = true
  }
}

variable "ec2_config" {
  description = "EC2, security group, EBS, ENI, and EIP settings."
  type = object({
    ami_owners                     = list(string)
    ami_name_filter                = string
    ami_architecture               = string
    security_group_name            = string
    ssh_port                       = number
    ssh_cidr_blocks                = list(string)
    app_cidr_blocks                = list(string)
    app_port                       = number
    egress_cidr_blocks             = list(string)
    instance_name                  = string
    associate_public_ip            = bool
    ebs_volume_size                = number
    ebs_volume_type                = string
    ebs_volume_name                = string
    ebs_device_name                = string
    network_interface_name         = string
    elastic_ip_name                = string
    network_interface_device_index = number
  })
  default = {
    ami_owners                     = ["amazon"]
    ami_name_filter                = "al2023-ami-*-x86_64"
    ami_architecture               = "x86_64"
    security_group_name            = "tr"
    ssh_port                       = 22
    ssh_cidr_blocks                = ["0.0.0.0/0"]
    app_cidr_blocks                = ["0.0.0.0/0"]
    app_port                       = 3000
    egress_cidr_blocks             = ["0.0.0.0/0"]
    instance_name                  = "my-terraform-server tr"
    associate_public_ip            = true
    ebs_volume_size                = 20
    ebs_volume_type                = "gp3"
    ebs_volume_name                = "app-data-volume tr"
    ebs_device_name                = "/dev/sdf"
    network_interface_name         = "app-eni tr"
    elastic_ip_name                = "app-eip tr"
    network_interface_device_index = 1
  }
}

variable "app_stacks" {
  description = "Application stacks deployed through ECR, IAM, logs, ALB, and ECS modules."
  type = map(object({
    ecr_repository_name              = string
    ecr_image_tag_mutability         = string
    ecr_scan_on_push                 = bool
    iam_execution_role_name          = string
    log_group_name                   = string
    log_group_tag_name               = string
    log_retention_in_days            = number
    alb_security_group_name          = string
    alb_ingress_cidr_blocks          = list(string)
    alb_egress_cidr_blocks           = list(string)
    ecs_task_security_group_name     = string
    ecs_task_egress_cidr_blocks      = list(string)
    alb_name                         = string
    target_group_name                = string
    listener_name                    = string
    listener_port                    = number
    target_group_port                = number
    health_check_path                = string
    health_check_interval            = number
    health_check_timeout             = number
    health_check_healthy_threshold   = number
    health_check_unhealthy_threshold = number
    health_check_matcher             = string
    cluster_name                     = string
    task_family                      = string
    task_cpu                         = number
    task_memory                      = number
    container_name                   = string
    image_tag                        = string
    container_port                   = number
    desired_count                    = number
    service_name                     = string
    awslogs_stream_prefix            = string
  }))
  default = {
    main = {
      ecr_repository_name              = "my-ecr-repo-tr"
      ecr_image_tag_mutability         = "MUTABLE"
      ecr_scan_on_push                 = true
      iam_execution_role_name          = "ecs-task-execution-role-tr"
      log_group_name                   = "/ecs/my-app-logs-tr"
      log_group_tag_name               = "my-app-logs-tr"
      log_retention_in_days            = 7
      alb_security_group_name          = "alb-sg-tr"
      alb_ingress_cidr_blocks          = ["0.0.0.0/0"]
      alb_egress_cidr_blocks           = ["0.0.0.0/0"]
      ecs_task_security_group_name     = "ecs-task-sg-tr"
      ecs_task_egress_cidr_blocks      = ["0.0.0.0/0"]
      alb_name                         = "app-alb-tr"
      target_group_name                = "app-tg-tr"
      listener_name                    = "app-listener-tr"
      listener_port                    = 80
      target_group_port                = 3000
      health_check_path                = "/"
      health_check_interval            = 30
      health_check_timeout             = 5
      health_check_healthy_threshold   = 2
      health_check_unhealthy_threshold = 2
      health_check_matcher             = "200-399"
      cluster_name                     = "my-ecs-cluster-tr"
      task_family                      = "my-app-task-tr"
      task_cpu                         = 256
      task_memory                      = 512
      container_name                   = "my-app"
      image_tag                        = "latest"
      container_port                   = 3000
      desired_count                    = 2
      service_name                     = "my-app-service-tr"
      awslogs_stream_prefix            = "ecs"
    }
  }
}

variable "domain_config" {
  description = <<EOF
  Configuration for custom domain + ACM certificate + Route53 alias record.
  Set enabled = true after you have created the Route53 hosted zone and updated nameservers at your registrar.

  Example:
    domain_config = {
      enabled     = true
      zone_id     = "Z02237983SGZXT8DWH3PD"
      domain_name = "app.terraformaws.online"
      record_name = "app"
    }
  EOF

  type = object({
    enabled                   = bool
    zone_id                   = string
    domain_name               = string
    subject_alternative_names = optional(list(string), [])
    record_name               = optional(string, "")
  })

  default = {
    enabled                   = false
    zone_id                   = ""
    domain_name               = ""
    subject_alternative_names = []
    record_name               = ""
  }
}

