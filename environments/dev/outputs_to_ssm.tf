# =============================================================================
# SSM Parameters & Secrets Manager Outputs
# =============================================================================

# -----------------------------------------------------------------------------
# Secrets Manager: DB Credentials (shared across services)
# -----------------------------------------------------------------------------
resource "aws_secretsmanager_secret" "petclinic_db_credentials" {
  name = "/petclinic/db_credentials"
}

resource "aws_secretsmanager_secret_version" "petclinic_db_credentials" {
  secret_id = aws_secretsmanager_secret.petclinic_db_credentials.id
  secret_string = jsonencode({
    CUSTOMERS_DATASOURCE_USERNAME = var.db_username_customers
    CUSTOMERS_DATASOURCE_PASSWORD = var.db_password_customers
    VETS_DATASOURCE_USERNAME      = var.db_username_vets
    VETS_DATASOURCE_PASSWORD      = var.db_password_vets
    VISITS_DATASOURCE_USERNAME    = var.db_username_visits
    VISITS_DATASOURCE_PASSWORD    = var.db_password_visits
  })
}

# -----------------------------------------------------------------------------
# SSM Parameters (Standard Tier)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "petclinic_db_host" {
  name  = "/petclinic/db_host"
  type  = "String"
  tier  = "Standard"
  value = aws_db_instance.main.endpoint
}

resource "aws_ssm_parameter" "petclinic_vpc_id" {
  name  = "/petclinic/vpc_id"
  type  = "String"
  tier  = "Standard"
  value = module.vpc.vpc_id
}

resource "aws_ssm_parameter" "petclinic_private_subnets_app" {
  name  = "/petclinic/subnets/private/app"
  type  = "StringList"
  tier  = "Standard"
  value = join(",", module.vpc.app_private_subnet_ids)
}

resource "aws_ssm_parameter" "petclinic_private_subnets_db" {
  name  = "/petclinic/subnets/private/db"
  type  = "StringList"
  tier  = "Standard"
  value = join(",", module.vpc.db_private_subnet_ids)
}

resource "aws_ssm_parameter" "petclinic_public_subnets" {
  name  = "/petclinic/subnets/public"
  type  = "StringList"
  tier  = "Standard"
  value = join(",", module.vpc.public_subnet_ids)
}

resource "aws_ssm_parameter" "petclinic_karpenter_ami_id" {
  name  = "/petclinic/karpenter/ami_id"
  type  = "String"
  tier  = "Standard"
  value = data.aws_ami.eks_al2023.id
}

resource "aws_ssm_parameter" "petclinic_aws_account_id" {
  name  = "/petclinic/aws_account_id"
  type  = "String"
  tier  = "Standard"
  value = data.aws_caller_identity.current.account_id
}

