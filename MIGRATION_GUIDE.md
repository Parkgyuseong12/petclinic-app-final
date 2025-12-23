# Terraform 프로젝트 리팩토링 가이드

## 개요

이 문서는 루트 중심 구조에서 디렉터리 기반 격리 구조로 전환하는 과정을 안내합니다.

## 리팩토링 완료 사항

✅ **1. Modules 폴더 정제**
- `modules/` 디렉터리 내부의 모든 파일에서 `provider "aws" {}` 블록과 `terraform { backend ... }` 블록 제거 확인 완료
- 모듈은 순수 리소스 정의만 포함

✅ **2. Dev 환경 구성**
- `environments/dev/` 폴더에 모든 필요한 파일 생성 완료:
  - `main.tf` - 모듈 호출 방식으로 변환
  - `variables.tf` - 변수 정의
  - `outputs.tf` - 출력 정의
  - `terraform.tfvars` - Dev 환경 변수 값
  - `backend.tf` - S3 Native Lock 사용
  - `versions.tf` - Provider 설정
  - `data.tf` - Data sources
  - `locals.tf` - Local values
  - `rds.tf` - RDS 리소스
  - `outputs_to_ssm.tf` - SSM 파라미터
  - `sql/init.sql` - SQL 초기화 파일

✅ **3. Backend 설정**
- S3 Native Lock 사용 (`use_lockfile = true`)
- DynamoDB 없이 동작

## 루트 디렉터리 청소 전략

### ⚠️ 주의사항

**리팩토링 전에 반드시 수행해야 할 작업:**

1. **현재 상태 백업**
   ```bash
   # 루트 디렉터리에서 실행
   cd /Users/hwangseung-gi/cursor_workspace/petclinic-test-infra
   
   # Git 상태 확인
   git status
   
   # 변경사항 커밋 (선택사항)
   git add .
   git commit -m "Before refactoring: backup current state"
   ```

2. **Terraform State 백업**
   ```bash
   # 현재 state 파일 백업
   cp terraform.tfstate terraform.tfstate.backup.refactor
   cp terraform.tfstate.backup terraform.tfstate.backup.refactor.backup 2>/dev/null || true
   ```

### 📋 청소 명령어 (순차 실행)

#### Step 1: 기존 Terraform 파일을 백업 디렉터리로 이동

```bash
# 루트 디렉터리에서 실행
cd /Users/hwangseung-gi/cursor_workspace/petclinic-test-infra

# 백업 디렉터리 생성
mkdir -p .backup/root-files

# 기존 구현체 파일들을 백업 디렉터리로 이동
mv ec2.tf .backup/root-files/ 2>/dev/null || true
mv vpc.tf .backup/root-files/ 2>/dev/null || true
mv rds.tf .backup/root-files/ 2>/dev/null || true
mv security_groups.tf .backup/root-files/ 2>/dev/null || true
mv iam.tf .backup/root-files/ 2>/dev/null || true
mv outputs.tf .backup/root-files/ 2>/dev/null || true
mv outputs_to_ssm.tf .backup/root-files/ 2>/dev/null || true
mv data.tf .backup/root-files/ 2>/dev/null || true
mv locals.tf .backup/root-files/ 2>/dev/null || true
mv versions.tf .backup/root-files/ 2>/dev/null || true
mv s3_backend.tf .backup/root-files/ 2>/dev/null || true
mv terraform.tfvars .backup/root-files/ 2>/dev/null || true
mv backend.tf.example .backup/root-files/ 2>/dev/null || true
```

#### Step 2: 스크립트 파일 처리

```bash
# 스크립트 파일들을 백업 디렉터리로 이동
mv cleanup_s3.sh .backup/root-files/ 2>/dev/null || true
mv destroy_without_s3.sh .backup/root-files/ 2>/dev/null || true
mv user_data_mgmt.sh .backup/root-files/ 2>/dev/null || true
```

