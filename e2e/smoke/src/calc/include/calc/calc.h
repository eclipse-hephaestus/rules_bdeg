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

#ifndef BDEG_CALC_H
#define BDEG_CALC_H

// Facade umbrella header. The `calc` cc_library owns no sources - only this
// header plus deps. A CMake consumer that includes this and links the exported
// `Calc` package must still resolve add()/mul() object code, which only works
// if BDEG exports the full transitive closure as a merged archive.
#include "calc/add.h"
#include "calc/mul.h"

#endif  // BDEG_CALC_H
