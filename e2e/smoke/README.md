<!-- ----------------------------------------------------------------------------
  Copyright (c) 2026 Contributors to the Eclipse Foundation

  See the NOTICE file(s) distributed with this work for additional
  information regarding copyright ownership.

  This program and the accompanying materials are made available under the
  terms of the Apache License Version 2.0 which is available at
  https://www.apache.org/licenses/LICENSE-2.0

  SPDX-License-Identifier: Apache-2.0
----------------------------------------------------------------------------- -->

# Smoke Test

A comprehensive end-to-end test for `rules_bdeg`. It validates that
`cmake_export` can be consumed via bzlmod, generates correct CMake packages,
and that those packages actually drive a real CMake `find_package` + link + run.

## What it covers

| Aspect | How it is tested |
|---|---|
| Package file generation | Asserts every `*Config/ConfigVersion/Targets.cmake` + umbrella + toolchain exists |
| Merged archive is built | Asserts `libexport_all_*_merged.a` is produced by `bazel build` (DefaultInfo) |
| Facade / transitive closure | `calc` has no sources; linking it must resolve `add`/`mul` object code |
| Cross-package references | `Calc` link line references `AddLib::add` |
| Compile-define propagation | `BDEG_CALC_VERSION=42` reaches the consumer (`static_assert`) and object code |
| Include propagation | Consumer includes `calc/calc.h` via `INTERFACE_INCLUDE_DIRECTORIES` |
| Version parsing | Non-default `version = "2.3.4"` in `ConfigVersion.cmake` |
| Repo-layout independence | Both `BDEG_EXECROOT` and `BDEG_OUTPUT_BASE` emitted; resolver present |
| Missing-library diagnostic | `_bdeg_report_missing_library` present in generated Targets |
| Per-package whole-archive | `export_calc_wa` emits `INTERFACE IMPORTED` + whole-archive + `--allow-multiple-definition` |
| Default stays STATIC | Non-listed packages remain `STATIC IMPORTED` |
| End-to-end link + run | `consumer/` builds `smoke_test` and runs it under `ctest` |

## Running

Full test (needs `bazel`, `cmake`, and a C++ toolchain):

```bash
cd e2e/smoke
bash run_tests.sh
```

Or from the repo root via Taskfile:

```bash
task test          # full comprehensive smoke test
task test:quick    # just builds the export, no CMake step
```

If `cmake` is not installed, `run_tests.sh` runs all generated-file assertions
and skips only the link/run step.

## Layout

```
e2e/smoke/
├── BUILD                      cc_library targets + cmake_export targets
├── MODULE.bazel               bzlmod deps (rules_bdeg via local_path_override)
├── run_tests.sh               orchestrates build + assertions + cmake/ctest
├── src/calc/                  first-party libraries (add, mul, facade calc)
└── consumer/                  CMake project that find_package()s and links
    ├── CMakeLists.txt
    └── main.cpp
```
