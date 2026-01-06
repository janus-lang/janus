// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const IntegrationTestSuite = @import("compiler/libjanus/integration_test.zig").IntegrationTestSuite;

test "simple ambiguous test" {
    var test_suite = try IntegrationTestSuite.init(std.testing.allocator);
    defer test_suite.deinit();

    // This should pass if ambiguous resolution works
    try test_suite.testAmbiguousResolution();

    std.debug.print("Ambiguous resolution test passed!\n", .{});
}
