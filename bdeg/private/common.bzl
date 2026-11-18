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

"""Common utilities for BDEG - shared across all export formats.

This module contains the format-agnostic logic for extracting metadata
from Bazel C++ targets (CcInfo provider). Format-specific renderers
(cmake, cargo, etc.) use these utilities to generate their output files.
"""

load("@rules_cc//cc:defs.bzl", "CcInfo")

# Re-export CcInfo for format-specific modules
CcInfoProvider = CcInfo

def sanitize_identifier(value):
    """Convert a string to a valid identifier by replacing invalid chars with underscore.

    This is useful for generating valid variable/target names in CMake, Cargo, etc.

    Args:
        value: The string to sanitize

    Returns:
        A string with only alphanumeric characters and underscores
    """
    allowed = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"
    result = []

    # In Starlark, use .elems() to iterate over string characters
    for character in value.elems():
        if character in allowed:
            result.append(character)
        else:
            result.append("_")
    return "".join(result)

def unique_strings(values):
    """Remove duplicates from a list while preserving order.

    Args:
        values: List of strings (may contain None or empty strings)

    Returns:
        List with duplicates removed, empty/None values filtered out
    """
    seen = {}
    result = []
    for value in values:
        if value and value not in seen:
            seen[value] = True
            result.append(value)
    return result

def collect_compilation_info(cc_info):
    """Extract compilation information from CcInfo provider.

    Args:
        cc_info: The CcInfo provider from a C++ target

    Returns:
        A struct with fields:
            - include_dirs: list of include directory paths
            - defines: list of compile definitions
            - compile_options: list of compile flags (may be empty)
    """
    context = cc_info.compilation_context

    include_dirs = []
    include_dirs.extend(context.includes.to_list())
    include_dirs.extend(context.quote_includes.to_list())
    include_dirs.extend(context.system_includes.to_list())

    # Extract directories containing direct headers for more complete include paths
    for header in context.direct_headers:
        header_dir = header.dirname
        if header_dir and header_dir not in include_dirs:
            include_dirs.append(header_dir)

    include_dirs = unique_strings(include_dirs)

    # Export ONLY `defines` (the public ones). Note: it is a depset, so .to_list().
    #
    # `local_defines` is deliberately excluded. Bazel applies it solely when
    # compiling the defining target's own sources and never propagates it to
    # dependents, so re-publishing it as an INTERFACE define would compile every
    # CMake consumer with a library's private configuration - the opposite of
    # what the library author asked for.
    #
    # This is not cosmetic. A private define that changes a struct's layout or
    # inlining leaves the library compiled one way and the consumer compiled
    # another. The result links cleanly and then misbehaves at runtime (an ODR
    # violation), which is very hard to diagnose. Exporting only `defines` gives
    # CMake consumers exactly what a Bazel consumer of the same target sees.
    defines = unique_strings(context.defines.to_list())

    # Note: user_compile_flags is not available in CompilationContext in newer Bazel
    # Compile flags come from the toolchain, not from CcInfo directly
    compile_options = []

    return struct(
        include_dirs = include_dirs,
        defines = defines,
        compile_options = compile_options,
    )

def select_library_file(library, prefer_pic = True):
    """Pick a single file to represent one LibraryToLink entry.

    A LibraryToLink can carry several variants of the same library (a non-PIC
    static archive, a PIC static archive, a dynamic library, an interface
    library). We must choose one to hand to CMake.

    Like rules_foreign_cc, which keeps both the `.a` and `.pic.a` variants and
    lets the toolchain decide, we try to pick the right one rather than blindly
    taking the first. Bazel's default build modes (fastbuild/opt) emit PIC
    object code, and CMake consumers commonly link into shared libraries or
    PIE executables, so the PIC static archive (`.pic.a`) is the safer default
    when both static variants exist.

    Args:
        library: A LibraryToLink object
        prefer_pic: When True, prefer pic_static_library over the non-PIC
            static_library if both are present.

    Returns:
        The chosen File, or None if the library carries no linkable file.
    """
    static_lib = getattr(library, "static_library", None)
    pic_static_lib = getattr(library, "pic_static_library", None)

    if prefer_pic:
        candidate = pic_static_lib or static_lib
    else:
        candidate = static_lib or pic_static_lib

    if candidate == None:
        candidate = getattr(library, "dynamic_library", None)
    if candidate == None:
        candidate = getattr(library, "interface_library", None)
    return candidate

def collect_linking_info(cc_info, prefer_pic = True):
    """Extract linking information from CcInfo provider.

    Args:
        cc_info: The CcInfo provider from a C++ target
        prefer_pic: Prefer PIC static archives when both variants exist.

    Returns:
        A struct with fields:
            - library_paths: list of library file paths
            - link_options: list of linker flags (excluding -l<lib> flags)
            - link_libs: list of -l<lib> flags, to be linked after archives
    """
    context = cc_info.linking_context
    library_paths = []
    link_options = []
    link_libs = []

    for linker_input in context.linker_inputs.to_list():
        for flag in getattr(linker_input, "user_link_flags", []):
            # Library-valued flags (-lm, -lssl) are order-sensitive: they must
            # follow the archive that references them. INTERFACE_LINK_OPTIONS is
            # emitted before the libraries, so route them separately so they can
            # be emitted via INTERFACE_LINK_LIBRARIES instead.
            if flag.startswith("-l") and len(flag) > 2:
                link_libs.append(flag)
            else:
                link_options.append(flag)
        for library in linker_input.libraries:
            candidate = select_library_file(library, prefer_pic)
            if candidate:
                library_paths.append(candidate.path)

    library_paths = unique_strings(library_paths)
    link_options = unique_strings(link_options)
    link_libs = unique_strings(link_libs)

    return struct(
        library_paths = library_paths,
        link_options = link_options,
        link_libs = link_libs,
    )

