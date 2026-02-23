// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Hello World End-to-End Compilation
//
// This test validates the ENTIRE compilation pipeline:
// Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");
const e2e = @import("e2e_helper");

test "Epic 1.4.1: Compile and Execute Hello World end-to-end" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    println("Hello, World!")
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "hello_world");
    defer allocator.free(output);

    try testing.expectEqualStrings("Hello, World!\n", output);

    std.debug.print("\n=== HELLO WORLD EXECUTED SUCCESSFULLY ===\n", .{});
}

test "Epic 1.4.1: Verify print function signature" {
    const allocator = testing.allocator;

    // Parse simple print call
    const source =
        \\func main() {
        \\    print("Test")
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify we have a Call node with function name set
    const graph = ir_graphs.items[0];
    var found_call = false;
    for (graph.nodes.items) |node| {
        if (node.op == .Call) {
            found_call = true;
            // Verify the Call node has string data (function name)
            switch (node.data) {
                .string => |name| {
                    // Should be a janus runtime function (janus_print or similar)
                    try testing.expect(std.mem.startsWith(u8, name, "janus_"));
                },
                else => return error.CallNodeMissingFunctionName,
            }
        }
    }

    try testing.expect(found_call);
    std.debug.print("\n=== Call node has function name set correctly ===\n", .{});
}
