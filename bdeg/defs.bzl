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

"""Public API for rules_bdeg.

This module provides the public interface for the BDEG (Bazel Dependency Export Generator)
ruleset. Import rules from this file in your BUILD files.

Currently supported export formats:
- cmake_export: Generate CMake Config packages

Future formats (planned):
- cargo_export: Generate Cargo build scripts (not yet implemented)

Example:
    ```python
    load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")

    cmake_export(
        name = "export",
        deps = {
            "@googletest//:gtest": "GTest",
            "@googletest//:gtest_main": "GTestMain",
            "@boost.program_options": "Boost",
        },
    )
    ```
"""

# CMake export - generates CMake Config packages
load("//bdeg/private/cmake:export.bzl", _cmake_export = "cmake_export")

cmake_export = _cmake_export

# Future: Cargo export
# load("//bdeg/private/cargo:export.bzl", _cargo_export = "cargo_export")
# cargo_export = _cargo_export
