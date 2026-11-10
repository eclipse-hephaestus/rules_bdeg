<!-- ----------------------------------------------------------------------------
  Copyright (c) 2026 Contributors to the Eclipse Foundation

  See the NOTICE file(s) distributed with this work for additional
  information regarding copyright ownership.

  This program and the accompanying materials are made available under the
  terms of the Apache License Version 2.0 which is available at
  https://www.apache.org/licenses/LICENSE-2.0

  SPDX-License-Identifier: Apache-2.0
----------------------------------------------------------------------------- -->

# rules_bdeg Examples

This directory contains examples demonstrating how to use rules_bdeg to export
Bazel C++ dependencies as CMake packages.

## Examples

### gtest_boost

A simple example that exports GoogleTest and Boost.Program_Options as CMake packages,
then builds a CMake project that uses them.

```bash
cd gtest_boost
./build.sh
```

## Running Examples

Each example directory contains:
- `BUILD.bazel` - Bazel build file with `cmake_export` rule
- `CMakeLists.txt` - CMake project that consumes the exported packages
- `build.sh` - Script to run the complete workflow

The general workflow is:

1. **Export dependencies from Bazel:**
   ```bash
   bazel build //:export
   ```

2. **Create symlink to generated packages:**
   ```bash
   ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages
   ```

3. **Build with CMake:**
   ```bash
   # From inside the example directory:
   cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages"
   cmake --build build
   ```

   If you are running from the repository root instead, use:
   ```bash
   cmake -S gtest_boost -B gtest_boost/build -DBDEG_DIR="$(pwd)/gtest_boost/cmake-packages"
   cmake --build gtest_boost/build
   ```

4. **Run tests:**
   ```bash
   ctest --test-dir build
   ```

## Structure

```
examples/
├── MODULE.bazel          # Shared module for all examples
├── .bazelversion         # Bazel version
├── .bazelrc              # Bazel configuration
├── BUILD.bazel           # Root build file
├── README.md             # This file
└── gtest_boost/          # GTest + Boost example
    ├── BUILD.bazel       # cmake_export rule
    ├── CMakeLists.txt    # CMake consumer project
    ├── main.cpp          # Test source
    └── build.sh          # Build script
```
