#!/bin/bash
# =============================================================================
# Management Server 초기화 스크립트
# AWS CLI v2, kubectl, eksctl, helm, mysql-client, docker 설치
# =============================================================================

set -e

# 로그 파일 설정
LOG_FILE="/var/log/user-data.log"
exec > >(tee -a $LOG_FILE) 2>&1

echo "=========================================="
echo "Management Server 초기화 시작"
echo "시작 시간: $(date)"
echo "=========================================="

# 환경 변수
AWS_REGION="${aws_region}"
EKS_CLUSTER_NAME="${eks_cluster_name}"

# 시스템 업데이트
echo "[1/8] 시스템 패키지 업데이트..."
apt-get update -y
apt-get upgrade -y

# 필수 패키지 설치
echo "[2/8] 필수 패키지 설치..."
apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    unzip \
    wget \
    vim \
    htop \
    jq \
    git \
    tree

# -----------------------------------------------------------------------------
# AWS CLI v2 설치
# -----------------------------------------------------------------------------
echo "[3/8] AWS CLI v2 설치..."
if ! command -v aws &> /dev/null; then
    curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
    unzip -q /tmp/awscliv2.zip -d /tmp
    /tmp/aws/install
    rm -rf /tmp/aws /tmp/awscliv2.zip
fi
aws --version

# AWS CLI 자동완성 설정
echo 'complete -C /usr/local/bin/aws_completer aws' >> /home/ubuntu/.bashrc

# 리전 설정
mkdir -p /home/ubuntu/.aws
cat > /home/ubuntu/.aws/config <<EOF
[default]
region = $AWS_REGION
output = json
EOF
chown -R ubuntu:ubuntu /home/ubuntu/.aws

# -----------------------------------------------------------------------------
# kubectl 설치
# -----------------------------------------------------------------------------
echo "[4/8] kubectl 설치..."
if ! command -v kubectl &> /dev/null; then
    # 최신 안정 버전 확인
    KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
    curl -LO "https://dl.k8s.io/release/$KUBECTL_VERSION/bin/linux/amd64/kubectl"
    chmod +x kubectl
    mv kubectl /usr/local/bin/
fi
kubectl version --client

# kubectl 자동완성 설정
echo 'source <(kubectl completion bash)' >> /home/ubuntu/.bashrc
echo 'alias k=kubectl' >> /home/ubuntu/.bashrc
echo 'complete -o default -F __start_kubectl k' >> /home/ubuntu/.bashrc

# -----------------------------------------------------------------------------
# eksctl 설치
# -----------------------------------------------------------------------------
echo "[5/8] eksctl 설치..."
if ! command -v eksctl &> /dev/null; then
    ARCH=amd64
    PLATFORM=$(uname -s)_$ARCH
    curl -sLO "https://github.com/eksctl-io/eksctl/releases/latest/download/eksctl_$PLATFORM.tar.gz"
    tar -xzf eksctl_$PLATFORM.tar.gz -C /tmp
    mv /tmp/eksctl /usr/local/bin
    rm -f eksctl_$PLATFORM.tar.gz
fi
eksctl version

# -----------------------------------------------------------------------------
# Helm 설치
# -----------------------------------------------------------------------------
echo "[6/8] Helm 설치..."
if ! command -v helm &> /dev/null; then
    curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
helm version

# Helm 자동완성 설정
echo 'source <(helm completion bash)' >> /home/ubuntu/.bashrc

# -----------------------------------------------------------------------------
# MySQL Client 설치
# -----------------------------------------------------------------------------
echo "[7/8] MySQL Client 설치..."
apt-get install -y mysql-client

# MySQL 연결 정보 파일 생성 (비밀번호는 보안상 저장하지 않음)
cat > /home/ubuntu/db-connect.sh <<'DBEOF'
#!/bin/bash
# RDS 연결 스크립트
# 사용법: ./db-connect.sh [database_name]

# Parameter Store에서 RDS 정보 가져오기
RDS_ENDPOINT=$(aws ssm get-parameter --name "/petclinic/prod/rds/endpoint" --query "Parameter.Value" --output text)
RDS_USERNAME=$(aws ssm get-parameter --name "/petclinic/prod/rds/username" --with-decryption --query "Parameter.Value" --output text)

echo "RDS Endpoint: $RDS_ENDPOINT"
echo "Username: $RDS_USERNAME"
echo ""

if [ -z "$1" ]; then
    mysql -h $(echo $RDS_ENDPOINT | cut -d: -f1) -u $RDS_USERNAME -p
else
    mysql -h $(echo $RDS_ENDPOINT | cut -d: -f1) -u $RDS_USERNAME -p $1
fi
DBEOF
chmod +x /home/ubuntu/db-connect.sh
chown ubuntu:ubuntu /home/ubuntu/db-connect.sh

