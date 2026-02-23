// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Compound Assignment Operators End-to-End
//
// Tests +=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

fn compileAndRun(allocator: std.mem.Allocator, source: []const u8, test_name: []const u8) ![]u8 {
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, test_name);
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== LLVM IR ===\n{s}\n", .{llvm_ir});

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{test_name});
    defer allocator.free(ir_file);
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(.{ .sub_path = ir_file, .data = llvm_ir });

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{test_name});
    defer allocator.free(obj_file);
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-opaque-pointers", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) {
        std.debug.print("LLC STDERR: {s}\n", .{llc_result.stderr});
        return error.LLCFailed;
    }

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, test_name });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);
    if (zig_build_result.term.Exited != 0) return error.RuntimeCompilationFailed;

    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cc", obj_file_path, rt_obj_path, "-o", exe_file_path },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.Exited != 0) return error.LinkFailed;

    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) {
        allocator.free(exec_result.stdout);
        return error.ExecutionFailed;
    }

    return exec_result.stdout;
}

test "Epic 12.1: Plus-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 10
        \\    x += 5
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "plus_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 10 + 5 = 15
    try testing.expectEqualStrings("15\n", output);

    std.debug.print("\n=== PLUS-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.2: Minus-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 20
        \\    x -= 7
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "minus_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 20 - 7 = 13
    try testing.expectEqualStrings("13\n", output);

    std.debug.print("\n=== MINUS-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.3: Star-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 6
        \\    x *= 7
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "star_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 6 * 7 = 42
    try testing.expectEqualStrings("42\n", output);

    std.debug.print("\n=== STAR-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.4: Slash-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 100
        \\    x /= 4
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "slash_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 100 / 4 = 25
    try testing.expectEqualStrings("25\n", output);

    std.debug.print("\n=== SLASH-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.5: Percent-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 17
        \\    x %= 5
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "percent_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 17 % 5 = 2
    try testing.expectEqualStrings("2\n", output);

    std.debug.print("\n=== PERCENT-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.6: Bitwise AND-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 0b1111
        \\    x &= 0b1010
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "and_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b1111 & 0b1010 = 0b1010 = 10
    try testing.expectEqualStrings("10\n", output);

    std.debug.print("\n=== AND-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.7: Bitwise OR-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 0b1100
        \\    x |= 0b0011
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "or_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b1100 | 0b0011 = 0b1111 = 15
    try testing.expectEqualStrings("15\n", output);

    std.debug.print("\n=== OR-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.8: Bitwise XOR-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 0b1111
        \\    x ^= 0b0101
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "xor_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b1111 ^ 0b0101 = 0b1010 = 10
    try testing.expectEqualStrings("10\n", output);

    std.debug.print("\n=== XOR-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.9: Left shift-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 3
        \\    x <<= 4
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "shl_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 3 << 4 = 48
    try testing.expectEqualStrings("48\n", output);

    std.debug.print("\n=== LEFT SHIFT-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.10: Right shift-assign operator" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 64
        \\    x >>= 2
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "shr_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 64 >> 2 = 16
    try testing.expectEqualStrings("16\n", output);

    std.debug.print("\n=== RIGHT SHIFT-ASSIGN PASSED ===\n", .{});
}

test "Epic 12.11: Chained compound assignment" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 10
        \\    x += 5
        \\    x *= 2
        \\    x -= 10
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "chained_compound");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // ((10 + 5) * 2) - 10 = (15 * 2) - 10 = 30 - 10 = 20
    try testing.expectEqualStrings("20\n", output);

    std.debug.print("\n=== CHAINED COMPOUND PASSED ===\n", .{});
}

test "Epic 12.12: Compound with expression RHS" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x = 100
        \\    let y = 3
        \\    x += y * 10
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "compound_expr_rhs");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 100 + (3 * 10) = 100 + 30 = 130
    try testing.expectEqualStrings("130\n", output);

    std.debug.print("\n=== COMPOUND WITH EXPRESSION RHS PASSED ===\n", .{});
}
