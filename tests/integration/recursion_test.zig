// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Control Flow & Recursion (Factorial)
//

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Recursion Execution (Factorial)" {
    const allocator = testing.allocator;

    // ========== STEP 1: Parse Source to ASTDB ==========
    const source =
        \\func factorial(n: i32) -> i32 {
        \\    if n < 2 {
        \\        return 1
        \\    }
        \\    return n * factorial(n - 1)
        \\}
        \\
        \\func main() {
        \\    let f = factorial(5)
        \\    print_int(f)
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    // Enable S0 since we need 'if' and 'less'
    parser.enableS0(true);

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // ========== STEP 2: Lower ASTDB to QTJIR ==========
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // ========== STEP 3: Emit QTJIR to LLVM IR ==========
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "recursion_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    // ========== STEP 4: Write LLVM IR to File ==========
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "recursion.ll" });
    defer allocator.free(ir_file_path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "recursion.ll", .data = llvm_ir });

    // ========== STEP 5: Compile LLVM IR to Object File ==========
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "recursion.o" });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "llc",
            "-filetype=obj",
            ir_file_path,
            "-o",
            obj_file_path,
        },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);

    if (llc_result.term.Exited != 0) {
        std.debug.print("LLC FAILED: {s}\n", .{llc_result.stderr});
        // Dump IR for debugging
        std.debug.print("IR Dump:\n{s}\n", .{llvm_ir});
        return error.LLCFailed;
    }

    // ========== STEP 6: Link with Runtime (Compile Zig Runtime) ==========
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "recursion_test_exe" });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    // Compile Runtime
    const zig_build_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "zig", // Assuming zig is in PATH (it must be to run tests)
            "build-obj",
            "runtime/janus_rt.zig",
            emit_arg,
            "-lc",
        },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);

    if (zig_build_result.term.Exited != 0) {
        std.debug.print("RUNTIME COMPILATION FAILED: {s}\n", .{zig_build_result.stderr});
        return error.RuntimeCompilationFailed;
    }

    // Link
    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{
            "cc",
            obj_file_path,
            rt_obj_path,
            "-o",
            exe_file_path,
        },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    if (link_result.term.Exited != 0) {
        std.debug.print("LINK FAILED: {s}\n", .{link_result.stderr});
        return error.LinkFailed;
    }

    // ========== STEP 7: Execute and Verify Output ==========
    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    if (exec_result.term.Exited != 0) {
        std.debug.print("EXEC FAILED: {s}\n", .{exec_result.stderr});
        return error.ExecutionFailed;
    }

    const expected =
        \\120
        \\
    ;

    try testing.expectEqualStrings(expected, exec_result.stdout);

    std.debug.print("✅ Recursion Test Passed\n", .{});
}
