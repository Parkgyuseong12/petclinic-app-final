# =============================================================================
# Terraform Backend Configuration
# S3 Native Lock 사용 (DynamoDB 없이)
# =============================================================================

terraform {
  backend "s3" {
    bucket       = "petclinic-terraform-state-prod-ap-northeast-2"
    key          = "dev/terraform.tfstate"
    region       = "ap-northeast-2"
    use_lockfile = true  # DynamoDB 없이 S3 Native Lock 활성화
  }
}

