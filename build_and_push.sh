#!/usr/bin/env bash

# 에러 발생 시 즉시 중단 및 변수 미설정 시 에러 처리
set -euo pipefail

# 스크립트가 프로젝트 루트에서 실행되는지 확인
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}" && pwd)"
cd "${PROJECT_ROOT}"

# 기본값 설정
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ECR_REGISTRY="${ECR_REGISTRY:-YOUR_ACCOUNT_ID.dkr.ecr.ap-northeast-2.amazonaws.com}"
IMAGE_TAG="${IMAGE_TAG:-V1.0.0}"

# ECR_REGISTRY 확인
if [[ -z "${ECR_REGISTRY}" ]]; then
  echo "[ERROR] ECR_REGISTRY 환경 변수가 필요합니다." >&2
  echo "예시: export ECR_REGISTRY=123456789012.dkr.ecr.ap-northeast-2.amazonaws.com" >&2
  exit 1
fi

echo "[INFO] ${ECR_REGISTRY} 레지스트리에 로그인합니다 (리전: ${AWS_REGION})..."
aws ecr get-login-password --region "${AWS_REGION}" \
  | docker login --username AWS --password-stdin "${ECR_REGISTRY}"

# ------------------------------------------------------------------
# [수정됨] Bash 3.2(macOS) 호환을 위해 일반 배열 사용
# 형식: "로컬디렉토리명:ECR이미지명"
# ------------------------------------------------------------------
SERVICES=(
  "spring-petclinic-api-gateway:petclinic-gateway"
  "spring-petclinic-customers-service:petclinic-customers"
  "spring-petclinic-vets-service:petclinic-vets"
  "spring-petclinic-visits-service:petclinic-visits"
  "spring-petclinic-frontend:petclinic-frontend"
)
# ------------------------------------------------------------------

# 배열 순회 및 빌드/푸시
for ITEM in "${SERVICES[@]}"; do
  # 문자열 파싱 (매킨토시 호환)
  SERVICE_DIR="${ITEM%%:*}"   # 콜론 앞부분 (디렉토리)
  IMAGE_NAME="${ITEM##*:}"    # 콜론 뒷부분 (이미지명)

  # 로컬 이미지 태그 (빌드용)
  LOCAL_IMAGE="${IMAGE_NAME}:${IMAGE_TAG}"
  
  # 원격 ECR 이미지 태그 (푸시용)
  # 새로운 형식: ECR_REGISTRY/petclinic-{service}
  REMOTE_IMAGE="${ECR_REGISTRY}/${IMAGE_NAME}:${IMAGE_TAG}"

  if [[ ! -d "${SERVICE_DIR}" ]]; then
    echo "[WARN] 디렉토리 '${SERVICE_DIR}'를 찾을 수 없습니다. 건너뜁니다."
    continue
  fi

  echo "========================================================"
  echo "[BUILD] ${SERVICE_DIR} -> ${LOCAL_IMAGE}"
  # --platform linux/amd64 옵션 추가 (EKS 노드가 x86인 경우 필수, 맥북 M1/M2/M3 사용자용)
  # 빌드 컨텍스트를 프로젝트 루트로 설정하고, Dockerfile 경로를 지정
  docker build --platform linux/amd64 \
    -f "${SERVICE_DIR}/Dockerfile" \
    -t "${LOCAL_IMAGE}" \
    .

  echo "[TAG]   ${LOCAL_IMAGE} -> ${REMOTE_IMAGE}"
  docker tag "${LOCAL_IMAGE}" "${REMOTE_IMAGE}"

  echo "[PUSH]  ${REMOTE_IMAGE}"
  docker push "${REMOTE_IMAGE}"
  echo "========================================================"
done

echo "[SUCCESS] 모든 이미지 푸시 완료."