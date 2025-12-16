# PetClinic 프로덕션 인프라 (Terraform)

Spring PetClinic MSA 애플리케이션을 위한 AWS 프로덕션 인프라 구축 코드입니다.

## 📋 목차

- [요구사항](#요구사항)
- [아키텍처](#아키텍처)
- [설치 및 사용](#설치-및-사용)
- [S3 Backend 설정](#s3-backend-설정)
- [주요 구성 요소](#주요-구성-요소)
- [구현 의도 및 주의사항](#구현-의도-및-주의사항)

## 🔧 요구사항

- **Terraform**: >= 1.10.0 (S3 Object Lock 지원)
- **AWS CLI**: 최신 버전
- **AWS 계정**: 적절한 권한 (IAM, VPC, EC2, RDS, S3 등)

## 🏗️ 아키텍처

```
┌─────────────────────────────────────────────────────────────┐
│                        Internet                              │
└───────────────────────┬─────────────────────────────────────┘
                        │
            ┌───────────▼───────────┐
            │   Internet Gateway   │
            └───────────┬───────────┘
                        │
        ┌───────────────┴───────────────┐
        │      VPC (10.0.0.0/16)        │
        │                               │
        │  ┌─────────────────────────┐ │
        │  │  Public Subnet A         │ │
        │  │  (10.0.1.0/24)          │ │
        │  │  - Bastion Host         │ │
        │  │  - NAT Gateway A        │ │
        │  └─────────────────────────┘ │
        │                               │
        │  ┌─────────────────────────┐ │
        │  │  Private Subnet A       │ │
        │  │  (10.0.11.0/24)         │ │
        │  │  - Management Server    │ │
        │  │  - EKS Nodes (예정)     │ │
        │  └─────────────────────────┘ │
        │                               │
        │  ┌─────────────────────────┐ │
        │  │  Private Subnet C       │ │
        │  │  (10.0.12.0/24)         │ │
        │  │  - RDS MySQL           │ │
        │  │  - EKS Nodes (예정)     │ │
        │  └─────────────────────────┘ │
        └───────────────────────────────┘
```

### 주요 특징

- **고가용성**: 2개 AZ 사용, NAT Gateway HA 구성
- **보안**: Private Subnet 배치, Security Group 최소 권한
- **확장성**: EKS 클러스터 준비 (eksctl로 생성 예정)

## 🚀 설치 및 사용

### 1. 저장소 클론 및 초기화

```bash
cd petclinic-test-infra
terraform init
```

### 2. 변수 설정

`terraform.tfvars` 파일 생성 (선택적):

```hcl
project_name = "petclinic"
environment  = "prod"
aws_region   = "ap-northeast-2"

# S3 Backend 설정
tfstate_bucket_name = "petclinic-terraform-state-prod-ap-northeast-2"
tfstate_key_prefix  = "terraform.tfstate"
enable_s3_object_lock = true
s3_object_lock_mode   = "GOVERNANCE"
s3_object_lock_days   = 7

# 보안 설정
allowed_ssh_cidr = "YOUR_IP/32"  # 본인 IP로 변경

# RDS 설정
db_username = "petclinic_admin"
db_password = "SecurePassword123!"  # 강력한 비밀번호 사용
```

### 3. S3 Backend 설정

#### 방법 1: backend.tf 파일 생성

```bash
cp backend.tf.example backend.tf
# backend.tf 파일을 편집하여 버킷 이름 등 설정
```

#### 방법 2: terraform init 시 설정

```bash
terraform init \
  -backend-config="bucket=petclinic-terraform-state-prod-ap-northeast-2" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=ap-northeast-2" \
  -backend-config="encrypt=true" \
  -backend-config="use_lockfile=true"
```

### 4. 인프라 배포

```bash
# 계획 확인
terraform plan

# 배포 실행
terraform apply
```

### 5. 출력 정보 확인

```bash
terraform output
```

## 📦 S3 Backend 설정

### use_lockfile 옵션

Terraform 1.10.0 이상에서는 `use_lockfile = true` 옵션을 사용하여 S3의 파일 기반 락킹을 활성화할 수 있습니다. 이 옵션을 활성화하면:

- **DynamoDB 불필요**: DynamoDB 테이블 없이도 락킹 기능 사용 가능
- **파일 기반 락킹**: S3에 `.tflock` 파일을 생성하여 state 파일에 대한 동시 접근 제어
- **Object Lock과 함께 사용**: Object Lock이 활성화된 버킷과 함께 사용하면 더욱 안전한 락킹 제공

⚠️ **중요**: `use_lockfile = true` 옵션은 `backend.tf` 파일에 명시적으로 설정해야 합니다.

### S3 Object Lock이란?

S3 Object Lock은 객체를 보호하고 실수로 삭제되거나 덮어쓰는 것을 방지합니다. Terraform state 파일의 무결성을 보장합니다.

### 설정 옵션

| 옵션 | 설명 | 기본값 |
|------|------|--------|
| `enable_s3_object_lock` | Object Lock 활성화 | `true` |
| `s3_object_lock_mode` | Lock 모드 (`GOVERNANCE` 또는 `COMPLIANCE`) | `GOVERNANCE` |
| `s3_object_lock_days` | 최소 보관 기간 (일) | `7` |

### Lock 모드 비교

- **GOVERNANCE**: 권한이 있는 사용자가 `s3:BypassGovernanceRetention` 권한으로 삭제 가능
- **COMPLIANCE**: 보관 기간 동안 누구도 삭제 불가 (더 엄격)

### 주의사항

⚠️ **중요**: S3 Object Lock은 버킷 생성 시에만 활성화할 수 있습니다. 생성 후에는 비활성화할 수 없습니다.

### State 마이그레이션

기존 로컬 state를 S3로 마이그레이션:

```bash
# 1. backend.tf 파일 생성
cp backend.tf.example backend.tf

# 2. 마이그레이션 실행
terraform init -migrate-state
```

## 🏛️ 주요 구성 요소

### 네트워크

- **VPC**: `10.0.0.0/16`
- **Public Subnets**: 2개 (각 AZ별)
- **Private Subnets**: 2개 (각 AZ별)
- **NAT Gateway**: 2개 (HA, Zonal Isolation)

### 컴퓨팅

- **Bastion Host**: Public Subnet, SSH 접근
- **Management Server**: Private Subnet, eksctl/kubectl 실행용

### 데이터베이스

- **RDS MySQL 8.0**: Multi-AZ (현재 false, 추후 true)
- **데이터베이스**: `customers_db`, `vets_db`, `visits_db`

### 보안

- **Security Groups**: 최소 권한 원칙
- **IAM Roles**: Management Server용 AdminAccess
- **암호화**: RDS, S3, EBS 암호화 활성화

## 📖 구현 의도 및 주의사항

각 리소스를 왜 해당 방식으로 작성했는지, 운영 시 주의할 점, Terraform으로 관리하지 않은 항목의 이유는 [IMPLEMENTATION.md](./IMPLEMENTATION.md)에서 상세히 설명합니다. AWS Terraform 공식 문서의 권장 사항을 기준으로 작성했습니다.

## 📝 사용 예시

### SSH 접속

```bash
# Bastion 접속
ssh -i petclinic-keypair.pem ubuntu@<BASTION_IP>

# Management Server 접속 (ProxyJump)
ssh -i petclinic-keypair.pem -J ubuntu@<BASTION_IP> ubuntu@<MGMT_IP>
```

### DB 초기화

Management Server에서:

```bash
# RDS 연결 스크립트 사용
./db-connect.sh

# 또는 직접 연결
mysql -h <RDS_ENDPOINT> -u <USERNAME> -p < /home/ubuntu/init.sql
```

### EKS 클러스터 생성

Management Server에서:

```bash
./create-eks-cluster.sh
```

## 🔒 보안 권장사항

1. **SSH 접근 제한**: `allowed_ssh_cidr`를 본인 IP로 설정
2. **RDS 비밀번호**: 강력한 비밀번호 사용, terraform.tfvars로 관리
3. **S3 버킷 정책**: 필요시 특정 IAM 역할/사용자로 제한
4. **State 파일**: 민감한 정보 포함 가능, 접근 제어 필수

## 📚 참고 자료

- [Terraform S3 Backend](https://developer.hashicorp.com/terraform/language/settings/backends/s3)
- [S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)
- [Terraform State Management](https://developer.hashicorp.com/terraform/language/state)

## 📄 라이선스

이 프로젝트는 내부 사용을 위한 것입니다.

