<!-- ----------------------------------------------------------------------------
  Copyright (c) 2026 Contributors to the Eclipse Foundation

  See the NOTICE file(s) distributed with this work for additional
  information regarding copyright ownership.

  This program and the accompanying materials are made available under the
  terms of the Apache License Version 2.0 which is available at
  https://www.apache.org/licenses/LICENSE-2.0

  SPDX-License-Identifier: Apache-2.0
----------------------------------------------------------------------------- -->

# User Guide

This guide covers everything you need to use `rules_bdeg` to export Bazel C++ dependencies as CMake packages.

## Prerequisites

- Bazel 8.0.0+
- CMake 3.16+

### Tested Versions

| Component | Tested Versions |
|-----------|-----------------|
| Bazel | 8.0.0, 8.3.0 |
| CMake | 3.16, 3.22, 3.28 |
| OS | Linux (Ubuntu 22.04, 24.04) |

---

## Installation

Add to your `MODULE.bazel`:

```python
bazel_dep(name = "rules_bdeg", version = "0.1.0")

# Until published to BCR, use git_override:
git_override(
    module_name = "rules_bdeg",
    remote = "https://github.com/siemens/rules_bdeg.git",  # Update with actual repo
    tag = "v0.1.0",
)
```

<details>
<summary><b>Alternative Installation Methods</b></summary>

### From Bazel Central Registry (when published)

```python
bazel_dep(name = "rules_bdeg", version = "0.1.0")
```

### From GitHub Archive

```python
bazel_dep(name = "rules_bdeg", version = "0.1.0")

archive_override(
    module_name = "rules_bdeg",
    urls = ["https://github.com/siemens/rules_bdeg/archive/refs/tags/v0.1.0.tar.gz"],
    strip_prefix = "rules_bdeg-0.1.0",
    integrity = "sha256-...",  # Recommended
)
```

### Local Development

```python
bazel_dep(name = "rules_bdeg", version = "0.1.0")

local_path_override(
    module_name = "rules_bdeg",
    path = "../rules_bdeg",
)
```

| Method | Use Case | Pros | Cons |
|--------|----------|------|------|
| BCR | Production | Simplest | Requires publishing |
| `git_override` | Pre-BCR | Easy updates | Network dependent |
| `archive_override` | Stable releases | Fast, cached | Manual URL updates |
| `local_path_override` | Local dev | Instant changes | Not shareable |

</details>

---

## Quick Start

### 1. Add rules_bdeg to MODULE.bazel

```python
# MODULE.bazel
module(
    name = "my_project",
    version = "0.1.0",
)

# Add rules_bdeg (see Installation section above)
bazel_dep(name = "rules_bdeg", version = "0.1.0")

# Your dependencies
bazel_dep(name = "googletest", version = "1.17.0")
bazel_dep(name = "boost.program_options", version = "1.87.0")
```

### 2. Define Exports

```python
# BUILD.bazel
load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")

cmake_export(
    name = "export",
    deps = {
        "@googletest//:gtest": "GTest",
        "@googletest//:gtest_main": "GTest",
        "@boost.program_options": "Boost",
    },
)
```

### 3. Build and Use

```bash
# Step 1: Generate CMake packages (also builds the merged archives they point at)
bazel build //:export

# Step 2: Create symlink to generated packages
ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages

# Step 3: Build with CMake
cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages"
cmake --build build
```

