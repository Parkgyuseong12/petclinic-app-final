# 모든 서비스 디렉토리에 대해 Dockerfile 수정
for service in spring-petclinic-*; do
  if [ -f "$service/Dockerfile" ]; then
    echo "Updating $service/Dockerfile..."
    cat > "$service/Dockerfile" << 'EOF'
# Multi-stage build for Spring PetClinic Service
# Stage 1: Build Stage
FROM maven:3.8-eclipse-temurin-17 AS builder

WORKDIR /app

# Copy pom files and source code from current directory
COPY pom.xml .
COPY src ./src

# Build the application
RUN mvn clean package -DskipTests

# Stage 2: Runtime Stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Create a non-root user for security
RUN groupadd -f -g 1000 spring && useradd -u 1000 -g spring spring 2>/dev/null || true

# Copy the built jar from builder stage
COPY --from=builder /app/target/*.jar app.jar

# Change ownership to non-root user
RUN chown -R spring:spring /app

# Switch to non-root user
USER spring

# Expose the port (각 서비스마다 다를 수 있음)
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-jar", "app.jar"]
EOF
  fi
done