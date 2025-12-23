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
package org.springframework.samples.petclinic.customers.web.dto;

import com.fasterxml.jackson.annotation.JsonIgnore;
import org.springframework.samples.petclinic.customers.model.Owner;

import java.util.List;
import java.util.stream.Collectors;

/**
 * @author Maciej Szarlinski
 */
public record OwnerDetails(
    int id,
    String firstName,
    String lastName,
    String address,
    String city,
    String telephone,
    List<PetDetails> pets) {

    @JsonIgnore
    public List<Integer> getPetIds() {
        return pets.stream()
            .map(PetDetails::id)
            .collect(Collectors.toList());
    }

    public OwnerDetails(Owner owner) {
        this(
            owner.getId(),
            owner.getFirstName(),
            owner.getLastName(),
            owner.getAddress(),
            owner.getCity(),
            owner.getTelephone(),
            owner.getPets().stream()
                .map(PetDetails::new)
                .collect(Collectors.toList())
        );
    }
}

