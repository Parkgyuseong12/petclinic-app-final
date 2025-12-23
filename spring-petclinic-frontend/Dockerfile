FROM maven:3.8-eclipse-temurin-17 AS builder

WORKDIR /app

COPY pom.xml .
COPY spring-petclinic-frontend ./spring-petclinic-frontend

RUN mvn clean package -f spring-petclinic-frontend/pom.xml -DskipTests

FROM eclipse-temurin:17-jre

WORKDIR /app

# jar 파일을 복사하면서 바로 권한 설정
COPY --from=builder --chown=1000:1000 /app/spring-petclinic-frontend/target/*.jar app.jar

# 사용자 생성 (더 안전한 방법)
RUN addgroup --gid 1000 spring || true && \
    adduser --uid 1000 --gid 1000 --disabled-password --gecos "" spring || true

USER 1000

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
