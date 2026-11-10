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

"""CMake export rule implementation.

This module contains the CMake-specific implementation of the export rule.
It uses common.bzl for metadata extraction and renders CMake Config packages.

Architecture note
-----------------
`cmake_export` is a *macro* wrapping the underlying `_cmake_export_rule`. For
each entry in `deps` the macro automatically synthesizes a native
`cc_static_library` (Bazel 8+) that merges the full transitive dependency
closure of the facade target into a single self-contained archive. The rule
then points `IMPORTED_LOCATION` at that merged archive while still reading
headers/include dirs/defines from the original facade target.

This means a facade `cc_library` (one that owns no sources of its own, only
`deps`) is exported as something a non-Bazel build can actually *link*
against, without the consumer having to hand-write `cc_static_library`
targets. The public `deps` API is unchanged.
"""

load("@rules_cc//cc:cc_static_library.bzl", "cc_static_library")
load("//bdeg/private:common.bzl", "CcInfoProvider", "build_label_to_export_map", "extract_target_metadata", "resolve_transitive_deps", "sanitize_identifier")

def _cmake_target_name(export_name, target_name):
    """Format a CMake target name as Package::target."""
    return "{0}::{1}".format(export_name, target_name)

def _cmake_list_join(values):
    """Join a list of strings with CMake list separator (semicolon)."""
    return ";".join(values)

def _merged_archive_path(target):
    """Return the path to the single static archive produced by a merged target.

    The merged target is a `cc_static_library`, whose DefaultInfo files contain
    exactly one `.a` archive holding the full transitive closure. Returns None
    if no archive is present (e.g. the target produced no object code).
    """
    if not target:
        return None
    for f in target[DefaultInfo].files.to_list():
        if f.extension == "a":
            return f.path
    return None

def _render_cmake_target_properties(
        metadata,
        imported_location,
        transitive_link_deps):
    """Render CMake target properties for template substitution.

    Args:
        metadata: Target metadata struct from extract_target_metadata()
        imported_location: Path to use for IMPORTED_LOCATION (merged archive if
            available, otherwise the facade target's primary library)
        transitive_link_deps: List of transitive dependencies (CMake target names or library paths)

    Returns:
        Dictionary with keys: imported_location, include_dirs, link_libraries,
        extra_properties

    Note:
        INTERFACE_LINK_LIBRARIES is emitted as its own substitution (not folded
        into extra_properties) so the Targets template can path-resolve any
        bazel-relative entries and compose the whole-archive link line without
        clobbering cross-package dependency references.
    """
    extra_lines = []

    if metadata.defines:
        extra_lines.append("  INTERFACE_COMPILE_DEFINITIONS \"{0}\"".format(_cmake_list_join(metadata.defines)))
    if metadata.compile_options:
        extra_lines.append("  INTERFACE_COMPILE_OPTIONS \"{0}\"".format(_cmake_list_join(metadata.compile_options)))
    if metadata.link_options:
        extra_lines.append("  INTERFACE_LINK_OPTIONS \"{0}\"".format(_cmake_list_join(metadata.link_options)))

    return {
        "imported_location": imported_location or "",
        "include_dirs": _cmake_list_join(metadata.include_dirs) if metadata.include_dirs else "",
        "link_libraries": _cmake_list_join(transitive_link_deps) if transitive_link_deps else "",
        "extra_properties": "\n".join(extra_lines) if extra_lines else "",
    }

