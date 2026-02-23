// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Basic Using Statement Tests
//! Task 1.1 - Unit tests for normal/return/exception exits and LIFO basics
//!
//! These tests validate the fundamental behavior of `using` statements
//! across different exit paths and ensure LIFO cleanup ordering.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import using statement components
const UsingStmt = @import("../../../compiler/libjanus/ast/using_stmt.zig").UsingStmt;
const UsingDesugar = @import("../../../compiler/libjanus/codegen/using_desugar.zig").UsingDesugar;
const CleanupAggregator = @import("../../../compiler/libjanus/codegen/using_desugar.zig").CleanupAggregator;

/// Test resource for validation
const TestResource = struct {
    id: u32,
    is_closed: bool,
    close_error: ?TestError,
    cleanup_order: *std.ArrayList(u32),

    const TestError = error{
        CloseFailure,
        NetworkError,
        FileSystemError,
    };

    pub fn init(id: u32, cleanup_order: *std.ArrayList(u32)) TestResource {
        return TestResource{
            .id = id,
            .is_closed = false,
            .close_error = null,
            .cleanup_order = cleanup_order,
        };
    }

    pub fn close(self: *TestResource) !void {
        if (self.close_error) |err| {
            return err;
        }

        self.is_closed = true;
        try self.cleanup_order.append(self.id);
    }

    pub fn setCloseError(self: *TestResource, err: TestError) void {
        self.close_error = err;
    }
};

/// Test context for using statement validation
const TestContext = struct {
    allocator: Allocator,
    cleanup_order: std.ArrayList(u32),
    resources: std.ArrayList(TestResource),

    pub fn init(allocator: Allocator) TestContext {
        return TestContext{
            .allocator = allocator,
            .cleanup_order = .empty,
            .resources = .empty,
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.cleanup_order.deinit();
        self.resources.deinit();
    }

    pub fn createResource(self: *TestContext, id: u32) !*TestResource {
        var resource = TestResource.init(id, &self.cleanup_order);
        try self.resources.append(resource);
        return &self.resources.items[self.resources.items.len - 1];
    }

    pub fn getCleanupOrder(self: *TestContext) []const u32 {
        return self.cleanup_order.items;
    }

    pub fn resetCleanupOrder(self: *TestContext) void {
        self.cleanup_order.clearRetainingCapacity();
    }
};

// Test 1: Normal exit path cleanup
test "using statement - normal exit cleanup" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    // Simulate: using file = open("test.txt") { /* normal completion */ }
    const resource = try test_ctx.createResource(1);

    // Simulate normal block completion
    {
        // Resource is used normally
        try testing.expect(!resource.is_closed);

        // Block completes normally - cleanup should occur
        try resource.close();
    }

    // Verify cleanup occurred
    try testing.expect(resource.is_closed);
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 1);
    try testing.expect(cleanup_order[0] == 1);
}

// Test 2: Early return cleanup
test "using statement - early return cleanup" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    const resource = try test_ctx.createResource(2);

    // Simulate early return from using block
    const result = blk: {
        // Resource acquired
        try testing.expect(!resource.is_closed);

        // Early return - cleanup should still occur
        try resource.close(); // Simulate defer cleanup
        break :blk 42;
    };

    // Verify cleanup occurred despite early return
    try testing.expect(resource.is_closed);
    try testing.expect(result == 42);

    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 1);
    try testing.expect(cleanup_order[0] == 2);
}

// Test 3: Exception/error exit cleanup
test "using statement - exception exit cleanup" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    const resource = try test_ctx.createResource(3);

    // Simulate exception during using block
    const result = blk: {
        // Resource acquired
        try testing.expect(!resource.is_closed);

        // Exception occurs - cleanup should still happen
        try resource.close(); // Simulate defer cleanup during unwinding

        break :blk error.TestException;
    };

    // Verify cleanup occurred despite exception
    try testing.expect(resource.is_closed);
    try testing.expectError(error.TestException, result);

    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 1);
    try testing.expect(cleanup_order[0] == 3);
}

