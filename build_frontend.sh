#!/bin/bash

# 프론트엔드 Docker 이미지 빌드 및 푸시 스크립트

set -e

# 프로젝트 루트 디렉토리로 이동
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 이미지 태그 (환경 변수로 오버라이드 가능)
IMAGE_TAG="${IMAGE_TAG:-v1.0.0}"
ECR_REGISTRY="${ECR_REGISTRY:-YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
IMAGE_NAME="petclinic-frontend"
FULL_IMAGE_NAME="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

echo "=========================================="
echo "프론트엔드 Docker 이미지 빌드 및 푸시"
echo "=========================================="
echo "이미지 태그: ${IMAGE_TAG}"
echo "전체 이미지 이름: ${FULL_IMAGE_NAME}"
echo ""

# Docker 이미지 빌드 (플랫폼 명시)
echo "[1단계] Docker 이미지 빌드 중..."
docker build --platform linux/amd64 -f spring-petclinic-frontend/Dockerfile -t ${IMAGE_NAME}:${IMAGE_TAG} .
echo "✅ 빌드 완료"
echo ""

# ECR 태그 지정
echo "[2단계] ECR 태그 지정 중..."
docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${FULL_IMAGE_NAME}
echo "✅ 태그 지정 완료"
echo ""

# ECR 로그인 확인
echo "[3단계] ECR 로그인 확인 중..."
if ! aws ecr get-login-password --region ${AWS_REGION} 2>/dev/null | docker login --username AWS --password-stdin ${ECR_REGISTRY} 2>/dev/null; then
    echo "⚠️  ECR 로그인 실패. 수동으로 로그인하세요:"
    echo "   aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}"
    exit 1
fi
echo "✅ ECR 로그인 완료"
echo ""

# ECR 푸시
echo "[4단계] ECR에 이미지 푸시 중..."
docker push ${FULL_IMAGE_NAME}
echo "✅ 푸시 완료"
echo ""

echo "=========================================="
echo "빌드 및 푸시 완료!"
echo "=========================================="
echo "이미지: ${FULL_IMAGE_NAME}"
echo ""
echo "다음 단계:"
echo "  kubectl apply -f k8s/frontend.yaml"
echo ""

