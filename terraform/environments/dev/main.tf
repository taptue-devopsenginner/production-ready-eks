locals {
  name = "${var.project_name}-dev"
  tags = {
    Project     = var.project_name
    Environment = "dev"
  }
}

module "vpc" {
  source               = "../../modules/vpc"
  name                 = local.name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  single_nat_gateway   = var.single_nat_gateway
  tags                 = local.tags
}

module "eks" {
  source                       = "../../modules/eks"
  cluster_name                 = local.name
  kubernetes_version           = var.kubernetes_version
  private_subnet_ids           = module.vpc.private_subnet_ids
  public_subnet_ids            = module.vpc.public_subnet_ids
  node_instance_types          = var.node_instance_types
  node_desired_size            = var.node_desired_size
  node_min_size                = var.node_min_size
  node_max_size                = var.node_max_size
  endpoint_public_access       = var.endpoint_public_access
  endpoint_public_access_cidrs = var.endpoint_public_access_cidrs
  tags                         = local.tags
}
