// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Unary Operators End-to-End
//
// Per SPEC-017-syntax.md:
//   unary <- ( 'not' | '-' ) unary / postfix
//
// Valid: -x (negation), not flag (boolean not)
// Invalid: !flag (use 'not' keyword instead)

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
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
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

test "Epic 7.1: Unary minus on literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = -42
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_minus_lit");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("-42\n", output);

    std.debug.print("\n=== UNARY MINUS ON LITERAL PASSED ===\n", .{});
}

test "Epic 7.2: Unary minus on variable" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 10
        \\    let y = -x
        \\    print_int(y)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_minus_var");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("-10\n", output);

    std.debug.print("\n=== UNARY MINUS ON VARIABLE PASSED ===\n", .{});
}

test "Epic 7.3: Double negation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 5
        \\    let y = - -x
        \\    print_int(y)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_double_neg");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("5\n", output);

    std.debug.print("\n=== DOUBLE NEGATION PASSED ===\n", .{});
}

test "Epic 7.4: Unary minus in expression" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = 10
        \\    let b = 3
        \\    let result = a + -b
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_in_expr");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 10 + (-3) = 7
    try testing.expectEqualStrings("7\n", output);

    std.debug.print("\n=== UNARY MINUS IN EXPRESSION PASSED ===\n", .{});
}

test "Epic 7.5: Boolean not with true" {
    const allocator = testing.allocator;

    // Test not keyword with boolean literal
    const source =
        \\func main() {
        \\    let flag = true
        \\    if not flag do
        \\        print_int(0)
        \\    else do
        \\        print_int(1)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_not_true");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // not true = false, so else branch prints 1
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("\n=== BOOLEAN NOT WITH TRUE PASSED ===\n", .{});
}

test "Epic 7.6: Boolean not with false" {
    const allocator = testing.allocator;

    // Test not keyword with false value
    const source =
        \\func main() {
        \\    let flag = false
        \\    if not flag do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_not_false");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // not false = true, so then branch prints 1
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("\n=== BOOLEAN NOT WITH FALSE PASSED ===\n", .{});
}

test "Epic 7.7: Not with comparison result" {
    const allocator = testing.allocator;

    // Test not with comparison result
    const source =
        \\func main() {
        \\    let x = 5
        \\    if not (x > 10) do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_not_cmp");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 5 > 10 is false, not false = true, so then branch prints 1
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("\n=== NOT WITH COMPARISON PASSED ===\n", .{});
}

test "Epic 7.8: Unary minus in conditional" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 5
        \\    if x < 0 do
        \\        print_int(-x)
        \\    else do
        \\        print_int(x)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "unary_neg_cond");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 5 is not < 0, so print 5
    try testing.expectEqualStrings("5\n", output);

    std.debug.print("\n=== UNARY MINUS IN CONDITIONAL PASSED ===\n", .{});
}
