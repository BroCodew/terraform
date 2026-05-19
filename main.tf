provider "aws" {
  region = var.aws_region
}

module "ec2" {
  source = "./modules/ec2"

  vpc_id           = module.network.vpc_id
  public_subnet_id = module.network.public_subnet_id
  instance_type    = var.instance_type
  key_name         = var.key_name
}

output "public_ip" {
  value = module.ec2.public_ip
}
