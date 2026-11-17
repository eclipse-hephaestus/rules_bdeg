<!-- ----------------------------------------------------------------------------
  Copyright (c) 2026 Contributors to the Eclipse Foundation

  See the NOTICE file(s) distributed with this work for additional
  information regarding copyright ownership.

  This program and the accompanying materials are made available under the
  terms of the Apache License Version 2.0 which is available at
  https://www.apache.org/licenses/LICENSE-2.0

  SPDX-License-Identifier: Apache-2.0
----------------------------------------------------------------------------- -->

# Architecture

Technical documentation for developers who want to understand how BDEG works internally or contribute to the project.

## Quick Reference

| What | Where |
|------|-------|
| Public API | `bdeg/defs.bzl` |
| CMake export rule | `bdeg/private/cmake/export.bzl` |
| Shared utilities | `bdeg/private/common.bzl` |
| CMake templates | `bdeg/private/cmake/templates/` |

---

## Overview

BDEG bridges Bazel and CMake by generating CMake "Config packages" from Bazel's dependency metadata:

```
MODULE.bazel                    # Define dependencies once
       │
       ▼
cmake_export() rule             # Starlark extracts CcInfo
       │
       ▼
CMake Config Packages           # *Config.cmake, *Targets.cmake
       │
       ▼
CMakeLists.txt                  # find_package() consumes them
```

---

## File Structure

```
rules_bdeg/
├── MODULE.bazel                      # Module definition
├── bdeg/
│   ├── defs.bzl                      # Public API
│   └── private/
│       ├── common.bzl                # Shared CcInfo extraction
│       └── cmake/
│           ├── export.bzl            # cmake_export rule
│           └── templates/
│               ├── Config.cmake.tpl
│               ├── ConfigVersion.cmake.tpl
│               ├── Targets.cmake.tpl
│               ├── umbrella.cmake.tpl
│               └── toolchain.cmake.tpl
```

### Multi-Format Design

The architecture supports multiple export formats. CMake is implemented; Cargo/Gradle can be added:

```
bdeg/private/
├── common.bzl              # Format-agnostic CcInfo extraction
├── cmake/                  # CMake format (implemented)
├── cargo/                  # Future: Cargo export
└── gradle/                 # Future: Gradle export
```

---

## How It Works

### 1. Extract Metadata from CcInfo

Every C++ target provides a `CcInfo` provider:

Simplified below; the real implementations live in `bdeg/private/common.bzl`.

```python
# Real name: collect_compilation_info()
def collect_compilation_info(cc_info):
    context = cc_info.compilation_context

    include_dirs = []
    include_dirs.extend(context.includes.to_list())
    include_dirs.extend(context.quote_includes.to_list())
    include_dirs.extend(context.system_includes.to_list())

    # Only the public `defines`. `local_defines` is deliberately NOT exported:
    # Bazel never propagates it to dependents, so publishing it would compile
    # consumers with the library's private configuration.
    defines = context.defines.to_list()

    return struct(include_dirs = include_dirs, defines = defines)
```

```python
# Real name: collect_linking_info()
def collect_linking_info(cc_info, prefer_pic = True):
    context = cc_info.linking_context
    library_paths = []

    for linker_input in context.linker_inputs.to_list():
        for library in linker_input.libraries:
            # select_library_file() picks ONE variant per LibraryToLink,
            # preferring the PIC static archive since that is what Bazel's
            # default build modes produce.
            candidate = select_library_file(library, prefer_pic)
            if candidate:
                library_paths.append(candidate.path)

    return struct(library_paths = library_paths)
```

### 2. Resolve Transitive Dependencies

When `gtest_main` depends on `gtest`, we want CMake's `INTERFACE_LINK_LIBRARIES` to reference `GTest::gtest` rather than a raw library path:

```python
# Real name: build_label_to_export_map(). The format function is passed in so
# the same logic can serve other output formats (Cargo, Gradle, ...).
def build_label_to_export_map(deps_dict, format_target_name_fn):
    """Maps Bazel labels to export target names."""
    label_map = {}
    for target, export_name in deps_dict.items():
        label_str = str(target.label)  # "@googletest//:gtest"
        target_name = sanitize_identifier(target.label.name)  # "gtest"
        label_map[label_str] = format_target_name_fn(export_name, target_name)

        # Fallback keyed by repository name alone, for labels that are not
        # themselves exported. First one registered wins - see
        # "Known issue: repository-level dependency mapping" below.
        repo_name = target.label.workspace_name
        if repo_name and "@" + repo_name not in label_map:
            label_map["@" + repo_name] = label_map[label_str]

    return label_map
```

### 3. Generate Files via Templates

```python
ctx.actions.expand_template(
    output = targets_file,
    template = ctx.file.targets_template,
    substitutions = {
        "@PACKAGE_NAME@": package_name,
        "@TARGET_NAME@": target_name,
        "@IMPORTED_LOCATION@": primary_library,
        "@INTERFACE_INCLUDE_DIRECTORIES@": ...,
    },
)
```

---

## Template System

### Targets.cmake.tpl

Creates CMake IMPORTED targets:

```cmake
if(NOT DEFINED BDEG_EXECROOT)
  message(FATAL_ERROR "BDEG_EXECROOT not defined.")
endif()

if(TARGET @PACKAGE_NAME@::@TARGET_NAME@)
  return()
endif()

add_library(@PACKAGE_NAME@::@TARGET_NAME@ @TARGET_KIND@ IMPORTED)

set_target_properties(@PACKAGE_NAME@::@TARGET_NAME@ PROPERTIES
  IMPORTED_LOCATION "${BDEG_EXECROOT}/@IMPORTED_LOCATION@"
  INTERFACE_INCLUDE_DIRECTORIES "${_ABS_INCLUDE_DIRS}"
)
```

