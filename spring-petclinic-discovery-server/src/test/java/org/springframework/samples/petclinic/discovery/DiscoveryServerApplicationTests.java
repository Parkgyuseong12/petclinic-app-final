/*
 * Copyright 2002-2021 the original author or authors.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
package org.springframework.samples.petclinic.discovery;

import org.junit.jupiter.api.Disabled;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.SpringBootTest;

/**
 * Discovery Server (Eureka) Test
 * 
 * NOTE: This test is disabled because in K8s environments,
 * Eureka-based service discovery is not needed.
 * Kubernetes provides built-in DNS-based service discovery.
 * 
 * The Discovery Server is deprecated for cloud-native deployments.
 */
@Disabled("Discovery Server (Eureka) is not needed in Kubernetes environment. " +
          "Use K8s native service discovery (DNS) instead.")
@SpringBootTest
class DiscoveryServerApplicationTests {

	@Test
	void contextLoads() {
	}

}
