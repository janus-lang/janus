// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const astdb = @import("compiler/astdb/astdb.zig");
const parser = @import("compiler/libjanus/passes/janus_parser.zig");
const tokenizer_mod = @import("compiler/libjanus/passes/janus_tokenizer.zig");

fn toUsize(value: anytype) usize {
    const info = @typeInfo(@TypeOf(value));
    return switch (info) {
        .Enum => @as(usize, @intCast(@intFromEnum(value))),
        .Int => @as(usize, @intCast(value)),
        else => @compileError("unsupported conversion to usize"),
    };
}

fn validateUnitColumnIntegrity(unit: *const astdb.CompilationUnit) !void {
    try testing.expect(!unit.is_removed);
    try testing.expect(unit.nodes.len > 0);
    try testing.expect(unit.edges.len >= unit.nodes.len);

    const source_len = unit.source.len;

    for (unit.tokens) |token| {
        try testing.expect(token.trivia_lo <= token.trivia_hi);
        try testing.expect(token.trivia_hi <= unit.trivia.len);
        try testing.expect(token.span.start <= token.span.end);
        try testing.expect(token.span.end <= source_len);
    }

    for (unit.nodes) |node| {
        const child_lo = toUsize(node.child_lo);
        const child_hi = toUsize(node.child_hi);
        try testing.expect(child_lo <= child_hi);
        try testing.expect(child_hi <= unit.edges.len);

        for (unit.edges[child_lo..child_hi]) |child_id| {
            const child_index = toUsize(child_id);
            try testing.expect(child_index < unit.nodes.len);
        }

        if (unit.tokens.len > 0) {
            const first_index = toUsize(node.first_token);
            const last_index = toUsize(node.last_token);
            try testing.expect(first_index < unit.tokens.len);
            try testing.expect(last_index < unit.tokens.len);
        }
    }

    for (unit.scopes) |scope| {
        if (scope.parent) |parent| {
            try testing.expect(toUsize(parent) < unit.scopes.len);
        }
        if (scope.first_decl) |decl_id| {
            try testing.expect(toUsize(decl_id) < unit.decls.len);
        }
    }

    for (unit.decls) |decl| {
        try testing.expect(toUsize(decl.node) < unit.nodes.len);
        if (unit.scopes.len > 0) {
            try testing.expect(toUsize(decl.scope) < unit.scopes.len);
        }
        if (decl.next_in_scope) |next| {
            try testing.expect(toUsize(next) < unit.decls.len);
        }
    }

    for (unit.refs) |ref| {
        try testing.expect(toUsize(ref.at_node) < unit.nodes.len);
        if (ref.decl) |decl_id| {
            try testing.expect(toUsize(decl_id) < unit.decls.len);
        }
    }

    for (unit.diags) |diag| {
        try testing.expect(diag.span.start <= diag.span.end);
        try testing.expect(diag.span.end <= source_len);
        if (diag.fix) |fix| {
            for (fix.edits) |edit| {
                try testing.expect(edit.span.start <= edit.span.end);
                try testing.expect(edit.span.end <= source_len);
            }
        }
    }

    if (unit.cids.len != 0) {
        try testing.expect(unit.cids.len == unit.nodes.len);
    }
}

// 🔧 SIMPLE ASTDB VALIDATION
// Basic validation that the ASTDB system works correctly with string interning

