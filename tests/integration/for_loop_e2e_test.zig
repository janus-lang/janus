// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: For Loop End-to-End Compilation
//
// This test validates for loop compilation through the ENTIRE pipeline:
// Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Epic 1.5: For loop with exclusive range - print 0 to 4" {
    const allocator = testing.allocator;
    const io = testing.io;

    // ========== STEP 1: Parse Source to ASTDB ==========
    // for i in 0..<5 do print_int(i) end
    const source =
        \\func main() {
        \\    for i in 0..<5 do
        \\        print_int(i)
        \\    end
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify we have nodes
    try testing.expect(snapshot.nodeCount() > 0);

    // ========== STEP 2: Lower ASTDB to QTJIR ==========
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify we have IR nodes
    try testing.expect(ir_graphs.items.len > 0);
    try testing.expect(ir_graphs.items[0].nodes.items.len > 0);
    try testing.expect(ir_graphs.items[0].nodes.items.len > 0);

    // Verify for loop specific nodes exist
    var has_phi = false;
    var has_branch = false;
    var has_add = false;
    var has_jump = false;
    for (ir_graphs.items[0].nodes.items) |node| {
        if (node.op == .Phi) has_phi = true;
        if (node.op == .Branch) has_branch = true;
        if (node.op == .Add) has_add = true;
        if (node.op == .Jump) has_jump = true;
    }
    try testing.expect(has_phi); // Loop counter phi node
    try testing.expect(has_branch); // Condition check
    try testing.expect(has_add); // Increment
    try testing.expect(has_jump); // Back-edge

    // ========== STEP 3: Emit QTJIR to LLVM IR ==========
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "for_loop_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    // Get LLVM IR as string
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify LLVM IR contains loop elements
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define") != null); // Has function definition
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "main") != null); // Has main function
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "phi") != null); // Has phi node
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_print_int") != null); // Has print call
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "icmp") != null); // Has comparison
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "br") != null); // Has branch

    // ========== STEP 4: Write LLVM IR to File ==========
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop.ll" });
    defer allocator.free(ir_file_path);

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "forloop.ll", .data = llvm_ir });

    // ========== STEP 5: Compile LLVM IR to Object File ==========
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop.o" });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "llc",
            "-opaque-pointers",
            "-filetype=obj",
            ir_file_path,
            "-o",
            obj_file_path,
        },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);

    switch (llc_result.term) {
        .exited => |code| {
            if (code != 0) {
                return error.LLCFailed;
            }
        },
        else => return error.LLCFailed,
    }


    // ========== STEP 6: Link with Runtime ==========
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop" });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    // Compile Runtime
    const zig_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "zig",
            "build-obj",
            "runtime/janus_rt.zig",
            emit_arg,
            "-lc",
        },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);

    if (zig_build_result.term.exited != 0) {
        return error.RuntimeCompilationFailed;
    }

    // Link
    const link_result = try std.process.run(allocator, io, .{
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

    switch (link_result.term) {
        .exited => |code| {
            if (code != 0) {
                return error.LinkFailed;
            }
        },
        else => return error.LinkFailed,
    }


    // ========== STEP 7: Execute and Verify Output ==========
    const exec_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    switch (exec_result.term) {
        .exited => |code| {
            if (code != 0) {
                return error.ExecutionFailed;
            }
        },
        else => {
            return error.ExecutionFailed;
        },
    }


    // Verify output: 0, 1, 2, 3, 4 (exclusive range 0..<5)
    try testing.expectEqualStrings("0\n1\n2\n3\n4\n", exec_result.stdout);

}

test "Epic 1.5: For loop with inclusive range - print 0 to 3" {
    const allocator = testing.allocator;
    const io = testing.io;

    // for i in 0..3 do print_int(i) end
    const source =
        \\func main() {
        \\    for i in 0..3 do
        \\        print_int(i)
        \\    end
        \\}
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    try testing.expect(snapshot.nodeCount() > 0);

    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "for_loop_inclusive");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    // ========== Compile and Run ==========
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop_inc.ll" });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "forloop_inc.ll", .data = llvm_ir });

    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop_inc.o" });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "llc", "-opaque-pointers", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.exited != 0) {
        return error.LLCFailed;
    }

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "forloop_inc" });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);
    if (zig_build_result.term.exited != 0) return error.RuntimeCompilationFailed;

    const link_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "cc", obj_file_path, rt_obj_path, "-o", exe_file_path },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.exited != 0) return error.LinkFailed;

    const exec_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.exited != 0) return error.ExecutionFailed;


    // Verify output: 0, 1, 2, 3 (inclusive range 0..3 means 0 to 3)
    try testing.expectEqualStrings("0\n1\n2\n3\n", exec_result.stdout);

}
