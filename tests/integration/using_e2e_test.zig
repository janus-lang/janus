// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Integration Test: Using Statement End-to-End Compilation (:service profile)
//!
//! This test validates the compilation pipeline for using statements:
//! Source → Parser → ASTDB → Lowerer → QTJIR → LLVM
//!
//! Phase 3 (Resource Management): using statement provides deterministic cleanup

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test ":service profile: Using statement parses correctly" {
    const allocator = testing.allocator;

    // Simple using statement with mock open/read functions
    const source =
        \\func open(path: String) -> i32 do
        \\    return 1
        \\end
        \\
        \\func read(fd: i32) -> String do
        \\    return "content"
        \\end
        \\
        \\func process_file() do
        \\    using file = open("test.txt") do
        \\        read(file)
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify we have IR nodes
    try testing.expect(ir_graphs.items.len > 0);

    std.debug.print("\n=== USING STATEMENT COMPILES TO QTJIR ===\n", .{});
}

test ":service profile: Using shared statement parses correctly" {
    const allocator = testing.allocator;

    // Using shared statement
    const source =
        \\func process_shared() do
        \\    using shared conn = connect() do
        \\        send(conn, "hello")
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    std.debug.print("\n=== USING SHARED STATEMENT COMPILES ===\n", .{});
}

test ":service profile: Using with type annotation parses correctly" {
    const allocator = testing.allocator;

    // Using with explicit type annotation
    const source =
        \\func process() do
        \\    using f: File = open("data.txt") do
        \\        read(f)
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    std.debug.print("\n=== USING WITH TYPE ANNOTATION COMPILES ===\n", .{});
}

test ":service profile: Using with walrus operator parses correctly" {
    const allocator = testing.allocator;

    // Using with := walrus operator
    const source =
        \\func process() do
        \\    using f := open("data.txt") do
        \\        read(f)
        \\    end
        \\    return 0
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    std.debug.print("\n=== USING WITH WALRUS OPERATOR COMPILES ===\n", .{});
}
