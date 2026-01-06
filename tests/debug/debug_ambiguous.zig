// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const IntegrationTestSuite = @import("compiler/libjanus/integration_test.zig").IntegrationTestSuite;

test "debug ambiguous resolution" {
    var test_suite = try IntegrationTestSuite.init(std.testing.allocator);
    defer test_suite.deinit();

    try test_suite.testAmbiguousResolution();
}
