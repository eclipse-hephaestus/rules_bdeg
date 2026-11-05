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

## Funding acknowledgement

> "The contribution was written within the Shift2SDV project (GA number 101194245) which is supported by the Chips Joint Undertaking and its members, including top-funding by the national authorities of Austria, Denmark, Germany, Greece, Finland, Italy, Netherlands, Poland, Portugal, Spain, Turkey. Co-funded by the European Union. Views and opinions expressed are however those of the author(s) only and do not necessarily reflect those of the European Union or the Chips Joint Undertaking. Neither the European Union nor the granting authorities can be held responsible for them."