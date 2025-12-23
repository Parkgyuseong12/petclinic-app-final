# =============================================================================
# Local Values
# 공통 태그, 이름 접두사 등 재사용 가능한 값 정의
# =============================================================================

locals {
  # 공통 태그 (모든 리소스에 적용)
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }

  # 이름 접두사
  name_prefix = "${var.project_name}-${var.environment}"

  # 리소스별 태그
  vpc_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-vpc"
  })

  igw_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-igw"
  })

  # Subnet 공통 태그
  subnet_common_tags = merge(local.common_tags, {
    "kubernetes.io/cluster/${var.eks_cluster_name}" = "shared"
  })

  public_subnet_tags = merge(local.subnet_common_tags, {
    "kubernetes.io/role/elb" = "1"
    Tier                     = "Public"
  })

  app_private_subnet_tags = merge(local.subnet_common_tags, {
    "kubernetes.io/role/internal-elb" = "1"
    "karpenter.sh/discovery"          = var.eks_cluster_name
    Tier                              = "Private-App"
    Purpose                           = "Application"
  })

  db_private_subnet_tags = merge(local.common_tags, {
    Tier    = "Private-DB"
    Purpose = "Database"
  })

  # NAT Gateway 태그
  nat_gateway_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-nat-gw"
  })

  # Route Table 태그
  public_rt_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-public-rt"
  })

  app_private_rt_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-app-rt"
    Tier = "Private-App"
  })

  db_private_rt_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-private-db-rt"
    Tier = "Private-DB"
  })

  # Security Group 태그
  sg_tags = {
    for name in ["bastion", "mgmt", "rds", "eks_cluster"] : name => merge(local.common_tags, {
      Name = "${local.name_prefix}-sg-${name}"
    })
  }

  # EC2 인스턴스 태그
  bastion_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-bastion"
    Role = "Bastion"
  })

  mgmt_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-mgmt-server"
    Role = "Management"
  })

  # RDS 태그
  rds_tags = merge(local.common_tags, {
    Name = "${local.name_prefix}-db-prod"
  })

  # IAM 태그
  iam_tags = {
    for name in ["mgmt_server_role", "mgmt_server_profile"] : name => merge(local.common_tags, {
      Name = "${local.name_prefix}-${name}"
    })
  }

  # S3 Backend 태그
  s3_backend_tags = merge(local.common_tags, {
    Name    = "${var.project_name}-terraform-state"
    Purpose = "Terraform State Storage"
  })
}

