variable "vpc_id" {
  description = "VPC ID for the EC2 security group"
  type        = string
}

variable "public_subnet_id" {
  description = "Public subnet ID for the EC2 instance and secondary ENI"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type"
  type        = string
}

variable "key_name" {
  description = "Name of the SSH key pair"
  type        = string
}

variable "config" {
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
}

variable "common_tags" {
  description = "Tags applied to EC2 resources."
  type        = map(string)
  default     = {}
}
