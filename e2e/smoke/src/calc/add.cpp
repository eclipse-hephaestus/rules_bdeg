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

#include "calc/add.h"

#ifndef BDEG_CALC_VERSION
#define BDEG_CALC_VERSION 0
#endif

namespace bdeg {

int add(int a, int b) {
  return a + b;
}

int calc_version() {
  return BDEG_CALC_VERSION;
}

}  // namespace bdeg
