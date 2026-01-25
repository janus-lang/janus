// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: If/Else End-to-End Compilation
//
// This test validates if/else compilation through the complete pipeline:
// Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Epic 1.6: If statement - condition true branch" {
    const allocator = testing.allocator;

    // if 5 > 3 do print_int(1) else print_int(0) end
    const source =
        \\func main() {
        \\    if 5 > 3 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);
    std.debug.print("\n=== Parsed {d} AST nodes ===\n", .{snapshot.nodeCount()});

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    try testing.expect(ir_graphs.items.len > 0);
    std.debug.print("\n=== QTJIR Graph ===\n", .{});
    std.debug.print("Nodes: {d}\n", .{ir_graphs.items[0].nodes.items.len});
    for (ir_graphs.items[0].nodes.items, 0..) |node, idx| {
        std.debug.print("  [{d}] {s}\n", .{ idx, @tagName(node.op) });
    }

    // Verify branch structure exists
    var has_branch = false;
    var has_greater = false;
    for (ir_graphs.items[0].nodes.items) |node| {
        if (node.op == .Branch) has_branch = true;
        if (node.op == .Greater) has_greater = true;
    }
    try testing.expect(has_branch);
    try testing.expect(has_greater);

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "if_else_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== LLVM IR ===\n{s}\n", .{llvm_ir});

    // Verify LLVM IR contains expected elements
    // Note: Constant expressions like "5 > 3" may be folded to "true" at compile time
    // So we check for either the comparison OR a direct branch (constant folding)
    const has_comparison = std.mem.indexOf(u8, llvm_ir, "icmp sgt") != null;
    const has_const_fold = std.mem.indexOf(u8, llvm_ir, "br i1 true") != null;
    try testing.expect(has_comparison or has_const_fold);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_print_int") != null);

    // Compile and run
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse.ll" });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(.{ .sub_path = "ifelse.ll", .data = llvm_ir });

    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse.o" });
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

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse" });
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
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) return error.ExecutionFailed;

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // 5 > 3 is true, so should print 1
    try testing.expectEqualStrings("1\n", exec_result.stdout);

    std.debug.print("\n✅ ✅ ✅ IF/ELSE (TRUE BRANCH) EXECUTED SUCCESSFULLY ✅ ✅ ✅\n", .{});
}

test "Epic 1.6: If statement - condition false branch" {
    const allocator = testing.allocator;

    // if 2 > 5 do print_int(1) else print_int(0) end
    const source =
        \\func main() {
        \\    if 2 > 5 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

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

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "if_else_false");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse_false.ll" });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(.{ .sub_path = "ifelse_false.ll", .data = llvm_ir });

    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse_false.o" });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) return error.LLCFailed;

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "ifelse_false" });
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
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) return error.ExecutionFailed;

    std.debug.print("\n=== EXECUTION OUTPUT (FALSE BRANCH) ===\n{s}\n", .{exec_result.stdout});

    // 2 > 5 is false, so should print 0
    try testing.expectEqualStrings("0\n", exec_result.stdout);

    std.debug.print("\n✅ ✅ ✅ IF/ELSE (FALSE BRANCH) EXECUTED SUCCESSFULLY ✅ ✅ ✅\n", .{});
}

test "Epic 1.6: If without else" {
    const allocator = testing.allocator;

    // if 10 > 5 do print_int(42) end
    const source =
        \\func main() {
        \\    if 10 > 5 do
        \\        print_int(42)
        \\    end
        \\}
    ;

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

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "if_no_else");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "if_no_else.ll" });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(.{ .sub_path = "if_no_else.ll", .data = llvm_ir });

    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "if_no_else.o" });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) return error.LLCFailed;

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "if_no_else" });
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
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) return error.ExecutionFailed;

    std.debug.print("\n=== EXECUTION OUTPUT (IF NO ELSE) ===\n{s}\n", .{exec_result.stdout});

    // 10 > 5 is true, so should print 42
    try testing.expectEqualStrings("42\n", exec_result.stdout);

    std.debug.print("\n✅ ✅ ✅ IF WITHOUT ELSE EXECUTED SUCCESSFULLY ✅ ✅ ✅\n", .{});
}
