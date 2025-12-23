# =============================================================================
# RDS MySQL Database
# PetClinic MSA를 위한 데이터베이스
# =============================================================================

# -----------------------------------------------------------------------------
# DB Subnet Group
# DB Private Subnet 2개를 사용하여 Multi-AZ 지원
# -----------------------------------------------------------------------------
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  description = "Database subnet group for ${var.project_name}"
  subnet_ids  = module.vpc.db_private_subnet_ids

  tags = {
    Name = "${var.project_name}-db-subnet-group"
  }
}

# -----------------------------------------------------------------------------
# DB Parameter Group
# MySQL 8.0 최적화 파라미터
# -----------------------------------------------------------------------------
resource "aws_db_parameter_group" "main" {
  family = "mysql8.0"
  name   = "${var.project_name}-db-params"

  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }

  parameter {
    name  = "character_set_client"
    value = "utf8mb4"
  }

  parameter {
    name  = "collation_server"
    value = "utf8mb4_unicode_ci"
  }

  parameter {
    name         = "max_connections"
    value        = "200"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "slow_query_log"
    value = "1"
  }

  parameter {
    name  = "long_query_time"
    value = "2"
  }

  # 1. Binlog 형식을 ROW로 설정
  parameter {
    name         = "binlog_format"
    value        = "ROW"
    apply_method = "pending-reboot" # 재부팅 적용
  }

  # 2. GTID 모드 활성화 (추가됨)
  parameter {
    name         = "gtid-mode"
    value        = "ON"
    apply_method = "pending-reboot" # 재부팅 적용
  }

  # 3. GTID 일관성 강제 (필수 추가!)
  # gtid_mode = ON을 위해서는 이 값이 반드시 ON이어야 합니다.
  parameter {
    name         = "enforce_gtid_consistency"
    value        = "ON"
    apply_method = "pending-reboot" # 재부팅 적용
  }

  tags = {
    Name = "${var.project_name}-db-params"
  }
}

# -----------------------------------------------------------------------------
# RDS MySQL Instance
# -----------------------------------------------------------------------------
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-db-${var.environment}"

  # 엔진 설정
  engine                = "mysql"
  engine_version        = var.db_engine_version
  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage
  max_allocated_storage = var.db_allocated_storage * 2 # 자동 스케일링

  # 데이터베이스 설정
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # 네트워크 설정
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [module.security_groups.rds_sg_id]
  publicly_accessible    = false
  port                   = 3306

  # 고가용성 설정
  multi_az = var.db_multi_az # 현재 false, 추후 true로 변경

  # 스토리지 설정
  storage_type      = "gp3"
  storage_encrypted = true

  # 백업 설정
  backup_retention_period = var.db_backup_retention_period
  backup_window           = "03:00-04:00"         # UTC (한국시간 12:00-13:00)
  maintenance_window      = "Mon:04:00-Mon:05:00" # UTC

  # 파라미터 그룹
  parameter_group_name = aws_db_parameter_group.main.name

  # 삭제 방지 (프로덕션에서는 true 권장)
  deletion_protection = false # 테스트를 위해 false
  skip_final_snapshot = true  # 프로덕션에서는 false 권장

  # 자동 마이너 버전 업그레이드
  auto_minor_version_upgrade = true

  tags = local.rds_tags
}

# -----------------------------------------------------------------------------
# null_resource: SQL 초기화 파일을 Management Server로 복사
# file provisioner를 사용하여 init.sql 파일 전송
# -----------------------------------------------------------------------------
resource "null_resource" "copy_sql_to_mgmt" {
  # Management Server와 RDS가 모두 생성된 후 실행
  depends_on = [
    module.ec2.mgmt_server_instance_id,
    aws_db_instance.main
  ]

  # RDS 엔드포인트 변경 시 재실행
  triggers = {
    rds_endpoint = aws_db_instance.main.endpoint
  }

  # Bastion을 통한 SSH 터널링으로 파일 복사
  # 실제로는 scp를 통해 수동으로 복사하거나, S3를 통해 전송하는 것이 더 안정적
  provisioner "local-exec" {
    command = <<-EOT
      echo "============================================"
      echo "SQL 파일 복사 가이드"
      echo "============================================"
      echo ""
      echo "1. 먼저 SSH 키 파일을 Bastion으로 복사:"
      echo "   scp -i ${var.key_name}.pem ${var.key_name}.pem ubuntu@${module.ec2.bastion_public_ip}:/home/ubuntu/"
      echo ""
      echo "2. Bastion에 SSH 접속:"
      echo "   ssh -i ${var.key_name}.pem ubuntu@${module.ec2.bastion_public_ip}"
      echo ""
      echo "3. Bastion에서 Management Server로 SSH 접속:"
      echo "   ssh -i ${var.key_name}.pem ubuntu@${module.ec2.mgmt_server_private_ip}"
      echo ""
      echo "4. Management Server에서 init.sql 파일이 있는지 확인:"
      echo "   ls -la /home/ubuntu/init.sql"
      echo ""
      echo "5. MySQL 클라이언트로 DB 초기화:"
      echo "   mysql -h ${aws_db_instance.main.endpoint} -u ${var.db_username} -p < /home/ubuntu/init.sql"
      echo ""
      echo "RDS Endpoint: ${aws_db_instance.main.endpoint}"
      echo "============================================"
    EOT
  }
}

# -----------------------------------------------------------------------------
# 추가: RDS 엔드포인트 정보를 Management Server에 환경 변수로 저장
# (AWS Systems Manager Parameter Store 사용)
# -----------------------------------------------------------------------------
resource "aws_ssm_parameter" "rds_endpoint" {
  name        = "/${var.project_name}/${var.environment}/rds/endpoint"
  description = "RDS MySQL endpoint for ${var.project_name}"
  type        = "String"
  value       = aws_db_instance.main.endpoint

  tags = {
    Name = "${var.project_name}-rds-endpoint"
  }
}

resource "aws_ssm_parameter" "rds_username" {
  name        = "/${var.project_name}/${var.environment}/rds/username"
  description = "RDS MySQL username for ${var.project_name}"
  type        = "SecureString"
  value       = var.db_username

  tags = {
    Name = "${var.project_name}-rds-username"
  }
}

resource "aws_ssm_parameter" "rds_password" {
  name        = "/${var.project_name}/${var.environment}/rds/password"
  description = "RDS MySQL password for ${var.project_name}"
  type        = "SecureString"
  value       = var.db_password

  tags = {
    Name = "${var.project_name}-rds-password"
  }
}

