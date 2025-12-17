# =============================================================================
# Security Groups Module
# 용도별 보안 그룹 정의
# 규칙은 별도 리소스로 관리하여 콘솔에서 수정해도 삭제되지 않도록 함
# =============================================================================

# -----------------------------------------------------------------------------
# Bastion Host Security Group
# SSH(22) 포트만 허용 - 특정 IP에서만 접근 가능
# -----------------------------------------------------------------------------
resource "aws_security_group" "bastion" {
  name        = "${var.name_prefix}-sg-bastion"
  description = "Security group for Bastion Host - SSH access from allowed IPs"
  vpc_id      = var.vpc_id

  tags = var.bastion_sg_tags
}

# Bastion Host - SSH Ingress Rule
resource "aws_security_group_rule" "bastion_ssh_ingress" {
  type              = "ingress"
  description       = "SSH from allowed CIDR"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.allowed_ssh_cidr]
  security_group_id = aws_security_group.bastion.id
}

# Bastion Host - All Outbound Rule
resource "aws_security_group_rule" "bastion_all_egress" {
  type              = "egress"
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.bastion.id
}

# -----------------------------------------------------------------------------
# Management Server Security Group
# SSH(22) - Bastion Host로부터만 접근 가능
# -----------------------------------------------------------------------------
resource "aws_security_group" "mgmt" {
  name        = "${var.name_prefix}-sg-mgmt"
  description = "Security group for Management Server - SSH from Bastion only"
  vpc_id      = var.vpc_id

  tags = var.mgmt_sg_tags
}

# Management Server - SSH Ingress Rule (from Bastion)
resource "aws_security_group_rule" "mgmt_ssh_ingress" {
  type                     = "ingress"
  description              = "SSH from Bastion Host"
  from_port                = 22
  to_port                  = 22
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.bastion.id
  security_group_id        = aws_security_group.mgmt.id
}

# Management Server - All Outbound Rule
resource "aws_security_group_rule" "mgmt_all_egress" {
  type              = "egress"
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.mgmt.id
}

# -----------------------------------------------------------------------------
# RDS Security Group
# MySQL(3306) - Management Server SG 및 Private Subnet CIDR에서 접근 가능
# (추후 EKS 파드에서 접근할 수 있도록 Private Subnet CIDR 허용)
# -----------------------------------------------------------------------------
resource "aws_security_group" "rds" {
  name        = "${var.name_prefix}-sg-rds"
  description = "Security group for RDS - MySQL access from Mgmt and Private subnets"
  vpc_id      = var.vpc_id

  tags = var.rds_sg_tags
}

# RDS - MySQL Ingress Rule (from Management Server)
resource "aws_security_group_rule" "rds_mysql_ingress_from_mgmt" {
  type                     = "ingress"
  description              = "MySQL from Management Server"
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.mgmt.id
  security_group_id        = aws_security_group.rds.id
}

# RDS - MySQL Ingress Rules (from App Private Subnets - EKS 파드용)
resource "aws_security_group_rule" "rds_mysql_ingress_from_app_subnets" {
  for_each          = toset(var.app_private_subnet_cidrs)
  type              = "ingress"
  description       = "MySQL from App Private Subnet ${index(var.app_private_subnet_cidrs, each.value) + 1}"
  from_port         = 3306
  to_port           = 3306
  protocol          = "tcp"
  cidr_blocks       = [each.value]
  security_group_id = aws_security_group.rds.id
}

# RDS - All Outbound Rule
resource "aws_security_group_rule" "rds_all_egress" {
  type              = "egress"
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.rds.id
}

# -----------------------------------------------------------------------------
# EKS Cluster Security Group (참조용 - 추후 eksctl에서 사용)
# 클러스터와 노드 간 통신을 위한 기본 규칙
# -----------------------------------------------------------------------------
resource "aws_security_group" "eks_cluster" {
  name        = "${var.name_prefix}-sg-eks-cluster"
  description = "Security group for EKS Cluster (created for future use)"
  vpc_id      = var.vpc_id

  tags = var.eks_cluster_sg_tags
}

# EKS Cluster - Internal Communication Ingress Rule
resource "aws_security_group_rule" "eks_cluster_internal_ingress" {
  type              = "ingress"
  description       = "Allow internal cluster communication"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  self              = true
  security_group_id = aws_security_group.eks_cluster.id
}

# EKS Cluster - HTTPS Ingress Rule (from VPC)
resource "aws_security_group_rule" "eks_cluster_https_ingress" {
  type              = "ingress"
  description       = "HTTPS from VPC"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [var.vpc_cidr]
  security_group_id = aws_security_group.eks_cluster.id
}

# EKS Cluster - All Outbound Rule
resource "aws_security_group_rule" "eks_cluster_all_egress" {
  type              = "egress"
  description       = "Allow all outbound traffic"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks_cluster.id
}