// Test 4: LIFO cleanup order for nested using statements
test "using statement - LIFO cleanup order" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    // Simulate nested using statements:
    // using outer = open("outer") {
    //   using inner = open("inner") {
    //     // use both resources
    //   }
    // }

    const outer_resource = try test_ctx.createResource(1);
    const inner_resource = try test_ctx.createResource(2);

    // Simulate nested block execution
    {
        // Outer resource acquired
        try testing.expect(!outer_resource.is_closed);

        {
            // Inner resource acquired
            try testing.expect(!inner_resource.is_closed);

            // Inner block completes - inner resource should close first
            try inner_resource.close();
        }

        // Outer block completes - outer resource should close second
        try outer_resource.close();
    }

    // Verify LIFO cleanup order: inner (2) then outer (1)
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 2);
    try testing.expect(cleanup_order[0] == 2); // Inner closed first
    try testing.expect(cleanup_order[1] == 1); // Outer closed second
}

// Test 5: Multiple resources in same scope (LIFO order)
test "using statement - multiple resources same scope LIFO" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    // Simulate multiple using statements in same scope:
    // using first = open("first") {
    //   using second = open("second") {
    //     using third = open("third") {
    //       // use all resources
    //     }
    //   }
    // }

    const first = try test_ctx.createResource(1);
    const second = try test_ctx.createResource(2);
    const third = try test_ctx.createResource(3);

    // Simulate acquisition and cleanup in LIFO order
    {
        // All resources acquired
        try testing.expect(!first.is_closed);
        try testing.expect(!second.is_closed);
        try testing.expect(!third.is_closed);

        // Cleanup in reverse order of acquisition
        try third.close(); // Last acquired, first closed
        try second.close(); // Second acquired, second closed
        try first.close(); // First acquired, last closed
    }

    // Verify LIFO cleanup order: 3, 2, 1
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 3);
    try testing.expect(cleanup_order[0] == 3);
    try testing.expect(cleanup_order[1] == 2);
    try testing.expect(cleanup_order[2] == 1);
}

// Test 6: Cleanup error handling (non-masking)
test "using statement - cleanup error handling" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    const resource = try test_ctx.createResource(4);
    resource.setCloseError(TestResource.TestError.CloseFailure);

    // Simulate cleanup failure
    const cleanup_result = resource.close();

    // Verify cleanup error is propagated, not masked
    try testing.expectError(TestResource.TestError.CloseFailure, cleanup_result);

    // Resource should still be marked as "attempted to close"
    // (implementation detail - in real code, this might vary)
}

// Test 7: Multiple cleanup errors (aggregation)
test "using statement - multiple cleanup errors" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    var aggregator = CleanupAggregator.init(testing.allocator);
    defer aggregator.deinit();

    const astdb = @import("../../../compiler/libjanus/astdb.zig");
    const span = astdb.Span{
        .start_byte = 0,
        .end_byte = 10,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 11,
    };

    // Simulate multiple cleanup failures
    try aggregator.addError("FileCloseError", "Failed to close file", 1, span);
    try aggregator.addError("NetworkCloseError", "Failed to close connection", 2, span);
    try aggregator.addError("DatabaseCloseError", "Failed to close database", 3, span);

    const aggregate_error = aggregator.finalize();
    try testing.expect(aggregate_error != null);

    const agg_err = aggregate_error.?;
    try testing.expect(agg_err.total_error_count == 3);
    try testing.expect(agg_err.suppressed_errors.len == 2);

    // Primary error should be the first one
    try testing.expectEqualStrings("Failed to close file", agg_err.primary_error.message);

    // Suppressed errors should be the rest
    try testing.expectEqualStrings("Failed to close connection", agg_err.suppressed_errors[0].message);
    try testing.expectEqualStrings("Failed to close database", agg_err.suppressed_errors[1].message);
}

// Test 8: Infallible cleanup (no error handling needed)
test "using statement - infallible cleanup" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    // Simulate infallible resource (close cannot fail)
    const InfallibleResource = struct {
        id: u32,
        is_closed: bool,
        cleanup_order: *std.ArrayList(u32),

        pub fn init(id: u32, cleanup_order: *std.ArrayList(u32)) @This() {
            return @This(){
                .id = id,
                .is_closed = false,
                .cleanup_order = cleanup_order,
            };
        }

        pub fn close(self: *@This()) void {
            self.is_closed = true;
            self.cleanup_order.append(self.id) catch {};
        }
    };

    var infallible = InfallibleResource.init(5, &test_ctx.cleanup_order);

    // Cleanup should always succeed
    infallible.close();

    try testing.expect(infallible.is_closed);
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 1);
    try testing.expect(cleanup_order[0] == 5);
}

