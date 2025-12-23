# Kubernetes 매니페스트 파일 구현 문서

이 문서는 `k8s/` 디렉토리에 있는 모든 Kubernetes 매니페스트 파일의 구조와 구현 내용을 상세히 설명합니다.

## 목차

1. [개요](#개요)
2. [애플리케이션 서비스](#애플리케이션-서비스)
3. [인프라 구성 요소](#인프라-구성-요소)
4. [설정 및 시크릿](#설정-및-시크릿)
5. [오토스케일링](#오토스케일링)
6. [인그레스 및 로드밸런싱](#인그레스-및-로드밸런싱)
7. [EKS 클러스터 설정](#eks-클러스터-설정)
8. [배포 스크립트](#배포-스크립트)

---

## 개요

이 프로젝트는 Spring PetClinic 마이크로서비스 애플리케이션을 AWS EKS(Elastic Kubernetes Service)에 배포하기 위한 Kubernetes 매니페스트 파일들을 포함합니다.

### 아키텍처

```
                    [Internet]
                         |
                    [AWS ALB]
                         |
                    [Ingress]
                         |
              ┌──────────┴──────────┐
              │                    │
        [Frontend]          [API Gateway]
              │                    │
              └──────────┬─────────┘
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   [Customers]      [Vets]         [Visits]
        │                │                │
        └────────────────┼────────────────┘
                         │
                    [RabbitMQ]
                         │
        ┌────────────────┼────────────────┐
        │                │                │
   [customers_db]  [vets_db]      [visits_db]
        │                │                │
        └────────────────┴────────────────┘
                         │
                    [AWS RDS]
```

---

## 애플리케이션 서비스

### 1. API Gateway (`api-gateway.yaml`)

**역할**: 모든 외부 요청의 진입점으로, 라우팅 및 로드밸런싱을 담당합니다.

**구성 요소**:
- **Deployment**: `petclinic-api-gateway`
- **Service**: `petclinic-api-gateway` (ClusterIP)

**주요 설정**:

```yaml
spec:
  replicas: 1
  containers:
    - name: api-gateway
      image: <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-gateway:v5.0.0
      ports:
        - containerPort: 8080
      env:
        - name: SPRING_PROFILES_ACTIVE
          value: mysql
      readinessProbe:
        httpGet:
          path: /actuator/health
          port: 8080
        initialDelaySeconds: 20
        periodSeconds: 10
      livenessProbe:
        httpGet:
          path: /actuator/health
          port: 8080
        initialDelaySeconds: 30
        periodSeconds: 15
      resources:
        requests:
          memory: "256Mi"
          cpu: "200m"
        limits:
          memory: "512Mi"
          cpu: "500m"
```

**특징**:
- Spring Boot Actuator를 통한 헬스체크 (`/actuator/health`)
- CPU/Memory 리소스 제한 설정
- HPA(Horizontal Pod Autoscaler)와 연동 가능

---

### 2. Frontend (`frontend.yaml`)

**역할**: 사용자 인터페이스를 제공하는 정적 웹 애플리케이션 (Nginx 기반)

**구성 요소**:
- **Deployment**: `petclinic-frontend`
- **Service**: `petclinic-frontend` (ClusterIP)

**주요 설정**:

```yaml
spec:
  replicas: 1
  containers:
    - name: frontend
      image: <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-frontend:v5.0.6
      ports:
        - containerPort: 80
          name: http
      readinessProbe:
        httpGet:
          path: /health
          port: 80
        initialDelaySeconds: 5
        periodSeconds: 5
      livenessProbe:
        httpGet:
          path: /health
          port: 80
        initialDelaySeconds: 10
        periodSeconds: 10
      resources:
        requests:
          memory: "64Mi"
          cpu: "50m"
        limits:
          memory: "128Mi"
          cpu: "100m"
```

**특징**:
- Nginx 기반 정적 파일 서빙
- 커스텀 헬스체크 엔드포인트 (`/health`)
- 낮은 리소스 요구사항 (정적 파일 서빙)
- `/petclinic` 경로 하위에서 동작하도록 Nginx 설정됨

**Nginx 설정 주요 내용** (`spring-petclinic-frontend/nginx.conf`):
- `/petclinic/webjars/` → API Gateway로 프록시
- `/petclinic/api/` → API Gateway로 프록시
- `/petclinic/images/`, `/petclinic/css/`, `/petclinic/scripts/` → 정적 파일 서빙
- SPA 라우팅 지원 (`try_files`)

---

### 3. Customers Service (`customers-service.yaml`)

**역할**: 고객(Owner) 및 애완동물(Pet) 정보를 관리하는 마이크로서비스

**구성 요소**:
- **Deployment**: `petclinic-customers`
- **Service**: `petclinic-customers` (ClusterIP)

**주요 설정**:

```yaml
spec:
  replicas: 1
  containers:
    - name: customers-service
      image: <YOUR_AWS_ACCOUNT_ID>.dkr.ecr.ap-northeast-2.amazonaws.com/petclinic-customers:v5.0.0
      env:
        - name: SPRING_PROFILES_ACTIVE
          value: mysql
        - name: DB_HOST
          valueFrom:
            configMapKeyRef:
              name: petclinic-config
              key: DB_HOST
        - name: SPRING_DATASOURCE_URL
          value: jdbc:mysql://$(DB_HOST):3306/customers_db
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: petclinic-db-secret
              key: CUSTOMERS_DATASOURCE_USERNAME
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: petclinic-db-secret
              key: CUSTOMERS_DATASOURCE_PASSWORD
      readinessProbe:
        httpGet:
          path: /actuator/health
          port: 8080
        initialDelaySeconds: 60
        periodSeconds: 10
        timeoutSeconds: 5
        failureThreshold: 3
      livenessProbe:
        httpGet:
          path: /actuator/health
          port: 8080
        initialDelaySeconds: 90
        periodSeconds: 15
        timeoutSeconds: 5
        failureThreshold: 3
      resources:
        requests:
          memory: "256Mi"
          cpu: "200m"
        limits:
          memory: "512Mi"
          cpu: "500m"
```

**특징**:
- ConfigMap에서 DB 호스트 정보 참조
- Secret에서 DB 자격증명 참조
- RDS 연결을 위한 긴 초기 지연 시간 설정 (60초 readiness, 90초 liveness)
- 전용 데이터베이스: `customers_db`

---

### 4. Vets Service (`vets-service.yaml`)

**역할**: 수의사(Veterinarian) 정보를 관리하는 마이크로서비스

**구성 요소**:
- **Deployment**: `petclinic-vets`
- **Service**: `petclinic-vets` (ClusterIP)

**주요 설정**: Customers Service와 동일한 구조이며, 다음만 다름:
- 이미지: `petclinic-vets:v5.0.0`
- Secret 키: `VETS_DATASOURCE_USERNAME`, `VETS_DATASOURCE_PASSWORD`
- 데이터베이스: `vets_db`

**특징**:
- Customers Service와 동일한 리소스 및 프로브 설정
- 전용 데이터베이스: `vets_db`

---

### 5. Visits Service (`visits-service.yaml`)

**역할**: 방문 기록(Visit) 정보를 관리하는 마이크로서비스

**구성 요소**:
- **Deployment**: `petclinic-visits`
- **Service**: `petclinic-visits` (ClusterIP)

**주요 설정**: Customers Service와 동일한 구조이며, 다음만 다름:
- 이미지: `petclinic-visits:v5.0.0`
- Secret 키: `VISITS_DATASOURCE_USERNAME`, `VISITS_DATASOURCE_PASSWORD`
- 데이터베이스: `visits_db`

**특징**:
- Customers Service와 동일한 리소스 및 프로브 설정
- 전용 데이터베이스: `visits_db`

---

### 6. RabbitMQ (`rabbitmq.yaml`)

**역할**: 메시지 브로커로 마이크로서비스 간 비동기 통신을 담당

**구성 요소**:
- **Deployment**: `rabbitmq`
- **Service**: `rabbitmq` (ClusterIP)

**주요 설정**:

```yaml
spec:
  replicas: 1
  containers:
    - name: rabbitmq
      image: rabbitmq:3.13-management
      ports:
        - name: amqp
          containerPort: 5672
        - name: management
          containerPort: 15672
      env:
        - name: RABBITMQ_DEFAULT_USER
          value: guest
        - name: RABBITMQ_DEFAULT_PASS
          value: guest
      readinessProbe:
        tcpSocket:
          port: 5672
        initialDelaySeconds: 10
        periodSeconds: 5
      livenessProbe:
        tcpSocket:
          port: 5672
        initialDelaySeconds: 30
        periodSeconds: 10
      resources:
        requests:
          memory: "256Mi"
          cpu: "100m"
        limits:
          memory: "512Mi"
          cpu: "500m"
```

**특징**:
- AMQP 포트: 5672 (메시지 큐)
- Management 포트: 15672 (웹 UI)
- TCP 소켓 기반 헬스체크
- 기본 자격증명: `guest/guest` (운영 환경에서는 Secret 사용 권장)

---

## 인프라 구성 요소

### ConfigMap (`petclinic-config.yaml`)

**역할**: 애플리케이션에서 공통으로 사용하는 설정값을 저장

**구성**:

```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: petclinic-config
data:
  DB_HOST: <YOUR_RDS_ENDPOINT>
```

**사용처**:
- `customers-service.yaml`: `DB_HOST` 환경 변수
- `vets-service.yaml`: `DB_HOST` 환경 변수
- `visits-service.yaml`: `DB_HOST` 환경 변수

**주의사항**:
- RDS 엔드포인트는 실제 값으로 교체 필요
- 민감하지 않은 정보만 저장 (자격증명은 Secret 사용)

---

### Secret (`petclinic-secret.yaml`)

**역할**: 민감한 정보(DB 자격증명 등)를 암호화하여 저장

**구성**:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: petclinic-db-secret
type: Opaque
stringData:
  # Customers Service DB credentials
  CUSTOMERS_DATASOURCE_USERNAME: <YOUR_CUSTOMERS_DB_USERNAME>
  CUSTOMERS_DATASOURCE_PASSWORD: <YOUR_CUSTOMERS_DB_PASSWORD>
  # Vets Service DB credentials
  VETS_DATASOURCE_USERNAME: <YOUR_VETS_DB_USERNAME>
  VETS_DATASOURCE_PASSWORD: <YOUR_VETS_DB_PASSWORD>
  # Visits Service DB credentials
  VISITS_DATASOURCE_USERNAME: <YOUR_VISITS_DB_USERNAME>
  VISITS_DATASOURCE_PASSWORD: <YOUR_VISITS_DB_PASSWORD>
```

**사용처**:
- 각 마이크로서비스 Deployment에서 `secretKeyRef`로 참조

**보안 권장사항**:
- Git에 커밋하기 전에 placeholder로 마스킹
- 운영 환경에서는 AWS Secrets Manager 또는 External Secrets Operator 사용 고려
- Base64 인코딩된 값으로 저장 가능 (`data` 필드 사용)

---

## 오토스케일링

### HPA (`hpa.yaml`)

**역할**: CPU 및 Memory 사용률에 따라 Pod 수를 자동으로 조정

**구성된 HPA**:

1. **API Gateway HPA**
   - `minReplicas`: 2
   - `maxReplicas`: 3
   - CPU 목표: 70%
   - Memory 목표: 80%
   - 스케일 다운: 5분 안정화 후 50%씩 감소
   - 스케일 업: 즉시, 최대 100% 또는 2 Pod씩 증가

2. **Frontend HPA**
   - `minReplicas`: 2
   - `maxReplicas`: 4
   - CPU 목표: 70%
   - Memory 목표: 80%

3. **Customers Service HPA**
   - `minReplicas`: 2
   - `maxReplicas`: 4
   - CPU 목표: 70%
   - Memory 목표: 80%

4. **Vets Service HPA**
   - `minReplicas`: 2
   - `maxReplicas`: 4
   - CPU 목표: 70%
   - Memory 목표: 80%

5. **Visits Service HPA**
   - `minReplicas`: 2
   - `maxReplicas`: 4
   - CPU 목표: 70%
   - Memory 목표: 80%

**동작 방식**:

```yaml
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: petclinic-api-gateway
  minReplicas: 2
  maxReplicas: 3
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
  - type: Resource
    resource:
      name: memory
      target:
        type: Utilization
        averageUtilization: 80
  behavior:
    scaleDown:
      stabilizationWindowSeconds: 300
      policies:
      - type: Percent
        value: 50
        periodSeconds: 60
    scaleUp:
      stabilizationWindowSeconds: 0
      policies:
      - type: Percent
        value: 100
        periodSeconds: 30
      - type: Pods
        value: 2
        periodSeconds: 30
      selectPolicy: Max
```

**주의사항**:
- HPA는 Deployment의 `resources.requests`가 설정되어 있어야 정확히 동작
- Metrics Server가 클러스터에 설치되어 있어야 함

---

## 인그레스 및 로드밸런싱

### Ingress (`ingress.yaml`)

**역할**: 외부 트래픽을 클러스터 내부 서비스로 라우팅 (AWS ALB 사용)

**구성**:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: petclinic-ingress
  namespace: default
  annotations:
    # ALB 설정
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/load-balancer-name: petclinic-alb
    
    # Health Check
    alb.ingress.kubernetes.io/healthcheck-path: /health
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: '15'
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: '5'
    alb.ingress.kubernetes.io/healthy-threshold-count: '2'
    alb.ingress.kubernetes.io/unhealthy-threshold-count: '2'
    
    # Subnet (Public Subnet에 ALB 생성)
    alb.ingress.kubernetes.io/subnets: <YOUR_PUBLIC_SUBNET_ID_1>, <YOUR_PUBLIC_SUBNET_ID_2>
    # 리스너 포트
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    
    # Path Rewrite: /petclinic을 제거하여 Frontend가 루트 경로로 인식하도록 함
    alb.ingress.kubernetes.io/rewrite-target: /
    
    # 태그
    alb.ingress.kubernetes.io/tags: Environment=dev,Project=petclinic-msa
spec:
  ingressClassName: alb
  rules:
  - http:
      paths:
      - path: /petclinic
        pathType: Prefix
        backend:
          service:
            name: petclinic-frontend
            port:
              number: 80
```

**주요 어노테이션 설명**:

| 어노테이션 | 설명 |
|-----------|------|
| `alb.ingress.kubernetes.io/scheme` | `internet-facing`: 외부 접근 가능한 ALB 생성 |
| `alb.ingress.kubernetes.io/target-type` | `ip`: Pod IP로 직접 연결 (NodePort 우회) |
| `alb.ingress.kubernetes.io/load-balancer-name` | ALB 이름 지정 |
| `alb.ingress.kubernetes.io/healthcheck-path` | 헬스체크 경로 (`/health`) |
| `alb.ingress.kubernetes.io/subnets` | ALB가 생성될 Public Subnet ID 목록 |
| `alb.ingress.kubernetes.io/rewrite-target` | 경로 재작성 (`/petclinic` → `/`) |

**경로 라우팅**:
- `/petclinic` → `petclinic-frontend:80`
- `rewrite-target: /`로 인해 `/petclinic/webjars/...` → `/webjars/...`로 변환
- Frontend의 Nginx가 `/petclinic` 경로를 처리하도록 설정됨

**필수 사전 요구사항**:
- AWS Load Balancer Controller 설치 필요
- IAM 역할 및 정책 설정 (`iam_policy.json` 참조)
- Public Subnet에 ALB 생성 권한

---

## EKS 클러스터 설정

### EKS Cluster Config (`eks/eks-cluster.yaml`)

**역할**: `eksctl`을 사용하여 EKS 클러스터를 생성하는 설정 파일

**구성**:

```yaml
apiVersion: eksctl.io/v1alpha5
kind: ClusterConfig

metadata:
  name: petclinic-cluster
  region: ap-northeast-2
  version: "1.34"

vpc:
  id: "<YOUR_VPC_ID>"
  subnets:
    private:
      ap-northeast-2a:
        id: "<YOUR_PRIVATE_SUBNET_ID_1>"
      ap-northeast-2b:
        id: "<YOUR_PRIVATE_SUBNET_ID_2>"
    public:
      ap-northeast-2a:
        id: "<YOUR_PUBLIC_SUBNET_ID_1>"
      ap-northeast-2b:
        id: "<YOUR_PUBLIC_SUBNET_ID_2>"

managedNodeGroups:
  - name: petclinic-ng-general
    instanceType: t3.medium
    minSize: 2
    desiredCapacity: 2
    maxSize: 5
    privateNetworking: true
    spot: true
    iam:
      withAddonPolicies:
        imageBuilder: true
        autoScaler: true
        externalDNS: true
        certManager: true
        ebs: true
        albIngress: true
        cloudWatch: true

iam:
  withOIDC: true

addons:
  - name: vpc-cni
  - name: coredns
  - name: kube-proxy
  - name: aws-ebs-csi-driver
```

**주요 설정 설명**:

| 설정 | 값 | 설명 |
|------|-----|------|
| `region` | `ap-northeast-2` | 서울 리전 |
| `version` | `1.34` | Kubernetes 버전 |
| `instanceType` | `t3.medium` | Worker Node 인스턴스 타입 (2 vCPU, 4GB RAM) |
| `minSize` | `2` | 최소 노드 수 |
| `desiredCapacity` | `2` | 기본 노드 수 |
| `maxSize` | `5` | 최대 노드 수 (Auto Scaling) |
| `privateNetworking` | `true` | Private Subnet에 배치 |
| `spot` | `true` | Spot 인스턴스 사용 (비용 절감) |
| `albIngress` | `true` | ALB Ingress Controller 권한 활성화 |

**클러스터 생성 명령**:

```bash
eksctl create cluster -f eks/eks-cluster.yaml
```

**주의사항**:
- 기존 VPC 및 Subnet을 재사용하도록 설정됨
- Spot 인스턴스 사용 시 중단 가능성 있음 (운영 환경에서는 `onDemand` 권장)
- IRSA(IAM Roles for Service Accounts) 활성화로 Pod 단위 권한 관리 가능

---

## 배포 스크립트

### Deploy Script (`deploy.sh`)

**역할**: 환경 변수를 치환하여 Kubernetes 매니페스트를 배포하는 자동화 스크립트

**주요 기능**:

1. **환경 변수 검증**
   - 필수 변수: `ECR_REGISTRY`, `RDS_ENDPOINT`
   - 누락 시 오류 메시지 출력

2. **환경 변수 치환**
   - `envsubst` 우선 사용 (있으면)
   - 없으면 `sed` 사용

3. **배포 실행**
   - 임시 디렉토리에 치환된 파일 생성
   - `kubectl apply` 실행

**사용 방법**:

```bash
# 환경 변수 설정
export ECR_REGISTRY=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com
export RDS_ENDPOINT=your-rds-endpoint.rds.amazonaws.com

# 배포 실행
cd k8s
./deploy.sh
```

**처리 흐름**:

```
1. 필수 환경 변수 확인
   ↓
2. kubectl 설치 확인
   ↓
3. 임시 디렉토리 생성
   ↓
4. 각 YAML 파일에 대해:
   - Secret 파일 제외
   - envsubst 또는 sed로 환경 변수 치환
   ↓
5. kubectl apply 실행
   ↓
6. 임시 디렉토리 정리
```

**주의사항**:
- `petclinic-secret.yaml`은 환경 변수 치환하지 않음 (직접 수정 필요)
- `envsubst` 설치 권장 (더 정확한 치환)

---

## 리소스 요약

### Deployment 리소스

| 서비스 | Replicas | CPU Request | CPU Limit | Memory Request | Memory Limit |
|--------|----------|-------------|-----------|----------------|--------------|
| API Gateway | 1 | 200m | 500m | 256Mi | 512Mi |
| Frontend | 1 | 50m | 100m | 64Mi | 128Mi |
| Customers | 1 | 200m | 500m | 256Mi | 512Mi |
| Vets | 1 | 200m | 500m | 256Mi | 512Mi |
| Visits | 1 | 200m | 500m | 256Mi | 512Mi |
| RabbitMQ | 1 | 100m | 500m | 256Mi | 512Mi |

### Service 리소스

| 서비스 | Type | Port | Target Port |
|--------|------|------|-------------|
| API Gateway | ClusterIP | 8080 | 8080 |
| Frontend | ClusterIP | 80 | 80 |
| Customers | ClusterIP | 8080 | 8080 |
| Vets | ClusterIP | 8080 | 8080 |
| Visits | ClusterIP | 8080 | 8080 |
| RabbitMQ | ClusterIP | 5672, 15672 | 5672, 15672 |

### HPA 설정

| 서비스 | Min Replicas | Max Replicas | CPU Target | Memory Target |
|--------|--------------|--------------|------------|---------------|
| API Gateway | 2 | 3 | 70% | 80% |
| Frontend | 2 | 4 | 70% | 80% |
| Customers | 2 | 4 | 70% | 80% |
| Vets | 2 | 4 | 70% | 80% |
| Visits | 2 | 4 | 70% | 80% |

---

## 배포 순서

권장 배포 순서:

1. **ConfigMap 및 Secret**
   ```bash
   kubectl apply -f petclinic-config.yaml
   kubectl apply -f petclinic-secret.yaml
   ```

2. **인프라 서비스**
   ```bash
   kubectl apply -f rabbitmq.yaml
   ```

3. **백엔드 서비스**
   ```bash
   kubectl apply -f customers-service.yaml
   kubectl apply -f vets-service.yaml
   kubectl apply -f visits-service.yaml
   ```

4. **API Gateway**
   ```bash
   kubectl apply -f api-gateway.yaml
   ```

5. **Frontend**
   ```bash
   kubectl apply -f frontend.yaml
   ```

6. **HPA**
   ```bash
   kubectl apply -f hpa.yaml
   ```

7. **Ingress**
   ```bash
   kubectl apply -f ingress.yaml
   ```

---

## 트러블슈팅

### Pod가 Pending 상태인 경우

1. **노드 확인**
   ```bash
   kubectl get nodes
   ```

2. **Pod 이벤트 확인**
   ```bash
   kubectl describe pod <pod-name>
   ```

3. **리소스 부족 확인**
   ```bash
   kubectl top nodes
   kubectl top pods
   ```

### Pod가 CrashLoopBackOff 상태인 경우

1. **로그 확인**
   ```bash
   kubectl logs <pod-name>
   kubectl logs <pod-name> --previous
   ```

2. **환경 변수 확인**
   ```bash
   kubectl describe pod <pod-name> | grep -A 10 "Environment:"
   ```

3. **헬스체크 확인**
   ```bash
   kubectl exec <pod-name> -- curl http://localhost:8080/actuator/health
   ```

### ALB가 생성되지 않는 경우

1. **AWS Load Balancer Controller 확인**
   ```bash
   kubectl get pods -n kube-system | grep aws-load-balancer
   ```

2. **Ingress 이벤트 확인**
   ```bash
   kubectl describe ingress petclinic-ingress
   ```

3. **IAM 권한 확인**
   - `iam_policy.json`의 권한이 ServiceAccount에 연결되어 있는지 확인
   - `elasticloadbalancing:DescribeListenerAttributes` 권한 포함 확인

### RDS 연결 실패

1. **보안 그룹 확인**
   - RDS 보안 그룹에 EKS 노드 서브넷 CIDR 허용 확인

2. **ConfigMap 확인**
   ```bash
   kubectl get configmap petclinic-config -o yaml
   ```

3. **Secret 확인**
   ```bash
   kubectl get secret petclinic-db-secret -o yaml
   ```

---

## 참고 자료

- [Kubernetes 공식 문서](https://kubernetes.io/docs/)
- [AWS EKS 사용자 가이드](https://docs.aws.amazon.com/eks/)
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)
- [Spring Boot Actuator](https://docs.spring.io/spring-boot/docs/current/reference/html/actuator.html)

---

**작성일**: 2024년
**버전**: v5.0.0