def _cmake_export_impl(ctx):
    """Implementation of the cmake_export rule."""
    outputs = []
    package_names = []

    # Build mapping from Bazel labels to CMake target names for transitive resolution
    label_map = build_label_to_export_map(ctx.attr.deps, _cmake_target_name)

    # Map from package name -> merged cc_static_library target (if any).
    # The macro passes these in via `merged_libraries`, keyed by the same
    # package name used in `deps`.
    merged_by_package = {}
    for merged_target, package_name in ctx.attr.merged_libraries.items():
        merged_by_package[package_name] = merged_target

    # Depsets of the merged archive files, so that building the export target
    # also builds the archives it references. Without this, `bazel build
    # //...:export` would only materialize the generated .cmake files and leave
    # IMPORTED_LOCATION pointing at a non-existent .a (CMake then fails to link).
    merged_archive_depsets = []
    seen_merged = {}

    for target, package_name in ctx.attr.deps.items():
        # Extract metadata using common utilities (headers, defines, includes)
        metadata = extract_target_metadata(target, package_name)
        cmake_target = _cmake_target_name(package_name, metadata.name)
        package_names.append(package_name)

        # Prefer the merged (fully-closed) archive for linking. Fall back to the
        # facade target's own primary library only if no merged archive exists.
        merged_target = merged_by_package.get(package_name)
        merged_path = _merged_archive_path(merged_target)
        imported_location = merged_path if merged_path else metadata.primary_library

        # Make the merged archive a build output of this target (dedup per
        # package) so a single `bazel build //...:export` produces it.
        if merged_target and package_name not in seen_merged:
            seen_merged[package_name] = True
            merged_archive_depsets.append(merged_target[DefaultInfo].files)

        # Resolve transitive dependencies to CMake target names. When we link a
        # merged archive we still want any *cross-package* references (other
        # exported packages) surfaced, but self-owned leaf libs are already
        # inside the merged archive, so exclude the imported location itself.
        transitive_link_deps = resolve_transitive_deps(
            target[CcInfoProvider],
            label_map,
            current_target_name = cmake_target,
            exclude_primary = imported_location,
            # When a merged archive is used it already contains this package's
            # own Bazel-built leaf object code, so drop those leaf-library paths
            # to avoid double-linking. Cross-package references and genuine
            # external/system libraries (not under bazel-out/) are still kept.
            drop_own_leaf_objects = merged_path != None,
        )

        # Declare output files
        config_file = ctx.actions.declare_file("{0}/{1}Config.cmake".format(ctx.attr.output_dir, package_name))
        version_file = ctx.actions.declare_file("{0}/{1}ConfigVersion.cmake".format(ctx.attr.output_dir, package_name))
        targets_file = ctx.actions.declare_file("{0}/{1}Targets.cmake".format(ctx.attr.output_dir, package_name))

        # Render Config.cmake
        ctx.actions.expand_template(
            output = config_file,
            template = ctx.file._config_template,
            substitutions = {
                "@PACKAGE_NAME@": package_name,
                "@PACKAGE_VERSION@": ctx.attr.version,
            },
        )

        # Render ConfigVersion.cmake
        version_parts = ctx.attr.version.split(".")
        ctx.actions.expand_template(
            output = version_file,
            template = ctx.file._version_template,
            substitutions = {
                "@PACKAGE_NAME@": package_name,
                "@PACKAGE_VERSION@": ctx.attr.version,
                "@PACKAGE_VERSION_MAJOR@": version_parts[0],
                "@PACKAGE_VERSION_MINOR@": version_parts[1] if len(version_parts) > 1 else "0",
                "@PACKAGE_VERSION_PATCH@": version_parts[2] if len(version_parts) > 2 else "0",
            },
        )

        # Linking strategy for the merged archive.
        #
        # Default (whole_archive = False): import the merged archive as a normal
        # STATIC library. Because the merged archive already contains the FULL
        # transitive closure of object code (unlike the old leaf-only export),
        # normal archive semantics resolve every symbol the consumer actually
        # references - which is exactly what fixes the "undefined reference"
        # failures - while leaving unused objects (e.g. a library's TLS/teardown
        # machinery that the consumer never calls) out of the final binary.
        #
        # Opt-in (whole_archive = True): force every object in the merged archive
        # into the link with --whole-archive and tolerate byte-identical diamond
        # duplicates with --allow-multiple-definition. Only needed for exports
        # whose objects must be present even without a direct reference (plugin
        # registries, static-init side effects, dlopen'd symbols). This is more
        # aggressive and can pull in duplicate static initializers, so it is not
        # the default.
        # Whole-archive is decided per package. A package is whole-archived when
        # it has a merged archive AND either the global `whole_archive` bool is
        # set (apply to all) or its name is listed in `whole_archive_packages`
        # (opt-in per package). This mirrors rules_foreign_cc's per-target
        # `alwayslink`, but at package granularity since one cmake_export call
        # declares many packages.
        package_whole_archive = ctx.attr.whole_archive or (package_name in ctx.attr.whole_archive_packages)
        whole_archive = "TRUE" if (merged_path and package_whole_archive) else "FALSE"
        if whole_archive == "TRUE":
            # Linked solely via the whole-archive INTERFACE_LINK_LIBRARIES entry
            # (once), so declare INTERFACE to avoid CMake also appending
            # IMPORTED_LOCATION and listing the archive twice.
            target_kind = "INTERFACE"
        elif imported_location:
            target_kind = "STATIC"
        else:
            target_kind = "INTERFACE"

        # Render Targets.cmake
        target_props = _render_cmake_target_properties(metadata, imported_location, transitive_link_deps)
        ctx.actions.expand_template(
            output = targets_file,
            template = ctx.file._targets_template,
            substitutions = {
                "@PACKAGE_NAME@": package_name,
                "@PACKAGE_VERSION@": ctx.attr.version,
                "@TARGET_NAME@": metadata.name,
                "@TARGET_KIND@": target_kind,
                "@WHOLE_ARCHIVE@": whole_archive,
                "@IMPORTED_LOCATION@": target_props["imported_location"],
                "@INTERFACE_INCLUDE_DIRECTORIES@": target_props["include_dirs"],
                "@INTERFACE_LINK_LIBRARIES@": target_props["link_libraries"],
                "@TARGET_PROPERTIES_EXTRA@": target_props["extra_properties"],
            },
        )

        outputs.extend([config_file, version_file, targets_file])

    # Render umbrella file (bdeg-deps.cmake)
    umbrella_file = ctx.actions.declare_file("{0}/bdeg-deps.cmake".format(ctx.attr.output_dir))
    ctx.actions.expand_template(
        output = umbrella_file,
        template = ctx.file._umbrella_template,
        substitutions = {
            "@PACKAGE_VERSION@": ctx.attr.version,
            "@INCLUDES@": "\n".join([
                "include(\"${{CMAKE_CURRENT_LIST_DIR}}/{0}Config.cmake\")".format(pkg)
                for pkg in package_names
            ]),
        },
    )

    # Render toolchain file (bdeg-toolchain.cmake)
    toolchain_file = ctx.actions.declare_file("{0}/bdeg-toolchain.cmake".format(ctx.attr.output_dir))
    ctx.actions.expand_template(
        output = toolchain_file,
        template = ctx.file._toolchain_template,
        substitutions = {
            "@BDEG_PREFIX@": ctx.attr.cmake_prefix,
            "@PACKAGE_VERSION@": ctx.attr.version,
            "@CXX_STANDARD@": ctx.attr.cxx_standard,
        },
    )

    outputs.extend([umbrella_file, toolchain_file])

    return [DefaultInfo(files = depset(outputs, transitive = merged_archive_depsets))]

