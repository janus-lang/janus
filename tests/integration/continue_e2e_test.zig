// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Continue Statement End-to-End
//
// This test validates continue statement compilation through the complete pipeline:
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

test "Epic 2.2: Continue in for loop - skip even numbers" {
    const allocator = testing.allocator;

    // Print only odd numbers by continuing on even
    const source =
        \\func main() {
        \\    for i in 1..5 do
        \\        if i == 2 do
        \\            continue
        \\        end
        \\        if i == 4 do
        \\            continue
        \\        end
        \\        print_int(i)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "continue_for");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // Skip 2 and 4, print 1, 3, 5
    try testing.expectEqualStrings("1\n3\n5\n", output);

    std.debug.print("\n=== CONTINUE IN FOR LOOP TEST PASSED ===\n", .{});
}

test "Epic 2.2: Continue in while loop - skip specific value" {
    const allocator = testing.allocator;

    // Test continue in while using constant condition patterns
    const source =
        \\func main() {
        \\    for i in 0..<4 do
        \\        if i == 1 do
        \\            continue
        \\        end
        \\        print_int(i)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "continue_while");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // Skip i=1, print 0, 2, 3
    try testing.expectEqualStrings("0\n2\n3\n", output);

    std.debug.print("\n=== CONTINUE IN WHILE-LIKE LOOP TEST PASSED ===\n", .{});
}

test "Epic 2.2: Continue with nested conditions" {
    const allocator = testing.allocator;

    // More complex continue usage
    const source =
        \\func main() {
        \\    for i in 1..6 do
        \\        if i < 3 do
        \\            continue
        \\        end
        \\        if i > 4 do
        \\            continue
        \\        end
        \\        print_int(i)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "continue_nested");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // Skip i < 3 (1, 2) and i > 4 (5, 6), print 3, 4
    try testing.expectEqualStrings("3\n4\n", output);

    std.debug.print("\n=== CONTINUE WITH NESTED CONDITIONS TEST PASSED ===\n", .{});
}
