# Kubernetes 배포 매니페스트

이 디렉토리에는 AWS EKS에 배포하기 위한 Kubernetes 매니페스트 파일들이 포함되어 있습니다.

## 파일 구조

- `petclinic-config.yaml`: ConfigMap (DB 호스트 등 공통 설정)
- `petclinic-secret.yaml`: Secret (DB 자격증명 - **실제 값으로 교체 필요**)
- `*-service.yaml`: 각 마이크로서비스의 Deployment 및 Service 매니페스트

## 중요: 민감한 정보 마스킹

모든 매니페스트 파일은 실제 값 대신 환경 변수 placeholder를 사용합니다:

- `${ECR_REGISTRY}`: AWS ECR 레지스트리 URL (예: `123456789012.dkr.ecr.ap-northeast-2.amazonaws.com`)
- `${RDS_ENDPOINT}`: AWS RDS MySQL 엔드포인트 (예: `your-db.rds.amazonaws.com`)

## 사전 요구사항

배포 전에 다음 사항이 준비되어 있어야 합니다:

### 1. kubectl 및 AWS CLI 설치 확인

```bash
# kubectl 확인
kubectl version --client

# AWS CLI 확인
aws --version
```

### 2. EKS 클러스터 연결 설정

**중요**: kubectl이 EKS 클러스터에 연결할 수 있도록 kubeconfig를 설정해야 합니다.

```bash
# EKS 클러스터 이름과 리전 설정
export CLUSTER_NAME=your-eks-cluster-name
export AWS_REGION=ap-northeast-2

# kubeconfig 업데이트 (EKS 클러스터 연결)
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# 연결 확인
kubectl get nodes
```

**연결이 안 되는 경우:**
- EKS 클러스터가 생성되어 있는지 확인
- Bastion 서버의 IAM 역할/사용자가 EKS 클러스터 접근 권한이 있는지 확인
- `aws eks list-clusters --region ap-northeast-2` 명령으로 클러스터 목록 확인

## 배포 방법

### 1. 환경 변수 설정

```bash
export ECR_REGISTRY=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
export RDS_ENDPOINT=your-rds-endpoint.rds.amazonaws.com
export IMAGE_TAG=v5.0.0  # 선택사항, 기본값: v4.0.0
```

### 2. Secret 파일 수정

`petclinic-secret.yaml` 파일을 열어 각 서비스별 DB 자격증명으로 수정:

```yaml
stringData:
  # Customers Service DB credentials
  CUSTOMERS_DATASOURCE_USERNAME: customers_user
  CUSTOMERS_DATASOURCE_PASSWORD: your_customers_password
  # Vets Service DB credentials
  VETS_DATASOURCE_USERNAME: vets_user
  VETS_DATASOURCE_PASSWORD: your_vets_password
  # Visits Service DB credentials
  VISITS_DATASOURCE_USERNAME: visits_user
  VISITS_DATASOURCE_PASSWORD: your_visits_password
```

**중요:** 각 서비스는 자신의 데이터베이스에 대한 전용 사용자를 사용합니다. RDS에서 각 사용자에게 해당 데이터베이스에 대한 권한을 부여해야 합니다:

```sql
-- Customers DB 사용자 생성 및 권한 부여
CREATE USER 'customers_user'@'%' IDENTIFIED BY 'your_customers_password';
GRANT ALL PRIVILEGES ON customers_db.* TO 'customers_user'@'%';
FLUSH PRIVILEGES;

-- Vets DB 사용자 생성 및 권한 부여
CREATE USER 'vets_user'@'%' IDENTIFIED BY 'your_vets_password';
GRANT ALL PRIVILEGES ON vets_db.* TO 'vets_user'@'%';
FLUSH PRIVILEGES;

-- Visits DB 사용자 생성 및 권한 부여
CREATE USER 'visits_user'@'%' IDENTIFIED BY 'your_visits_password';
GRANT ALL PRIVILEGES ON visits_db.* TO 'visits_user'@'%';
FLUSH PRIVILEGES;
```

### 3. 배포 실행

#### 방법 1: 배포 스크립트 사용 (권장)

```bash
# k8s 디렉토리로 이동
cd k8s

# 배포 실행
./deploy.sh
```

이 스크립트는 자동으로 환경 변수를 치환합니다:
- `envsubst`가 있으면 사용 (권장)
- 없으면 `sed`를 사용하여 치환

**envsubst 설치 (선택사항, 없어도 동작함):**
- **macOS**: `brew install gettext`
- **Ubuntu/Debian**: `sudo apt-get install gettext-base`
- **RHEL/CentOS**: `sudo yum install gettext`

**Bastion 서버에서 사용 예시:**
```bash
# 환경 변수 설정
export ECR_REGISTRY=YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
export RDS_ENDPOINT=your-rds-endpoint.rds.amazonaws.com

# 배포 실행
cd k8s
./deploy.sh
```

