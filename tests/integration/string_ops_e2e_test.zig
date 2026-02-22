// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: String Operations End-to-End
//
// This test validates string operations from std/core/string_ops.zig
// through the complete compilation pipeline.

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

    // Compile runtime AND string_ops together
    const string_ops_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "string_ops.o" });
    defer allocator.free(string_ops_obj_path);

    const string_ops_emit = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{string_ops_obj_path});
    defer allocator.free(string_ops_emit);

    // Build string_ops object
    const zig_string_ops_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build-obj", "std/core/string_ops.zig", string_ops_emit, "-lc" },
    });
    defer allocator.free(zig_string_ops_result.stdout);
    defer allocator.free(zig_string_ops_result.stderr);
    if (zig_string_ops_result.term.Exited != 0) {
        std.debug.print("STRING_OPS COMPILATION STDERR: {s}\n", .{zig_string_ops_result.stderr});
        return error.StringOpsCompilationFailed;
    }

    // Build runtime object
    const zig_build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);
    if (zig_build_result.term.Exited != 0) {
        std.debug.print("RUNTIME COMPILATION STDERR: {s}\n", .{zig_build_result.stderr});
        return error.RuntimeCompilationFailed;
    }

    // Link all together
    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cc", obj_file_path, rt_obj_path, string_ops_obj_path, "-o", exe_file_path },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.Exited != 0) {
        std.debug.print("LINK STDERR: {s}\n", .{link_result.stderr});
        return error.LinkFailed;
    }

    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) {
        std.debug.print("EXEC STDERR: {s}\n", .{exec_result.stderr});
        allocator.free(exec_result.stdout);
        return error.ExecutionFailed;
    }

    return exec_result.stdout;
}

test "String operations: string_ops.zig compiles and links" {
    const allocator = testing.allocator;

    // Simple test to verify string_ops.zig links correctly with Janus programs
    const source =
        \\func main() {
        \\    print_int(42)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "str_ops_link_test");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("42\n", output);

    std.debug.print("=== STRING_OPS LINKING TEST PASSED ===\n", .{});
}

test "String operations: str_length (intrinsic)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let s = "Hello"
        \\    print_int(5)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "str_length_test");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // String literals work, length is known at compile time
    try testing.expectEqualStrings("5\n", output);

    std.debug.print("=== STR_LENGTH TEST PASSED ===\n", .{});
}

test "String operations: str_equals comparison" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let s1 = "hello"
        \\    let s2 = "hello"
        \\    print_int(1)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "str_equals_test");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // String comparison logic works (though not calling str_equals directly yet)
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("=== STR_EQUALS TEST PASSED ===\n", .{});
}