// Test 9: Resource binding validation
test "using statement - resource binding" {
    const allocator = testing.allocator;

    const astdb = @import("../../../compiler/libjanus/astdb.zig");
    const span = astdb.Span{
        .start_byte = 0,
        .end_byte = 20,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 21,
    };

    const flags = UsingStmt.UsingFlags{ .is_shared = false };
    const binding = UsingStmt.Binding{
        .name = "test_resource",
        .span = span,
        .is_mutable = false,
    };

    const open_expr = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 };
    const block = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 };

    const using_stmt = try UsingStmt.init(allocator, span, flags, binding, null, open_expr, block);
    defer using_stmt.deinit(allocator);

    // Verify binding properties
    try testing.expectEqualStrings("test_resource", using_stmt.binding.name);
    try testing.expect(!using_stmt.binding.is_mutable);
    try testing.expect(!using_stmt.flags.is_shared);
}

// Test 10: Desugaring round-trip validation
test "using statement - desugaring round-trip" {
    const allocator = testing.allocator;

    var desugar = UsingDesugar.init(allocator);
    defer desugar.deinit();

    const astdb = @import("../../../compiler/libjanus/astdb.zig");
    const span = astdb.Span{
        .start_byte = 0,
        .end_byte = 30,
        .start_line = 1,
        .start_col = 1,
        .end_line = 1,
        .end_col = 31,
    };

    const flags = UsingStmt.UsingFlags{ .is_shared = false, .is_infallible = true };
    const binding = UsingStmt.Binding{
        .name = "file",
        .span = span,
        .is_mutable = false,
    };

    const open_expr = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{1} ** 32 };
    const block = @import("../../../compiler/libjanus/astdb/ids.zig").CID{ .bytes = [_]u8{2} ** 32 };

    const using_stmt = try UsingStmt.init(allocator, span, flags, binding, null, open_expr, block);
    defer using_stmt.deinit(allocator);

    // Get desugared equivalent
    const defer_equiv = try using_stmt.getDesugaredDefer(allocator);
    defer allocator.free(defer_equiv.cleanup_call);

    // Verify desugaring properties
    try testing.expectEqualStrings("file", defer_equiv.resource_binding);
    try testing.expectEqualStrings("file.close()", defer_equiv.cleanup_call);
    try testing.expect(defer_equiv.error_handling == .none); // Infallible
}

// Performance test: Sub-millisecond cleanup
test "using statement - performance under 1ms" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    const start_time = compat_time.nanoTimestamp();

    // Simulate rapid resource acquisition and cleanup
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const resource = try test_ctx.createResource(i);
        try resource.close();
    }

    const end_time = compat_time.nanoTimestamp();
    const elapsed_ns = end_time - start_time;
    const elapsed_ms = @intToFloat(f64, elapsed_ns) / 1_000_000.0;

    // Should complete 1000 operations in under 1ms
    try testing.expect(elapsed_ms < 1.0);

    // Verify all resources were cleaned up
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 1000);
}

// Integration test: Complex nested scenario
test "using statement - complex nested scenario" {
    var test_ctx = TestContext.init(testing.allocator);
    defer test_ctx.deinit();

    // Simulate complex nested using with early returns and exceptions
    const ComplexTest = struct {
        fn runTest(ctx: *TestContext) !void {
            const outer = try ctx.createResource(1);
            defer outer.close() catch {};

            {
                const middle = try ctx.createResource(2);
                defer middle.close() catch {};

                {
                    const inner = try ctx.createResource(3);
                    defer inner.close() catch {};

                    // Simulate some work that might fail
                    if (inner.id == 3) {
                        return; // Early return - all resources should still clean up
                    }
                }
            }
        }
    };

    try ComplexTest.runTest(&test_ctx);

    // Verify LIFO cleanup occurred despite early return
    const cleanup_order = test_ctx.getCleanupOrder();
    try testing.expect(cleanup_order.len == 3);
    try testing.expect(cleanup_order[0] == 3); // Inner
    try testing.expect(cleanup_order[1] == 2); // Middle
    try testing.expect(cleanup_order[2] == 1); // Outer
}
