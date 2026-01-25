// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Arrays End-to-End
//
// This test validates array compilation through the complete pipeline:
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

test "Epic 6.1: Array literal and index access" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [10, 20, 30]
        \\    print_int(arr[0])
        \\    print_int(arr[1])
        \\    print_int(arr[2])
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_simple");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("10\n20\n30\n", output);

    std.debug.print("\n=== ARRAY LITERAL AND INDEX PASSED ===\n", .{});
}

test "Epic 6.2: Array element in computation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [5, 10, 15]
        \\    let sum = arr[0] + arr[1] + arr[2]
        \\    print_int(sum)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_compute");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 5 + 10 + 15 = 30
    try testing.expectEqualStrings("30\n", output);

    std.debug.print("\n=== ARRAY ELEMENT COMPUTATION PASSED ===\n", .{});
}

test "Epic 6.3: Array with variable index" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [100, 200, 300]
        \\    let i = 1
        \\    print_int(arr[i])
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_var_index");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("200\n", output);

    std.debug.print("\n=== ARRAY VARIABLE INDEX PASSED ===\n", .{});
}

test "Epic 6.4: Array in loop" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [1, 2, 3, 4, 5]
        \\    for i in 0..<5 do
        \\        print_int(arr[i])
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_loop");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("1\n2\n3\n4\n5\n", output);

    std.debug.print("\n=== ARRAY IN LOOP PASSED ===\n", .{});
}

test "Epic 6.5: Array with conditional access" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [10, 20, 30]
        \\    let i = 2
        \\    if i > 1 do
        \\        print_int(arr[i])
        \\    else do
        \\        print_int(arr[0])
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_cond");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("30\n", output);

    std.debug.print("\n=== ARRAY CONDITIONAL ACCESS PASSED ===\n", .{});
}

test "Epic 6.6: Array element assignment" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [1, 2, 3]
        \\    print_int(arr[1])
        \\    arr[1] = 99
        \\    print_int(arr[1])
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_assign");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("2\n99\n", output);

    std.debug.print("\n=== ARRAY ELEMENT ASSIGNMENT PASSED ===\n", .{});
}

test "Epic 6.7: Array assignment in loop" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [0, 0, 0]
        \\    for i in 0..<3 do
        \\        arr[i] = i + 1
        \\    end
        \\    print_int(arr[0])
        \\    print_int(arr[1])
        \\    print_int(arr[2])
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_assign_loop");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("1\n2\n3\n", output);

    std.debug.print("\n=== ARRAY ASSIGNMENT IN LOOP PASSED ===\n", .{});
}

test "Epic 6.8: Array swap elements" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let arr = [10, 20, 30]
        \\    let tmp = arr[0]
        \\    arr[0] = arr[2]
        \\    arr[2] = tmp
        \\    print_int(arr[0])
        \\    print_int(arr[1])
        \\    print_int(arr[2])
        \\}
    ;

    const output = try compileAndRun(allocator, source, "array_swap");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("30\n20\n10\n", output);

    std.debug.print("\n=== ARRAY SWAP ELEMENTS PASSED ===\n", .{});
}