#### Step 3: State 파일 처리 (주의!)

```bash
# State 파일은 백업만 하고 삭제하지 않음 (필요시 참조용)
# environments/dev에서 새로 생성될 예정이므로 루트의 state는 백업만
mv terraform.tfstate .backup/root-files/terraform.tfstate.old 2>/dev/null || true
mv terraform.tfstate.backup .backup/root-files/terraform.tfstate.backup.old 2>/dev/null || true
```

#### Step 4: mykey 디렉터리 처리

```bash
# mykey 디렉터리는 environments/dev/mykey로 이미 복사되었으므로
# 루트의 mykey는 백업 후 삭제 (또는 유지)
mv mykey .backup/root-files/mykey 2>/dev/null || true
```

#### Step 5: 최종 확인

```bash
# 루트 디렉터리 구조 확인
ls -la

# 남아있는 파일 확인 (modules/, environments/, .gitignore, README.md만 남아야 함)
# 필요시 추가 정리
```

### 📁 최종 루트 디렉터리 구조

리팩토링 후 루트 디렉터리는 다음과 같이 구성됩니다:

```
petclinic-test-infra/
├── modules/              # 순수 모듈 정의
│   ├── ec2/
│   ├── security-groups/
│   └── vpc/
├── environments/         # 환경별 구성
│   ├── dev/
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   ├── terraform.tfvars
│   │   ├── backend.tf
│   │   ├── versions.tf
│   │   ├── data.tf
│   │   ├── locals.tf
│   │   ├── rds.tf
│   │   ├── outputs_to_ssm.tf
│   │   ├── sql/
│   │   └── mykey/
│   └── prod/             # 추후 생성 예정
├── .backup/              # 백업 파일 (선택사항)
│   └── root-files/
├── .gitignore
├── README.md
└── MIGRATION_GUIDE.md    # 이 문서
```

## 다음 단계

### 1. Terraform 초기화 및 마이그레이션

```bash
# environments/dev 디렉터리로 이동
cd environments/dev

# Terraform 초기화 (S3 Native Lock 활성화)
terraform init -reconfigure

# State 마이그레이션 (기존 리소스가 있는 경우)
# 주의: 이 단계는 기존 인프라를 유지하면서 state만 이동하는 경우에만 필요
# terraform state mv <resource_address> <new_resource_address>
```

### 2. Terraform 버전 확인

```bash
# Terraform 버전 확인 (v1.10.0 이상 필요)
terraform version

# 버전이 낮은 경우 업그레이드 필요
```

### 3. Plan 및 Apply

```bash
# 변경사항 확인
terraform plan

# 적용 (주의: 실제 인프라에 변경사항 적용)
# terraform apply
```

## 주의사항

1. **State 파일 마이그레이션**: 기존 리소스가 있는 경우, state 파일을 새 위치로 마이그레이션해야 합니다.

2. **S3 버킷 이름**: `backend.tf`의 `bucket` 값이 실제 S3 버킷 이름과 일치하는지 확인하세요.

3. **변수 값 확인**: `terraform.tfvars`의 값들이 Dev 환경에 적합한지 확인하세요.

4. **모듈 경로**: 모든 모듈 경로가 상대 경로(`../../modules/...`)로 설정되어 있는지 확인하세요.

## 롤백 방법

문제가 발생한 경우:

```bash
# 백업 디렉터리에서 파일 복원
cd /Users/hwangseung-gi/cursor_workspace/petclinic-test-infra
cp -r .backup/root-files/* .

# Git을 사용하는 경우
git checkout HEAD -- .
```

## 참고사항

- `.backup/` 디렉터리는 필요시 삭제 가능합니다.
- `environments/dev/mykey/` 디렉터리는 SSH 키가 생성될 위치입니다.
- `sql/init.sql` 파일은 `environments/dev/sql/init.sql`로 복사되었습니다.