# -----------------------------------------------------------------------------
# Docker 설치
# -----------------------------------------------------------------------------
echo "[8/8] Docker 설치..."
if ! command -v docker &> /dev/null; then
    # Docker GPG 키 추가
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    chmod a+r /etc/apt/keyrings/docker.gpg

    # Docker 저장소 추가
    echo \
      "deb [arch="$(dpkg --print-architecture)" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
      "$(. /etc/os-release && echo "$VERSION_CODENAME")" stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Docker 설치
    apt-get update -y
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # ubuntu 사용자를 docker 그룹에 추가
    usermod -aG docker ubuntu
fi
docker --version

# Docker 서비스 시작 및 활성화
systemctl enable docker
systemctl start docker

# -----------------------------------------------------------------------------
# 추가 도구 설치: k9s (Kubernetes TUI)
# -----------------------------------------------------------------------------
echo "[추가] k9s 설치..."
if ! command -v k9s &> /dev/null; then
    K9S_VERSION=$(curl -s https://api.github.com/repos/derailed/k9s/releases/latest | jq -r '.tag_name')
    curl -sLO "https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_amd64.tar.gz"
    tar -xzf k9s_Linux_amd64.tar.gz -C /tmp
    mv /tmp/k9s /usr/local/bin
    rm -f k9s_Linux_amd64.tar.gz
fi

# -----------------------------------------------------------------------------
# EKS 클러스터 생성 스크립트 생성
# -----------------------------------------------------------------------------
cat > /home/ubuntu/create-eks-cluster.sh <<'EKSEOF'
#!/bin/bash
# =============================================================================
# EKS 클러스터 생성 스크립트
# 이 스크립트를 실행하기 전에 VPC 서브넷 ID를 확인하세요.
# =============================================================================

set -e

CLUSTER_NAME="petclinic-cluster"
REGION="ap-northeast-2"

echo "=========================================="
echo "EKS 클러스터 생성: $CLUSTER_NAME"
echo "리전: $REGION"
echo "=========================================="

# VPC 서브넷 조회
echo "VPC 서브넷 조회 중..."
PRIVATE_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=petclinic-private-subnet-*" \
    --query "Subnets[*].SubnetId" \
    --output text | tr '\t' ',')

PUBLIC_SUBNETS=$(aws ec2 describe-subnets \
    --filters "Name=tag:Name,Values=petclinic-public-subnet-*" \
    --query "Subnets[*].SubnetId" \
    --output text | tr '\t' ',')

echo "Private Subnets: $PRIVATE_SUBNETS"
echo "Public Subnets: $PUBLIC_SUBNETS"

# EKS 클러스터 생성 (노드 그룹 없이)
echo ""
echo "EKS 클러스터 생성 중... (약 15-20분 소요)"
eksctl create cluster \
    --name $CLUSTER_NAME \
    --region $REGION \
    --vpc-private-subnets $PRIVATE_SUBNETS \
    --vpc-public-subnets $PUBLIC_SUBNETS \
    --without-nodegroup \
    --version 1.29

# kubeconfig 업데이트
aws eks update-kubeconfig --name $CLUSTER_NAME --region $REGION

# 관리형 노드 그룹 생성
echo ""
echo "관리형 노드 그룹 생성 중..."
eksctl create nodegroup \
    --cluster $CLUSTER_NAME \
    --region $REGION \
    --name "$CLUSTER_NAME-ng" \
    --node-type t3.medium \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 4 \
    --node-private-networking \
    --managed

echo ""
echo "=========================================="
echo "EKS 클러스터 생성 완료!"
echo "kubectl get nodes 로 노드 상태를 확인하세요."
echo "=========================================="
EKSEOF
chmod +x /home/ubuntu/create-eks-cluster.sh
chown ubuntu:ubuntu /home/ubuntu/create-eks-cluster.sh

# -----------------------------------------------------------------------------
# 버전 확인 스크립트
# -----------------------------------------------------------------------------
cat > /home/ubuntu/check-versions.sh <<'VEREOF'
#!/bin/bash
echo "=========================================="
echo "설치된 도구 버전 확인"
echo "=========================================="
echo ""
echo "AWS CLI:"
aws --version
echo ""
echo "kubectl:"
kubectl version --client --short 2>/dev/null || kubectl version --client
echo ""
echo "eksctl:"
eksctl version
echo ""
echo "helm:"
helm version --short
echo ""
echo "docker:"
docker --version
echo ""
echo "mysql:"
mysql --version
echo ""
echo "k9s:"
k9s version --short 2>/dev/null || echo "k9s installed"
echo ""
echo "=========================================="
VEREOF
chmod +x /home/ubuntu/check-versions.sh
chown ubuntu:ubuntu /home/ubuntu/check-versions.sh

# -----------------------------------------------------------------------------
# 소유권 설정
# -----------------------------------------------------------------------------
chown -R ubuntu:ubuntu /home/ubuntu

echo ""
echo "=========================================="
echo "Management Server 초기화 완료!"
echo "완료 시간: $(date)"
echo "=========================================="
echo ""
echo "다음 명령어로 설치된 도구를 확인하세요:"
echo "  ./check-versions.sh"
echo ""
echo "EKS 클러스터 생성:"
echo "  ./create-eks-cluster.sh"
echo ""
echo "RDS 연결:"
echo "  ./db-connect.sh"
echo ""

