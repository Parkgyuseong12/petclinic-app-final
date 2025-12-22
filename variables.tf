# =============================================================================
# 변수 정의
# PetClinic 프로덕션 환경을 위한 Terraform 변수
# =============================================================================

# -----------------------------------------------------------------------------
# General Settings
# -----------------------------------------------------------------------------
variable "project_name" {
  description = "petclinic-basic-infra"
  type        = string
  default     = "petclinic"
}

variable "environment" {
  description = "환경 (prod, staging, dev)"
  type        = string
  default     = "prod"

  validation {
    condition     = contains(["prod", "staging", "dev"], var.environment)
    error_message = "Environment must be one of: prod, staging, dev."
  }
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-2"
}

# -----------------------------------------------------------------------------
# Network Settings
# -----------------------------------------------------------------------------
variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "사용할 가용 영역 목록"
  type        = list(string)
  default     = ["ap-northeast-2a", "ap-northeast-2b"]

  validation {
    condition     = length(var.availability_zones) >= 2 && length(var.availability_zones) <= 3
    error_message = "Availability zones must be between 2 and 3 for high availability."
  }
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDR 블록 목록"
  type        = list(string)
  default     = ["10.0.0.0/25", "10.0.10.0/25"]
}

variable "app_private_subnet_cidrs" {
  description = "App Private Subnet CIDR 블록 목록 (각 AZ별 1개)"
  type        = list(string)
  default     = ["10.0.0.128/25", "10.0.10.128/25"]
}

variable "db_private_subnet_cidrs" {
  description = "DB Private Subnet CIDR 블록 목록 (각 AZ별 1개)"
  type        = list(string)
  default     = ["10.0.1.0/25", "10.0.11.0/25"]
}

variable "azure_bgp_asn" {
  description = "Azure VPN Gateway의 BGP ASN (정적 라우팅 기본값: 65000, 동적: 65515)"
  type        = string
  default     = "65000"
}

variable "azure_public_ip" {
  description = "Azure VPN Gateway의 Public IP"
  type        = string
  default     = "4.218.15.218"
}

variable "azure_cidr" {
  description = "Azure VNet의 CIDR (라우팅 대상)"
  type        = string
  default     = "192.168.0.0/16"
}

variable "azure_dns_ip" {
  description = "Azure Private DNS Resolver IP (Inbound)"
  type        = string
  default     = "192.168.200.4"
}

# -----------------------------------------------------------------------------
# EKS Cluster Name (for tagging)
# -----------------------------------------------------------------------------
variable "eks_cluster_name" {
  description = "EKS 클러스터 이름 (추후 eksctl로 생성 예정)"
  type        = string
  default     = "petclinic-cluster"
}

# -----------------------------------------------------------------------------
# EC2 Settings
# -----------------------------------------------------------------------------
variable "bastion_instance_type" {
  description = "Bastion Host 인스턴스 타입"
  type        = string
  default     = "t3.micro"
}

variable "mgmt_instance_type" {
  description = "Management Server 인스턴스 타입"
  type        = string
  default     = "t3.medium"
}

variable "ec2_ami_id" {
  description = "EC2 AMI ID (Ubuntu 22.04 LTS). null이면 최신 AMI 자동 조회"
  type        = string
  default     = null
}

variable "key_name" {
  description = "EC2 Key Pair 이름"
  type        = string
  default     = "petclinic-keypair"
}

variable "allowed_ssh_cidr" {
  description = "SSH 접근을 허용할 CIDR 블록 (보안을 위해 특정 IP로 제한 권장)"
  type        = string
  default     = "0.0.0.0/0" # 프로덕션에서는 반드시 특정 IP로 변경하세요!
}

# -----------------------------------------------------------------------------
# RDS Settings
# -----------------------------------------------------------------------------
variable "db_instance_class" {
  description = "RDS 인스턴스 클래스"
  type        = string
  default     = "db.t3.small"
}

variable "db_engine_version" {
  description = "MySQL 엔진 버전"
  type        = string
  default     = "8.0"
}

variable "db_allocated_storage" {
  description = "RDS 할당 스토리지 (GB)"
  type        = number
  default     = 20
}

variable "db_name" {
  description = "초기 데이터베이스 이름"
  type        = string
  default     = "petclinic"
}

variable "db_username" {
  description = "RDS 마스터 사용자 이름"
  type        = string
  default     = "admin"
  sensitive   = true
}

variable "db_password" {
  description = "RDS 마스터 비밀번호"
  type        = string
  default     = "petclinic1234" # 프로덕션에서는 terraform.tfvars로 관리하세요!
  sensitive   = true
}

variable "db_multi_az" {
  description = "RDS Multi-AZ 활성화 여부"
  type        = bool
  default     = false # 추후 true로 변경 예정
}

variable "db_backup_retention_period" {
  description = "자동 백업 보관 기간 (일)"
  type        = number
  default     = 7

  validation {
    condition     = var.db_backup_retention_period >= 0 && var.db_backup_retention_period <= 35
    error_message = "Backup retention period must be between 0 and 35 days."
  }
}

# -----------------------------------------------------------------------------
# S3 Backend Settings (Terraform State)
# -----------------------------------------------------------------------------
variable "tfstate_bucket_name" {
  description = "Terraform state 파일을 저장할 S3 버킷 이름 (전역적으로 고유해야 함)"
  type        = string
  default     = "" # 예: "petclinic-terraform-state-prod-ap-northeast-2"
}

variable "tfstate_key_prefix" {
  description = "Terraform state 파일의 S3 키 접두사"
  type        = string
  default     = "terraform.tfstate"
}

variable "enable_s3_object_lock" {
  description = "S3 Object Lock 활성화 여부 (버킷 생성 시에만 설정 가능)"
  type        = bool
  default     = true
}

variable "s3_object_lock_mode" {
  description = "S3 Object Lock 모드 (GOVERNANCE 또는 COMPLIANCE)"
  type        = string
  default     = "GOVERNANCE" # COMPLIANCE는 삭제 불가, GOVERNANCE는 권한 있는 사용자가 삭제 가능

  validation {
    condition     = contains(["GOVERNANCE", "COMPLIANCE"], var.s3_object_lock_mode)
    error_message = "S3 Object Lock mode must be either GOVERNANCE or COMPLIANCE."
  }
}

variable "s3_object_lock_days" {
  description = "S3 Object Lock 최소 보관 기간 (일)"
  type        = number
  default     = 7
}

