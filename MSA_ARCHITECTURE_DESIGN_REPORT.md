# 클라우드 네이티브 MSA 전환 및 아키텍처 설계 보고서

## 1. 아키텍처 설계 원칙 (Design Principles)

본 프로젝트는 기존의 모놀리식(Monolithic) 애플리케이션을 클라우드 네이티브 환경으로 전환하며 다음 3가지 핵심 원칙을 수립하였다.

1. **Loose Coupling (느슨한 결합):** 서비스 간의 직접적인 의존성을 제거하여, 하나의 장애가 전체로 전파되는 것을 방지한다.

2. **Database per Service (서비스별 데이터 독립):** 각 마이크로서비스는 자신의 데이터에만 접근 권한을 가지며, 타 서비스의 데이터를 직접 조회(JOIN)하지 않는다.

3. **Infrastructure as Code (IaC):** 모든 인프라(네트워크, 컴퓨팅, 미들웨어)는 코드로 관리되어야 하며, 재현 가능해야 한다.

---

## 2. 핵심 아키텍처 결정 사항 (Key Decisions & Justification)

### 2.1. 데이터베이스 전략: 물리적 통합, 논리적 분리 (Shared RDS with Logical Separation)

- **결정 사항:** 단일 AWS RDS(MySQL) 인스턴스 내에 서비스별 데이터베이스(`customers_db`, `vets_db`, `visits_db`)를 논리적으로 분리하여 운영한다.

- **구현 세부사항:**
  - 각 서비스는 독립적인 데이터베이스에 연결: `jdbc:mysql://${DB_HOST}:3306/{service}_db`
  - `customers_db`: `types`, `owners`, `pets` 테이블 (FK: `pets.owner_id` → `owners.id`, `pets.type_id` → `types.id`)
  - `vets_db`: `vets`, `specialties`, `vet_specialties` 테이블 (FK: 내부 참조만 허용)
  - `visits_db`: `visits` 테이블 (FK 없음, `pet_id`는 단순 INT 타입)

- **논리적 근거 (Why?):**

    - **MSA 원칙 준수:** 서비스별로 물리적인 DB를 나누는 것이 이상적이나, 초기 구축 비용과 운영 복잡도를 고려하여 **'논리적 스키마 분리'** 방식을 채택했다.

    - **참조 무결성 제거 (FK Removal):** 서비스 간의 강한 결합을 끊기 위해 `visits_db.visits` 테이블에서 `customers_db.pets` 테이블을 참조하는 외래 키(Foreign Key)를 **완전히 제거**했다. 
      - `pet_id`는 단순 `INT(4) UNSIGNED` 타입으로 저장되며, 데이터 일관성은 애플리케이션 레벨에서 보장한다.
      - 이를 통해 향후 물리적 DB 분리가 필요할 때 코드 수정 없이 즉시 마이그레이션이 가능한 구조를 확보했다.

- **Trade-off:** 
  - 물리적 장애 포인트(SPOF)가 존재한다는 리스크가 있으나, 이는 Multi-AZ 설정과 RDS의 자동 백업 기능으로 완화하였다.
  - 데이터 일관성 보장이 애플리케이션 레벨로 이동하여 개발 복잡도가 증가했으나, 서비스 독립성 확보라는 더 큰 가치를 선택했다.

### 2.2. 통신 전략: 하이브리드 통신 모델 (Synchronous HTTP + Asynchronous Event)

- **결정 사항:** 서비스 간 통신에 **동기 HTTP 통신**과 **비동기 이벤트 기반 통신**을 혼합하여 사용한다.

- **구현 세부사항:**

    **동기 통신 (Synchronous):**
    - API Gateway → Backend Services: `WebClient`를 사용한 HTTP 호출
    - 서비스 간 직접 통신: K8s Service DNS (`petclinic-customers:8080`, `petclinic-visits:8080`) 사용
    - 예시: `ApiGatewayController.getOwnerDetails()`에서 `CustomersServiceClient`와 `VisitsServiceClient`를 순차 호출하여 데이터를 조합

    **비동기 통신 (Asynchronous):**
    - Producer: `Visits Service`에서 `RabbitTemplate.convertAndSend()`를 사용하여 메시지 발행
      - 큐 이름: `visit-events`
      - 메시지 형식: `"Visit Created: [Pet ID: {petId}, Date: {date}]"`
      - **주의:** `convertAndSend()`는 동기 방식이지만, 메시지 큐를 통한 전달 자체는 비동기적으로 처리됨
    - Consumer: `Customers Service`에서 `@RabbitListener(queues = "visit-events")`를 사용하여 메시지 수신
      - 별도 스레드 풀에서 비동기적으로 처리
      - 현재는 로깅만 수행하며, 향후 비즈니스 로직 확장 가능

