// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const SemanticResolver = @import("compiler/libjanus/semantic_resolver.zig").SemanticResolver;
const CallSite = @import("compiler/libjanus/semantic_resolver.zig").CallSite;

test "minimal semantic resolver test" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    var resolver = try SemanticResolver.init(gpa.allocator());
    defer resolver.deinit();

    const call_site = CallSite{
        .function_name = "test",
        .argument_types = &[_]u32{ 1, 2 },
        .source_location = .{
            .file = "test.jan",
            .line = 1,
            .column = 1,
            .start_byte = 0,
            .end_byte = 4,
        },
    };

    var result = try resolver.resolve(call_site);
    defer result.deinit(gpa.allocator());

}
