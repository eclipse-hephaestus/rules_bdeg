/********************************************************************************
 * Copyright (c) 2026 Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) distributed with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0
 ********************************************************************************/

#ifndef BDEG_CALC_MUL_H
#define BDEG_CALC_MUL_H

namespace bdeg {

// Depends on add() - its object code lives in a *different* cc_library.
// Linking this through a facade proves the merged archive captures the full
// transitive closure (not just the facade's own, empty, archive).
int mul(int a, int b);

}  // namespace bdeg

#endif  // BDEG_CALC_MUL_H