#### 방법 2: 파일별 개별 배포 (간단)

각 파일을 하나씩 직접 apply하는 방법입니다:

```bash
# 1. 환경 변수 설정
export ECR_REGISTRY=YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
export RDS_ENDPOINT=your-rds-endpoint.rds.amazonaws.com

# 2. k8s 디렉토리로 이동
cd k8s

# 3. 각 파일을 하나씩 apply (순서대로 실행)
# ConfigMap 배포
sed "s|\${RDS_ENDPOINT}|${RDS_ENDPOINT}|g" petclinic-config.yaml | kubectl apply -f -

# Secret 배포 (먼저 실제 값으로 수정 필요)
kubectl apply -f petclinic-secret.yaml

# 각 서비스 배포
sed "s|\${ECR_REGISTRY}|${ECR_REGISTRY}|g" api-gateway.yaml | kubectl apply -f -
sed "s|\${ECR_REGISTRY}|${ECR_REGISTRY}|g" customers-service.yaml | kubectl apply -f -
sed "s|\${ECR_REGISTRY}|${ECR_REGISTRY}|g" vets-service.yaml | kubectl apply -f -
sed "s|\${ECR_REGISTRY}|${ECR_REGISTRY}|g" visits-service.yaml | kubectl apply -f -
```

**또는 envsubst가 있는 경우:**
```bash
envsubst < petclinic-config.yaml | kubectl apply -f -
kubectl apply -f petclinic-secret.yaml
envsubst < api-gateway.yaml | kubectl apply -f -
envsubst < customers-service.yaml | kubectl apply -f -
envsubst < vets-service.yaml | kubectl apply -f -
envsubst < visits-service.yaml | kubectl apply -f -
```

## 데이터베이스 초기화

**중요**: 파드를 배포하기 전에 RDS에 데이터베이스 스키마를 생성해야 합니다.

### 방법 1: 직접 MySQL 클라이언트 사용

```bash
# RDS 엔드포인트와 자격증명으로 연결
mysql -h your-rds-endpoint.rds.amazonaws.com \
      -u your_username \
      -p \
      < k8s/init-customers-db.sql
```

### 방법 2: Bastion 서버에서 실행

```bash
# k8s 디렉토리로 이동
cd k8s

# SQL 파일 실행
mysql -h ${RDS_ENDPOINT} \
      -u ${DB_USERNAME} \
      -p${DB_PASSWORD} \
      < init-database.sql
```

**환경 변수 예시:**
```bash
export RDS_ENDPOINT=your-rds-endpoint.rds.amazonaws.com
export DB_USERNAME=your_username
export DB_PASSWORD=your_password
```

### 생성되는 테이블

- `types`: 애완동물 타입 (cat, dog 등)
- `owners`: 주인 정보
- `pets`: 애완동물 정보
- `vets`: 수의사 정보
- `specialties`: 전문 분야
- `vet_specialties`: 수의사-전문 분야 연관
- `visits`: 방문 기록

## 배포 확인

```bash
# 모든 리소스 확인
kubectl get all -l app

# Pod 상태 확인
kubectl get pods

# 로그 확인
kubectl logs -f deployment/petclinic-api-gateway
```

## 문제 해결

### kubectl 연결 오류

**오류 메시지:**
```
error: error validating data: failed to download openapi: Get "http://localhost:8080/openapi/v2?timeout=32s": dial tcp 127.0.0.1:8080: connect: connection refused
```

**해결 방법:**
1. EKS 클러스터 연결 확인:
   ```bash
   aws eks update-kubeconfig --region ap-northeast-2 --name your-cluster-name
   ```

2. kubectl 연결 테스트:
   ```bash
   kubectl get nodes
   ```

3. kubeconfig 파일 확인:
   ```bash
   cat ~/.kube/config
   ```

4. AWS 자격증명 확인:
   ```bash
   aws sts get-caller-identity
   ```

## 주의사항

1. **kubectl 연결**: 배포 전에 반드시 `kubectl get nodes` 명령으로 EKS 클러스터 연결을 확인하세요.

2. **Secret 파일**: `petclinic-secret.yaml`에는 실제 DB 자격증명이 포함되므로, Git에 커밋하기 전에 반드시 placeholder로 변경하세요.

3. **환경 변수**: 배포 전에 모든 필수 환경 변수가 설정되었는지 확인하세요.

4. **ECR 인증**: EKS 클러스터가 ECR에서 이미지를 pull할 수 있도록 IAM 역할이 올바르게 설정되어 있어야 합니다.

5. **RDS 접근**: EKS 노드의 보안 그룹이 RDS 인스턴스에 접근할 수 있도록 설정되어 있어야 합니다.

