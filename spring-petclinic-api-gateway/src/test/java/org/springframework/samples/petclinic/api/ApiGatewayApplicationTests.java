package org.springframework.samples.petclinic.api;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

/**
 * API Gateway Application Test
 * 
 * NOTE: Spring Cloud service registry and config server are disabled
 * because in K8s environments, we use ConfigMaps/Secrets and DNS-based
 * service discovery instead of Eureka and Config Server.
 */
@ActiveProfiles("test")
@SpringBootTest(
	webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
	properties = {
		// Disable Spring Cloud service registry (Eureka)
		"spring.cloud.service-registry.auto-registration.enabled=false",
		// Disable service discovery
		"spring.cloud.discovery.enabled=false",
		// Disable config server
		"spring.cloud.config.enabled=false"
	}
)
class ApiGatewayApplicationTests {

	@Test
	void contextLoads() {
	}

}
