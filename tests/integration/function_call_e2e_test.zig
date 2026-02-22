// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: User-Defined Function Calls End-to-End
//
// This test validates that user-defined functions can call other user-defined
// functions through the complete pipeline:
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

test "Epic 2.1: Simple function call - add function" {
    const allocator = testing.allocator;

    // Define add(a, b) and call it from main
    const source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func main() {
        \\    let result = add(3, 4)
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "func_add");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 3 + 4 = 7
    try testing.expectEqualStrings("7\n", output);

    std.debug.print("\n=== SIMPLE FUNCTION CALL TEST PASSED ===\n", .{});
}

test "Epic 2.1: Chained function calls - double then add" {
    const allocator = testing.allocator;

    // Define double(x) and add(a, b), use them together
    const source =
        \\func double(x: i32) -> i32 {
        \\    return x + x
        \\}
        \\
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func main() {
        \\    let a = double(5)
        \\    let b = double(3)
        \\    let result = add(a, b)
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "func_chain");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // double(5) = 10, double(3) = 6, add(10, 6) = 16
    try testing.expectEqualStrings("16\n", output);

    std.debug.print("\n=== CHAINED FUNCTION CALLS TEST PASSED ===\n", .{});
}

test "Epic 2.1: Function calling function - nested calls" {
    const allocator = testing.allocator;

    // One function calls another function
    const source =
        \\func increment(x: i32) -> i32 {
        \\    return x + 1
        \\}
        \\
        \\func add_three(x: i32) -> i32 {
        \\    let step1 = increment(x)
        \\    let step2 = increment(step1)
        \\    let step3 = increment(step2)
        \\    return step3
        \\}
        \\
        \\func main() {
        \\    let result = add_three(10)
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "func_nested");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 10 + 1 + 1 + 1 = 13
    try testing.expectEqualStrings("13\n", output);

    std.debug.print("\n=== NESTED FUNCTION CALLS TEST PASSED ===\n", .{});
}

test "Epic 2.1: Function with loop - print sequence" {
    const allocator = testing.allocator;

    // Function that uses a loop to print numbers
    // (Avoids mutable accumulator which needs var semantics)
    const source =
        \\func print_range(n: i32) {
        \\    for i in 1..n do
        \\        print_int(i)
        \\    end
        \\}
        \\
        \\func main() {
        \\    print_range(3)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "func_loop");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // Print 1, 2, 3 (inclusive range)
    try testing.expectEqualStrings("1\n2\n3\n", output);

    std.debug.print("\n=== FUNCTION WITH LOOP TEST PASSED ===\n", .{});
}

test "Epic 2.1: Function with conditional - absolute value" {
    const allocator = testing.allocator;

    // Function with if/else
    const source =
        \\func abs(x: i32) -> i32 {
        \\    if x < 0 do
        \\        return 0 - x
        \\    else do
        \\        return x
        \\    end
        \\}
        \\
        \\func main() {
        \\    print_int(abs(5))
        \\    print_int(abs(0 - 7))
        \\}
    ;

    const output = try compileAndRun(allocator, source, "func_abs");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // abs(5) = 5, abs(-7) = 7
    try testing.expectEqualStrings("5\n7\n", output);

    std.debug.print("\n=== FUNCTION WITH CONDITIONAL TEST PASSED ===\n", .{});
}
