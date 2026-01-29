// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Integration Test: Async/Await End-to-End Compilation (:service profile)
//!
//! This test validates the ENTIRE compilation pipeline for async constructs:
//! Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution
//!
//! Phase 1 (Blocking Model): Async code executes synchronously but syntax works E2E

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test ":service profile: Async function compiles to LLVM IR" {
    const allocator = testing.allocator;

    // Simple async function
    const source =
        \\async func main() do
        \\    return 42
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify parsing succeeded
    try testing.expect(snapshot.nodeCount() > 0);

    // Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Verify we have IR nodes
    try testing.expect(ir_graphs.items.len > 0);
    try testing.expect(ir_graphs.items[0].nodes.items.len > 0);

    std.debug.print("\n=== ASYNC FUNCTION QTJIR ===\n", .{});
    for (ir_graphs.items[0].nodes.items, 0..) |node, i| {
        std.debug.print("  [{d}] {s}\n", .{ i, @tagName(node.op) });
    }

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "async_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== LLVM IR ===\n{s}\n", .{llvm_ir});

    // Verify LLVM IR has function definition
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "main") != null);

    std.debug.print("\n=== ASYNC FUNCTION COMPILES TO LLVM IR ===\n", .{});
}

test ":service profile: Nursery block generates Begin/End opcodes" {
    const allocator = testing.allocator;

    const source =
        \\async func main() do
        \\    nursery do
        \\        return 1
        \\    end
        \\end
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

    // Find Nursery_Begin and Nursery_End opcodes
    var found_begin = false;
    var found_end = false;

    std.debug.print("\n=== NURSERY QTJIR ===\n", .{});
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            std.debug.print("  [{d}] {s}\n", .{ i, @tagName(node.op) });
            if (node.op == .Nursery_Begin) found_begin = true;
            if (node.op == .Nursery_End) found_end = true;
        }
    }

    try testing.expect(found_begin);
    try testing.expect(found_end);

    // Emit to LLVM IR - should not error on nursery opcodes
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "nursery_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== NURSERY LLVM IR ===\n{s}\n", .{llvm_ir});

    // Should compile without errors
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define") != null);

    std.debug.print("\n=== NURSERY BLOCK COMPILES TO LLVM IR ===\n", .{});
}

test ":service profile: Async function E2E execution (blocking model)" {
    const allocator = testing.allocator;

    // Async function that returns a value
    const source =
        \\async func main() do
        \\    print(42)
        \\    return 0
        \\end
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

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "async_e2e");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== ASYNC E2E LLVM IR ===\n{s}\n", .{llvm_ir});

    // Write IR to temp file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "async.ll" });
    defer allocator.free(ir_file_path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "async.ll", .data = llvm_ir });

    // Compile to object file
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "async.o" });
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

    switch (llc_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("LLC STDERR: {s}\n", .{llc_result.stderr});
                return error.LLCFailed;
            }
        },
        else => return error.LLCFailed,
    }

    // Compile runtime
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "async" });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.Child.run(.{
        .allocator = allocator,
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

    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("LINK STDERR: {s}\n", .{link_result.stderr});
                return error.LinkFailed;
            }
        },
        else => return error.LinkFailed,
    }

    // Execute
    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    switch (exec_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("EXEC STDERR: {s}\n", .{exec_result.stderr});
                std.debug.print("Exit code: {d}\n", .{code});
                return error.ExecutionFailed;
            }
        },
        else => {
            std.debug.print("EXEC terminated abnormally: {any}\n", .{exec_result.term});
            return error.ExecutionFailed;
        },
    }

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // In blocking model, async function should execute and print 42
    try testing.expectEqualStrings("42\n", exec_result.stdout);

    std.debug.print("\n=== ASYNC E2E EXECUTION PASSED (Blocking Model) ===\n", .{});
}

test ":service profile: Spawn generates janus_nursery_spawn_noarg call (Phase 2.3)" {
    const allocator = testing.allocator;

    // Spawn a task inside a nursery
    const source =
        \\func task() do
        \\    return 0
        \\end
        \\
        \\async func main() do
        \\    nursery do
        \\        spawn task()
        \\    end
        \\    return 0
        \\end
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

    // Check that Spawn node was created in QTJIR
    var found_spawn = false;
    std.debug.print("\n=== SPAWN QTJIR ===\n", .{});
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            std.debug.print("  [{d}] {s}", .{ i, @tagName(node.op) });
            if (node.op == .Spawn) {
                found_spawn = true;
                // Check that function name is stored in data
                switch (node.data) {
                    .string => |s| std.debug.print(" -> '{s}'", .{s}),
                    else => {},
                }
            }
            std.debug.print("\n", .{});
        }
    }
    try testing.expect(found_spawn);

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "spawn_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== SPAWN LLVM IR ===\n{s}\n", .{llvm_ir});

    // Verify janus_nursery_spawn_noarg is called
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_nursery_spawn_noarg") != null);
    // Verify task function is defined
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@task") != null);

    std.debug.print("\n=== SPAWN GENERATES janus_nursery_spawn_noarg CALL ===\n", .{});
}

