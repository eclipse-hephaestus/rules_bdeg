#!/usr/bin/env bash
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

#
# Comprehensive smoke test for rules_bdeg.
#
# Builds the exports, asserts the generated CMake package files cover every
# feature of cmake_export, then does a real find_package + link + run with a
# CMake consumer. Requires: bazel, cmake, a C++ toolchain.
#
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

# cmake_export generates cc_static_library targets to merge each exported
# package's transitive closure into one linkable archive. cc_static_library is
# still gated behind --experimental_cc_static_library on Bazel 8.x.
#
# This workspace's .bazelrc imports the repo-root .bazelrc, which already sets
# the flag. It is repeated explicitly on the command line so the smoke test
# also works when invoked with --noworkspace_rc or from a checkout where the
# rc files were not picked up.
BAZEL_FLAGS=(--experimental_cc_static_library)
BAZEL_STARTUP=()

GREEN=$'\033[32m'; RED=$'\033[31m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
fails=0

section() { printf '\n%s== %s ==%s\n' "$BOLD" "$1" "$RESET"; }
pass()    { printf '  %s[PASS]%s %s\n' "$GREEN" "$RESET" "$1"; }
fail()    { printf '  %s[FAIL]%s %s\n' "$RED" "$RESET" "$1"; fails=$((fails + 1)); }

# assert_file <path> <description>
assert_file() {
  if [ -f "$1" ]; then pass "$2"; else fail "$2 (missing: $1)"; fi
}

# assert_grep <file> <regex> <description>
assert_grep() {
  if [ -f "$1" ] && grep -qE "$2" "$1"; then
    pass "$3"
  else
    fail "$3 (pattern '/$2/' not found in $1)"
  fi
}

section "Step 1: build all export targets"
bazel "${BAZEL_STARTUP[@]}" build "${BAZEL_FLAGS[@]}" //:export_all //:export_calc_wa //:export_gtest

BB="$(bazel "${BAZEL_STARTUP[@]}" info "${BAZEL_FLAGS[@]}" bazel-bin)"
PKG="$BB/cmake-packages"
PKG_WA="$BB/cmake-packages-wa"

section "Aspect: all generated files exist"
for base in GTest GTestMain Calc AddLib; do
  for kind in Config ConfigVersion Targets; do
    assert_file "$PKG/${base}${kind}.cmake" "${base}${kind}.cmake generated"
  done
done
assert_file "$PKG/bdeg-deps.cmake" "umbrella (bdeg-deps.cmake) generated"
assert_file "$PKG/bdeg-toolchain.cmake" "toolchain (bdeg-toolchain.cmake) generated"

section "Aspect: merged archives are built (DefaultInfo fix)"
assert_file "$BB/libexport_all_Calc_merged.a" "Calc merged archive built"
assert_file "$BB/libexport_all_AddLib_merged.a" "AddLib merged archive built"

section "Aspect: ConfigVersion parses non-default version 2.3.4"
assert_grep "$PKG/CalcConfigVersion.cmake" "2\.3\.4" "version string 2.3.4 present"
assert_grep "$PKG/CalcConfigVersion.cmake" "(PACKAGE_VERSION_MAJOR|_VERSION_MAJOR).*2|\"2\"" "major version parsed"

section "Aspect: facade exported as STATIC with merged IMPORTED_LOCATION"
assert_grep "$PKG/CalcTargets.cmake" "add_library\(Calc::calc STATIC IMPORTED\)" "Calc is STATIC IMPORTED"
assert_grep "$PKG/CalcTargets.cmake" "libexport_all_Calc_merged\.a" "Calc IMPORTED_LOCATION -> merged archive"

section "Aspect: cross-package reference (Calc -> AddLib::add)"
assert_grep "$PKG/CalcTargets.cmake" "AddLib::add" "Calc link line references AddLib::add"

section "Aspect: compile-define propagation"
assert_grep "$PKG/CalcTargets.cmake" "BDEG_CALC_VERSION=42" "Calc carries INTERFACE_COMPILE_DEFINITIONS"

section "Aspect: both repository roots emitted (layout independence)"
assert_grep "$PKG/bdeg-deps.cmake" "BDEG_EXECROOT" "BDEG_EXECROOT defined"
assert_grep "$PKG/bdeg-deps.cmake" "BDEG_OUTPUT_BASE" "BDEG_OUTPUT_BASE defined"
assert_grep "$PKG/CalcTargets.cmake" "_bdeg_resolve_path" "path resolver present in Targets"
assert_grep "$PKG/CalcTargets.cmake" "_bdeg_report_missing_library" "clear missing-library diagnostic present"

section "Aspect: per-package whole-archive variant"
assert_grep "$PKG_WA/CalcTargets.cmake" "add_library\(Calc::calc INTERFACE IMPORTED\)" "WA Calc is INTERFACE IMPORTED"
assert_grep "$PKG_WA/CalcTargets.cmake" "WHOLE_ARCHIVE|whole-archive" "WA uses whole-archive linking"
assert_grep "$PKG_WA/CalcTargets.cmake" "allow-multiple-definition" "WA adds --allow-multiple-definition"

section "Aspect: default export leaves non-listed packages STATIC"
assert_grep "$PKG/GTestTargets.cmake" "add_library\(GTest::gtest STATIC IMPORTED\)" "GTest stays STATIC in default export"

if ! command -v cmake >/dev/null 2>&1; then
  section "RESULT"
  echo "cmake not found - skipped end-to-end link/run. Generated-file aspects above still ran."
  [ "$fails" -eq 0 ] || { echo "${RED}${fails} assertion(s) failed${RESET}"; exit 1; }
  echo "${GREEN}All generated-file aspects passed (link/run skipped).${RESET}"
  exit 0
fi

section "Aspect: end-to-end find_package + link + run"
rm -f cmake-packages
ln -sf "$PKG" cmake-packages
rm -rf consumer/build
cmake -S consumer -B consumer/build -DBDEG_DIR="$PKG" >/dev/null
cmake --build consumer/build >/dev/null
if ctest --test-dir consumer/build --output-on-failure; then
  pass "consumer linked and all ctest cases passed"
else
  fail "consumer build/test failed"
fi

section "RESULT"
if [ "$fails" -eq 0 ]; then
  echo "${GREEN}${BOLD}All smoke aspects passed.${RESET}"
else
  echo "${RED}${BOLD}${fails} assertion(s) failed.${RESET}"
  exit 1
fi
