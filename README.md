# rules_bdeg

Bazel Dependency Export Generator - Export Bazel C++ dependencies as CMake packages.

## Overview

**Problem:** You have a CMake project that needs to use C++ libraries managed by Bazel (e.g., from the Bazel Central Registry), but CMake doesn't know how to find them.

**Solution:** `rules_bdeg` generates CMake Config packages from Bazel C++ targets, so you can use `find_package()` normally.

| Tool | Direction | Use Case |
|------|-----------|----------|
| **rules_bdeg** | Bazel → CMake | CMake project consuming Bazel deps |
| [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) | CMake → Bazel | Bazel project building CMake deps |

## Quick Start

**1. Add to MODULE.bazel:**

```python
bazel_dep(name = "rules_bdeg", version = "0.1.0")
bazel_dep(name = "googletest", version = "1.17.0")
```

> **Note:** Before BCR publication, see [Installation Options](docs/user-guide.md#installation) for `git_override` setup.

**2. Define exports in BUILD.bazel:**

```python
load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")

cmake_export(
    name = "export",
    deps = {
        # Bazel target           → CMake namespace
        "@googletest//:gtest":      "GTest",      # becomes GTest::gtest
        "@googletest//:gtest_main": "GTest",      # becomes GTest::gtest_main
    },
)
```

**3. Build and use:**

```bash
# Build deps first (BDEG reads metadata from built artifacts)
bazel build @googletest//:gtest @googletest//:gtest_main
bazel build //:export

# Create symlink and build with CMake
ln -sf "$(bazel info bazel-bin)/cmake-packages" cmake-packages
cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages" && cmake --build build
```

**4. In CMakeLists.txt:**

```cmake
include("${BDEG_DIR}/bdeg-deps.cmake")
find_package(GTest REQUIRED)
target_link_libraries(my_app PRIVATE GTest::gtest)
```

## Requirements

- Bazel 8.0.0+
- CMake 3.16+

## Documentation

| Document | Description |
|----------|-------------|
| [User Guide](docs/user-guide.md) | Complete usage guide, patterns, troubleshooting |
| [Architecture](docs/architecture.md) | Technical internals for contributors |
| [Design Proposal](docs/bdeg-engineering-design-proposal.md) | Original design document (historical) |

## Examples

See [`examples/`](examples/) for complete working examples.

## Related Projects

- [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) - Build CMake/Make/Meson projects inside Bazel
- [bazel-to-cmake](https://github.com/google/bazel-to-cmake) - Google's Bazel to CMake conversion tool
- [Deploying Bazel Rules](https://bazel.build/rules/deploying) - Official guide for publishing Bazel rulesets

## License

Apache License 2.0

## Funding acknowledgement

> "The contribution was written within the Shift2SDV project (GA number 101194245) which is supported by the Chips Joint Undertaking and its members, including top-funding by the national authorities of Austria, Denmark, Germany, Greece, Finland, Italy, Netherlands, Poland, Portugal, Spain, Turkey. Co-funded by the European Union. Views and opinions expressed are however those of the author(s) only and do not necessarily reflect those of the European Union or the Chips Joint Undertaking. Neither the European Union nor the granting authorities can be held responsible for them."