# =============================================================================
# Main Terraform Configuration
# Dev 환경 리소스 정의 - 모듈 호출 방식
# =============================================================================

# -----------------------------------------------------------------------------
# VPC Module 호출
# -----------------------------------------------------------------------------
module "vpc" {
  source = "../../modules/vpc"

  # Basic Network Config
  vpc_cidr                 = var.vpc_cidr
  availability_zones       = var.availability_zones
  public_subnet_cidrs      = var.public_subnet_cidrs
  app_private_subnet_cidrs = var.app_private_subnet_cidrs
  db_private_subnet_cidrs  = var.db_private_subnet_cidrs
  eks_cluster_name         = var.eks_cluster_name
  name_prefix              = local.name_prefix

  # Azure VPN & DNS Configuration
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

# -----------------------------------------------------------------------------
# Security Groups Module 호출
# -----------------------------------------------------------------------------
module "security_groups" {
  source = "../../modules/security-groups"

  vpc_id                   = module.vpc.vpc_id
  vpc_cidr                 = module.vpc.vpc_cidr
  name_prefix              = local.name_prefix
  allowed_ssh_cidr         = var.allowed_ssh_cidr
  app_private_subnet_cidrs = var.app_private_subnet_cidrs

  # Tags
  bastion_sg_tags     = local.sg_tags["bastion"]
  mgmt_sg_tags        = local.sg_tags["mgmt"]
  rds_sg_tags         = local.sg_tags["rds"]
  eks_cluster_sg_tags = local.sg_tags["eks_cluster"]
}

# -----------------------------------------------------------------------------
# IAM Roles and Policies
# Management Server를 위한 IAM 설정
# -----------------------------------------------------------------------------
resource "aws_iam_role" "mgmt_server" {
  name = "${var.project_name}-mgmt-server-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = local.iam_tags["mgmt_server_role"]
}

# -----------------------------------------------------------------------------
# AdministratorAccess Policy 연결
# EKS 클러스터 생성 및 관리를 위해 필요
# 프로덕션에서는 최소 권한 원칙에 따라 세분화된 정책 사용 권장
# -----------------------------------------------------------------------------
resource "aws_iam_role_policy_attachment" "mgmt_admin" {
  role       = aws_iam_role.mgmt_server.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# -----------------------------------------------------------------------------
# IAM Instance Profile
# EC2 인스턴스에 IAM Role 연결을 위한 프로파일
# -----------------------------------------------------------------------------
resource "aws_iam_instance_profile" "mgmt_server" {
  name = "${var.project_name}-mgmt-server-profile"
  role = aws_iam_role.mgmt_server.name

  tags = local.iam_tags["mgmt_server_profile"]
}

# -----------------------------------------------------------------------------
# EC2 Module 호출
# -----------------------------------------------------------------------------
module "ec2" {
  source = "../../modules/ec2"

  name_prefix                    = local.name_prefix
  common_tags                    = local.common_tags
  key_name                       = var.key_name
  key_output_path                = "${path.module}/mykey"
  ec2_ami_id                     = var.ec2_ami_id
  ubuntu_ami_id                  = data.aws_ami.ubuntu.id
  bastion_instance_type          = var.bastion_instance_type
  mgmt_instance_type             = var.mgmt_instance_type
  bastion_volume_size            = 20
  mgmt_volume_size               = 50
  public_subnet_ids              = module.vpc.public_subnet_ids
  app_private_subnet_ids         = module.vpc.app_private_subnet_ids
  bastion_sg_id                  = module.security_groups.bastion_sg_id
  mgmt_sg_id                     = module.security_groups.mgmt_sg_id
  mgmt_iam_instance_profile_name  = aws_iam_instance_profile.mgmt_server.name
  bastion_tags                   = local.bastion_tags
  mgmt_tags                      = local.mgmt_tags

  # User Data
  bastion_user_data = <<-EOF
    #!/bin/bash
    set -e
    
    # 시스템 업데이트
    apt-get update -y
    apt-get upgrade -y
    
    # 기본 도구 설치
    apt-get install -y vim htop curl wget unzip
    
    echo "Bastion host initialization completed!" >> /var/log/user-data.log
  EOF

  mgmt_user_data = templatefile("${path.module}/user_data_mgmt.sh", {
    aws_region       = var.aws_region
    eks_cluster_name = var.eks_cluster_name
    db_endpoint      = "" # RDS 생성 후 업데이트됨
    db_username      = var.db_username
    db_password      = var.db_password
  })

  nat_gateway_dependency = module.vpc.nat_gateway_ids
}

