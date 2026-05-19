variable "config" {
  description = "Network CIDR blocks, availability zones, and resource names."
  type = object({
    vpc_cidr                   = string
    vpc_name                   = string
    public_subnet_a_cidr       = string
    public_subnet_a_az         = string
    public_subnet_a_name       = string
    public_subnet_b_cidr       = string
    public_subnet_b_az         = string
    public_subnet_b_name       = string
    private_subnet_a_cidr      = string
    private_subnet_a_az        = string
    private_subnet_a_name      = string
    private_subnet_b_cidr      = string
    private_subnet_b_az        = string
    private_subnet_b_name      = string
    internet_gateway_name      = string
    public_route_table_name    = string
    private_route_table_name   = string
    nat_gateway_name           = string
    public_route_cidr_block    = string
    private_route_cidr_block   = string
    map_public_ip_on_launch    = bool
  })
}

variable "common_tags" {
  description = "Tags applied to network resources."
  type        = map(string)
  default     = {}
}
