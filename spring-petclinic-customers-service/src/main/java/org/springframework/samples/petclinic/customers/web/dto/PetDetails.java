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

import org.springframework.samples.petclinic.customers.model.Pet;

import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.List;

/**
 * @author Maciej Szarlinski
 */
public record PetDetails(
    int id,
    String name,
    String birthDate,
    PetType type,
    List<Object> visits) {

    public PetDetails {
        if (visits == null) {
            visits = new ArrayList<>();
        }
    }

    public PetDetails(Pet pet) {
        this(
            pet.getId(),
            pet.getName(),
            pet.getBirthDate() != null ? new SimpleDateFormat("yyyy-MM-dd").format(pet.getBirthDate()) : null,
            pet.getType() != null ? new PetType(pet.getType()) : null,
            new ArrayList<>()
        );
    }
}