def extract_target_metadata(target, export_name):
    """Extract all metadata from a Bazel target for export.

    This is the main entry point for format-specific exporters to get
    all the information they need about a target.

    Args:
        target: A Bazel target with CcInfo provider
        export_name: The name to use in the exported format (e.g., CMake package name)

    Returns:
        A struct with fields:
            - label: The target's label (as string)
            - name: Sanitized target name
            - export_name: The export name (e.g., CMake package name)
            - include_dirs: list of include directories
            - defines: list of compile definitions
            - compile_options: list of compile flags
            - library_paths: list of library file paths
            - primary_library: path to primary library (or None)
            - link_options: list of linker flags
    """
    cc_info = target[CcInfo]

    compilation = collect_compilation_info(cc_info)
    linking = collect_linking_info(cc_info)

    return struct(
        label = str(target.label),
        name = sanitize_identifier(target.label.name),
        export_name = export_name,
        include_dirs = compilation.include_dirs,
        defines = compilation.defines,
        compile_options = compilation.compile_options,
        library_paths = linking.library_paths,
        primary_library = linking.library_paths[0] if linking.library_paths else None,
        link_options = linking.link_options,
        link_libs = linking.link_libs,
    )

def build_label_to_export_map(deps_dict, format_target_name_fn):
    """Build a mapping from Bazel labels to export target names.

    Args:
        deps_dict: Dictionary mapping Target to export_name
        format_target_name_fn: Function(export_name, target_name) -> formatted target string
            e.g., for CMake: lambda pkg, tgt: "{}::{}".format(pkg, tgt)
            e.g., for Cargo: lambda pkg, tgt: pkg.lower().replace("-", "_")

    Returns:
        Dictionary mapping label string to formatted target name
    """
    label_map = {}
    for target, export_name in deps_dict.items():
        label_str = str(target.label)
        target_name = sanitize_identifier(target.label.name)
        formatted_name = format_target_name_fn(export_name, target_name)

        # Exact label only. Matching by repository alone would map any
        # unexported library from the same repo onto this export and silently
        # drop its archive; unmatched libraries fall through to raw-path logic.
        label_map[label_str] = formatted_name

    return label_map

def _has_compiled_objects(library):
    """True if Bazel compiled object files for this library (so it gets merged)."""
    for attr in ["objects", "pic_objects"]:
        objs = getattr(library, attr, None)
        if objs:
            return True
    return False

def resolve_transitive_deps(cc_info, label_map, current_target_name, exclude_primary = None, drop_own_leaf_objects = False):
    """Resolve transitive link dependencies to export target names where possible.

    Args:
        cc_info: The CcInfo provider
        label_map: Mapping from Bazel labels to export target names
        current_target_name: The export target name of the current target (to avoid self-reference)
        exclude_primary: Library path to exclude (the primary library)
        drop_own_leaf_objects: When True, drop unmapped libraries whose object
            files were compiled by Bazel. Their object code is already
            contained in the merged static archive we export, so re-emitting
            them would double-link (the "diamond duplicate" /
            multiple-definition problem).

            Libraries without compiled objects are still kept, regardless of
            output directory. Those are prebuilt or archive-only deps (e.g. a
            `libacl.a` from a repo rule, or a generated archive wrapped by
            `cc_import`) that are NOT part of the merged archive, so the CMake
            consumer still needs to link them.

            Set this True when the current package is exported as a single
            merged static archive (full transitive closure). Genuine
            cross-package references (other exported packages) are always kept.

    Returns:
        List of export target references or library paths for unmapped deps
    """
    context = cc_info.linking_context
    transitive_deps = []
    seen_libs = {}
    seen_targets = {}

    for linker_input in context.linker_inputs.to_list():
        owner = linker_input.owner
        owner_str = str(owner) if owner else None

        for library in linker_input.libraries:
            lib_path = None
            candidate = select_library_file(library)
            if candidate:
                lib_path = candidate.path

            if not lib_path or lib_path in seen_libs:
                continue
            seen_libs[lib_path] = True

            # Skip the primary library
            if exclude_primary and lib_path == exclude_primary:
                continue

            # Try to resolve to an export target name
            export_target = None
            if owner_str and owner_str in label_map:
                export_target = label_map[owner_str]

            if export_target:
                # Skip self-references
                if export_target == current_target_name:
                    continue

                # Avoid duplicates
                if export_target in seen_targets:
                    continue
                seen_targets[export_target] = True
                transitive_deps.append(export_target)
            else:
                # Unmapped raw library path.
                if drop_own_leaf_objects and _has_compiled_objects(library):
                    # Object code compiled by Bazel for this closure - already
                    # inside the merged archive, so skip it to avoid
                    # double-linking.
                    continue

                # Keep everything else, wherever it lives: genuine external or
                # system libraries and archive-only deps (e.g. a generated
                # archive wrapped by cc_import) that carry no compiled objects
                # and so are not part of the merged archive.
                transitive_deps.append(lib_path)

    return transitive_deps