test "Simple ASTDB Validation" {
    std.debug.print("\n🔧 SIMPLE ASTDB VALIDATION\n", .{});
    std.debug.print("==========================\n", .{});

    // Test that we can import the modules
    const interners = @import("compiler/astdb/intern.zig");

    std.debug.print("✅ Successfully imported ASTDB modules\n", .{});

    // Test basic string interner
    var str_interner = interners.StrInterner.initWithMode(testing.allocator, true);
    defer str_interner.deinit();

    const hello_id = try str_interner.intern("hello");
    const world_id = try str_interner.intern("world");
    const hello_id2 = try str_interner.intern("hello"); // Should deduplicate

    try testing.expectEqual(hello_id, hello_id2);
    try testing.expect(hello_id != world_id);

    try testing.expectEqualStrings("hello", str_interner.getString(hello_id));
    try testing.expectEqualStrings("world", str_interner.getString(world_id));

    std.debug.print("✅ String interner working correctly\n", .{});

    // Test ASTDB system
    var db = astdb.AstDB.initWithMode(testing.allocator, true);
    defer db.deinit();

    // Test unit creation
    const unit_id = try db.addUnit("test.jan", "func main() {}");
    const unit = db.getUnit(unit_id);
    try testing.expect(unit != null);
    try testing.expectEqualStrings("test.jan", unit.?.path);

    std.debug.print("✅ ASTDB unit creation working\n", .{});

    // Test string interning through ASTDB
    const func_str = try db.internString("function");
    const main_str = try db.internString("main");
    const func_str2 = try db.internString("function"); // Should deduplicate

    try testing.expectEqual(func_str, func_str2);
    try testing.expect(func_str != main_str);

    try testing.expectEqualStrings("function", db.getString(func_str));
    try testing.expectEqualStrings("main", db.getString(main_str));

    std.debug.print("✅ ASTDB string interning working\n", .{});

    // Test CID computation
    const module_cid = try db.computeCID(.{ .module_unit = unit_id }, testing.allocator);
    try testing.expectEqual(@as(usize, 32), module_cid.len);

    // Should not be all zeros
    const zero_cid = [_]u8{0} ** 32;
    try testing.expect(!std.mem.eql(u8, &module_cid, &zero_cid));

    std.debug.print("✅ CID computation working\n", .{});

    std.debug.print("\n🎯 SIMPLE ASTDB VALIDATION COMPLETE\n", .{});
    std.debug.print("✅ All basic functionality working correctly\n", .{});
}

test "ASTDB Column Integrity Invariants" {
    std.debug.print("\n🧱 ASTDB COLUMN INTEGRITY CHECK\n", .{});
    std.debug.print("===============================\n", .{});

    const allocator = testing.allocator;
    const Parser = parser.Parser;
    const source =
        "use math.core\n" ++
        "func main() do\n" ++
        "    let value := 42\n" ++
        "    return 42\n" ++
        "end\n" ++
        "struct Point {\n" ++
        "    x: i32\n" ++
        "}\n";

    const empty_tokens = [_]tokenizer_mod.Token{};
    var parser_instance = Parser.init(allocator, &empty_tokens);
    defer parser_instance.deinit();

    var snapshot = try parser_instance.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.astdb_system.units.items.len > 0);

    for (snapshot.astdb_system.units.items) |unit| {
        if (unit.is_removed) continue;
        try validateUnitColumnIntegrity(unit);
    }

    std.debug.print("✅ Column integrity validated for parsed compilation unit\n", .{});
}

test "ASTDB Memory Stress Test" {
    std.debug.print("\n⚡ ASTDB MEMORY STRESS TEST\n", .{});
    std.debug.print("===========================\n", .{});

    // Multiple cycles to test memory management
    for (0..10) |cycle| {
        var db = astdb.AstDB.initWithMode(testing.allocator, true);
        defer db.deinit();

        // Create multiple units
        var buffer: [64]u8 = undefined;
        for (0..20) |i| {
            const path = std.fmt.bufPrint(&buffer, "cycle_{d}_file_{d}.jan", .{ cycle, i }) catch unreachable;
            const source = std.fmt.bufPrint(&buffer, "func test_{d}() {{}}", .{i}) catch unreachable;

            _ = try db.addUnit(path, source);

            // Intern strings
            const func_name = std.fmt.bufPrint(&buffer, "function_{d}_{d}", .{ cycle, i }) catch unreachable;
            _ = try db.internString(func_name);
        }

        if (cycle % 3 == 0) {
            std.debug.print("   🔄 Cycle {d}/10 completed\n", .{cycle + 1});
        }
    }

    std.debug.print("✅ Memory stress test completed successfully\n", .{});
}
