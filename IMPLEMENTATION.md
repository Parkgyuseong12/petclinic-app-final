# Terraform 구현 의도 및 운영 주의사항

이 문서는 AWS 공식 Terraform 문서를 바탕으로 현재 코드가 해당 구조로 작성된 이유, 운영 시 주의할 점, 그리고 일부 리소스를 Terraform으로 관리하지 않은 이유를 설명합니다. 각 항목은 관련 Terraform 리소스 정의와 매핑되어 있습니다.

## 공통 설계 원칙

- **버전 고정 및 지역 태깅**: `versions.tf`에서 Terraform 1.10.0 이상과 AWS Provider 5.x를 요구하여 S3 Object Lock 기반 락킹과 최신 리소스 스키마를 사용합니다. 기본 태그는 모든 리소스에 일관된 식별자(`Project`, `Environment`, `ManagedBy`)를 제공해 비용/거버넌스 보고를 단순화합니다.
- **불필요한 재생성 방지**: CIDR, 인스턴스 타입처럼 빈번히 바뀌지 않는 값은 변수화하고, `prevent_destroy`(S3)와 같이 실수로 인프라를 제거하지 않도록 방어적 설정을 넣었습니다.

## 상태 관리(S3 Backend)

- **Object Lock & 락파일**: `s3_backend.tf`는 S3 Object Lock을 기본 활성화하고 Terraform 1.10+의 `use_lockfile`을 전제로 합니다. DynamoDB 락 테이블 대신 S3의 파일 기반 락킹을 사용해 관리 리소스를 최소화하며, Object Lock으로 실수 삭제/덮어쓰기를 방지합니다. Object Lock은 **버킷 생성 시에만 설정 가능**하므로 기존 버킷을 재사용하지 않고 새 버킷을 만들도록 `count` 조건을 둡니다.
- **암호화와 공용 차단**: AES256 SSE와 Public Access Block을 강제해 상태 파일 노출 위험을 줄입니다. 수명 주기 규칙으로 이전 버전 정리를 하지만, Object Lock 보존 기간을 존중하도록 주의합니다.
- **미구현 리소스**: DynamoDB 테이블을 Terraform으로 만들지 않은 이유는 S3 락파일 기능으로 동시성 제어를 충족했기 때문입니다. 추가 테이블은 운영팀이 필요 시 별도 프로비저닝하도록 분리했습니다.

## 네트워크(VPC, 서브넷, 라우팅)

- **AZ 분리 설계**: `vpc.tf`는 퍼블릭/프라이빗(앱)/프라이빗(DB) 서브넷을 AZ별로 1개씩 생성합니다. 이는 AWS VPC 모범 사례(멀티 AZ, 계층 분리)에 맞춰 장애 도메인을 축소하고, EKS/ALB 태그를 미리 지정해 향후 클러스터/로드밸런서 연동을 수월하게 합니다.
- **NAT 고가용성**: 각 AZ에 NAT Gateway와 대응 EIP를 배치해 Zonal Isolation을 유지합니다. 프라이빗 앱/DB 라우트 테이블이 동일 AZ의 NAT를 바라보도록 count 인덱스를 정렬했습니다. 비용 최적화가 필요하면 `availability_zones`를 1개로 줄이거나 NAT 수를 조정해야 합니다.
- **DB 라우팅 예외**: DB 서브넷에도 0.0.0.0/0 -> NAT 규칙을 두어 패치/백업 트래픽을 허용합니다. 인터넷 격리가 더 엄격해야 한다면 해당 라우트를 제거하거나 VPC 엔드포인트를 대체로 사용해야 합니다.

## 보안 그룹

- **최소 권한**: `security_groups.tf`에서 바스천은 지정 CIDR만 22번 포트를 허용하고, 관리 서버는 바스천 SG에서만 SSH를 받습니다. RDS는 관리 서버 SG와 앱 프라이빗 CIDR만 3306을 허용해 EKS 파드 대비 여지를 둡니다.
- **주의**: `allowed_ssh_cidr` 기본값은 0.0.0.0/0이므로 프로덕션 배포 전 반드시 제한 CIDR로 변경해야 합니다. 또한 EKS 클러스터 SG는 참고용으로만 생성되므로 실제 워커 노드 SG/룰은 eksctl 또는 후속 Terraform에 맞게 재검토해야 합니다.

## EC2 (Bastion & Management Server)