> **One build step is enough.** With the default `merge_static_libraries = True`, building `//:export` also builds a merged `.a` archive per package (they are part of the target's outputs). That means the libraries CMake links against are produced in the same `bazel build` - you no longer need to build each dependency separately first. The export still reads headers/include dirs/defines from the Bazel targets' `CcInfo`.

---

## CMake Integration

### Minimal CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.16)
project(my_project)

# BDEG integration
set(BDEG_DIR "${CMAKE_SOURCE_DIR}/cmake-packages" CACHE PATH "BDEG packages")
include("${BDEG_DIR}/bdeg-deps.cmake")
include("${BDEG_DIR}/bdeg-toolchain.cmake")

# Use packages normally
find_package(GTest REQUIRED)
find_package(Boost REQUIRED)

add_executable(my_app main.cpp)
target_link_libraries(my_app PRIVATE GTest::gtest Boost::Boost)
```

### Generated Files

For each exported dependency, BDEG generates:

```
cmake-packages/
├── GTestConfig.cmake
├── GTestConfigVersion.cmake
├── GTestTargets.cmake        # imported target, link line, include dirs
├── BoostConfig.cmake
├── BoostConfigVersion.cmake
├── BoostTargets.cmake
├── bdeg-deps.cmake          # Umbrella: sets BDEG_EXECROOT + BDEG_OUTPUT_BASE, includes all packages
└── bdeg-toolchain.cmake     # C++ standard settings
```

Alongside these, the merged archives each package links against are produced in
`bazel-bin` as `libexport_<Package>_merged.a`.

> `bdeg-deps.cmake` sets two roots - `BDEG_EXECROOT` and `BDEG_OUTPUT_BASE` -
> and the generated `Targets.cmake` resolves paths against whichever exists.
> This makes the packages work under both the legacy and the modern (bzlmod
> sibling) Bazel repository layouts without any manual symlinking.

---

## Rule Reference

### `cmake_export`

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `deps` | `label_keyed_string_dict` | required | Map of Bazel targets to CMake package names |
| `merge_static_libraries` | `bool` | `True` | Auto-generate one merged archive per package containing the full transitive closure (see [Linking model](#linking-model-merged-archives)). Leave this on for real code. |
| `whole_archive` | `bool` | `False` | Link **all** exported packages with `--whole-archive`. Rarely needed; prefer `whole_archive_packages`. |
| `whole_archive_packages` | `string_list` | `[]` | List of package names to whole-archive individually, leaving the rest as normal `STATIC`. |
| `cmake_prefix` | `string` | `"BDEG"` | Prefix for CMake variables |
| `output_dir` | `string` | `"cmake-packages"` | Output directory name. **Must be unique** if you have more than one `cmake_export` in the same Bazel package. |
| `version` | `string` | `"0.1.0"` | Version for generated packages |
| `cxx_standard` | `string` | `"17"` | C++ standard for toolchain file |

> One `cmake_export` can declare many packages at once. Standard rule attributes like `visibility` and `tags` are also accepted.

---

## Linking model: merged archives

Understanding this one concept explains most of BDEG's behavior.

### Why a "merged archive"

In Bazel, a `cc_library` only ever archives *its own* sources. A **facade**
library - one with no `srcs`, only `hdrs` + `deps` - therefore owns almost no
object code; the real implementation lives in its (possibly deep) dependency
tree. If BDEG exported only the facade's own tiny archive, your CMake build
would compile fine (headers resolve) but fail to **link** with dozens of
"undefined reference" errors.

To prevent that, for each exported package BDEG automatically synthesizes a
single **merged archive** (a native `cc_static_library`) that bundles the
package's *entire transitive closure* of object code into one self-contained
`.a`. The generated `IMPORTED_LOCATION` points at this merged archive, so
`target_link_libraries(... Calc::Calc)` links everything the library actually
needs. You do **not** have to hand-write `cc_static_library` targets.

```
facade cc_library (headers + deps, no sources)
        │  merge_static_libraries = True (default)
        ▼
one merged .a  ──►  IMPORTED_LOCATION in <Pkg>Targets.cmake
```

You will see these archives in `bazel-bin` named like
`libexport_<Package>_merged.a`. They are built as part of `bazel build //:export`.

### STATIC vs whole-archive

By default the merged archive is imported as a normal `STATIC` library: the
linker pulls in exactly the objects your code references and drops the rest.
That is the right choice for almost everything.

Some libraries need **every** object kept even if nothing references it
directly - plugin registries, static-initialization side effects, or symbols
reached only via `dlopen`. For those, enable whole-archive:

```python
# All packages whole-archived (rarely what you want):
cmake_export(name = "export", deps = {...}, whole_archive = True)

# Just the packages that need it (preferred):
cmake_export(
    name = "export",
    deps = {
        "@score_communication//score/mw/com": "ScoreCommunication",
        "@score_baselibs//...": "ScoreBaseLibs",
    },
    whole_archive_packages = ["ScoreCommunication"],  # NOT ScoreBaseLibs
)
```

> **Avoid double whole-archiving overlapping packages.** If package A's closure
> already contains package B (A depends on B), whole-archiving *both* links B's
> objects twice and can cause "multiple definition" errors. Whole-archive only
> the top-level component and leave the subsumed one as the default `STATIC`.
> (In the default `STATIC` mode this overlap is harmless - normal archive
> semantics ignore the duplicate.)

### External and system libraries

The merged archive contains only code **Bazel built**. A genuine prebuilt
system library (e.g. a `libacl.a` shipped by a repo rule) is not merged in;
BDEG keeps its path in the package's `INTERFACE_LINK_LIBRARIES` so the consumer
still links it. Bazel-built leaf archives that are already inside the merged
archive are dropped from that list to avoid double-linking.

---

## Understanding the deps Mapping

The `deps` attribute maps Bazel targets to CMake namespaces. The resulting CMake target name is:

```
<CMake namespace>::<Bazel target name>
```

### Examples

```python
deps = {
    # Bazel label                    CMake namespace    →  CMake target
    "@googletest//:gtest":           "GTest",           #  GTest::gtest
    "@googletest//:gtest_main":      "GTest",           #  GTest::gtest_main
    "@abseil-cpp//absl/strings":     "AbslStrings",     #  AbslStrings::strings
    "@boost.program_options":        "Boost",           #  Boost::program_options
}
```

### Naming Rules

| Bazel Label | CMake Namespace | Resulting CMake Target |
|-------------|-----------------|------------------------|
| `@repo//:target` | `"Pkg"` | `Pkg::target` |
| `@repo//path:target` | `"Pkg"` | `Pkg::target` |
| `@repo//path/to:target` | `"Pkg"` | `Pkg::target` |

The **Bazel target name** (after the colon) becomes the CMake target suffix. The **CMake namespace** (the dict value) becomes the prefix.

### Grouping Related Targets

Use the same namespace for related targets:

```python
deps = {
    "@googletest//:gtest": "GTest",       # GTest::gtest
    "@googletest//:gtest_main": "GTest",  # GTest::gtest_main
    "@googletest//:gmock": "GTest",       # GTest::gmock
}
```

Then in CMake:
```cmake
find_package(GTest REQUIRED)
target_link_libraries(my_test PRIVATE GTest::gtest_main GTest::gmock)
```

---

## What to Export

### Export targets you'll link against

Export the Bazel targets that your CMake code will use via `target_link_libraries()`:

```python
# Good: Export what CMake needs to link
deps = {
    "@googletest//:gtest_main": "GTest",  # Your tests link this
    "@abseil-cpp//absl/strings": "Absl",  # Your code links this
}
```

### Don't export internal targets

Skip internal or implementation-detail targets that aren't part of the public API:

```python
# Avoid: Internal targets users shouldn't link directly
deps = {
    "@some_lib//:internal_impl": "SomeLib",  # Don't export internals
}
```

### Header-only libraries work automatically

Header-only libraries generate `INTERFACE` CMake targets (no `IMPORTED_LOCATION`):

```python
deps = {
    "@nlohmann_json//:json": "nlohmann_json",  # Header-only → INTERFACE target
}
```

### Transitive dependencies

BDEG handles transitive dependencies automatically (see
[Linking model](#linking-model-merged-archives)):

- Object code from the whole dependency tree is bundled into the package's
  merged archive, so the library links completely even for facade targets.
- If a transitive dep is **also** exported as its own package (e.g. both
  `gtest_main` and `gtest`), the generated `INTERFACE_LINK_LIBRARIES`
  cross-references the CMake target (`GTest::gtest`) instead of a raw path.
- Genuine external/system libraries (prebuilt `.a` files not built by Bazel)
  are kept as resolved absolute paths so you still link them.

You generally only need to list the targets you link against directly; their
dependencies come along inside the merged archive.

---

## Common Patterns

### Multiple Targets from Same Repository

```python
cmake_export(
    name = "export",
    deps = {
        "@abseil-cpp//absl/strings": "AbslStrings",
        "@abseil-cpp//absl/container:flat_hash_map": "AbslFlatHashMap",
        "@abseil-cpp//absl/synchronization": "AbslSync",
    },
)
```

### Custom Output Directory

```python
cmake_export(
    name = "export",
    deps = {...},
    output_dir = "my-cmake-deps",
)
```

### Specifying C++ Standard

```python
cmake_export(
    name = "export",
    deps = {...},
    cxx_standard = "20",
)
```

### Whole-archiving specific packages

Keep every object of a component (static-init side effects, plugin registries,
`dlopen`'d symbols) while leaving the rest lean:

```python
cmake_export(
    name = "export",
    deps = {
        "@my_service//service": "MyService",
        "@my_baselibs//...": "MyBaseLibs",
    },
    whole_archive_packages = ["MyService"],  # subsumes MyBaseLibs; don't list both
)
```

See [STATIC vs whole-archive](#static-vs-whole-archive) for when (and when not)
to use this.

### Multiple exports in the same Bazel package

Each `cmake_export` in the same `BUILD` file must use a distinct `output_dir`,
otherwise two targets would try to generate the same files:

```python
cmake_export(name = "export_app",  deps = {...}, output_dir = "cmake-packages")
cmake_export(name = "export_tools", deps = {...}, output_dir = "cmake-packages-tools")
```

---

## Build Workflow

### Development Script

Create `build.sh` to automate the workflow:

```bash
#!/bin/bash
set -e

echo "=== Generating CMake packages (also builds the merged archives) ==="
bazel build //:export

echo "=== Creating symlink ==="
ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages

echo "=== Configuring CMake ==="
cmake -B build -DBDEG_DIR="$(pwd)/cmake-packages"

echo "=== Building ==="
cmake --build build

echo "=== Done ==="
```

### CI Workflow (GitHub Actions)

```yaml
- name: Export Bazel deps
  run: |
    bazel build //:export        # also builds the merged archives
    ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages

- name: Build with CMake
  run: |
    cmake -B build -DBDEG_DIR="$(pwd)/cmake-packages"
    cmake --build build
```

---

## Project Structure

Recommended layout:

```
my_project/
├── MODULE.bazel              # Bazel dependencies + rules_bdeg
├── BUILD.bazel               # cmake_export rule
├── CMakeLists.txt            # CMake project
├── cmake-packages/           # Symlink to generated packages
├── build.sh                  # Build automation
└── src/
    └── main.cpp
```

---

## Bazel-CMake Round-Trip Workflow

BDEG enables a complete round-trip between Bazel and CMake ecosystems. Together with `rules_foreign_cc`, you can:
1. Use Bazel dependencies in CMake projects
2. Publish your CMake project back as a Bazel module

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BAZEL ECOSYSTEM                                      │
│                                                                              │
│   @googletest          @boost           @score_baselibs                     │
│        │                  │                   │                              │
│        └──────────────────┴───────────────────┘                              │
│                           │                                                  │
│                           │  rules_bdeg cmake_export()                       │
│                           ▼                                                  │
│                  ┌─────────────────────┐                                     │
│                  │  CMake Packages     │                                     │
│                  │  - GTestConfig.cmake│                                     │
│                  │  - BoostConfig.cmake│                                     │
│                  └──────────┬──────────┘                                     │
└─────────────────────────────│────────────────────────────────────────────────┘
                              │
                              │  find_package()
                              ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                       YOUR CMAKE PROJECT                                     │
│                                                                              │
│   CMakeLists.txt                                                            │
│   ├── find_package(GTest REQUIRED)                                          │
│   ├── find_package(Boost REQUIRED)                                          │
│   ├── add_library(mylib src/*.cpp)                                          │
│   └── target_link_libraries(mylib GTest::gtest Boost::boost)                │
│                                                                              │
│   Develop and build normally with CMake                                      │
└──────────────────────────────┬──────────────────────────────────────────────┘
                               │
                               │  rules_foreign_cc cmake()
                               ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         BAZEL ECOSYSTEM                                      │
│                                                                              │
│   # Your project as a Bazel module                                          │
│   cmake(                                                                     │
│       name = "mylib",                                                        │
│       lib_source = ":cmake_sources",                                         │
│       deps = ["@googletest//:gtest", "@boost//:boost"],                      │
│   )                                                                          │
│                                                                              │
│   # Other Bazel projects can depend on it:                                  │
│   cc_binary(                                                                 │
│       name = "consumer_app",                                                 │
│       deps = ["@your_module//:mylib"],                                       │
│   )                                                                          │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Complementary Tools

| Tool | Direction | Use Case |
|------|-----------|----------|
| **rules_bdeg** | Bazel → CMake | CMake project consuming Bazel deps |
| **rules_foreign_cc** | CMake → Bazel | Bazel project building CMake deps |

---

## Troubleshooting

### "BDEG packages not found"

**Error:** CMake can't find `bdeg-deps.cmake`

**Fix:**
```bash
# 1. Build the export
bazel build //:export

# 2. Create the symlink
ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages

# 3. Verify it exists
ls -la cmake-packages/bdeg-deps.cmake
```

### "Library not found" at CMake configure time

BDEG prints one of two precise messages so you can tell the cause apart:

- **"...its directory exists but the archive is missing - the providing Bazel
  target is likely not built yet."** The path resolved, but the `.a` isn't on
  disk. Build the export (which now also builds the merged archives):
  ```bash
  bazel build //:export
  ```
- **"...its directory does not exist - BDEG could not resolve the path."** The
  path itself couldn't be found under either repository root. This usually
  means a stale symlink or a cache that was cleaned. Re-generate and re-link:
  ```bash
  bazel build //:export
  ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages
  ```

### CMake can't find package with find_package()

**Error:** `Could not find a package configuration file provided by "GTest"`

**Checklist:**
1. Package name in `find_package(GTest)` matches the namespace in `cmake_export` deps
2. `BDEG_DIR` is set correctly: `cmake -DBDEG_DIR="$(pwd)/cmake-packages" ...`
3. You included the umbrella file: `include("${BDEG_DIR}/bdeg-deps.cmake")`
4. Symlink is valid: `ls -la cmake-packages`

### Undefined reference at link time

**Error:** Linker errors for symbols that should be in the exported library

**Causes & fixes:**
- A required **external/system** library isn't linked. BDEG keeps prebuilt
  system `.a` paths, but if a symbol comes from a system `.so` your consumer
  must link it (e.g. `target_link_libraries(my_app PRIVATE ... pthread dl)`).
- The symbols are only reachable via static-init/registration (nothing
  references them directly), so normal `STATIC` linking drops them. Enable
  whole-archive for that package - see
  [STATIC vs whole-archive](#static-vs-whole-archive):
  ```python
  cmake_export(name = "export", deps = {...}, whole_archive_packages = ["MyPkg"])
  ```
- Wrong CMake target name in `target_link_libraries()` - check your `deps`
  mapping.

**Debug:**
```cmake
get_target_property(_loc Calc::calc IMPORTED_LOCATION)
message(STATUS "Calc::calc location: ${_loc}")
```

### "file 'cmake-packages/...' is generated by these conflicting actions"

**Error:** Two `cmake_export` targets in the same Bazel package write the same
output files.

**Fix:** Give each `cmake_export` a distinct `output_dir`:
```python
cmake_export(name = "export_a", deps = {...}, output_dir = "cmake-packages")
cmake_export(name = "export_b", deps = {...}, output_dir = "cmake-packages-b")
```

### Verify the repository roots

Add to CMakeLists.txt for debugging path resolution:
```cmake
message(STATUS "BDEG_EXECROOT    = ${BDEG_EXECROOT}")
message(STATUS "BDEG_OUTPUT_BASE = ${BDEG_OUTPUT_BASE}")
# EXECROOT is like:    /home/user/.cache/bazel/.../execroot/_main
# OUTPUT_BASE is like: /home/user/.cache/bazel/...
```

### Common Error Messages

| Error | Cause | Fix |
|-------|-------|-----|
| `BDEG_EXECROOT not defined` | Missing umbrella include | Add `include("${BDEG_DIR}/bdeg-deps.cmake")` |
| `Target "Pkg::target" not found` | Typo in target name | Check `cmake_export` deps mapping |
| `Library not found ... not built yet` | Merged archive not materialized | Run `bazel build //:export` |
| `generated by these conflicting actions` | Two exports share `output_dir` | Give each a unique `output_dir` |

---

## Examples

See [`examples/`](../examples/) for complete working examples:

- **gtest_boost** - Exports GoogleTest and Boost as CMake packages, with a CMake
  consumer that `find_package`s and links them (`examples/gtest_boost/build.sh`).

For a worked reference covering every feature (facade/transitive closure,
cross-package references, defines, per-package whole-archive, version parsing,
and an end-to-end `find_package` + link + run), see
[`e2e/smoke/`](../e2e/smoke/) and its `run_tests.sh`.

---

## Related Resources

- [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) - The inverse of rules_bdeg: build CMake projects inside Bazel
- [rules_foreign_cc CMake Integration](https://deepwiki.com/bazel-contrib/rules_foreign_cc/3.1-cmake-integration) - Detailed CMake integration guide
- [bazel-to-cmake](https://github.com/google/bazel-to-cmake) - Google's tool for converting Bazel BUILD files to CMakeLists.txt - archived
- [Deploying Bazel Rules](https://bazel.build/rules/deploying) - Official guide for publishing Bazel rulesets