- **논리적 근거 (Why?):**

    - **결합도 감소:** 방문 기록 생성 시 고객 정보를 동기(HTTP)로 업데이트하면, `Customers` 서비스 장애 시 `Visits` 서비스까지 마비되는 연쇄 장애(Cascading Failure)가 발생한다. 비동기 이벤트를 통해 이 결합을 끊었다.

    - **응답성 향상:** `Visits` 서비스는 "방문 기록 생성됨"이라는 이벤트만 발행하고 자신의 할 일을 마친다. `Customers` 서비스는 이를 구독하여 비동기적으로 처리함으로써 시스템의 응답성과 가용성을 높였다.

    - **확장성:** 이벤트 기반 아키텍처는 향후 새로운 서비스가 동일한 이벤트를 구독하여 확장 가능한 구조를 제공한다.

- **구현 방식:**
    - RabbitMQ는 EKS 클러스터 내부에 Kubernetes Deployment로 직접 배포 (`rabbitmq:3.13-management`)
    - K8s Service DNS를 통한 내부 통신: `rabbitmq.default.svc.cluster.local:5672`
    - 향후 Amazon MQ(Managed)로의 이관을 염두에 두고 표준 AMQP 프로토콜 사용

### 2.3. API Gateway 전략: BFF 패턴과 Circuit Breaker 적용

- **결정 사항:** 외부 트래픽 진입은 **Spring Cloud Gateway**가 담당하며, **BFF (Backend for Frontend)** 패턴과 **Circuit Breaker** 패턴을 적용한다.

- **구현 세부사항:**

    **라우팅 규칙:**
    - `/api/customer/**` → `petclinic-customers:8080` (StripPrefix=2)
    - `/api/vet/**` → `petclinic-vets:8080` (StripPrefix=2)
    - `/api/visit/**` → `petclinic-visits:8080` (StripPrefix=2)
    - `/api/genai/**` → `petclinic-genai:8080` (StripPrefix=2, CircuitBreaker 적용)

    **BFF 패턴 구현:**
    - `/api/gateway/owners/{ownerId}` 엔드포인트에서 여러 서비스의 데이터를 조합
      - `CustomersServiceClient.getOwner()` → Owner 정보 조회
      - `VisitsServiceClient.getVisitsForPets()` → 해당 Owner의 Pet들의 Visit 정보 조회
      - Circuit Breaker로 `Visits` 서비스 장애 시 빈 Visit 리스트 반환 (Graceful Degradation)

    **장애 처리:**
    - Resilience4j Circuit Breaker 적용 (기본 타임아웃: 10초)
    - Retry 필터: POST 요청에 대해 SERVICE_UNAVAILABLE 상태일 때 1회 재시도
    - Fallback URI: `/fallback` 엔드포인트로 장애 시 대체 응답

- **논리적 근거 (Why?):**

    - **프론트엔드와 백엔드의 결합도 감소:** Spring Cloud Gateway에서 `StripPrefix` 필터를 통해 클라이언트의 요청 경로(`/api/customer/owners`)를 각 마이크로서비스의 실제 경로(`/owners`)로 매핑해줌으로써, 프론트엔드는 서비스별 엔드포인트를 몰라도 된다.

    - **장애 격리:** Circuit Breaker를 통해 특정 서비스의 장애가 전체 시스템으로 전파되는 것을 방지한다. 예를 들어, `Visits` 서비스가 다운되어도 Owner 정보는 정상적으로 조회 가능하다.

    - **서비스 디스커버리:** K8s 네이티브 DNS를 사용하여 별도의 Service Registry(Eureka) 없이도 서비스 간 통신이 가능하다.

### 2.4. 프론트엔드 배포 전략: Nginx Reverse Proxy를 통한 CORS 해결

- **결정 사항:** 프론트엔드(Angular SPA)를 별도의 컨테이너로 분리하고, **Nginx를 Reverse Proxy**로 사용하여 CORS 문제를 해결한다.

- **구현 세부사항:**

    **아키텍처:**
    - 프론트엔드: Nginx Alpine 이미지로 정적 파일 서빙
    - 정적 파일: API Gateway의 `/static/` 폴더에서 복사
    - Nginx 설정:
      - `/api/**` → `petclinic-api-gateway.default.svc.cluster.local:8080/api/`로 프록시
      - `/webjars/**` → `petclinic-api-gateway.default.svc.cluster.local:8080/webjars/`로 프록시 (Spring Boot Webjars)
      - `/` → SPA 라우팅 지원 (`try_files $uri $uri/ /index.html;`)

    **배포 방식:**
    - LoadBalancer 타입의 Service로 외부 노출
    - Multi-stage Dockerfile: 정적 파일을 직접 복사 (빌드 단계 없음)