- **AMI 동적 조회**: `ec2.tf`의 `data "aws_ami"`는 Canonical의 최신 Ubuntu 22.04를 선택해 보안 업데이트를 자동 반영합니다. 필요 시 `ec2_ami_id`로 고정 버전을 주입할 수 있습니다.
- **SSH 키 관리**: TLS provider로 RSA 키를 생성하고 `local_file`로 저장해 배포 시점에 키 유실을 방지합니다. 키 파일은 로컬 경로(`mykey/…`)에 저장되므로 CI 환경에서 노출되지 않도록 .gitignore 관리가 필요합니다.
- **보안 옵션**: IMDSv2 강제(`http_tokens = "required"`)와 루트 볼륨 암호화를 통해 EC2 모범 사례를 준수합니다. 관리 서버는 IMDS 홉 리밋을 2로 설정해 컨테이너 워크로드가 IMDS에 접근할 수 있게 합니다.
- **User Data 스크립트**: `user_data_mgmt.sh`를 템플릿으로 주입해 AWS CLI, kubectl, eksctl, Helm, Docker 등을 설치합니다. 이는 관리 서버가 EKS 생성과 CI/CD 배포 도구 실행의 단일 진입점이 되도록 하기 위함입니다. 스크립트는 인터넷에 의존하므로 폐쇄망에서는 미러 저장소를 사용하거나 AMI를 미리 커스터마이즈해야 합니다.

## IAM

- **역할 단순화**: `iam.tf`는 관리 서버에 AdministratorAccess를 부여해 초기 구축을 단순화했습니다. AWS 공식 문서에서는 최소 권한을 권장하므로, 운영 전에는 eksctl/ECR/SSM/RDS 등에 필요한 액션만 포함한 커스텀 정책으로 교체해야 합니다.
- **인스턴스 프로파일 사용**: EC2에 역할을 직접 부여하기 위해 인스턴스 프로파일을 생성했습니다. 이는 키 기반 자격증명 배포를 피하고, STS 자격 증명을 사용하도록 하기 위함입니다.

## RDS

- **DB 서브넷/파라미터 그룹 분리**: `rds.tf`에서 별도 서브넷 그룹과 파라미터 그룹을 정의해 네트워크 및 설정을 명시적으로 관리합니다. UTF-8MB4 설정과 슬로우 쿼리 로깅은 애플리케이션 특성에 맞춘 기본값입니다.
- **가용성/복구 선택지**: `db_multi_az`, `backup_retention_period`, `skip_final_snapshot` 등이 변수화되어 있어 비용/복구 정책을 환경에 맞게 조정할 수 있습니다. 프로덕션에서는 `multi_az=true`, `skip_final_snapshot=false`, `deletion_protection=true`로 변경해야 합니다.
- **비밀 관리**: RDS 엔드포인트/계정 정보를 SSM Parameter Store(`SecureString`)에 저장해 User Data나 스크립트에서 참조합니다. AWS Secrets Manager를 사용하지 않은 것은 비용 절감과 단순성을 우선한 결정이며, 회전이 필요한 경우 Secrets Manager로 이전해야 합니다.
- **수동 SQL 초기화**: `null_resource.copy_sql_to_mgmt`는 파일 전송 가이드를 출력하는 용도입니다. RDS 초기 스키마 로드는 사람이 Bastion/Management Server에서 실행하도록 의도했으며, 이는 데이터베이스 변경을 애플리케이션 릴리스 절차와 분리하기 위함입니다.

## 출력 및 운영 가이드

- `outputs.tf`는 접속 명령과 eksctl 명령 샘플을 함께 출력해 운영자가 필요한 정보를 한 곳에서 확인하도록 합니다. 출력 문자열에 민감 정보는 포함하지 않으므로 state 노출 시에도 직접적인 자격 증명 유출을 피합니다.

## Terraform으로 관리하지 않은 항목

- **EKS 클러스터**: 현재 클러스터 생성은 `user_data_mgmt.sh` 내 `eksctl` 스크립트를 통해 수행하도록 설계했습니다. 이는 초기 PoC 단계에서 빠르게 생성/삭제하기 위함이며, Terraform으로 옮길 경우 관리 서버의 수명 주기와 클러스터 수명 주기가 강하게 묶이는 것을 피하려는 의도입니다.
- **DB 스키마/데이터 마이그레이션**: 애플리케이션 릴리스 파이프라인(예: Liquibase, Flyway)과 분리하기 위해 Terraform에 포함하지 않았습니다. Terraform은 인프라 전용으로 유지하고, 데이터 변경은 CI/CD나 DBA 절차로 관리합니다.
- **인프라 모니터링/로깅 리소스**: CloudWatch 대시보드, 알람, 로그 수집은 팀 표준 스택(Grafana/Prometheus 또는 별도 계정)에 맞춰 다른 코드베이스에서 관리하므로 여기서는 생성하지 않았습니다.

## 적용 시 체크리스트

- `allowed_ssh_cidr`를 반드시 제한하고, 필요 시 VPN/SSM Session Manager를 사용해 SSH를 제거합니다.
- `tfstate_bucket_name`을 비워두면 로컬 상태를 사용하므로, 팀 협업 시에는 S3 Backend로 마이그레이션해야 합니다.
- 프라이빗 서브넷 인터넷 접근을 더 엄격히 해야 한다면 DB 라우트의 NAT 경로를 제거하고, VPC 엔드포인트(S3, STS 등)를 추가로 배포합니다.
- 운영 전에는 IAM 권한을 최소화하고 RDS 삭제 방지/스냅샷 설정을 강화합니다.

