/********************************************************************************
 * Copyright (c) 2026 Contributors to the Eclipse Foundation
 *
 * See the NOTICE file(s) distributed with this work for additional
 * information regarding copyright ownership.
 *
 * This program and the accompanying materials are made available under the
 * terms of the Apache License Version 2.0 which is available at
 * https://www.apache.org/licenses/LICENSE-2.0
 *
 * SPDX-License-Identifier: Apache-2.0
 ********************************************************************************/

// Example test file demonstrating BDEG integration
// This file uses GTest and Boost.Program_Options from Bazel via BDEG

#include <gtest/gtest.h>
#include <boost/program_options.hpp>
#include <string>
#include <vector>

namespace po = boost::program_options;

// Test that GTest works
TEST(BdegExample, GTestWorks) {
    EXPECT_EQ(1 + 1, 2);
    EXPECT_TRUE(true);
}

// Test that Boost.Program_Options is available
TEST(BdegExample, BoostProgramOptionsWorks) {
    po::options_description desc("Test options");
    desc.add_options()
        ("help,h", "produce help message")
        ("name,n", po::value<std::string>()->default_value("World"), "name to greet");

    // Parse empty command line
    std::vector<std::string> args = {"test_program"};
    po::variables_map vm;
    po::store(po::command_line_parser(args).options(desc).run(), vm);
    po::notify(vm);

    // Verify default value
    EXPECT_EQ(vm["name"].as<std::string>(), "World");
}

// Test string operations
TEST(BdegExample, StringTest) {
    std::string hello = "Hello";
    std::string world = "World";
    std::string result = hello + ", " + world + "!";
    EXPECT_EQ(result, "Hello, World!");
}
