# rules_bdeg

Bazel Dependency Export Generator - Export Bazel C++ dependencies as CMake packages.

## Overview

**Problem:** You have a CMake project that needs to use C++ libraries managed by Bazel (e.g., from the Bazel Central Registry), but CMake doesn't know how to find them.

**Solution:** `rules_bdeg` generates CMake Config packages from Bazel C++ targets, so you can use `find_package()` normally.

| Tool | Direction | Use Case |
|------|-----------|----------|
| **rules_bdeg** | Bazel → CMake | CMake project consuming Bazel deps |
| [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) | CMake → Bazel | Bazel project building CMake deps |

## Related Projects

- [rules_foreign_cc](https://github.com/bazel-contrib/rules_foreign_cc) - Build CMake/Make/Meson projects inside Bazel
- [bazel-to-cmake](https://github.com/google/bazel-to-cmake) - Google's Bazel to CMake conversion tool
- [Deploying Bazel Rules](https://bazel.build/rules/deploying) - Official guide for publishing Bazel rulesets

## License

Apache License 2.0
