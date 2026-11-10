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

"""Comprehensive smoke test for rules_bdeg.

This BUILD exercises every aspect of `cmake_export`:

* First-party libraries with their own sources, include dirs and defines.
* A *facade* cc_library (`calc`) that owns no sources, only `hdrs` + `deps` -
  the case that only links if BDEG exports the full transitive closure.
* A transitive dependency chain: calc -> mul -> add (mul calls add).
* Cross-package references: `calc` and `add` are both exported, so Calc's
  generated link line must reference AddLib::add.
* Compile-define propagation: `BDEG_CALC_VERSION=42` set on `add`.
* Per-package whole-archive via `whole_archive_packages`.
* Non-default `version` (2.3.4) to exercise ConfigVersion parsing.
* External framework (`googletest`) consumed via find_package.

The companion `consumer/` CMake project and `run_tests.sh` turn these exports
into a real find_package + link + run verification.
"""

load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")
load("@rules_cc//cc:defs.bzl", "cc_library")

# ---------------------------------------------------------------------------
# First-party C++ libraries
# ---------------------------------------------------------------------------

# Leaf library with its own source + a compile define.
cc_library(
    name = "add",
    srcs = ["src/calc/add.cpp"],
    hdrs = ["src/calc/include/calc/add.h"],
    defines = ["BDEG_CALC_VERSION=42"],
    includes = ["src/calc/include"],
)

# Depends on :add - its implementation calls bdeg::add().
cc_library(
    name = "mul",
    srcs = ["src/calc/mul.cpp"],
    hdrs = ["src/calc/include/calc/mul.h"],
    includes = ["src/calc/include"],
    deps = [":add"],
)

# Facade: NO srcs of its own, only an umbrella header + deps. This is the
# headline case - exporting just this must still link add()/mul() object code.
cc_library(
    name = "calc",
    hdrs = ["src/calc/include/calc/calc.h"],
    includes = ["src/calc/include"],
    deps = [":mul"],
)

# ---------------------------------------------------------------------------
# Export targets
# ---------------------------------------------------------------------------

# Primary export consumed end-to-end by consumer/CMakeLists.txt.
# Covers: facade/transitive closure, cross-package refs, defines, includes,
# external framework, non-default version, and (via DefaultInfo) that the
# merged archives are actually built by `bazel build`.
cmake_export(
    name = "export_all",
    version = "2.3.4",
    deps = {
        "@googletest//:gtest": "GTest",
        "@googletest//:gtest_main": "GTestMain",
        ":calc": "Calc",
        ":add": "AddLib",
    },
)

# Whole-archive variant (per-package opt-in). Generated into a separate
# output_dir so run_tests.sh can assert the INTERFACE + whole-archive output
# without disturbing the primary export.
cmake_export(
    name = "export_calc_wa",
    output_dir = "cmake-packages-wa",
    whole_archive_packages = ["Calc"],
    deps = {":calc": "Calc"},
)

# Minimal original export kept for a quick sanity build. Uses its own
# output_dir: two cmake_export targets in the same package must not share an
# output_dir, or they would generate the same files (conflicting actions).
cmake_export(
    name = "export_gtest",
    output_dir = "cmake-packages-gtest",
    deps = {
        "@googletest//:gtest": "GTest",
        "@googletest//:gtest_main": "GTestMain",
    },
)
