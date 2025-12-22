
terraform {
  # 테라폼 자체의 최소 버전을 명시 (호환성 문제 방지)
  required_version = ">=1.0"

  required_providers {
    # Azure Resource Manager (azurerm) 프로바이더 설정
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # 4.x 버전대를 사용 (최신 기능 사용)
    }
    # 랜덤 문자열 생성 등을 위한 random 프로바이더 (선택 사항)
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

# Azure 프로바이더 초기화
provider "azurerm" {
  # features 블록은 현재 비어있더라도 필수입니다.
  # 리소스 삭제 시 복구 가능 여부 등 프로바이더 수준의 동작을 제어합니다.
  features {}
  subscription_id = var.subscription_id
}