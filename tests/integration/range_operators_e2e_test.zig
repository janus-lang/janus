// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Range Operators End-to-End
//
// This test validates both inclusive (..) and exclusive (..<) range operators
// through the complete compilation pipeline.

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Range operators: Inclusive range (0..3)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    for i in 0..3 {
        \\        print_int(i)
        \\    }
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);
    std.debug.print("\n=== Range Inclusive Test ===\n", .{});

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "range_inclusive");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("=== LLVM IR ===\n{s}\n", .{llvm_ir});

    // Compile and execute
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_inc.ll" });
    defer allocator.free(ir_file);

    try tmp_dir.dir.writeFile(.{ .sub_path = "range_inc.ll", .data = llvm_ir });

    const obj_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_inc.o" });
    defer allocator.free(obj_file);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file, "-o", obj_file },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) return error.LLCFailed;

    const exe_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_inc" });
    defer allocator.free(exe_file);

    const rt_obj = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj});
    defer allocator.free(emit_arg);

    const zig_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_result.stdout);
    defer allocator.free(zig_result.stderr);
    if (zig_result.term.Exited != 0) return error.RuntimeFailed;

    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cc", obj_file, rt_obj, "-o", exe_file },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.Exited != 0) return error.LinkFailed;

    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // 0..3 is INCLUSIVE: 0, 1, 2, 3
    try testing.expectEqualStrings("0\n1\n2\n3\n", exec_result.stdout);

    std.debug.print("=== INCLUSIVE RANGE PASSED ===\n", .{});
}

test "Range operators: Exclusive range (0..<4)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    for i in 0..<4 {
        \\        print_int(i)
        \\    }
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);
    std.debug.print("\n=== Range Exclusive Test ===\n", .{});

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "range_exclusive");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("=== LLVM IR ===\n{s}\n", .{llvm_ir});

    // Compile and execute
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_exc.ll" });
    defer allocator.free(ir_file);

    try tmp_dir.dir.writeFile(.{ .sub_path = "range_exc.ll", .data = llvm_ir });

    const obj_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_exc.o" });
    defer allocator.free(obj_file);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file, "-o", obj_file },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) return error.LLCFailed;

    const exe_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "range_exc" });
    defer allocator.free(exe_file);

    const rt_obj = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj});
    defer allocator.free(emit_arg);

    const zig_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_result.stdout);
    defer allocator.free(zig_result.stderr);
    if (zig_result.term.Exited != 0) return error.RuntimeFailed;

    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "cc", obj_file, rt_obj, "-o", exe_file },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.Exited != 0) return error.LinkFailed;

    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // 0..<4 is EXCLUSIVE: 0, 1, 2, 3 (NOT 4)
    try testing.expectEqualStrings("0\n1\n2\n3\n", exec_result.stdout);

    std.debug.print("=== EXCLUSIVE RANGE PASSED ===\n", .{});
}

// TODO: Variable bounds test - parser currently has issues with `let` statements in this context
// test "Range operators: Variable bounds" {
//     const allocator = testing.allocator;
//     const source =
//         \\func main() {
//         \\    let start = 2
//         \\    let end = 5
//         \\    for i in start..end {
//         \\        print_int(i)
//         \\    }
//         \\}
//     ;
//     // Implementation when parser issue resolved
// }
