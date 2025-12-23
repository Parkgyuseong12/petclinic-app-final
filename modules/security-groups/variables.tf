# =============================================================================
# Security Groups Module Variables
# =============================================================================

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
}

variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "SSH 접근을 허용할 CIDR 블록"
  type        = string
}

variable "app_private_subnet_cidrs" {
  description = "App Private Subnet CIDR 블록 목록"
  type        = list(string)
}

# Tag Variables
variable "bastion_sg_tags" {
  description = "Bastion Security Group 태그"
  type        = map(string)
  default     = {}
}

variable "mgmt_sg_tags" {
  description = "Management Security Group 태그"
  type        = map(string)
  default     = {}
}

variable "rds_sg_tags" {
  description = "RDS Security Group 태그"
  type        = map(string)
  default     = {}
}

variable "eks_cluster_sg_tags" {
  description = "EKS Cluster Security Group 태그"
  type        = map(string)
  default     = {}
}

variable "azure_cidr" {
  description = "Azure VNet의 CIDR 블록 (라우팅 대상)"
  type        = string
  default = "192.168.0.0/16"
}
