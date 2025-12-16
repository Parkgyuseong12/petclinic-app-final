# Terraform 구현 문서 (Implementation Documentation)

이 문서는 AWS 공식 Terraform 문서([AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs))를 바탕으로 현재 코드가 해당 구조로 작성된 이유, 운영 시 주의할 점, 그리고 일부 리소스를 Terraform으로 관리하지 않은 이유를 상세히 설명합니다.

---

## 목차

1. [공통 설계 원칙](#공통-설계-원칙)
2. [Terraform 버전 및 Provider 설정](#terraform-버전-및-provider-설정)
3. [상태 관리 (S3 Backend)](#상태-관리-s3-backend)
4. [네트워크 인프라 (VPC Module)](#네트워크-인프라-vpc-module)
5. [보안 그룹 (Security Groups Module)](#보안-그룹-security-groups-module)
6. [EC2 인스턴스 (EC2 Module)](#ec2-인스턴스-ec2-module)
7. [IAM 역할 및 정책](#iam-역할-및-정책)
8. [RDS 데이터베이스](#rds-데이터베이스)
9. [로컬 값 및 데이터 소스](#로컬-값-및-데이터-소스)
10. [모듈화 구조](#모듈화-구조)
11. [Terraform으로 관리하지 않은 리소스](#terraform으로-관리하지-않은-리소스)
12. [운영 체크리스트](#운영-체크리스트)

---

## 공통 설계 원칙

### 1. 버전 고정 및 호환성

**구현 이유:**
- `versions.tf`에서 Terraform 1.10.0 이상을 요구하는 이유는 S3 Backend의 `use_lockfile` 기능이 Terraform 1.10.0부터 지원되기 때문입니다.
- AWS Provider 5.x를 사용하는 이유는 최신 AWS 리소스 스키마와 기능을 활용하기 위함입니다.

**주의사항:**
- Terraform 버전이 1.10.0 미만이면 `use_lockfile = true` 설정이 작동하지 않습니다.
- AWS Provider 버전을 업그레이드할 때는 [Breaking Changes](https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md)를 확인해야 합니다.

**참고 문서:**
- [Terraform Version Constraints](https://www.terraform.io/docs/language/expressions/version-constraints.html)
- [AWS Provider Versioning](https://registry.terraform.io/providers/hashicorp/aws/latest/docs#versioning)

### 2. 태깅 전략

**구현 이유:**
- `locals.tf`에서 중앙 집중식 태그 관리를 통해 모든 리소스에 일관된 식별자(`Project`, `Environment`, `ManagedBy`)를 제공합니다.
- AWS 비용 관리, 리소스 거버넌스, 자동화 스크립트에서 태그를 활용할 수 있습니다.

**주의사항:**
- 태그는 대소문자를 구분하며, 공백이나 특수문자 사용 시 주의가 필요합니다.
- EKS 클러스터 태그(`kubernetes.io/cluster/${var.eks_cluster_name} = "shared"`)는 Kubernetes가 서브넷을 자동으로 인식하기 위해 필수입니다.

**참고 문서:**
- [AWS Tagging Best Practices](https://docs.aws.amazon.com/general/latest/gr/aws_tagging.html)
- [EKS Subnet Tagging](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)

### 3. 변수 검증 (Variable Validation)

**구현 이유:**
- `variables.tf`에서 `validation` 블록을 사용하여 잘못된 입력값을 사전에 차단합니다.
- 예: `environment` 변수는 `prod`, `staging`, `dev`만 허용하도록 검증합니다.

**주의사항:**
- 검증 실패 시 Terraform은 계획 단계에서 오류를 발생시킵니다.
- 복잡한 검증 로직은 `locals`에서 처리하는 것이 더 유연합니다.

**참고 문서:**
- [Terraform Variable Validation](https://www.terraform.io/docs/language/values/variables.html#custom-validation-rules)

---

## Terraform 버전 및 Provider 설정

### 파일: `versions.tf`

**구현 이유:**
```terraform
terraform {
  required_version = ">= 1.10.0" # S3 use_lockfile 지원
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
```

- **Terraform 1.10.0 이상**: S3 Backend의 `use_lockfile` 기능을 사용하기 위해 필요합니다.
- **AWS Provider 5.x**: 최신 AWS 리소스 스키마와 기능을 활용합니다.

**주의사항:**
- Provider 버전을 `~> 5.0`으로 고정하면 5.x 버전 내에서 자동 업그레이드됩니다.
- Major 버전 업그레이드 시 Breaking Changes를 확인해야 합니다.

**참고 문서:**
- [Terraform Backend Configuration](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [AWS Provider Documentation](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)

---

## 상태 관리 (S3 Backend)

### 파일: `s3_backend.tf`, `backend.tf`

### 1. S3 버킷 생성

**구현 이유:**
```terraform
resource "aws_s3_bucket" "terraform_state" {
  count  = var.tfstate_bucket_name != "" ? 1 : 0
  bucket = var.tfstate_bucket_name
  lifecycle {
    prevent_destroy = true
  }
}
```

- **조건부 생성 (`count`)**: `tfstate_bucket_name`이 비어있으면 버킷을 생성하지 않아 로컬 백엔드로 동작할 수 있습니다.
- **`prevent_destroy = true`**: 실수로 상태 파일이 저장된 버킷을 삭제하는 것을 방지합니다.

**주의사항:**
- `prevent_destroy`가 활성화된 상태에서는 `terraform destroy`로 버킷을 삭제할 수 없습니다.
- 버킷을 삭제하려면 먼저 `prevent_destroy = false`로 변경하고 `terraform apply`를 실행해야 합니다.

**참고 문서:**
- [AWS S3 Bucket Resource](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket)
- [Terraform Lifecycle Meta-Arguments](https://www.terraform.io/docs/language/meta-arguments/lifecycle.html)

### 2. 버전 관리 (Versioning)

**구현 이유:**
```terraform
resource "aws_s3_bucket_versioning" "terraform_state" {
  versioning_configuration {
    status = "Enabled"
  }
}
```

- 상태 파일의 이전 버전을 보존하여 실수로 덮어쓴 경우 복구할 수 있습니다.
- `use_lockfile` 기능을 사용하려면 버전 관리가 활성화되어 있어야 합니다.

**주의사항:**
- 버전 관리가 활성화되면 모든 객체 버전이 저장되어 스토리지 비용이 증가할 수 있습니다.
- `lifecycle_configuration`으로 오래된 버전을 정리할 수 있습니다.

**참고 문서:**
- [AWS S3 Bucket Versioning](https://docs.aws.amazon.com/AmazonS3/latest/userguide/Versioning.html)

### 3. S3 Object Lock vs use_lockfile

**구현 이유:**
- **Object Lock**: `enable_s3_object_lock = false`로 설정했습니다. Object Lock은 버킷 생성 시에만 활성화 가능하며, `use_lockfile`과 함께 사용 시 충돌할 수 있습니다.
- **use_lockfile**: `backend.tf`에서 `use_lockfile = true`로 설정했습니다. Terraform 1.10.0 이상에서 지원하는 파일 기반 락킹 메커니즘으로, DynamoDB 테이블 없이 동시성 제어가 가능합니다.

**주의사항:**
- Object Lock과 `use_lockfile`을 동시에 사용하면 `InvalidRequest: Content-MD5 OR x-amz-checksum- HTTP header is required` 오류가 발생할 수 있습니다.
- `use_lockfile = true`를 사용할 때는 Object Lock을 비활성화해야 합니다.

**참고 문서:**
- [Terraform S3 Backend Configuration](https://www.terraform.io/docs/language/settings/backends/s3.html#use_lockfile)
- [AWS S3 Object Lock](https://docs.aws.amazon.com/AmazonS3/latest/userguide/object-lock.html)

### 4. 암호화 및 공용 접근 차단

**구현 이유:**
```terraform
resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}
```

- **AES256 암호화**: 상태 파일에 민감한 정보가 포함될 수 있으므로 암호화가 필수입니다.
- **공용 접근 차단**: 상태 파일이 공개되지 않도록 모든 공용 접근을 차단합니다.

**주의사항:**
- KMS 키를 사용하려면 `kms_master_key_id`를 지정해야 하며, 추가 비용이 발생할 수 있습니다.
- 버킷 정책에서 특정 IAM 역할/사용자만 접근할 수 있도록 제한하는 것이 권장됩니다.

**참고 문서:**
- [AWS S3 Server-Side Encryption](https://docs.aws.amazon.com/AmazonS3/latest/userguide/serv-side-encryption.html)
- [AWS S3 Public Access Block](https://docs.aws.amazon.com/AmazonS3/latest/userguide/access-control-block-public-access.html)

### 5. DynamoDB 테이블을 사용하지 않는 이유

**구현 이유:**
- DynamoDB 테이블은 `use_lockfile = true`를 사용할 때 필요하지 않습니다.
- `use_lockfile`은 S3의 파일 기반 락킹 메커니즘을 사용하므로 추가 리소스가 필요 없습니다.

**주의사항:**
- `use_lockfile = false`로 설정하면 DynamoDB 테이블이 필요합니다.
- 팀 규모가 크고 동시 작업이 많은 경우 DynamoDB 테이블을 사용하는 것이 더 안정적일 수 있습니다.

**참고 문서:**
- [Terraform S3 Backend Locking](https://www.terraform.io/docs/language/settings/backends/s3.html#dynamodb-state-locking)

---

## 네트워크 인프라 (VPC Module)

### 파일: `modules/vpc/main.tf`

### 1. VPC 구성

**구현 이유:**
```terraform
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
}
```

- **DNS 지원 활성화**: EKS 클러스터와 RDS 엔드포인트를 위한 DNS 해석이 필요합니다.
- **CIDR 블록**: `10.0.0.0/16`을 사용하여 충분한 IP 주소 공간을 확보합니다.

**주의사항:**
- VPC CIDR 블록은 변경할 수 없으므로 초기 설계가 중요합니다.
- 다른 VPC나 온프레미스 네트워크와 겹치지 않도록 주의해야 합니다.

**참고 문서:**
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)

### 2. 서브넷 분리 전략

**구현 이유:**
- **Public Subnets (2개)**: Bastion Host, NAT Gateway, ALB를 위한 서브넷입니다.
- **App Private Subnets (2개)**: Management Server, EKS Nodes, Application Pods를 위한 서브넷입니다.
- **DB Private Subnets (2개)**: RDS 데이터베이스를 위한 서브넷입니다.

**주의사항:**
- 각 서브넷은 다른 Availability Zone에 배치되어 고가용성을 보장합니다.
- 서브넷 CIDR 블록은 VPC CIDR 내에서 겹치지 않아야 합니다.

**참고 문서:**
- [AWS VPC Subnets](https://docs.aws.amazon.com/vpc/latest/userguide/configure-subnets.html)

### 3. NAT Gateway 고가용성 (HA)

**구현 이유:**
```terraform
resource "aws_nat_gateway" "main" {
  count = length(var.availability_zones)
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
}
```

- **각 AZ별 NAT Gateway**: Zonal Isolation을 보장하여 한 AZ의 NAT Gateway가 장애가 나도 다른 AZ의 서브넷은 정상 동작합니다.
- **Elastic IP**: NAT Gateway는 정적 IP 주소가 필요하므로 EIP를 할당합니다.

**주의사항:**
- NAT Gateway는 시간당 및 데이터 전송 비용이 발생합니다. 비용 최적화가 필요하면 NAT Gateway 수를 줄이거나 NAT Instance를 사용할 수 있습니다.
- 각 Private Subnet의 Route Table이 같은 AZ의 NAT Gateway를 가리키도록 설정해야 합니다.

**참고 문서:**
- [AWS NAT Gateway](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-nat-gateway.html)
- [AWS High Availability Best Practices](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/high-availability.html)

### 4. Route Table 및 Zonal Isolation

**구현 이유:**
```terraform
resource "aws_route_table" "private_app" {
  count = length(var.availability_zones)
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main[count.index].id
  }
}
```

- **각 AZ별 Route Table**: App Private Subnet과 DB Private Subnet은 각각 별도의 Route Table을 사용하여 Zonal Isolation을 보장합니다.
- **같은 AZ의 NAT Gateway 사용**: 각 Private Subnet은 자신과 같은 AZ에 있는 NAT Gateway를 사용합니다.

**주의사항:**
- Route Table Association은 서브넷과 Route Table의 인덱스가 일치해야 합니다.
- DB Private Subnet에 NAT Gateway 경로를 추가한 이유는 패치/백업 트래픽을 허용하기 위함입니다. 더 엄격한 격리가 필요하면 이 경로를 제거하거나 VPC Endpoint를 사용해야 합니다.

**참고 문서:**
- [AWS Route Tables](https://docs.aws.amazon.com/vpc/latest/userguide/VPC_Route_Tables.html)
- [AWS VPC Endpoints](https://docs.aws.amazon.com/vpc/latest/privatelink/vpc-endpoints.html)

### 5. EKS 서브넷 태깅

**구현 이유:**
```terraform
public_subnet_tags = merge(local.subnet_common_tags, {
  "kubernetes.io/role/elb" = "1"
})

app_private_subnet_tags = merge(local.subnet_common_tags, {
  "kubernetes.io/role/internal-elb" = "1"
  "karpenter.sh/discovery"          = var.eks_cluster_name
})
```

- **Kubernetes 태그**: EKS 클러스터가 서브넷을 자동으로 인식하고 사용할 수 있도록 태그를 설정합니다.
- **Karpenter 태그**: Karpenter가 노드를 자동으로 프로비저닝할 서브넷을 식별합니다.

**주의사항:**
- 태그 키는 정확히 일치해야 하며, 대소문자를 구분합니다.
- EKS 클러스터 생성 전에 태그가 설정되어 있어야 합니다.

**참고 문서:**
- [EKS Subnet Requirements](https://docs.aws.amazon.com/eks/latest/userguide/network_reqs.html)
- [Karpenter Discovery Tags](https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/#discovery-tags)

---

## 보안 그룹 (Security Groups Module)

### 파일: `modules/security-groups/main.tf`

### 1. 최소 권한 원칙

**구현 이유:**
```terraform
resource "aws_security_group" "bastion" {
  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }
}
```

- **Bastion Host**: 특정 IP 주소에서만 SSH 접근을 허용합니다.
- **Management Server**: Bastion Host의 Security Group에서만 SSH 접근을 허용합니다.
- **RDS**: Management Server Security Group과 App Private Subnet CIDR에서만 MySQL 접근을 허용합니다.

**주의사항:**
- `allowed_ssh_cidr`의 기본값이 `0.0.0.0/0`이므로 프로덕션 배포 전 반드시 제한된 CIDR로 변경해야 합니다.
- Security Group 규칙은 명시적으로 `description`을 포함하여 유지보수성을 높입니다.

**참고 문서:**
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/security-groups.html)
- [AWS Security Best Practices](https://docs.aws.amazon.com/securityhub/latest/userguide/securityhub-standards-fsbp-controls.html)

### 2. Dynamic Block을 사용한 CIDR 기반 접근 제어

**구현 이유:**
```terraform
dynamic "ingress" {
  for_each = var.app_private_subnet_cidrs
  content {
    description = "MySQL from App Private Subnet ${ingress.key + 1}"
    from_port   = 3306
    to_port     = 3306
    protocol    = "tcp"
    cidr_blocks = [ingress.value]
  }
}
```

- **EKS Pod 접근**: EKS Pod가 RDS에 접근할 수 있도록 App Private Subnet CIDR을 허용합니다.
- **동적 규칙 생성**: 서브넷 수가 변경되어도 자동으로 규칙이 생성됩니다.

**주의사항:**
- CIDR 기반 접근 제어는 Security Group 기반 접근 제어보다 덜 세밀합니다.
- 가능하면 Security Group 기반 접근 제어를 사용하는 것이 권장됩니다.

**참고 문서:**
- [Terraform Dynamic Blocks](https://www.terraform.io/docs/language/expressions/dynamic-blocks.html)

### 3. EKS Cluster Security Group (참조용)

**구현 이유:**
```terraform
resource "aws_security_group" "eks_cluster" {
  description = "Security group for EKS Cluster (created for future use)"
  # ...
}
```

- **참조용 생성**: EKS 클러스터는 `eksctl`로 생성되지만, Terraform에서 생성한 Security Group을 참조할 수 있도록 미리 생성합니다.
- **실제 사용**: `eksctl`에서 `--node-security-groups` 옵션으로 이 Security Group을 지정할 수 있습니다.

**주의사항:**
- EKS 클러스터의 실제 Security Group 규칙은 `eksctl` 또는 Kubernetes Network Policies로 관리됩니다.
- 이 Security Group은 기본 규칙만 포함하므로, 실제 운영 시 추가 규칙이 필요할 수 있습니다.

**참고 문서:**
- [EKS Security Groups](https://docs.aws.amazon.com/eks/latest/userguide/sec-group-reqs.html)

---

## EC2 인스턴스 (EC2 Module)

### 파일: `modules/ec2/main.tf`

### 1. SSH 키 쌍 생성

**구현 이유:**
```terraform
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = var.key_name
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${var.key_output_path}/${var.key_name}.pem"
  file_permission = "0400"
}
```

- **자동 키 생성**: Terraform이 SSH 키 쌍을 자동으로 생성하여 수동 작업을 줄입니다.
- **로컬 저장**: Private Key를 로컬에 저장하여 인스턴스 접근에 사용합니다.

**주의사항:**
- Private Key는 `.gitignore`에 포함되어 Git에 커밋되지 않도록 해야 합니다.
- Private Key 파일 권한은 `0400`으로 설정하여 다른 사용자가 읽을 수 없도록 합니다.
- CI/CD 환경에서는 Private Key를 안전하게 관리해야 합니다 (예: AWS Secrets Manager, HashiCorp Vault).

**참고 문서:**
- [AWS EC2 Key Pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
- [TLS Provider](https://registry.terraform.io/providers/hashicorp/tls/latest/docs)

### 2. AMI 동적 조회

**구현 이유:**
```terraform
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}
```

- **최신 AMI 사용**: `most_recent = true`로 최신 Ubuntu 22.04 LTS AMI를 자동으로 선택합니다.
- **보안 업데이트**: 최신 AMI를 사용하여 보안 패치가 자동으로 반영됩니다.

**주의사항:**
- AMI ID는 리전별로 다르므로 `data` 소스를 사용하는 것이 권장됩니다.
- 특정 AMI 버전을 고정하려면 `ec2_ami_id` 변수를 사용할 수 있습니다.

**참고 문서:**
- [AWS AMI Data Source](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/ami)

### 3. IMDSv2 강제

**구현 이유:**
```terraform
metadata_options {
  http_endpoint               = "enabled"
  http_tokens                 = "required" # IMDSv2 강제
  http_put_response_hop_limit = 1 # Bastion, 2 # Management Server
}
```

- **보안 강화**: IMDSv1은 SSRF 공격에 취약하므로 IMDSv2를 강제합니다.
- **Hop Limit**: Management Server는 Docker 컨테이너에서 IMDS에 접근할 수 있도록 `hop_limit = 2`로 설정합니다.

**주의사항:**
- IMDSv2를 강제하면 기존 스크립트가 동작하지 않을 수 있습니다.
- 컨테이너 환경에서는 `hop_limit`을 적절히 설정해야 합니다.

**참고 문서:**
- [AWS IMDSv2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-metadata.html#instance-metadata-v2-how-it-works)

### 4. 볼륨 암호화

**구현 이유:**
```terraform
root_block_device {
  volume_type           = "gp3"
  volume_size           = var.bastion_volume_size
  encrypted             = true
  delete_on_termination = true
}
```

- **암호화**: 민감한 데이터가 저장될 수 있으므로 볼륨 암호화를 활성화합니다.
- **gp3 스토리지**: gp3는 gp2보다 저렴하고 성능이 우수합니다.

**주의사항:**
- 기본 암호화는 AWS 관리형 키를 사용합니다. KMS 키를 사용하려면 `kms_key_id`를 지정해야 합니다.
- `delete_on_termination = true`로 설정하면 인스턴스 종료 시 볼륨이 자동으로 삭제됩니다.

**참고 문서:**
- [AWS EBS Encryption](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/EBSEncryption.html)
- [AWS EBS Volume Types](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ebs-volume-types.html)

### 5. User Data 스크립트

**구현 이유:**
- **Management Server 초기화**: `user_data_mgmt.sh`를 통해 AWS CLI, kubectl, eksctl, Helm, Docker 등을 자동 설치합니다.
- **외부 파일 사용**: `file()` 함수로 외부 스크립트 파일을 읽어 User Data로 전달합니다.

**주의사항:**
- User Data 스크립트는 Base64로 인코딩되어 전달되므로 크기 제한(16KB)이 있습니다.
- 스크립트는 인터넷에 의존하므로 폐쇄망 환경에서는 미러 저장소를 사용하거나 AMI를 미리 커스터마이즈해야 합니다.

**참고 문서:**
- [AWS EC2 User Data](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/user-data.html)

---

## IAM 역할 및 정책

### 파일: `iam.tf`

### 1. IAM 역할 및 Instance Profile

**구현 이유:**
```terraform
resource "aws_iam_role" "mgmt_server" {
  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
    }]
  })
}

resource "aws_iam_instance_profile" "mgmt_server" {
  role = aws_iam_role.mgmt_server.name
}
```

- **Instance Profile**: EC2 인스턴스에 IAM 역할을 연결하기 위해 Instance Profile이 필요합니다.
- **Assume Role**: EC2 서비스가 역할을 가정할 수 있도록 Trust Policy를 설정합니다.

**주의사항:**
- Instance Profile은 인스턴스 생성 시에만 연결할 수 있습니다. 이후 변경하려면 인스턴스를 재생성해야 합니다.
- IAM 역할 이름은 전역적으로 고유해야 합니다.

**참고 문서:**
- [AWS IAM Roles for EC2](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/iam-roles-for-amazon-ec2.html)

### 2. AdministratorAccess 정책

**구현 이유:**
```terraform
resource "aws_iam_role_policy_attachment" "mgmt_admin" {
  role       = aws_iam_role.mgmt_server.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}
```

- **초기 구축 단순화**: EKS 클러스터 생성 및 관리에 광범위한 권한이 필요하므로 초기에는 AdministratorAccess를 부여합니다.

**주의사항:**
- **프로덕션 환경에서는 최소 권한 원칙을 적용해야 합니다.** 다음 정책만 포함하는 커스텀 정책을 생성하는 것이 권장됩니다:
  - `eks:*` (EKS 클러스터 관리)
  - `ec2:*` (EC2 인스턴스 관리)
  - `iam:*` (IAM 역할/정책 관리, 제한적)
  - `ecr:*` (컨테이너 이미지 관리)
  - `ssm:*` (Systems Manager 접근)

**참고 문서:**
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)
- [AWS EKS IAM Roles](https://docs.aws.amazon.com/eks/latest/userguide/service-roles.html)

---

## RDS 데이터베이스

### 파일: `rds.tf`

### 1. DB Subnet Group

**구현 이유:**
```terraform
resource "aws_db_subnet_group" "main" {
  name        = "${var.project_name}-db-subnet-group"
  subnet_ids  = module.vpc.db_private_subnet_ids
}
```

- **Multi-AZ 지원**: RDS가 여러 AZ에 배치될 수 있도록 DB Private Subnet 2개를 지정합니다.
- **네트워크 격리**: DB 서브넷은 Public Subnet과 분리되어 보안을 강화합니다.

**주의사항:**
- DB Subnet Group에는 최소 2개의 서브넷이 필요하며, 서로 다른 AZ에 있어야 합니다.
- 서브넷 CIDR 블록은 충분한 IP 주소를 제공해야 합니다.

**참고 문서:**
- [AWS RDS DB Subnet Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_VPC.WorkingWithRDSInstanceinaVPC.html#USER_VPC.Subnets)

### 2. DB Parameter Group

**구현 이유:**
```terraform
resource "aws_db_parameter_group" "main" {
  family = "mysql8.0"
  parameter {
    name  = "character_set_server"
    value = "utf8mb4"
  }
}
```

- **문자 인코딩**: UTF-8MB4를 사용하여 이모지 및 다국어 문자를 지원합니다.
- **성능 최적화**: `max_connections`, `slow_query_log` 등을 설정하여 모니터링 및 성능 튜닝을 용이하게 합니다.

**주의사항:**
- 일부 파라미터는 `apply_method = "pending-reboot"`로 설정되어 있어 재부팅 후에만 적용됩니다.
- 파라미터 변경은 다운타임을 유발할 수 있으므로 주의가 필요합니다.

**참고 문서:**
- [AWS RDS Parameter Groups](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithParamGroups.html)

### 3. RDS 인스턴스 설정

**구현 이유:**
```terraform
resource "aws_db_instance" "main" {
  multi_az               = var.db_multi_az
  backup_retention_period = var.db_backup_retention_period
  deletion_protection    = false
  skip_final_snapshot    = true
  storage_encrypted       = true
}
```

- **Multi-AZ**: 고가용성을 위해 Multi-AZ 배포를 지원하지만, 비용 절감을 위해 기본값은 `false`입니다.
- **백업**: `backup_retention_period`로 자동 백업 보관 기간을 설정합니다.
- **암호화**: 스토리지 암호화를 활성화하여 데이터 보안을 강화합니다.

**주의사항:**
- **프로덕션 환경에서는 다음 설정을 변경해야 합니다:**
  - `multi_az = true`
  - `deletion_protection = true`
  - `skip_final_snapshot = false`
- `skip_final_snapshot = true`로 설정하면 인스턴스 삭제 시 최종 스냅샷이 생성되지 않습니다.

**참고 문서:**
- [AWS RDS Multi-AZ](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Concepts.MultiAZ.html)
- [AWS RDS Backup and Restore](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_WorkingWithAutomatedBackups.html)

### 4. SSM Parameter Store를 사용한 비밀 관리

**구현 이유:**
```terraform
resource "aws_ssm_parameter" "rds_password" {
  name  = "/${var.project_name}/${var.environment}/rds/password"
  type  = "SecureString"
  value = var.db_password
}
```

- **비밀 저장**: RDS 엔드포인트, 사용자 이름, 비밀번호를 SSM Parameter Store에 저장하여 User Data나 스크립트에서 참조할 수 있습니다.
- **비용 절감**: AWS Secrets Manager 대신 SSM Parameter Store를 사용하여 비용을 절감합니다.

**주의사항:**
- SSM Parameter Store는 자동 비밀번호 회전을 지원하지 않습니다. 비밀번호 회전이 필요한 경우 AWS Secrets Manager를 사용해야 합니다.
- `SecureString` 타입은 KMS 키를 사용하여 암호화되므로 추가 비용이 발생할 수 있습니다.

**참고 문서:**
- [AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html)
- [AWS Secrets Manager](https://docs.aws.amazon.com/secretsmanager/latest/userguide/intro.html)

### 5. SQL 초기화 파일 전송 (null_resource)

**구현 이유:**
```terraform
resource "null_resource" "copy_sql_to_mgmt" {
  provisioner "local-exec" {
    command = <<-EOT
      echo "SQL 파일 복사 가이드"
      # ...
    EOT
  }
}
```

- **수동 초기화**: RDS 초기 스키마 로드는 사람이 Bastion/Management Server에서 실행하도록 의도했습니다.
- **데이터베이스 변경 분리**: 데이터베이스 변경을 애플리케이션 릴리스 절차와 분리합니다.

**주의사항:**
- `null_resource`의 `provisioner`는 Terraform의 권장되지 않는 기능입니다. 가능하면 `local-exec` 대신 다른 방법을 사용하는 것이 좋습니다.
- 실제 파일 전송은 `scp` 또는 S3를 통해 수동으로 수행해야 합니다.

**참고 문서:**
- [Terraform null_resource](https://registry.terraform.io/providers/hashicorp/null/latest/docs/resources/resource)
- [Terraform Provisioners](https://www.terraform.io/docs/language/resources/provisioners/syntax.html)

---

## 로컬 값 및 데이터 소스

### 파일: `locals.tf`, `data.tf`

### 1. 로컬 값 (Locals)

**구현 이유:**
```terraform
locals {
  common_tags = {
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  }
  name_prefix = "${var.project_name}-${var.environment}"
}
```

- **중앙 집중식 관리**: 공통 태그와 이름 접두사를 한 곳에서 관리하여 일관성을 보장합니다.
- **재사용성**: 여러 리소스에서 동일한 값을 재사용할 수 있습니다.

**주의사항:**
- `locals`는 모듈 내에서만 접근 가능합니다. 다른 모듈에서 사용하려면 `output`으로 노출해야 합니다.

**참고 문서:**
- [Terraform Locals](https://www.terraform.io/docs/language/values/locals.html)

### 2. 데이터 소스 (Data Sources)

**구현 이유:**
```terraform
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]
}
```

- **동적 값 조회**: 현재 AWS 계정 ID, 리전, 최신 AMI ID 등을 동적으로 조회합니다.
- **하드코딩 방지**: 리전이나 계정 ID를 하드코딩하지 않고 동적으로 가져옵니다.

**주의사항:**
- `data` 소스는 `terraform plan` 또는 `apply` 시점에 실행되므로, 실행 시간이 길어질 수 있습니다.
- `data` 소스는 외부 리소스에 의존하므로, 해당 리소스가 존재하지 않으면 오류가 발생합니다.

**참고 문서:**
- [Terraform Data Sources](https://www.terraform.io/docs/language/data-sources/index.html)

---

## 모듈화 구조

### 모듈 디렉토리 구조

```
modules/
├── vpc/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── README.md
├── security-groups/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
└── ec2/
    ├── main.tf
    ├── variables.tf
    └── outputs.tf
```

### 모듈화의 장점

**구현 이유:**
1. **재사용성**: 모듈을 다른 프로젝트나 환경에서 재사용할 수 있습니다.
2. **유지보수성**: 각 모듈이 독립적으로 관리되어 코드 변경이 용이합니다.
3. **테스트 용이성**: 모듈 단위로 테스트할 수 있습니다.
4. **가독성**: 루트 모듈이 간결해져 전체 구조를 파악하기 쉽습니다.

**주의사항:**
- 모듈 간 의존성을 명확히 해야 합니다 (예: VPC 모듈 → Security Groups 모듈 → EC2 모듈).
- 모듈의 `outputs`를 통해 필요한 값만 노출해야 합니다.

**참고 문서:**
- [Terraform Modules](https://www.terraform.io/docs/language/modules/index.html)
- [AWS Terraform Module Best Practices](https://docs.aws.amazon.com/prescriptive-guidance/latest/terraform-aws-provider-best-practices/structure.html)

---

## Terraform으로 관리하지 않은 리소스

### 1. EKS 클러스터

**구현하지 않은 이유:**
- **eksctl 사용**: EKS 클러스터는 Management Server에서 `eksctl`을 사용하여 생성하도록 설계했습니다.
- **수명 주기 분리**: Management Server의 수명 주기와 EKS 클러스터의 수명 주기를 분리하여 독립적으로 관리할 수 있습니다.
- **빠른 PoC**: 초기 PoC 단계에서 빠르게 클러스터를 생성/삭제할 수 있습니다.

**주의사항:**
- Terraform으로 EKS 클러스터를 관리하려면 `aws_eks_cluster` 리소스를 사용할 수 있습니다.
- `eksctl`과 Terraform을 혼용하면 상태 불일치가 발생할 수 있으므로 주의가 필요합니다.

**참고 문서:**
- [AWS EKS Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/eks_cluster)
- [eksctl Documentation](https://eksctl.io/)

### 2. 데이터베이스 스키마 및 데이터 마이그레이션

**구현하지 않은 이유:**
- **애플리케이션 릴리스와 분리**: 데이터베이스 스키마 변경은 애플리케이션 릴리스 파이프라인(예: Liquibase, Flyway)과 분리하여 관리합니다.
- **Terraform의 역할**: Terraform은 인프라 전용으로 유지하고, 데이터 변경은 CI/CD나 DBA 절차로 관리합니다.

**주의사항:**
- 데이터베이스 스키마를 Terraform으로 관리하려면 `null_resource`와 `local-exec` provisioner를 사용할 수 있지만, 권장되지 않습니다.

**참고 문서:**
- [Terraform Best Practices: Data Management](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### 3. 인프라 모니터링 및 로깅 리소스

**구현하지 않은 이유:**
- **팀 표준 스택**: CloudWatch 대시보드, 알람, 로그 수집은 팀 표준 스택(Grafana/Prometheus 또는 별도 계정)에 맞춰 다른 코드베이스에서 관리합니다.
- **관심사 분리**: 인프라 프로비저닝과 모니터링 설정을 분리하여 관리합니다.

**주의사항:**
- 모니터링 리소스를 Terraform으로 관리하려면 `aws_cloudwatch_dashboard`, `aws_cloudwatch_metric_alarm` 등을 사용할 수 있습니다.

**참고 문서:**
- [AWS CloudWatch Terraform Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_dashboard)

### 4. Application Load Balancer (ALB)

**구현하지 않은 이유:**
- **EKS Ingress**: ALB는 EKS 클러스터의 Ingress Controller (예: AWS Load Balancer Controller)를 통해 자동으로 생성됩니다.
- **Kubernetes 리소스**: ALB는 Kubernetes Ingress 리소스로 관리되므로 Terraform에서 별도로 생성할 필요가 없습니다.

**주의사항:**
- ALB를 Terraform으로 관리하려면 `aws_lb` 리소스를 사용할 수 있습니다.
- EKS와 함께 사용할 때는 ALB가 EKS 서브넷 태그를 인식할 수 있도록 설정해야 합니다.

**참고 문서:**
- [AWS Load Balancer Controller](https://kubernetes-sigs.github.io/aws-load-balancer-controller/)

### 5. DynamoDB 테이블

**구현하지 않은 이유:**
- **S3 use_lockfile 사용**: Terraform 상태 파일 락킹을 위해 DynamoDB 테이블 대신 S3의 `use_lockfile` 기능을 사용합니다.
- **비용 절감**: DynamoDB 테이블을 생성하지 않아 비용을 절감합니다.

**주의사항:**
- `use_lockfile = false`로 설정하면 DynamoDB 테이블이 필요합니다.
- 팀 규모가 크고 동시 작업이 많은 경우 DynamoDB 테이블을 사용하는 것이 더 안정적일 수 있습니다.

**참고 문서:**
- [Terraform S3 Backend Locking](https://www.terraform.io/docs/language/settings/backends/s3.html#dynamodb-state-locking)

---

## 운영 체크리스트

### 배포 전 확인 사항

- [ ] `allowed_ssh_cidr`를 제한된 CIDR로 변경 (기본값 `0.0.0.0/0`은 보안 위험)
- [ ] `tfstate_bucket_name`이 올바르게 설정되어 있는지 확인
- [ ] `db_multi_az = true` (프로덕션 환경)
- [ ] `deletion_protection = true` (RDS, 프로덕션 환경)
- [ ] `skip_final_snapshot = false` (RDS, 프로덕션 환경)
- [ ] IAM 역할의 AdministratorAccess 정책을 최소 권한 정책으로 교체
- [ ] `db_password`가 강력한 비밀번호로 설정되어 있는지 확인
- [ ] S3 버킷 정책에서 특정 IAM 역할/사용자만 접근할 수 있도록 제한

### 배포 후 확인 사항

- [ ] Bastion Host에 SSH 접속 테스트
- [ ] Management Server에 Bastion을 통한 SSH 접속 테스트
- [ ] RDS 엔드포인트가 SSM Parameter Store에 저장되었는지 확인
- [ ] Management Server에서 AWS CLI, kubectl, eksctl이 정상 설치되었는지 확인
- [ ] NAT Gateway가 각 AZ에서 정상 동작하는지 확인
- [ ] Security Group 규칙이 올바르게 설정되었는지 확인

### 유지보수 시 주의사항

- [ ] Terraform 버전 업그레이드 시 Breaking Changes 확인
- [ ] AWS Provider 버전 업그레이드 시 [CHANGELOG](https://github.com/hashicorp/terraform-provider-aws/blob/main/CHANGELOG.md) 확인
- [ ] S3 버킷의 `prevent_destroy`를 변경하려면 먼저 `terraform apply` 실행
- [ ] RDS 파라미터 변경 시 다운타임 가능성 확인
- [ ] 서브넷 CIDR 블록은 변경할 수 없으므로 초기 설계가 중요

### 비용 최적화

- [ ] NAT Gateway 비용이 높으면 NAT Instance로 대체 검토
- [ ] 사용하지 않는 리소스 정리 (예: 테스트 환경)
- [ ] RDS `multi_az = false`로 설정하여 비용 절감 (개발 환경)
- [ ] S3 버킷의 오래된 버전 정리 (Lifecycle Configuration)

---

## 참고 문서

### AWS 공식 문서
- [AWS VPC Documentation](https://docs.aws.amazon.com/vpc/latest/userguide/what-is-amazon-vpc.html)
- [AWS EKS Documentation](https://docs.aws.amazon.com/eks/latest/userguide/what-is-eks.html)
- [AWS RDS Documentation](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/Welcome.html)
- [AWS IAM Best Practices](https://docs.aws.amazon.com/IAM/latest/UserGuide/best-practices.html)

### Terraform 공식 문서
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Terraform Modules](https://www.terraform.io/docs/language/modules/index.html)
- [Terraform Backend Configuration](https://www.terraform.io/docs/language/settings/backends/s3.html)
- [Terraform Best Practices](https://www.terraform.io/docs/cloud/guides/recommended-practices/index.html)

### AWS Well-Architected Framework
- [Reliability Pillar](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/welcome.html)
- [Security Pillar](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/welcome.html)
- [Cost Optimization Pillar](https://docs.aws.amazon.com/wellarchitected/latest/cost-optimization-pillar/welcome.html)

---

## 변경 이력

- **2024-XX-XX**: 초기 문서 작성
- **2024-XX-XX**: 모듈화 구조 추가
- **2024-XX-XX**: S3 Backend use_lockfile 설명 추가

---

**문서 작성자**: Infrastructure Team  
**최종 업데이트**: 2024년  
**문서 버전**: 1.0
