variable "vpc_id" {
  description = "VPC ID for ALB resources"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the internet-facing ALB"
  type        = list(string)
}
