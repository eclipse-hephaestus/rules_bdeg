<!-- ----------------------------------------------------------------------------
  Copyright (c) 2026 Contributors to the Eclipse Foundation

  See the NOTICE file(s) distributed with this work for additional
  information regarding copyright ownership.

  This program and the accompanying materials are made available under the
  terms of the Apache License Version 2.0 which is available at
  https://www.apache.org/licenses/LICENSE-2.0

  SPDX-License-Identifier: Apache-2.0
----------------------------------------------------------------------------- -->

# Engineering Design Proposal: Bazel Dependency Export Generator (BDEG)

> **Historical Document** - This is the original design proposal. For current documentation, see:
> - [User Guide](user-guide.md) - How to use rules_bdeg
> - [Architecture](architecture.md) - Technical internals

**Document Status:** Implemented - See `rules_bdeg/` for the standalone ruleset  
**Project Reference:** scrample (Eclipse Score)  
**Date:** 2026-08-31  
**Updated:** 2026-09-01 (Migration to standalone `rules_bdeg` ruleset complete)

---

## Implementation Status

> **BDEG has been successfully implemented as `rules_bdeg`** - a standalone Bazel ruleset following the [rules-template](https://github.com/bazel-contrib/rules-template) conventions.
>
> **Key accomplishments:**
> - Starlark `cmake_export()` rule implemented (Approach B from this proposal)
> - CMake Config packages generated for GTest, Boost, ScoreFuturecpp
> - Dynamic execroot path resolution (works with any package depth)
> - All tests passing in scrample consumer project
> - **Multi-format architecture** implemented for future Cargo/Gradle support
>
> **Repository structure:**
> ```
> rules_bdeg/
> ├── MODULE.bazel              # v0.1.0
> ├── bdeg/defs.bzl             # Public API (cmake_export, future: cargo_export)
> └── bdeg/private/
>     ├── common.bzl            # Shared CcInfo extraction logic
>     └── cmake/
>         ├── export.bzl        # CMake-specific rule
>         └── templates/        # CMake templates
> ```

---

## 1. Executive Summary

The **Bazel Dependency Export Generator (BDEG)** is a proposed subsystem that uses Bzlmod as the single authoritative source for external dependency definitions, and generates CMake-consumable metadata (Config packages, imported targets, toolchain files) as a Bazel build output. CMake projects consume these artifacts without being aware of Bazel. Developers define dependencies exactly once, in `MODULE.bazel`.

---

## 2. Architecture Proposal

### 2.1 System Layers

```
┌──────────────────────────────────────────────────────────────────────┐
│                        MODULE.bazel  (Single Source of Truth)        │
│   bazel_dep(name="googletest", version="1.17.0")                     │
│   bazel_dep(name="boost.program_options", version="1.87.0")          │
│   bazel_dep(name="score_communication", version="0.1.1")             │
└──────────────────────────┬───────────────────────────────────────────┘
                           │  Bzlmod resolution + lock file
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    BDEG Bazel Extension Layer                        │
│  bdeg = use_extension("//tools/bdeg:extension.bzl", "cmake_export") │
│  bdeg.target(label="@googletest//:gtest", cmake_name="GTest")        │
│  bdeg.target(label="@boost.program_options", cmake_name="Boost")    │
└──────────────────────────┬───────────────────────────────────────────┘
                           │  bazel build //tools/bdeg:export
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Generator Rule (Starlark)                         │
│   Reads:  cquery output, provider metadata, header paths,            │
│           link flags, transitive closure                             │
│   Emits:  cmake_export() provider graph                              │
└──────────────────────────┬───────────────────────────────────────────┘
                           │
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    Artifact Generation Layer                         │
│  bazel-out/bdeg/                                                     │
│    GTestConfig.cmake          BoostConfig.cmake                      │
│    GTestConfigVersion.cmake   BoostConfigVersion.cmake               │
│    GTestTargets.cmake         BoostTargets.cmake                     │
│    bdeg-toolchain.cmake       bdeg-deps.cmake  (umbrella include)   │
└──────────────────────────┬───────────────────────────────────────────┘
                           │  CMAKE_PREFIX_PATH or include()
                           ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    CMakeLists.txt (consumer)                         │
│   include(${BDEG_DIR}/bdeg-deps.cmake)                               │
│   find_package(GTest REQUIRED)                                       │
│   target_link_libraries(scrample PRIVATE GTest::gtest_main)          │
└──────────────────────────────────────────────────────────────────────┘
```

### 2.2 Data Flow

```
MODULE.bazel
    │
    ├─► Bzlmod resolves transitive graph (MODULE.lock)
    │
    ├─► bazel cquery "deps(@googletest//:gtest)" --output=starlark
    │       └─► emits: include dirs, link libs, defines, solib paths
    │
    ├─► bdeg_export() Starlark rule
    │       └─► template engine renders .cmake files per dependency
    │
    └─► bazel build //tools/bdeg:all
            └─► writes artifacts to bazel-out/bdeg/ (symlinked)
```

---

## 3. Comparison with Conan CMakeDeps

| Dimension | Conan CMakeDeps | BDEG (Proposed) |
|---|---|---|
| **Source of truth** | `conanfile.py` / `conanfile.txt` | `MODULE.bazel` |
| **Resolution engine** | Conan graph solver | Bzlmod SAT resolver |
| **Build isolation** | Conan cache (`~/.conan2`) | Bazel output base |
| **Output artifacts** | `FindXXX.cmake`, `XXXConfig.cmake`, toolchain | Same targets, same format |
| **Transitive deps** | Fully automatic | Requires `cquery` traversal |
| **Cross-compilation** | Via Conan profiles | Via Bazel platform/toolchain |
| **Hermetic builds** | Partial (depends on local system libs) | Full hermetic via Bazel |
| **Ecosystem coverage** | C/C++ focused, ~1,800 packages | Any Bazel dep (C++, Go, Rust, Python) |
| **Incremental** | Package-level | Target-level (finer grain) |
| **Vendor/offline** | `conan download` | `bazel fetch --all` |
| **Lock file** | `conan.lock` | `MODULE.bazel.lock` |
| **Existing CMake friction** | Low (widely adopted) | Requires one `include()` or `CMAKE_PREFIX_PATH` |
| **Cross-ecosystem export** | CMake only | Extensible to Cargo, Maven, Gradle |

**Key Conan advantage:** battle-tested generator infrastructure, `pkg-config` integration, rich metadata from recipe authors.

**Key BDEG advantage:** unifies Rust (`rules_rust`), Go (`rules_go`), Python (`rules_python`), and C++ under a single dependency graph — Conan cannot do this.

---

## 4. Gap Analysis of Current Bazel Capabilities

| Capability | Current State | Gap |
|---|---|---|
| Dependency resolution | Bzlmod — fully capable | None |
| Transitive query | `bazel cquery` with Starlark output | Needs structured provider extraction |
| Header path export | `CcInfo.compilation_context.headers` | No CMake serializer exists |
| Link flag export | `CcInfo.linking_context.linker_inputs` | No CMake serializer exists |
| `XXXConfig.cmake` generation | No built-in rule | Must author Starlark templates |
| Version metadata | `module()` version field | No propagation to generated files |
| CMake imported target generation | Not in `rules_cc` | Must author generator rule |
| Toolchain file generation | No CMake toolchain exporter | Must author Starlark rule |
| Bazel→CMake path mapping | No canonical mapping | Need output-base path resolution |
| Incremental re-generation | Bazel action cache | Works once generator rule is defined |
| CI artifact publishing | Not standardized | Need `bazel run` + artifact upload pattern |
| Transitive `INTERFACE_LINK_LIBRARIES` | Available via `CcInfo` traversal | Must manually flatten graph |

---

## 5. Implementation Approaches

### Approach A — `bazel cquery` + External Generator Script

**Mechanism:** A Python or Go script runs `bazel cquery 'deps(//...)'` with `--output=starlark`, parses the JSON/Starlark output, and renders CMake files using Jinja2 templates.

**Advantages:**
- No changes to `MODULE.bazel` or any `.bzl` files
- Can be written and shipped as a standalone CLI tool (`bdeg-cli`)
- Easy to prototype; debuggable with standard Python tooling
- Decoupled from Bazel version specifics

**Disadvantages:**
- Runs outside Bazel — not a hermetic Bazel action, not cached
- Requires Bazel to be installed and a working `WORKSPACE`/Bzlmod setup just to query
- Path resolution between Bazel output base and absolute paths is fragile
- No Starlark providers — must scrape `--output=jsonproto` which is semi-stable API

**Verdict:** Viable as a prototype / MVP path. Not suitable for production.

---

### Approach B — Starlark `cmake_export()` Generator Rule

**Mechanism:** A new `cmake_export()` Starlark rule accepts a list of Bazel targets and produces `XXXConfig.cmake` files as declared build outputs.

```python
# tools/bdeg/defs.bzl
def cmake_export(name, targets, cmake_prefix = None):
    _cmake_export_impl(
        name = name,
        targets = targets,
        cmake_prefix = cmake_prefix or name,
    )
```

Internally, the rule implementation uses `CcInfo` providers to extract compile and link metadata, then renders cmake templates via `ctx.actions.expand_template()`.

**Advantages:**
- First-class Bazel action: hermetic, cached, parallelizable
- Uses stable provider API (`CcInfo`, `DefaultInfo`, `PyInfo`, etc.)
- Output paths are deterministic Bazel outputs — no fragile path stitching
- Naturally integrates with `bazel build` in CI
- Can express transitive dependencies via `depset` traversal

**Disadvantages:**
- Must handle Starlark provider API changes between Bazel versions
- Generated paths inside `bazel-out/` are long; CMake projects need a stable symlink
- Complex for rules that don't expose `CcInfo` (e.g., some `rules_boost` targets)
- Requires Starlark expertise to implement and maintain

**Verdict:** Recommended production approach.

---

### Approach C — Bzlmod Module Extension

**Mechanism:** A Bzlmod `module_extension()` declared in `MODULE.bazel` generates CMake artifacts as part of the Bzlmod extension evaluation phase (repository rules), writing files into an external repository that CMake can then reference via `CMAKE_PREFIX_PATH`.

```python
# MODULE.bazel
cmake_export = use_extension("//tools/bdeg:cmake_extension.bzl", "cmake_export")
cmake_export.dep(label = "@googletest//:gtest", cmake_name = "GTest", version = "1.17.0")
cmake_export.dep(label = "@boost.program_options", cmake_name = "Boost")
use_repo(cmake_export, "bdeg_cmake_packages")
```

**Advantages:**
- Metadata is generated during `bazel fetch` / `bazel sync` — before any build
- Output lives in `bazel-out/external/bdeg_cmake_packages/` — stable reference
- Declarative in `MODULE.bazel` — single file for all dependency concerns
- Supports CI `bazel fetch --all` caching

**Disadvantages:**
- Module extensions run as repository rules — constrained execution environment
- Header file sets are not fully resolved until after analysis phase; a repository rule cannot access `CcInfo` from targets that haven't been analyzed yet
- Creates a chicken-and-egg problem: you need to fetch to get CMake files, but CMake files describe what to fetch
- More complex to implement correctly (lockfile interactions, reproducibility)

**Verdict:** Architecturally elegant but technically constrained. Best for version/URL metadata export only; combine with Approach B for full target metadata.

---

### Approach D — `FindXXX.cmake` Module Generation

**Mechanism:** Generate traditional `FindXXX.cmake` modules rather than modern Config packages. These use `find_path()` / `find_library()` hints populated from Bazel's knowledge of include directories and library paths.

```cmake
# Generated: FindGTest.cmake
set(GTEST_INCLUDE_HINTS "/root/.cache/bazel/_bazel_root/execroot/score_scrample/external/googletest/include")
find_path(GTest_INCLUDE_DIR gtest/gtest.h HINTS ${GTEST_INCLUDE_HINTS})
find_library(GTest_LIBRARY NAMES gtest HINTS ${GTEST_LIB_HINTS})
```

**Advantages:**
- Compatible with older CMake versions (pre-3.0)
- Familiar pattern for CMake developers
- Works without imported targets for very old workflows

**Disadvantages:**
- `find_path` / `find_library` introduces non-hermetic behavior (could find system libs instead)
- No transitive dependency modeling
- Deprecated approach for modern CMake (3.x+)
- Paths are absolute and environment-specific — breaks on other machines unless normalized

**Verdict:** Not recommended. Use Config packages (Approach B) with `IMPORTED` targets instead.

---

### Approach E — CMake Toolchain + Prebuilt Package Export

**Mechanism:** Bazel pre-builds all dependencies as shared or static libraries (via `cc_binary`/`cc_library` with `linkshared`), then generates a CMake toolchain file and Config packages that point to these pre-built artifacts in Bazel's output directory.

**Advantages:**
- CMake does zero compilation of dependency sources — fastest possible CMake configure
- Strongly reproducible: exact Bazel-built artifacts are referenced
- Works even for deps with non-CMake build systems internally (Bazel handles the build)

**Disadvantages:**
- Bazel must fully build all deps before CMake can configure — slow cold builds
- `linkshared` in Bazel is not universally supported for all `cc_library` targets
- Shared library paths in Bazel output base are not installation-stable
- Debugging becomes harder (no source-level stepping through deps)

**Verdict:** Viable for CI/release scenarios, not ideal for local development.

---

## 6. Recommended MVP

### Architecture Decision

**Use Approach B (Starlark `cmake_export()` rule) with a thin bootstrapping script.**

MVP scope is deliberately narrow: generate `XXXConfig.cmake` + `XXXTargets.cmake` with `IMPORTED INTERFACE` targets for C++ header-only and static library dependencies from `MODULE.bazel`.

### MVP Components

> **Status: Implemented** - The MVP is complete and available in `rules_bdeg/`.

```
rules_bdeg/                         # Standalone Bazel ruleset
├── MODULE.bazel                    # Module definition
├── .bazelversion                   # Bazel 8.3.0
├── BUILD.bazel                     # Root package
├── LICENSE                         # Apache 2.0
├── README.md                       # Usage documentation
├── bdeg/
│   ├── BUILD.bazel                 # Public package
│   ├── defs.bzl                    # Public API: cmake_export (+ future formats)
│   └── private/
│       ├── BUILD.bazel
│       ├── common.bzl              # Shared CcInfo extraction logic
│       └── cmake/                  # CMake-specific implementation
│           ├── BUILD.bazel
│           ├── export.bzl          # cmake_export rule
│           └── templates/
│               ├── BUILD.bazel
│               ├── Config.cmake.tpl
│               ├── ConfigVersion.cmake.tpl
│               ├── Targets.cmake.tpl
│               ├── umbrella.cmake.tpl
│               └── toolchain.cmake.tpl
└── e2e/smoke/                      # Integration test
    ├── MODULE.bazel
    ├── BUILD
    └── README.md
```

**Consumer project usage (e.g., scrample):**

```python
# MODULE.bazel
bazel_dep(name = "rules_bdeg", version = "0.1.0")

# tools/bdeg/BUILD.bazel
load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")

cmake_export(
    name = "export",
    deps = {
        "@googletest//:gtest_main":                  "GTest",
        "@boost.program_options":                    "Boost",
        "@score_baselibs//score/language/futurecpp": "ScoreBaselibsFuturecpp",
        "@score_communication//score/mw/com":        "ScoreCom",
        "@score_logging//score/mw/log":              "ScoreLog",
    },
    output_dir = "cmake-packages",
)
```

---

## 7. Example User Workflow

### Developer Setup (Local)

```bash
# Step 1: Resolve and export (one command)
bazel build //tools/bdeg:export

# Step 2: Create symlink to generated packages
ln -sf "$(bazel info bazel-bin)/tools/bdeg/cmake-packages" cmake-packages

# Step 3: Point CMake at the generated packages
cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages"

# Step 4: Normal CMake workflow — no Bazel awareness needed
cmake --build build
ctest --test-dir build
```

### CMakeLists.txt Change (Minimal)

```cmake
# Existing CMakeLists.txt — add only this block near the top:
if(DEFINED BDEG_DIR)
  list(PREPEND CMAKE_PREFIX_PATH "${BDEG_DIR}")
endif()

# Everything below is unchanged:
find_package(GTest REQUIRED)
find_package(Boost COMPONENTS program_options REQUIRED)

target_link_libraries(scrample
    PRIVATE
        GTest::gtest_main
        Boost::program_options
)
```

### CI Workflow

```yaml
# .github/workflows/cmake-build.yml
- name: Export Bazel deps to CMake
  run: bazel build //tools/bdeg:export

- name: Create symlink
  run: ln -sf "$(bazel info bazel-bin)/tools/bdeg/cmake-packages" cmake-packages

- name: Configure CMake
  run: cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages"

- name: Build
  run: cmake --build build --parallel

- name: Test
  run: ctest --test-dir build --output-on-failure
```

---

## 8. Example Generated Artifacts

### `GTestConfig.cmake`

```cmake
# Auto-generated by Bazel Dependency Export Generator (BDEG)
# Source: @googletest//:gtest_main  version: 1.17.0
# DO NOT EDIT — regenerate with: bazel build //tools/bdeg:export

cmake_minimum_required(VERSION 3.14)

set(GTest_VERSION "1.17.0")
set(GTest_VERSION_MAJOR 1)
set(GTest_VERSION_MINOR 17)
set(GTest_VERSION_PATCH 0)

include("${CMAKE_CURRENT_LIST_DIR}/GTestTargets.cmake")

set(GTest_FOUND TRUE)
set(GTEST_FOUND TRUE)  # legacy variable
```

### `GTestTargets.cmake`

```cmake
# Auto-generated by BDEG
if(TARGET GTest::gtest_main)
  return()
endif()

add_library(GTest::gtest STATIC IMPORTED)
set_target_properties(GTest::gtest PROPERTIES
  IMPORTED_LOCATION
    "/root/.cache/bazel/_bazel_root/execroot/score_scrample/bazel-out/k8-fastbuild/bin/external/googletest/libgtest.a"
  INTERFACE_INCLUDE_DIRECTORIES
    "/root/.cache/bazel/_bazel_root/execroot/score_scrample/external/googletest/googletest/include"
  INTERFACE_COMPILE_FEATURES
    "cxx_std_14"
)

add_library(GTest::gtest_main STATIC IMPORTED)
set_target_properties(GTest::gtest_main PROPERTIES
  IMPORTED_LOCATION
    "/root/.cache/bazel/_bazel_root/execroot/score_scrample/bazel-out/k8-fastbuild/bin/external/googletest/libgtest_main.a"
  INTERFACE_LINK_LIBRARIES
    "GTest::gtest"
)
```

### `bdeg-deps.cmake` (Umbrella)

```cmake
# Auto-generated by BDEG — include this file from your CMakeLists.txt
# or add the directory to CMAKE_PREFIX_PATH and use find_package() normally.
set(BDEG_PACKAGE_DIR "${CMAKE_CURRENT_LIST_DIR}")
list(APPEND CMAKE_PREFIX_PATH "${BDEG_PACKAGE_DIR}")

include("${BDEG_PACKAGE_DIR}/GTestConfig.cmake")
include("${BDEG_PACKAGE_DIR}/BoostConfig.cmake")
include("${BDEG_PACKAGE_DIR}/ScoreComConfig.cmake")
include("${BDEG_PACKAGE_DIR}/ScoreLogConfig.cmake")
include("${BDEG_PACKAGE_DIR}/ScoreBaselibsFuturecppConfig.cmake")
```

### `bdeg-toolchain.cmake`

```cmake
# Compiler settings derived from Bazel toolchain (score_toolchains_qnx / default host)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

# When cross-compiling for QNX (matches Bazel platform //platforms:qnx_aarch64)
if(DEFINED BDEG_PLATFORM AND BDEG_PLATFORM STREQUAL "qnx_aarch64")
  set(CMAKE_SYSTEM_NAME QNX)
  set(CMAKE_SYSTEM_PROCESSOR aarch64)
  set(CMAKE_CXX_COMPILER "$ENV{QNX_HOST}/usr/bin/aarch64-unknown-nto-qnx7.1.0-g++")
endif()
```

---

## 9. Bazel → Cargo Integration Comparison

### Why CMake Integration Is Achievable

CMake is a **build description language** — it does not own or perform dependency resolution. It accepts externally provided package metadata via `find_package()` and `CMAKE_PREFIX_PATH`. This makes it a passive consumer. BDEG can therefore act as a translation layer: Bazel resolves, BDEG translates, CMake consumes.

### Why Cargo Integration Is Fundamentally Harder

Cargo is an **opinionated, integrated build + dependency resolution system**. It is not designed as a passive consumer of externally resolved dependencies. The key blockers:

| Problem | Detail |
|---|---|
| **Cargo owns `Cargo.lock`** | Cargo will re-resolve dependencies from `Cargo.toml` ignoring any external lock. Forcing Bazel's resolved graph means patching Cargo's resolver — invasive. |
| **`Cargo.toml` is mandatory** | Every Rust crate must have a `Cargo.toml`. Bazel-managed crates (via `rules_rust` + `crate_universe`) generate synthetic `Cargo.toml` files, but Cargo will try to re-resolve them. |
| **Build scripts (`build.rs`)** | Cargo executes `build.rs` scripts that generate code. `rules_rust` reimplements this, but the two execution environments are not synchronized. |
| **Proc-macro resolution** | Requires Cargo's own toolchain pipeline. `rules_rust` has its own, non-interchangeable implementation. |
| **Workspace semantics** | Cargo workspaces enforce a single resolver across all crates. Injecting Bazel-resolved metadata breaks workspace resolver invariants. |
| **Feature unification** | Cargo performs feature unification across the dependency graph. Bazel's `crate_universe` mimics this but the results are not guaranteed identical. |

**Viable Cargo Integration Path:** `rules_rust` + `crate_universe` can generate a `Cargo.lock`-compatible lockfile from Bzlmod declarations. This allows `cargo check` and IDE tools (rust-analyzer) to work. This is not full build delegation but it is the closest achievable integration.

---

## 10. Extensible Multi-Build-System Architecture

BDEG is designed as a **Dependency Metadata Platform** — Bazel acts as the universal resolver and emits format-specific metadata adapters.

```
                    MODULE.bazel (Universal Truth)
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        cmake_export  cargo_export  maven_export
              │            │            │
              ▼            ▼            ▼
      XXXConfig.cmake  Cargo.lock   pom.xml stubs
      Targets.cmake    .cargo/      Maven BOM
      toolchain.cmake  config.toml  Gradle catalog
```

**Implemented architecture:**

```
bdeg/private/
├── common.bzl              # Shared CcInfo extraction (format-agnostic)
│   ├── extract_target_metadata()     # Returns struct with all metadata
│   ├── build_label_to_export_map()   # Maps Bazel labels → export names
│   └── resolve_transitive_deps()     # Resolves deps to export names
│
├── cmake/                  # CMake format (IMPLEMENTED)
│   ├── export.bzl          # cmake_export rule using common.bzl
│   └── templates/          # CMake-specific templates
│
├── cargo/                  # Cargo format (FUTURE)
│   ├── export.bzl          # cargo_export rule using common.bzl
│   └── templates/          # Cargo.toml, build.rs templates
│
└── gradle/                 # Gradle format (FUTURE)
    ├── export.bzl
    └── templates/
```

**Public API (defs.bzl):**

```python
# Currently available
load("//bdeg/private/cmake:export.bzl", _cmake_export = "cmake_export")
cmake_export = _cmake_export

# Future additions
# load("//bdeg/private/cargo:export.bzl", _cargo_export = "cargo_export")
# cargo_export = _cargo_export
```

**Adding a new format requires:**
1. Create `bdeg/private/<format>/export.bzl` that loads `common.bzl`
2. Implement format-specific `_<format>_target_name()` function
3. Create templates in `bdeg/private/<format>/templates/`
4. Re-export from `bdeg/defs.bzl`

---

## 11. Technical Challenges and Risks

| Challenge | Severity | Mitigation |
|---|---|---|
| **Absolute path instability** — Bazel output base path varies per machine/user | High | Use `$(bazel info output_base)` in wrapper script; generate relative paths where possible using CMake `${CMAKE_CURRENT_LIST_DIR}` |
| **Header sets not fully resolved at repository phase** | High | Use Approach B (build-time rule), not Approach C (extension), for header extraction |
| **`rules_boost` wrapping** — boost targets don't expose clean `CcInfo` for all variants | Medium | Add explicit `cmake_export()` overrides for known-complex deps; fallback to manual header/lib hints |
| **Cross-compilation mismatch** — Bazel platform ≠ CMake toolchain | Medium | Generate one export artifact per Bazel `--platforms` configuration; name them by platform triple |
| **Debug symbol paths** — DWARF paths reference Bazel sandbox dirs | Medium | Document limitation; provide `debuginfod` or remap script for GDB/LLDB |
| **API stability of `CcInfo`** | Low-Medium | Pin Bazel version; add CI check that builds the exporter itself on Bazel upgrades |
| **Shared lib RPATH** — shared libs in `bazel-out/` need RPATH or install step | Medium | Prefer static libraries in BDEG MVP; add `CMAKE_INSTALL_RPATH` helpers for shared lib path |
| **Incremental invalidation** — CMake doesn't know when Bazel exports are stale | Low | Provide `bdeg-version.cmake` with a hash of `MODULE.bazel.lock`; CMake can check it |

---

## 12. Backlog: Epic, Features, User Stories, Acceptance Criteria, and Technical Spikes

---

### EPIC: BDEG-0001 — Bazel Dependency Export Generator

> **Goal:** Enable CMake projects to consume Bazel-managed external C++ dependencies without duplicating dependency definitions, with full transitive dependency support, and minimal changes to existing CMake projects.

---

### Feature: BDEG-F001 — Core Starlark `cmake_export()` Rule

**Description:** Implement the foundational `cmake_export()` Starlark rule that ingests Bazel C++ targets and produces `XXXConfig.cmake` + `XXXTargets.cmake` artifacts.

#### User Story BDEG-US001

**As a** build systems engineer,  
**I want** to declare a list of Bazel C++ targets in a `cmake_export()` rule,  
**So that** I can generate CMake Config packages for those targets with a single `bazel build` invocation.

**Acceptance Criteria:**
- [ ] `cmake_export(name, deps)` rule is callable from any `BUILD.bazel` file
- [ ] Running `bazel build //tools/bdeg:export` produces one `XXXConfig.cmake` and one `XXXTargets.cmake` per declared dependency
- [ ] Generated files pass `cmake --find-package -DNAME=GTest -DCOMPILER_ID=GNU -DLANGUAGE=CXX -DMODE=EXIST` validation
- [ ] Rule is idempotent: rebuilding without changes produces no new actions (Bazel action cache hit)
- [ ] Unit test: `bazel test //tools/bdeg:cmake_export_test` covers at least googletest export

---

#### User Story BDEG-US002

**As a** C++ developer,  
**I want** generated CMake targets to carry correct include directories and compile flags,  
**So that** I can use `target_link_libraries(my_target PRIVATE GTest::gtest_main)` without manually specifying include paths.

**Acceptance Criteria:**
- [ ] `INTERFACE_INCLUDE_DIRECTORIES` in generated `XXXTargets.cmake` matches `CcInfo.compilation_context.includes` from Bazel
- [ ] `INTERFACE_COMPILE_DEFINITIONS` matches `CcInfo.compilation_context.defines`
- [ ] `INTERFACE_COMPILE_OPTIONS` matches `CcInfo.compilation_context.user_compile_flags`
- [ ] Paths use `${CMAKE_CURRENT_LIST_DIR}`-relative forms or are generated via CMake `file(REAL_PATH ...)` for portability
- [ ] Verified by integration test that builds a simple CMake project against generated packages

---

#### User Story BDEG-US003

**As a** build systems engineer,  
**I want** transitive dependencies to be expressed as `INTERFACE_LINK_LIBRARIES` chains in generated CMake files,  
**So that** consumers do not need to list every transitive dependency explicitly.

**Acceptance Criteria:**
- [ ] Transitive `CcInfo` providers are traversed via `depset(transitive=...)` walk
- [ ] Each transitive dependency node generates its own `XXXTargets.cmake` entry as an `IMPORTED` target
- [ ] Circular dependency guards (`if(TARGET ...)`) are present in all generated files
- [ ] `INTERFACE_LINK_LIBRARIES` chains are validated to not contain raw `-l` flags for managed deps — only `Namespace::Target` references
- [ ] Test: `score_communication` exported target correctly chains `score_baselibs` and `score_logging` as transitive deps

---

### Feature: BDEG-F002 — CMake Toolchain Export

**Description:** Generate a `bdeg-toolchain.cmake` file that mirrors the active Bazel toolchain's compiler, sysroot, and standard version settings.

#### User Story BDEG-US004

**As a** developer cross-compiling for QNX,  
**I want** a generated CMake toolchain file derived from the active Bazel toolchain,  
**So that** `cmake -DCMAKE_TOOLCHAIN_FILE=bdeg-toolchain.cmake` uses the same compiler as `bazel build --platforms=//platforms:qnx_aarch64`.

**Acceptance Criteria:**
- [ ] `bdeg-toolchain.cmake` is generated alongside Config packages
- [ ] When `--platforms=//platforms:qnx_aarch64` is active, `CMAKE_CXX_COMPILER` in the toolchain file points to the QNX `aarch64-unknown-nto-qnx*-g++` binary
- [ ] `CMAKE_CXX_STANDARD` matches the Bazel `copts` standard setting
- [ ] Host (x86_64 Linux) and QNX target toolchains each produce a distinct, named toolchain file

---

### Feature: BDEG-F003 — Developer Experience & Umbrella Integration

#### User Story BDEG-US005

**As a** CMake developer unfamiliar with Bazel,  
**I want** a single `include(bdeg-deps.cmake)` in my `CMakeLists.txt`,  
**So that** all dependencies are available via `find_package()` without understanding how BDEG works.

**Acceptance Criteria:**
- [ ] `bdeg-deps.cmake` umbrella file is generated, including all exported packages
- [ ] Adding `include(${BDEG_DIR}/bdeg-deps.cmake)` before any `find_package()` call is the only required CMake change
- [ ] `CMakeLists.txt` change is documented in `README.md` with a copy-paste snippet
- [ ] Works with CMake 3.16+ (minimum supported version)
- [ ] `bdeg-deps.cmake` contains a `BDEG_VERSION` variable matching `MODULE.bazel` module version

---

#### User Story BDEG-US006

**As a** CI engineer,  
**I want** the export step to be a single shell command usable in any CI runner,  
**So that** I can add Bazel dependency export to any pipeline without Bazel expertise.

**Acceptance Criteria:**
- [ ] `tools/bdeg/run_export.sh [--platform <name>]` runs `bazel build //tools/bdeg:export` and symlinks output to `cmake-packages/`
- [ ] Exit code is non-zero if `bazel build` fails
- [ ] Script works in a clean Docker container with only Bazel installed (no pre-installed packages)
- [ ] CI example workflow is provided for GitHub Actions

---

### Feature: BDEG-F004 — Validation & Regression Testing

#### User Story BDEG-US007

**As a** contributor to BDEG,  
**I want** automated tests that verify generated CMake files are syntactically valid and functionally correct,  
**So that** regressions are caught before they reach users.

**Acceptance Criteria:**
- [ ] `bazel test //tools/bdeg:validate_cmake` runs `cmake --find-package` on all generated packages and asserts exit 0
- [ ] Integration test builds the `scrample` binary using only generated BDEG packages (no manual `include_directories`)
- [ ] Test matrix covers: Linux x86_64 host, QNX cross-compilation target
- [ ] CMake version matrix: 3.16, 3.22, 3.28 (latest)
- [ ] Tests are run in GitHub Actions CI on every PR touching `MODULE.bazel` or `tools/bdeg/`

---

### Technical Spike: BDEG-SPIKE-001 — `CcInfo` Provider Extraction Feasibility

**Goal:** Determine whether `CcInfo` providers from `@googletest`, `@boost.program_options`, `@score_communication`, and `@score_baselibs` expose sufficient metadata (include dirs, link libs, static lib paths) to generate correct CMake Config packages without requiring manual overrides.

**Time-box:** 3 days

**Deliverables:**
1. Starlark script that uses `cquery --output=starlark` to dump `CcInfo` fields for the four target sets
2. Written analysis: which fields are populated, which are empty, which require fallback
3. Decision: proceed with Approach B as-is, or require hybrid of B + manual hint system
4. Prototype of one `cmake_export()` rule that successfully generates `GTestConfig.cmake` importable by a test CMake project

**Acceptance Criteria:**
- [ ] Spike output is committed to `tools/bdeg/spike/` with a `FINDINGS.md`
- [ ] At least one working `GTestConfig.cmake` generated and tested in a CMake configure step
- [ ] Go/no-go recommendation for Feature BDEG-F001 is documented

---

### Technical Spike: BDEG-SPIKE-002 — Cross-Platform Path Portability

**Goal:** Determine the correct strategy for generated paths in CMake files so they work on developer machines, in Docker CI containers, and in Bazel Remote Build Execution (RBE) environments.

**Time-box:** 2 days

**Deliverables:**
1. Matrix of path types: `bazel-out/`, `external/`, `execroot/` — and their stability guarantees
2. Recommendation: relative paths, CMake `file(REAL_PATH)`, or wrapper script path injection
3. Prototype CMake snippet that resolves a generated path correctly across 2+ environments

---

## 13. Recommended Implementation Sequence

| Sprint | Work Items |
|---|---|
| Sprint 1 | BDEG-SPIKE-001 + BDEG-SPIKE-002 |
| Sprint 2 | BDEG-F001: US001 + US002 (core rule, include/compile metadata) |
| Sprint 3 | BDEG-F001: US003 (transitive dependency chains) |
| Sprint 4 | BDEG-F003: US005 + US006 (DX umbrella + CI integration) |
| Sprint 5 | BDEG-F002: US004 (toolchain file export) |
| Sprint 6 | BDEG-F004: US007 (validation & regression tests) + architecture review for multi-ecosystem extensibility |

---

## 14. Summary

| Dimension | Recommendation |
|---|---|
| **Approach** | Starlark `cmake_export()` build rule (Approach B) |
| **Source of truth** | `MODULE.bazel` — no duplication |
| **CMake change required** | One `include()` or `CMAKE_PREFIX_PATH` addition |
| **Transitive deps** | Via `CcInfo` depset traversal |
| **Cross-compilation** | Separate export per Bazel `--platforms` config |
| **Cargo integration** | Out of scope for MVP; proceed via `rules_rust` lockfile export only |
| **Future extensibility** | Exporter plugin architecture in `tools/bdeg/exporters/` |
| **MVP milestone** | googletest + boost.program_options + score_* stack exporting correctly, scrample CMake build passing |

The scrample project's `MODULE.bazel` is an excellent reference implementation for BDEG. It already uses Bzlmod cleanly, has well-defined `CcInfo`-compatible C++ targets (`@googletest`, `@boost.program_options`, `@score_baselibs`, `@score_communication`, `@score_logging`), and has an existing `src/BUILD` that documents the exact dependency graph to export. The technical spike can be executed directly against this project with no setup overhead.
