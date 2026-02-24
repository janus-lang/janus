// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: jfind End-to-End Compilation
//
// This test validates the ENTIRE compilation pipeline with native Zig grafting:
// Source → Parser → ASTDB → Lowerer (with extern registry) → QTJIR → LLVM → Object → Link → Execute

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "jfind: End-to-end compilation with native Zig grafting" {
    const allocator = testing.allocator;
    const io = testing.io;

    // ========== STEP 1: Parse jfind.jan Source ==========
    // Full jfind with if-else (syntax: if ... do ... else ... end)
    const source =
        \\use zig "std/core/fs_ops.zig"
        \\
        \\func main() do
        \\    let dir = fs_dir_open(".", 1)
        \\    var count = 0
        \\    while fs_dir_next(dir) == 1 do
        \\        let is_dir = fs_dir_entry_is_dir(dir)
        \\        if is_dir == 1 do
        \\            print(1)
        \\        else
        \\            print(0)
        \\        end
        \\        count = count + 1
        \\    end
        \\    fs_dir_close(dir)
        \\    print(count)
        \\end
    ;

    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // Verify we have nodes
    try testing.expect(snapshot.nodeCount() > 0);

    // ========== STEP 2: Lower ASTDB to QTJIR with Extern Registry ==========
    const unit_id: astdb_core.UnitId = @enumFromInt(0);

    // Use lowerUnitWithExterns to handle `use zig` imports
    var result = try qtjir.lower.lowerUnitWithExterns(allocator, &snapshot.core_snapshot, unit_id, ".");
    defer result.deinit(allocator);

    try testing.expect(result.graphs.items.len > 0);

    // Print extern functions
    var fn_iter = result.extern_registry.functions.iterator();
    while (fn_iter.next()) |entry| {
    }

    // ========== STEP 3: Emit QTJIR to LLVM IR ==========
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "jfind");
    defer emitter.deinit();

    // Set the extern registry so the emitter knows about grafted functions
    emitter.setExternRegistry(&result.extern_registry);

    try emitter.emit(result.graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);


    // Verify LLVM IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "define") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "main") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "fs_dir_open") != null);
    try testing.expect(std.mem.indexOf(u8, llvm_ir, "fs_dir_next") != null);

    // ========== STEP 4: Write LLVM IR to File ==========
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const tmp_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(tmp_path);

    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "jfind.ll" });
    defer allocator.free(ir_file_path);

    try tmp_dir.dir.writeFile(io, .{ .sub_path = "jfind.ll", .data = llvm_ir });

    // ========== STEP 5: Compile LLVM IR to Object File ==========
    const jfind_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "jfind.o" });
    defer allocator.free(jfind_obj_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "llc",
            "-O3",              // MAXIMUM OPTIMIZATION
            "-filetype=obj",
            ir_file_path,
            "-o",
            jfind_obj_path,
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

    // ========== STEP 6: Compile Runtime ==========
    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const rt_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(rt_emit_arg);

    const rt_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "zig",
            "build-obj",
            "runtime/janus_rt.zig",
            rt_emit_arg,
            "-O", "ReleaseFast",  // RELEASE MODE OPTIMIZATION
            "-lc",
        },
    });
    defer allocator.free(rt_result.stdout);
    defer allocator.free(rt_result.stderr);

    if (rt_result.term.exited != 0) {
        return error.RuntimeCompilationFailed;
    }

    // ========== STEP 7: Compile Grafted fs_ops.zig ==========
    const fs_ops_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "fs_ops.o" });
    defer allocator.free(fs_ops_obj_path);

    const fs_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{fs_ops_obj_path});
    defer allocator.free(fs_emit_arg);

    const fs_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "zig",
            "build-obj",
            "std/core/fs_ops.zig",
            fs_emit_arg,
            "-O", "ReleaseFast",  // RELEASE MODE OPTIMIZATION
            "-lc",
        },
    });
    defer allocator.free(fs_result.stdout);
    defer allocator.free(fs_result.stderr);

    if (fs_result.term.exited != 0) {
        return error.FsOpsCompilationFailed;
    }

    // ========== STEP 8: Link Everything ==========
    const exe_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "jfind" });
    defer allocator.free(exe_path);

    const link_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "cc",
            jfind_obj_path,
            rt_obj_path,
            fs_ops_obj_path,
            "-o",
            exe_path,
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

    // ========== STEP 9: Execute jfind ==========
    const exec_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{exe_path},
        .cwd = tmp_path, // Run in temp dir so we have a known directory
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


    // Verify output - should have 0s and 1s (file/dir markers) and final count
    try testing.expect(exec_result.stdout.len > 0);

    // Parse the output - last line should be the total count
    var lines = std.mem.splitScalar(u8, std.mem.trim(u8, exec_result.stdout, "\n"), '\n');
    var count: usize = 0;
    var last_line: []const u8 = "";
    while (lines.next()) |line| {
        last_line = line;
        count += 1;
    }


    // Last line should be the total count (a number > 0)
    const total = std.fmt.parseInt(i32, last_line, 10) catch {
        return error.InvalidOutput;
    };

    try testing.expect(total > 0);
}
