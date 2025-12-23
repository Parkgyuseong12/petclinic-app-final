# Multi-stage build for Spring PetClinic Vets Service
# Stage 1: Build Stage
FROM maven:3.8-eclipse-temurin-17 AS builder

WORKDIR /app

# Copy the root pom.xml and all source files
COPY pom.xml .
COPY spring-petclinic-vets-service ./spring-petclinic-vets-service
COPY spring-petclinic-vets-service/pom.xml ./spring-petclinic-vets-service/

# Build the application
RUN mvn clean package -f spring-petclinic-vets-service/pom.xml -DskipTests

# Stage 2: Runtime Stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Copy the built jar from builder stage
COPY --from=builder /app/spring-petclinic-vets-service/target/spring-petclinic-vets-service-*.jar app.jar

# Create a non-root user for security and change ownership in one step
RUN groupadd -g 1001 spring 2>/dev/null || groupadd spring && \
    useradd -u 1001 -g spring spring 2>/dev/null || useradd -g spring spring && \
    chown -R spring:spring /app

# Switch to non-root user
USER spring

# Expose the port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8080/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-Dcom.sun.management.jmxremote.port=5000", "-Dcom.sun.management.jmxremote.rmi.port=5000", "-Dcom.sun.management.jmxremote.authenticate=false", "-Dcom.sun.management.jmxremote.ssl=false", "-Djava.rmi.server.hostname=127.0.0.1", "-jar", "app.jar"]
