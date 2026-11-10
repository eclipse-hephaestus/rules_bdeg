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

#ifndef BDEG_CALC_ADD_H
#define BDEG_CALC_ADD_H

namespace bdeg {

// Leaf operation. Lives in the `add` cc_library (own sources).
int add(int a, int b);

// Returns the value of the BDEG_CALC_VERSION compile define, proving the
// define set on the `add` cc_library reaches the compiled object code and
// (via INTERFACE_COMPILE_DEFINITIONS) the CMake consumer too.
int calc_version();

}  // namespace bdeg

#endif  // BDEG_CALC_ADD_H
