#!/bin/bash
# *******************************************************************************
# Copyright (c) 2026 Contributors to the Eclipse Foundation
#
# See the NOTICE file(s) distributed with this work for additional
# information regarding copyright ownership.
#
# This program and the accompanying materials are made available under the
# terms of the Apache License Version 2.0 which is available at
# https://www.apache.org/licenses/LICENSE-2.0
#
# SPDX-License-Identifier: Apache-2.0
# *******************************************************************************

# Build script for gtest_boost example
#
# This script demonstrates the complete workflow:
# 1. Build Bazel dependencies
# 2. Generate CMake packages with BDEG
# 3. Build with CMake
# 4. Run tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "=== Step 1: Build Bazel dependencies ==="
bazel build @googletest//:gtest @googletest//:gtest_main @boost.program_options

echo ""
echo "=== Step 2: Generate CMake packages with BDEG ==="
bazel build //gtest_boost:export

echo ""
echo "=== Step 3: Create symlink to generated packages ==="
rm -f cmake-packages
ln -sf "$(bazel info bazel-bin)/gtest_boost/cmake-packages" cmake-packages
echo "Created symlink: cmake-packages -> $(readlink cmake-packages)"

echo ""
echo "=== Step 4: Configure CMake ==="
rm -rf build
cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages" -DCMAKE_BUILD_TYPE=Release

echo ""
echo "=== Step 5: Build with CMake ==="
cmake --build build

echo ""
echo "=== Step 6: Run tests ==="
cd build
ctest --output-on-failure

echo ""
echo "=== SUCCESS ==="
echo "The example demonstrates that Bazel dependencies (GTest, Boost) are"
echo "successfully exported and consumed by CMake via BDEG."