### umbrella.cmake.tpl (bdeg-deps.cmake)

Discovers `BDEG_EXECROOT` dynamically by walking up the directory tree:

```cmake
get_filename_component(_BDEG_REAL_DIR "${CMAKE_CURRENT_LIST_DIR}" REALPATH)

set(_BDEG_SEARCH_DIR "${_BDEG_REAL_DIR}")
foreach(_i RANGE 20)
  get_filename_component(_BDEG_DIRNAME "${_BDEG_SEARCH_DIR}" NAME)
  if(_BDEG_DIRNAME STREQUAL "bazel-out")
    get_filename_component(BDEG_EXECROOT "${_BDEG_SEARCH_DIR}" DIRECTORY)
    break()
  endif()
  get_filename_component(_BDEG_SEARCH_DIR "${_BDEG_SEARCH_DIR}" DIRECTORY)
endforeach()
```

---

## Path Resolution

### The Problem

Bazel outputs files to paths like:
```
bazel-out/k8-fastbuild/bin/external/googletest+/libgtest.a
```

These are relative to the Bazel execroot, not absolute paths.

### The Solution

1. **Build time**: Store relative paths in generated files
2. **CMake configure time**: Umbrella file finds `BDEG_EXECROOT` dynamically
3. **Target properties**: Prepend `BDEG_EXECROOT` to make paths absolute

---

## Key Concepts Mapping

| Bazel Concept | CMake Equivalent | BDEG Mapping |
|---------------|------------------|--------------|
| `cc_library` target | IMPORTED library | `add_library(... IMPORTED)` |
| `CcInfo.compilation_context.includes` | `INTERFACE_INCLUDE_DIRECTORIES` | Direct |
| `CcInfo.compilation_context.defines` | `INTERFACE_COMPILE_DEFINITIONS` | Direct |
| `CcInfo.linking_context.libraries` | `IMPORTED_LOCATION` | Path + BDEG_EXECROOT |
| Transitive deps | `INTERFACE_LINK_LIBRARIES` | Resolved to CMake targets |

---

## Adding a New Export Format

To add Cargo support:

1. Create `bdeg/private/cargo/export.bzl` using `common.bzl`
2. Implement format-specific naming: `_cargo_target_name()`
3. Create templates in `bdeg/private/cargo/templates/`
4. Re-export from `bdeg/defs.bzl`

```python
# bdeg/private/cargo/export.bzl
load("//bdeg/private:common.bzl", "extract_target_metadata")

def _cargo_export_impl(ctx):
    for target, crate_name in ctx.attr.deps.items():
        metadata = extract_target_metadata(target, crate_name)
        # Render Cargo.toml templates...
```

---

## Current Limitations

- **Static libraries only** - Shared library RPATH handling not implemented
- **Single platform** - One export per `--platforms` configuration
- **C++ only** - Only `CcInfo` providers supported
- **Hardcoded version** - Version from rule attribute, not from MODULE.bazel
- **One target per CMake package** - A package name maps to exactly one Bazel
  target, because the generated `<Pkg>Config.cmake` / `<Pkg>Targets.cmake` file
  names derive from the package name alone. Reusing a name fails at load time
  with a diagnostic naming both targets. Upstream CMake packages conventionally
  group related targets under one name (`GTest::gtest` and `GTest::gtest_main`
  from a single `GTest` package); supporting that needs `Targets.cmake.tpl` to
  emit several imported targets, and the merged archive to cover every label of
  the package rather than only the first.

### Known issue: repository-level dependency mapping

`build_label_to_export_map()` registers a fallback entry keyed by repository
name alone, in addition to the exact label. When two exported targets come from
the same repository, that fallback resolves to whichever was registered first,
so a transitive library can be attributed to the wrong `Pkg::target` name.

In practice the effect is limited: the fallback is only consulted when exact
label matching misses, and those libraries are already inside the package's
merged archive, so the usual outcome is a redundant or oddly-named link-line
entry rather than a missing symbol. Removing the fallback outright is not safe
either - it would turn unmatched Bazel-built archives into dropped entries. The
fix is to register the repository-level key only when exactly one exported
target comes from that repository, and is best done alongside the
multiple-targets-per-package work above.

---

## Debugging

### Inspect Generated Files

```bash
cat bazel-bin/cmake-packages/GTestTargets.cmake
```

### Verify BDEG_EXECROOT

```cmake
message(STATUS "BDEG_EXECROOT = ${BDEG_EXECROOT}")
```

### Check Library Paths

```bash
ls -la $(bazel info output_base)/execroot/_main/bazel-out/k8-fastbuild/bin/external/googletest+/
```

### Dump CcInfo (Advanced)

```python
def _debug_ccinfo_impl(ctx):
    cc_info = ctx.attr.dep[CcInfo]
    print("Includes:", cc_info.compilation_context.includes.to_list())
    print("Defines:", cc_info.compilation_context.defines.to_list())
    return []

debug_ccinfo = rule(
    implementation = _debug_ccinfo_impl,
    attrs = {"dep": attr.label(providers = [CcInfo])},
)
```

---

## Related Resources

- [Deploying Bazel Rules](https://bazel.build/rules/deploying) - Official guide for publishing Bazel rulesets
- [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) - Build CMake/Make/Meson projects inside Bazel
- [rules_foreign_cc CMake Integration](https://deepwiki.com/bazel-contrib/rules_foreign_cc/3.1-cmake-integration) - Detailed CMake integration patterns
- [bazel-to-cmake](https://github.com/google/bazel-to-cmake) - Google's alternative approach: convert BUILD files to CMakeLists.txt
