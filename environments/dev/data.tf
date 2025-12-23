# =============================================================================
# Data Sources
# AWS 리소스 조회 및 공통 데이터 소스 정의
# =============================================================================

# -----------------------------------------------------------------------------
# AWS Account & Region Information
# -----------------------------------------------------------------------------
data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Availability Zones
# -----------------------------------------------------------------------------
data "aws_availability_zones" "available" {
  state = "available"
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required", "opted-in"]
  }
}

# -----------------------------------------------------------------------------
# Latest Ubuntu 22.04 LTS AMI
# -----------------------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# -----------------------------------------------------------------------------
# EKS Optimized Amazon Linux 2023 AMI (x86_64)
# -----------------------------------------------------------------------------
data "aws_ami" "eks_al2023" {
  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account

  filter {
    name   = "name"
    values = ["amazon-eks-node-al2023-x86_64-standard-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