_cmake_export_rule = rule(
    implementation = _cmake_export_impl,
    doc = """Underlying implementation of cmake_export. Use the cmake_export macro instead.""",
    attrs = {
        "deps": attr.label_keyed_string_dict(
            providers = [CcInfoProvider],
            doc = "Dictionary mapping Bazel targets to CMake package names (headers/metadata source)",
        ),
        "merged_libraries": attr.label_keyed_string_dict(
            doc = "Dictionary mapping auto-generated cc_static_library targets to CMake package names (link source)",
        ),
        "whole_archive": attr.bool(
            default = False,
            doc = "If True, link ALL merged archives with --whole-archive (forces all objects in). " +
                  "Only needed for exports relying on static-init side effects or unreferenced symbols. " +
                  "For finer control, leave this False and use whole_archive_packages instead.",
        ),
        "whole_archive_packages": attr.string_list(
            default = [],
            doc = "List of CMake package names to link with --whole-archive, leaving all other " +
                  "packages as normal STATIC. Use this (instead of the global whole_archive bool) " +
                  "when only some components need every object forced in - e.g. whole-archive a " +
                  "top-level component but NOT a dependency it already subsumes, which would " +
                  "otherwise double-link and produce multiple-definition errors.",
        ),
        "cmake_prefix": attr.string(
            default = "BDEG",
            doc = "Prefix for CMake variables in generated files",
        ),
        "output_dir": attr.string(
            default = "cmake-packages",
            doc = "Output directory name for generated CMake files",
        ),
        "version": attr.string(
            default = "0.1.0",
            doc = "Version string for generated CMake packages",
        ),
        "cxx_standard": attr.string(
            default = "17",
            doc = "C++ standard version for generated toolchain file",
        ),
        # Private attributes for templates
        "_config_template": attr.label(
            default = Label("//bdeg/private/cmake/templates:Config.cmake.tpl"),
            allow_single_file = True,
        ),
        "_version_template": attr.label(
            default = Label("//bdeg/private/cmake/templates:ConfigVersion.cmake.tpl"),
            allow_single_file = True,
        ),
        "_targets_template": attr.label(
            default = Label("//bdeg/private/cmake/templates:Targets.cmake.tpl"),
            allow_single_file = True,
        ),
        "_umbrella_template": attr.label(
            default = Label("//bdeg/private/cmake/templates:umbrella.cmake.tpl"),
            allow_single_file = True,
        ),
        "_toolchain_template": attr.label(
            default = Label("//bdeg/private/cmake/templates:toolchain.cmake.tpl"),
            allow_single_file = True,
        ),
    },
)

