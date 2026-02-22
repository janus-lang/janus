// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Match Statement End-to-End
//
// This test validates match statement compilation through the complete pipeline:
// Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution

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

test "Epic 2.3: Match on integer literals - simple" {
    const allocator = testing.allocator;

    // Simple match with integer literals
    const source =
        \\func main() {
        \\    let x = 2
        \\    match x do
        \\        1 => print_int(10)
        \\        2 => print_int(20)
        \\        3 => print_int(30)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "match_simple");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // x = 2, so should print 20
    try testing.expectEqualStrings("20\n", output);

    std.debug.print("\n=== SIMPLE MATCH TEST PASSED ===\n", .{});
}

test "Epic 2.3: Match with wildcard default" {
    const allocator = testing.allocator;

    // Match with wildcard _ as catch-all
    const source =
        \\func main() {
        \\    let x = 99
        \\    match x do
        \\        1 => print_int(10)
        \\        2 => print_int(20)
        \\        _ => print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "match_wildcard");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // x = 99, doesn't match 1 or 2, falls to wildcard
    try testing.expectEqualStrings("0\n", output);

    std.debug.print("\n=== MATCH WILDCARD TEST PASSED ===\n", .{});
}

test "Epic 2.3: Match with guard conditions" {
    const allocator = testing.allocator;

    // Match with when guards
    const source =
        \\func main() {
        \\    let x = 5
        \\    match x do
        \\        5 when x > 10 => print_int(1)
        \\        5 when x < 10 => print_int(2)
        \\        _ => print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "match_guard");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // x = 5, first arm fails guard (5 > 10 is false), second arm matches (5 < 10 is true)
    try testing.expectEqualStrings("2\n", output);

    std.debug.print("\n=== MATCH GUARD TEST PASSED ===\n", .{});
}

test "Epic 2.3: Match with negation pattern !0" {
    const allocator = testing.allocator;

    // Match with negation pattern: !0 matches any value != 0
    const source =
        \\func main() {
        \\    let x = 5
        \\    match x do
        \\        0 => print_int(0)
        \\        !0 => print_int(1)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "match_negation");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // x = 5 which is != 0, so matches !0 pattern
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("\n=== MATCH NEGATION PATTERN TEST PASSED ===\n", .{});
}

test "Epic 2.3: Match negation with zero value" {
    const allocator = testing.allocator;

    // Negation pattern should NOT match when value equals the negated value
    const source =
        \\func main() {
        \\    let x = 0
        \\    match x do
        \\        !0 => print_int(99)
        \\        _ => print_int(42)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "match_negation_zero");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // x = 0, !0 means != 0, so it doesn't match, falls to wildcard
    try testing.expectEqualStrings("42\n", output);

    std.debug.print("\n=== MATCH NEGATION ZERO TEST PASSED ===\n", .{});
}
