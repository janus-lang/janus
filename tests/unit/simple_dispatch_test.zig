// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const DispatchFamily = @import("compiler/libjanus/dispatch_family.zig").DispatchFamily;
const DispatchFamilyRegistry = @import("compiler/libjanus/dispatch_family.zig").DispatchFamilyRegistry;
const FuncDecl = @import("compiler/libjanus/dispatch_family.zig").FuncDecl;
const SourceLocation = @import("compiler/libjanus/dispatch_family.zig").SourceLocation;

test "Simple dispatch family integration" {
    var registry = DispatchFamilyRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Create test functions
    var add_i32 = FuncDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
            .start_byte = 0,
            .end_byte = 10,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    var add_f64 = FuncDecl{
        .name = "add",
        .parameter_types = "f64,f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "test.jan",
            .line = 5,
            .column = 1,
            .start_byte = 50,
            .end_byte = 60,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    // Register functions
    try registry.registerFunction(&add_i32);
    try registry.registerFunction(&add_f64);

    // Test family creation
    const family = registry.getFamily("add").?;
    try std.testing.expect(family.getOverloadCount() == 2);
    try std.testing.expect(!family.isSingleFunction());

    // Test dispatch resolution
    const best_match = family.findBestMatch("i32,i32");
    try std.testing.expect(best_match != null);
    try std.testing.expectEqualStrings(best_match.?.parameter_types, "i32,i32");

    // Test no match
    const no_match = family.findBestMatch("string,string");
    try std.testing.expect(no_match == null);

    std.debug.print("✅ Simple dispatch integration test passed!\n", .{});
}

test "Multiple dispatch families" {
    var registry = DispatchFamilyRegistry.init(std.testing.allocator);
    defer registry.deinit();

    // Create functions for different families
    var add_func = FuncDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "math.jan",
            .line = 1,
            .column = 1,
            .start_byte = 0,
            .end_byte = 10,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    var multiply_func = FuncDecl{
        .name = "multiply",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = SourceLocation{
            .file = "math.jan",
            .line = 10,
            .column = 1,
            .start_byte = 100,
            .end_byte = 120,
        },
        .dispatch_family = null,
        .overload_index = 0,
        .signature_hash = 0,
    };

    // Register functions
    try registry.registerFunction(&add_func);
    try registry.registerFunction(&multiply_func);

    // Test registry properties
    try std.testing.expect(registry.getFamilyCount() == 2);
    try std.testing.expect(registry.getTotalOverloads() == 2);

    // Test individual families
    const add_family = registry.getFamily("add").?;
    const multiply_family = registry.getFamily("multiply").?;

    try std.testing.expect(add_family.isSingleFunction());
    try std.testing.expect(multiply_family.isSingleFunction());

    std.debug.print("✅ Multiple dispatch families test passed!\n", .{});
}
