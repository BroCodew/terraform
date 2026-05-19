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
