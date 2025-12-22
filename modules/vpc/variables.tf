# =============================================================================
# VPC Module Variables
# =============================================================================

variable "vpc_cidr" {
  description = "VPC CIDR Block"
  type        = string
}

variable "availability_zones" {
  description = "사용할 가용 영역 목록"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public Subnet CIDR 블록 목록"
  type        = list(string)
}

variable "app_private_subnet_cidrs" {
  description = "App Private Subnet CIDR 블록 목록"
  type        = list(string)
}

variable "db_private_subnet_cidrs" {
  description = "DB Private Subnet CIDR 블록 목록"
  type        = list(string)
}

variable "eks_cluster_name" {
  description = "EKS 클러스터 이름 (태깅용)"
  type        = string
}

variable "name_prefix" {
  description = "리소스 이름 접두사"
  type        = string
}

# Tag Variables
variable "vpc_tags" {
  description = "VPC 태그"
  type        = map(string)
  default     = {}
}

variable "igw_tags" {
  description = "Internet Gateway 태그"
  type        = map(string)
  default     = {}
}

variable "public_subnet_tags" {
  description = "Public Subnet 공통 태그"
  type        = map(string)
  default     = {}
}

variable "app_private_subnet_tags" {
  description = "App Private Subnet 공통 태그"
  type        = map(string)
  default     = {}
}

variable "db_private_subnet_tags" {
  description = "DB Private Subnet 공통 태그"
  type        = map(string)
  default     = {}
}

variable "nat_gateway_tags" {
  description = "NAT Gateway 태그"
  type        = map(string)
  default     = {}
}

variable "public_rt_tags" {
  description = "Public Route Table 태그"
  type        = map(string)
  default     = {}
}

variable "app_private_rt_tags" {
  description = "App Private Route Table 태그"
  type        = map(string)
  default     = {}
}

variable "db_private_rt_tags" {
  description = "DB Private Route Table 태그"
  type        = map(string)
  default     = {}
}

# =============================================================================
# [New] Azure VPN & DNS Integration Variables
# =============================================================================

variable "azure_bgp_asn" {
  description = "Azure VPN Gateway의 BGP ASN (일반적으로 65515)"
  type        = string
}

variable "azure_public_ip" {
  description = "Azure VPN Gateway의 Public IP 주소"
  type        = string
}

variable "azure_cidr" {
  description = "Azure VNet의 CIDR 블록 (라우팅 대상)"
  type        = string
}

variable "azure_dns_ip" {
  description = "Azure Private DNS Resolver의 Inbound IP 주소"
  type        = string
}