def cmake_export(
        name,
        deps,
        merge_static_libraries = True,
        whole_archive = False,
        whole_archive_packages = [],
        **kwargs):
    """Generates CMake Config packages from Bazel C++ targets.

    This macro extracts compilation and linking metadata from Bazel targets
    that provide CcInfo and generates CMake-compatible package files that can
    be consumed by CMake projects via find_package().

    For each entry in `deps`, the macro automatically synthesizes a native
    `cc_static_library` merging that target's full transitive dependency
    closure into a single self-contained archive, and points the generated
    CMake `IMPORTED_LOCATION` at it. This makes facade `cc_library` targets
    (which own no object code of their own) linkable from CMake without the
    caller having to author `cc_static_library` targets by hand.

    Args:
        name: Name of the export target.
        deps: Dictionary mapping Bazel targets (labels) to CMake package names.
        merge_static_libraries: If True (default), auto-generate a merged
            `cc_static_library` per dep for a linkable transitive closure. Set
            to False to fall back to the legacy behaviour of exporting only the
            facade target's own leaf archive (rarely useful for real code).
        whole_archive: If True, ALL generated CMake targets link their merged
            archive with --whole-archive (all objects forced in) plus
            --allow-multiple-definition. Default False links each merged archive
            as a normal STATIC library, which already resolves the full
            transitive closure. Only enable this if an export relies on
            static-initialization side effects or symbols that are never
            directly referenced (plugin registries, dlopen, etc.).
        whole_archive_packages: List of CMake package names (the values in
            `deps`) to whole-archive individually, leaving the rest as normal
            STATIC. Prefer this over the global `whole_archive` when only some
            components need it - e.g. whole-archive "ScoreCommunication" but not
            "ScoreBaseLibs" (which the former already subsumes), avoiding
            multiple-definition errors from double-whole-archiving.
        **kwargs: Forwarded to the underlying rule (output_dir, version,
            cmake_prefix, cxx_standard, visibility, tags, etc.).

    Example:
        ```python
        load("@rules_bdeg//bdeg:defs.bzl", "cmake_export")

        cmake_export(
            name = "export",
            deps = {
                "@googletest//:gtest": "GTest",
                "@boost.program_options": "Boost",
            },
        )
        ```
    """
    merged_libraries = {}

    if merge_static_libraries:
        # Synthesize one merged archive per exported package. Deduplicate on
        # package name: several deps entries can share a package name, but a
        # single merged archive per package is enough (and avoids duplicate
        # cc_static_library target names).
        seen_packages = {}
        for dep_label, package_name in deps.items():
            if package_name in seen_packages:
                continue
            seen_packages[package_name] = True

            merged_name = "{0}_{1}_merged".format(name, sanitize_identifier(package_name))
            cc_static_library(
                name = merged_name,
                deps = [dep_label],
                # Real-world service repos have diamond dependencies that trip
                # cc_static_library's default symbol_check with byte-identical
                # duplicate objects. Disabling it lets the merged archive build;
                # the generated CMake link line uses --allow-multiple-definition
                # to tolerate the identical duplicates safely (see Targets tpl).
                features = ["-symbol_check"],
                visibility = ["//visibility:private"],
                tags = ["manual"],
            )
            merged_libraries[":{0}".format(merged_name)] = package_name

    _cmake_export_rule(
        name = name,
        deps = deps,
        merged_libraries = merged_libraries,
        whole_archive = whole_archive,
        whole_archive_packages = whole_archive_packages,
        **kwargs
    )
