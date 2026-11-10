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

```python
def _collect_compilation_flags(cc_info):
    context = cc_info.compilation_context
    
    include_dirs = []
    include_dirs.extend(context.includes.to_list())
    include_dirs.extend(context.system_includes.to_list())
    
    defines = context.defines.to_list()
    
    return include_dirs, defines
```

```python
def _collect_link_flags(cc_info):
    context = cc_info.linking_context
    
    for linker_input in context.linker_inputs.to_list():
        for library in linker_input.libraries:
            lib_path = library.static_library.path
            library_paths.append(lib_path)
    
    return library_paths
```

### 2. Resolve Transitive Dependencies

When `gtest_main` depends on `gtest`, we want CMake's `INTERFACE_LINK_LIBRARIES` to reference `GTest::gtest` rather than a raw library path:

```python
def _build_label_to_cmake_map(deps_dict):
    """Maps Bazel labels to CMake target names"""
    label_map = {}
    for target, cmake_name in deps_dict.items():
        label_str = str(target.label)  # "@googletest//:gtest"
        target_name = target.label.name  # "gtest"
        label_map[label_str] = f"{cmake_name}::{target_name}"
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