- **논리적 근거 (Why?):**

    - **CORS 문제 해결:** 브라우저에서 직접 API Gateway로 요청 시 CORS 문제가 발생할 수 있으나, Nginx Reverse Proxy를 통해 같은 도메인으로 요청이 전달되므로 CORS 문제가 발생하지 않는다.

    - **서버 측 라우팅:** SPA의 클라이언트 사이드 라우팅을 지원하기 위해 모든 요청을 `index.html`로 리다이렉트한다.

    - **리소스 최적화:** Spring Boot의 Webjars(Bootstrap, AngularJS 등)를 API Gateway에서 제공하므로, 프론트엔드 컨테이너에는 정적 파일만 포함하여 이미지 크기를 최소화했다.

### 2.5. 서비스 간 통신: K8s 네이티브 DNS 기반 Service Discovery

- **결정 사항:** 별도의 Service Registry(Eureka, Consul 등) 없이 **K8s 네이티브 DNS**를 사용하여 서비스 간 통신을 구현한다.

- **구현 세부사항:**
    - 서비스 이름 규칙: `petclinic-{service-name}` (예: `petclinic-customers`, `petclinic-visits`)
    - K8s Service DNS 형식: `{service-name}.{namespace}.svc.cluster.local:8080`
    - 실제 사용: `petclinic-customers:8080` (같은 namespace이므로 축약 가능)

- **논리적 근거 (Why?):**

    - **단순성:** 별도의 Service Registry를 운영할 필요가 없어 인프라 복잡도가 감소한다.
    - **K8s 네이티브:** K8s의 기본 기능을 활용하여 추가 의존성을 제거했다.
    - **성능:** DNS 기반이지만 K8s 내부 통신이므로 지연시간이 낮다.

---

## 3. 기술 스택 및 구현 상세

### 3.1. 데이터베이스 계층

| 서비스 | 데이터베이스 | 주요 테이블 | FK 제약조건 |
|--------|-------------|-----------|------------|
| Customers Service | `customers_db` | `types`, `owners`, `pets` | 내부 FK만 허용 (`pets.owner_id`, `pets.type_id`) |
| Vets Service | `vets_db` | `vets`, `specialties`, `vet_specialties` | 내부 FK만 허용 |
| Visits Service | `visits_db` | `visits` | **FK 없음** (`pet_id`는 단순 INT) |

**핵심 설계 결정:**
- `visits.pet_id`는 `customers_db.pets.id`를 참조하지만, FK 제약조건이 없음
- 데이터 일관성은 애플리케이션 레벨에서 보장 (예: Visit 생성 시 Pet ID 유효성 검증)

### 3.2. 메시징 계층

**RabbitMQ 배포:**
- 배포 방식: Kubernetes Deployment (Helm Chart 미사용)
- 이미지: `rabbitmq:3.13-management`
- 서비스 타입: ClusterIP
- 접속 정보: `rabbitmq.default.svc.cluster.local:5672`

**이벤트 흐름:**
1. `Visits Service`에서 Visit 생성 (`VisitResource.create()`)
2. `RabbitTemplate.convertAndSend("visit-events", message)` 호출
3. RabbitMQ 큐에 메시지 저장
4. `Customers Service`의 `VisitEventListener.handleVisitEvent()`가 비동기적으로 메시지 수신
5. 로깅 처리 (향후 비즈니스 로직 확장 가능)

**비동기성 분석:**
- Producer (`convertAndSend`): 동기 방식 (메시지 전송 완료까지 블로킹)
- Consumer (`@RabbitListener`): 비동기 방식 (별도 스레드에서 처리)
- 전체 흐름: 부분적으로 비동기 (Producer는 동기, Consumer는 비동기)

### 3.3. API Gateway 계층

**Spring Cloud Gateway 설정:**
- Circuit Breaker: Resilience4j 사용 (기본 타임아웃 10초)
- Retry: POST 요청에 대해 SERVICE_UNAVAILABLE 시 1회 재시도
- BFF 패턴: `/api/gateway/owners/{ownerId}` 엔드포인트에서 데이터 조합

**서비스 클라이언트:**
- `CustomersServiceClient`: `http://petclinic-customers:8080/owners/{ownerId}`
- `VisitsServiceClient`: `http://petclinic-visits:8080/pets/visits?petId={petIds}`
- WebClient 기반 비동기 통신 (Reactor Mono)