test ":service profile: Spawn with arguments generates thunk and janus_nursery_spawn call (Phase 2.4)" {
    const allocator = testing.allocator;

    // Spawn a task with arguments inside a nursery
    const source =
        \\func task_with_arg(x: i32) do
        \\    print(x)
        \\    return x
        \\end
        \\
        \\async func main() do
        \\    nursery do
        \\        spawn task_with_arg(42)
        \\    end
        \\    return 0
        \\end
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

    // Check that Spawn node was created with argument input
    var found_spawn_with_args = false;
    std.debug.print("\n=== SPAWN WITH ARGS QTJIR ===\n", .{});
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            std.debug.print("  [{d}] {s}", .{ i, @tagName(node.op) });
            if (node.op == .Spawn) {
                switch (node.data) {
                    .string => |s| std.debug.print(" -> '{s}'", .{s}),
                    else => {},
                }
                std.debug.print(" (args: {d})", .{node.inputs.items.len});
                // Verify spawn has at least one argument input
                if (node.inputs.items.len > 0) {
                    found_spawn_with_args = true;
                }
            }
            std.debug.print("\n", .{});
        }
    }
    try testing.expect(found_spawn_with_args);

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "spawn_args_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== SPAWN WITH ARGS LLVM IR ===\n{s}\n", .{llvm_ir});

    // Verify janus_nursery_spawn (not noarg) is called for functions with arguments
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "janus_nursery_spawn") != null);
    // Verify a thunk function was generated
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "__spawn_thunk") != null);
    // Verify target function is defined
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@task_with_arg") != null);

    std.debug.print("\n=== SPAWN WITH ARGS GENERATES THUNK AND janus_nursery_spawn CALL ===\n", .{});
}

test ":service profile: Multiple spawns in nursery (Phase 2.5)" {
    const allocator = testing.allocator;

    // Spawn multiple tasks in a single nursery
    const source =
        \\func task_a() do
        \\    return 1
        \\end
        \\
        \\func task_b() do
        \\    return 2
        \\end
        \\
        \\func task_c() do
        \\    return 3
        \\end
        \\
        \\async func main() do
        \\    nursery do
        \\        spawn task_a()
        \\        spawn task_b()
        \\        spawn task_c()
        \\    end
        \\    return 0
        \\end
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

    // Count Spawn nodes in QTJIR
    var spawn_count: usize = 0;
    std.debug.print("\n=== MULTIPLE SPAWNS QTJIR ===\n", .{});
    for (ir_graphs.items) |ir_graph| {
        for (ir_graph.nodes.items, 0..) |node, i| {
            if (node.op == .Spawn) {
                spawn_count += 1;
                std.debug.print("  [{d}] Spawn", .{i});
                switch (node.data) {
                    .string => |s| std.debug.print(" -> '{s}'", .{s}),
                    else => {},
                }
                std.debug.print("\n", .{});
            }
        }
    }
    // Verify we have 3 spawn nodes
    try testing.expectEqual(@as(usize, 3), spawn_count);

    // Emit to LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "multi_spawn_test");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== MULTIPLE SPAWNS LLVM IR ===\n{s}\n", .{llvm_ir});

    // Count janus_nursery_spawn_noarg calls in LLVM IR (not declarations)
    var call_count: usize = 0;
    var search_pos: usize = 0;
    while (std.mem.indexOfPos(u8, llvm_ir, search_pos, "call i32 @janus_nursery_spawn_noarg")) |pos| {
        call_count += 1;
        search_pos = pos + 1;
    }
    // Should have 3 spawn calls
    try testing.expectEqual(@as(usize, 3), call_count);

    // Verify all task functions are defined
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@task_a") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@task_b") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "@task_c") != null);

    std.debug.print("\n=== MULTIPLE SPAWNS GENERATES 3 janus_nursery_spawn_noarg CALLS ===\n", .{});
}

test ":service profile: Multiple spawns E2E execution (Phase 2.5)" {
    const allocator = testing.allocator;

    // Multiple tasks that print their values
    const source =
        \\func task_one() do
        \\    print(1)
        \\    return 0
        \\end
        \\
        \\func task_two() do
        \\    print(2)
        \\    return 0
        \\end
        \\
        \\func task_three() do
        \\    print(3)
        \\    return 0
        \\end
        \\
        \\async func main() do
        \\    nursery do
        \\        spawn task_one()
        \\        spawn task_two()
        \\        spawn task_three()
        \\    end
        \\    return 0
        \\end
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

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "multi_spawn_e2e");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    // Write IR to temp file
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    try tmp_dir.dir.writeFile(.{ .sub_path = "multi.ll", .data = llvm_ir });

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "multi.ll" });
    defer allocator.free(ir_file_path);

    // Compile to object file
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "multi.o" });
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

    switch (llc_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("LLC STDERR: {s}\n", .{llc_result.stderr});
                return error.LLCFailed;
            }
        },
        else => return error.LLCFailed,
    }

    // Compile runtime
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "multi" });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.Child.run(.{
        .allocator = allocator,
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

    switch (link_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("LINK STDERR: {s}\n", .{link_result.stderr});
                return error.LinkFailed;
            }
        },
        else => return error.LinkFailed,
    }

    // Execute
    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stdout);
    defer allocator.free(exec_result.stderr);

    switch (exec_result.term) {
        .Exited => |code| {
            if (code != 0) {
                std.debug.print("EXEC STDERR: {s}\n", .{exec_result.stderr});
                std.debug.print("Exit code: {d}\n", .{code});
                return error.ExecutionFailed;
            }
        },
        else => {
            std.debug.print("EXEC terminated abnormally: {any}\n", .{exec_result.term});
            return error.ExecutionFailed;
        },
    }

    std.debug.print("\n=== MULTI-SPAWN EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // All three tasks should have printed (order may vary due to parallelism)
    // Check that we got all three values (1, 2, 3)
    try testing.expect(std.mem.indexOf(u8, exec_result.stdout, "1") != null);
    try testing.expect(std.mem.indexOf(u8, exec_result.stdout, "2") != null);
    try testing.expect(std.mem.indexOf(u8, exec_result.stdout, "3") != null);

    std.debug.print("\n=== MULTI-SPAWN E2E EXECUTION PASSED ===\n", .{});
}
