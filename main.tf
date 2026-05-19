module "ec2" {
  source = "./modules/ec2"

  vpc_id           = module.network.vpc_id
  public_subnet_id = module.network.public_subnet_id
  instance_type    = var.instance_type
  key_name         = var.key_name
  config           = var.ec2_config
  common_tags      = var.common_tags
}

output "public_ip" {
  value = module.ec2.public_ip
}