### 3.4. 프론트엔드 계층

**Nginx Reverse Proxy 설정:**
- 정적 파일 서빙: `/usr/share/nginx/html`
- API 프록시: `/api/**` → API Gateway
- Webjars 프록시: `/webjars/**` → API Gateway (Spring Boot에서 제공)
- SPA 라우팅: 모든 요청을 `index.html`로 리다이렉트

**배포:**
- LoadBalancer 타입으로 외부 노출
- Multi-stage Dockerfile 사용 (빌드 단계 없음, 정적 파일 직접 복사)

---

## 4. 아키텍처 다이어그램

```
┌─────────────────────────────────────────────────────────────┐
│                    External Users                            │
└──────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│         Frontend (Nginx) - LoadBalancer                     │
│  - Serves static files                                      │
│  - Proxies /api/** → API Gateway                            │
│  - Proxies /webjars/** → API Gateway                        │
└──────────────────────┬──────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│         API Gateway (Spring Cloud Gateway)                  │
│  - Routes: /api/customer/** → Customers Service            │
│  - Routes: /api/visit/** → Visits Service                  │
│  - Routes: /api/vet/** → Vets Service                       │
│  - BFF: /api/gateway/owners/{id} → Aggregates data         │
│  - Circuit Breaker (Resilience4j)                           │
└──────┬──────────────────┬──────────────────┬───────────────┘
       │                  │                  │
       ▼                  ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Customers   │  │   Visits     │  │    Vets     │
│   Service    │  │   Service    │  │   Service   │
└──────┬───────┘  └──────┬───────┘  └──────┬──────┘
       │                 │                  │
       │                 │                  │
       ▼                 ▼                  ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│ customers_db │  │  visits_db   │  │   vets_db    │
│              │  │              │  │              │
│ - types      │  │ - visits     │  │ - vets       │
│ - owners     │  │   (no FK)    │  │ - specialties│
│ - pets       │  │              │  │ - vet_       │
│   (FK:       │  │              │  │   specialties│
│    internal) │  │              │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
       │                 │
       │                 │
       │      ┌──────────▼──────────┐
       │      │   RabbitMQ         │
       │      │   (visit-events)   │
       │      └──────────┬──────────┘
       │                 │
       │      (Async Event)
       │                 │
       └─────────────────┘
```

---

## 5. 결론 (Conclusion)

본 아키텍처는 제한된 리소스 내에서 **클라우드 네이티브의 핵심 가치(유연성, 확장성, 독립성)**를 최대한 구현하기 위해 설계되었다.

### 주요 성과:

1. **진정한 서비스 분리:** 단순한 '배포 단위 분리'를 넘어, DB 스키마의 논리적 분리와 FK 제거를 통해 서비스 간 강한 결합을 제거했다.

2. **이벤트 기반 통신 도입:** RabbitMQ를 통한 비동기 이벤트 발행/구독 패턴을 구현하여 서비스 간 결합도를 낮추고 확장성을 확보했다.

3. **장애 격리:** Circuit Breaker와 Fallback 메커니즘을 통해 특정 서비스의 장애가 전체 시스템으로 전파되는 것을 방지했다.

4. **운영 단순화:** K8s 네이티브 DNS를 활용하여 별도의 Service Registry 없이도 서비스 간 통신이 가능하도록 설계했다.

### 향후 개선 방향:

1. **물리적 DB 분리:** 트래픽 증가 시 각 서비스별로 독립적인 RDS 인스턴스로 분리
2. **Managed Service 전환:** RabbitMQ → Amazon MQ, RDS → Aurora Serverless
3. **비동기 처리 강화:** Producer 측에서도 비동기 메시지 발행 (`@Async` 또는 `CompletableFuture`)
4. **모니터링 강화:** Distributed Tracing (Zipkin/Jaeger), APM 도구 도입

이 문서는 프로젝트의 기술적 의사결정 과정을 투명하게 보여주며, 향후 시스템 확장(Scale-out)이나 Managed Service로의 고도화(Evolution)를 위한 탄탄한 기반이 됨을 명시한다.

---

## 부록: 주요 파일 참조

- 데이터베이스 스키마: `k8s/init-{service}-db.sql`
- 서비스 설정: `spring-petclinic-{service}/src/main/resources/application.yml`
- RabbitMQ 설정: `k8s/rabbitmq.yaml`
- API Gateway 설정: `spring-petclinic-api-gateway/src/main/resources/application.yml`
- 프론트엔드 설정: `spring-petclinic-frontend/nginx.conf`
- K8s 매니페스트: `k8s/{service}.yaml`

