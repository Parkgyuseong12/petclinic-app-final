variable "resource_group_name" {
  description = "리소스 그룹의 이름"
  type        = string
}

variable "location" {
  description = "Azure 리전"
  type        = string
}

variable "vm_name" {
  description = "가상 머신 이름"
  type        = string
}

variable "admin_username" {
  description = "VM 관리자 계정 이름"
  type        = string
}

variable "ssh_public_key_path" {
  description = "SSH 공개키 파일 경로 (Terraform 실행 위치 기준 상대 경로 또는 절대 경로)"
  type        = string
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

# DB 관련 변수 추가
variable "db_admin_username" {
  description = "MySQL 관리자 계정 이름"
  type        = string
}

variable "db_admin_password" {
  description = "MySQL 관리자 계정 비밀번호"
  type        = string
}

# --- [추가] AWS VPN 연결 정보 ---
variable "aws_vpc_cidr" {
  description = "AWS VPC의 내부 CIDR (예: 10.0.0.0/16)"
  type        = string
}

variable "aws_vpn_public_ip" {
  description = "AWS VPN 터널의 외부(Public) IP (Tunnel 1 Outside IP)"
  type        = string
}

variable "vpn_shared_key" {
  description = "IPSec Pre-Shared Key (AWS에서 다운로드 받은 구성 파일의 공유 키)"
  type        = string
  sensitive   = true
}