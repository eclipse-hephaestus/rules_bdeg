# CMakeLists.txt - Example CMake project consuming Bazel dependencies via BDEG
#
# Usage:
#   bazel build //gtest_boost:export
#   ln -sf "$(bazel info bazel-bin)/gtest_boost/cmake-packages" cmake-packages
#   cmake -S . -B build -DBDEG_DIR="$(pwd)/cmake-packages"
#   cmake --build build
#   ctest --test-dir build

cmake_minimum_required(VERSION 3.16)

project(gtest_boost_example
    VERSION 1.0.0
    LANGUAGES CXX
    DESCRIPTION "Example using BDEG to consume Bazel dependencies in CMake"
)

# =============================================================================
# BDEG Integration
# =============================================================================

# BDEG_DIR should point to the generated cmake-packages directory
if(NOT DEFINED BDEG_DIR)
    set(BDEG_DIR "${CMAKE_SOURCE_DIR}/cmake-packages")
endif()

if(NOT EXISTS "${BDEG_DIR}/bdeg-deps.cmake")
    message(FATAL_ERROR
        "BDEG packages not found at ${BDEG_DIR}\n"
        "Please run:\n"
        "  bazel build //gtest_boost:export\n"
        "  ln -sf \"$(bazel info bazel-bin)/gtest_boost/cmake-packages\" cmake-packages"
    )
endif()

# Include BDEG umbrella file - sets up CMAKE_PREFIX_PATH and BDEG_EXECROOT
include("${BDEG_DIR}/bdeg-deps.cmake")

# Optional: Include toolchain for consistent C++ standard
if(EXISTS "${BDEG_DIR}/bdeg-toolchain.cmake")
    include("${BDEG_DIR}/bdeg-toolchain.cmake")
endif()

message(STATUS "BDEG version: ${BDEG_VERSION}")
message(STATUS "BDEG packages: ${BDEG_DIR}")

# =============================================================================
# Find Dependencies (provided by BDEG)
# =============================================================================

find_package(GTest REQUIRED)
find_package(GTestMain REQUIRED)
find_package(Boost REQUIRED)

# =============================================================================
# Example Executable
# =============================================================================

add_executable(example_test main.cpp)

target_link_libraries(example_test
    PRIVATE
        GTestMain::gtest_main
        GTest::gtest
        Boost::Boost
)

# =============================================================================
# Tests
# =============================================================================

enable_testing()
include(GoogleTest)
gtest_discover_tests(example_test)

# =============================================================================
# Summary
# =============================================================================

message(STATUS "")
message(STATUS "gtest_boost_example configuration:")
message(STATUS "  C++ Standard: ${CMAKE_CXX_STANDARD}")
message(STATUS "  BDEG dir:     ${BDEG_DIR}")
message(STATUS "")
