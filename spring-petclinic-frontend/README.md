# PetClinic Frontend

## 구조

이 디렉토리는 Spring PetClinic의 프론트엔드 애플리케이션을 포함합니다.

## 빌드 및 배포

### 1. Docker 이미지 빌드

**중요:** 빌드 컨텍스트를 프로젝트 루트로 설정해야 합니다.

```bash
# 프로젝트 루트에서 실행
cd /path/to/spring-petclinic-microservice
docker build -f spring-petclinic-frontend/Dockerfile -t kdt-final-petclinic-frontend:v1.0.0 .
```

### 2. ECR에 푸시

```bash
# 환경 변수 설정
export ECR_REGISTRY=YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com
export AWS_REGION=ap-northeast-2

# ECR 로그인
aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}

# 태그 지정
docker tag kdt-final-petclinic-frontend:v1.0.0 ${ECR_REGISTRY}/kdt-final-petclinic-frontend:v1.0.0

# 푸시
docker push ${ECR_REGISTRY}/kdt-final-petclinic-frontend:v1.0.0
```

### 3. K8s 배포

```bash
kubectl apply -f ../k8s/frontend.yaml
```

## 설정

### Nginx 설정

- **포트**: 80
- **정적 파일 경로**: `/usr/share/nginx/html`
- **API 프록시**: `/api/` → `http://petclinic-api-gateway.default.svc.cluster.local:8080/api/`
- **CORS**: 모든 origin 허용 (프로덕션에서는 제한 권장)

### 환경 변수

현재는 하드코딩된 설정을 사용합니다. 필요시 ConfigMap을 통해 설정을 외부화할 수 있습니다.

## 주의사항

1. **프론트엔드 소스**: 현재 API Gateway의 `static/` 폴더에 있는 정적 파일들을 이 디렉토리로 복사하거나, 빌드 프로세스를 통해 생성해야 합니다.

2. **package.json**: Dockerfile에서 `npm run build`를 실행하므로, `package.json`과 빌드 스크립트가 필요합니다.

3. **빌드 결과물**: `npm run build`의 결과물이 `dist/` 폴더에 생성되어야 합니다.

