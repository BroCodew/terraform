module "network" {
  source = "./modules/network"

  config      = var.network_config
  common_tags = var.common_tags
}
