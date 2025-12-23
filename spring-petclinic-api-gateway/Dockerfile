FROM maven:3.8-eclipse-temurin-17 AS builder

WORKDIR /app

# 루트 pom.xml 복사
COPY pom.xml .

# 현재 서비스 복사
COPY spring-petclinic-api-gateway ./spring-petclinic-api-gateway

# 빌드
RUN mvn clean package -f spring-petclinic-api-gateway/pom.xml -DskipTests

FROM eclipse-temurin:17-jre

WORKDIR /app

RUN groupadd -f -g 1000 spring && useradd -u 1000 -g spring spring 2>/dev/null || true

COPY --from=builder /app/spring-petclinic-api-gateway/target/*.jar app.jar

RUN chown -R spring:spring /app

USER spring

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

ENTRYPOINT ["java", "-jar", "app.jar"]
