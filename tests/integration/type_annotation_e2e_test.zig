// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Type Annotations End-to-End
//
// This test validates type annotation compilation through the complete pipeline:
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

test "Epic 5.1: let with i32 type annotation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x: i32 = 42
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "type_let_i32");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("42\n", output);

    std.debug.print("\n=== LET WITH I32 ANNOTATION PASSED ===\n", .{});
}

test "Epic 5.2: var with i32 type annotation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var x: i32 = 10
        \\    print_int(x)
        \\    x = 20
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "type_var_i32");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("10\n20\n", output);

    std.debug.print("\n=== VAR WITH I32 ANNOTATION PASSED ===\n", .{});
}

test "Epic 5.3: Multiple typed declarations" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a: i32 = 1
        \\    let b: i32 = 2
        \\    let c: i32 = a + b
        \\    print_int(c)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "type_multi");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("3\n", output);

    std.debug.print("\n=== MULTIPLE TYPED DECLARATIONS PASSED ===\n", .{});
}

test "Epic 5.4: Mixed typed and untyped" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x: i32 = 5
        \\    let y = 10
        \\    print_int(x + y)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "type_mixed");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("15\n", output);

    std.debug.print("\n=== MIXED TYPED AND UNTYPED PASSED ===\n", .{});
}

test "Epic 5.5: Type annotation in function parameter" {
    const allocator = testing.allocator;

    // Function params already use type annotations
    const source =
        \\func square(n: i32) -> i32 {
        \\    return n * n
        \\}
        \\
        \\func main() {
        \\    let result: i32 = square(7)
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "type_func_param");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("49\n", output);

    std.debug.print("\n=== TYPE ANNOTATION IN FUNCTION PASSED ===\n", .{});
}
