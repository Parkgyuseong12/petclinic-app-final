# =============================================================================
# VPC Module 호출
# =============================================================================

module "vpc" {
  source = "./modules/vpc"

  # Basic Network Config
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  app_private_subnet_cidrs = var.app_private_subnet_cidrs
  db_private_subnet_cidrs  = var.db_private_subnet_cidrs
  eks_cluster_name         = var.eks_cluster_name
  name_prefix              = local.name_prefix

  # ---------------------------------------------------------------------------
  # Azure VPN & DNS Configuration
  # ---------------------------------------------------------------------------
  azure_bgp_asn   = var.azure_bgp_asn
  azure_public_ip = var.azure_public_ip
  azure_cidr      = var.azure_cidr
  azure_dns_ip    = var.azure_dns_ip

  # Tags
  vpc_tags                = local.vpc_tags
  igw_tags                = local.igw_tags
  public_subnet_tags      = local.public_subnet_tags
  app_private_subnet_tags = local.app_private_subnet_tags
  db_private_subnet_tags  = local.db_private_subnet_tags
  nat_gateway_tags        = local.nat_gateway_tags
  public_rt_tags          = local.public_rt_tags
  app_private_rt_tags     = local.app_private_rt_tags
  db_private_rt_tags      = local.db_private_rt_tags
}