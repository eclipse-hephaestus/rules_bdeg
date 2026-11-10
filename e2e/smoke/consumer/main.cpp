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

// Smoke-test consumer: a plain CMake translation unit that links against
// Bazel-built libraries exported via BDEG. Exercises, in one binary:
//   * GTest / GTestMain  -> framework find_package + linking
//   * Calc (facade)      -> transitive-closure linking (add/mul object code)
//   * define propagation -> BDEG_CALC_VERSION arrives at consumer compile time
//   * include propagation -> calc/calc.h resolves via INTERFACE_INCLUDE_DIRECTORIES
#include <gtest/gtest.h>

#include "calc/calc.h"

// INTERFACE_COMPILE_DEFINITIONS from the exported Calc package must make the
// define visible here. If propagation breaks, this fails to compile.
static_assert(BDEG_CALC_VERSION == 42,
              "BDEG_CALC_VERSION define did not propagate to the consumer");

TEST(BdegSmoke, LeafAdd) {
  EXPECT_EQ(bdeg::add(2, 5), 7);
}

TEST(BdegSmoke, TransitiveMul) {
  // mul() lives in one library and calls add() in another; both object files
  // must be present in the merged archive for this to link and run.
  EXPECT_EQ(bdeg::mul(3, 4), 12);
}

TEST(BdegSmoke, DefineReachedObjectCode) {
  EXPECT_EQ(bdeg::calc_version(), 42);
}
