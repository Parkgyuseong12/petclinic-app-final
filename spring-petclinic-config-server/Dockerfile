# Multi-stage build for Spring PetClinic Config Server
# Stage 1: Build Stage
FROM maven:3.8-eclipse-temurin-17 AS builder

WORKDIR /app

# Copy the root pom.xml and all source files
COPY pom.xml .
COPY spring-petclinic-config-server ./spring-petclinic-config-server

# Build the application
RUN mvn clean package -f spring-petclinic-config-server/pom.xml -DskipTests

# Stage 2: Runtime Stage
FROM eclipse-temurin:17-jre

WORKDIR /app

# Create a non-root user for security
RUN groupadd -f -g 1000 spring && useradd -u 1000 -g spring spring 2>/dev/null || true

# Copy the built jar from builder stage
COPY --from=builder /app/spring-petclinic-config-server/target/spring-petclinic-config-server-*.jar app.jar

# Change ownership to non-root user
RUN chown -R spring:spring /app

# Switch to non-root user
USER spring

# Expose the port
EXPOSE 8888

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD wget --quiet --tries=1 --spider http://localhost:8888/actuator/health || exit 1

# Run the application
ENTRYPOINT ["java", "-Dcom.sun.management.jmxremote.port=5000", "-Dcom.sun.management.jmxremote.rmi.port=5000", "-Dcom.sun.management.jmxremote.authenticate=false", "-Dcom.sun.management.jmxremote.ssl=false", "-Djava.rmi.server.hostname=127.0.0.1", "-jar", "app.jar"]