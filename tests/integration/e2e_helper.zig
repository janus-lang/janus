// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

/// Shared E2E test helper: compiles Janus source to a native binary and executes it.
///
/// Consolidates the parse → lower → emit → llc → link → exec pipeline so every
/// E2E integration test can call a single function instead of duplicating ~100
/// lines of build scaffolding.
///
/// Uses Zig 0.16 Io-based APIs throughout:
///   - std.testing.io   for the Io vtable
///   - std.process.run  (gpa, io, RunOptions)
///   - dir.writeFile    (io, WriteFileOptions)
///   - dir.realPathFileAlloc(io, sub_path, allocator)
///   - result.term.exited (lowercase tagged union)
const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

const Io = std.Io;

/// Compile Janus source all the way to a native binary, execute it, and return stdout.
///
/// Caller owns the returned slice — free with `allocator.free(result)`.
pub fn compileAndRun(allocator: std.mem.Allocator, source: []const u8, test_name: []const u8) ![]u8 {
    const io = testing.io;

    // ── 1. Parse source → ASTDB snapshot ──
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();

    // ── 2. Lower ASTDB → QTJIR ──
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // ── 3. Emit QTJIR → LLVM IR text ──
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, test_name);
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== LLVM IR ({s}) ===\n{s}\n", .{ test_name, llvm_ir });

    // ── 4. Write IR to temp dir ──
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Resolve absolute path of the temp directory for child process argv
    const ir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ir_path);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{test_name});
    defer allocator.free(ir_file);
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);

    try tmp_dir.dir.writeFile(io, .{ .sub_path = ir_file, .data = llvm_ir });

    // ── 5. llc: LLVM IR → object file ──
    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{test_name});
    defer allocator.free(obj_file);
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);

    switch (llc_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("LLC STDERR: {s}\n", .{llc_result.stderr});
                return error.LLCFailed;
            }
        },
        else => return error.LLCFailed,
    }

    // ── 6. Compile Zig runtime → object ──
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, test_name });
    defer allocator.free(exe_file_path);

    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const asm_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "context_switch.o" });
    defer allocator.free(asm_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);

    switch (zig_build_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("RUNTIME COMPILATION FAILED: {s}\n", .{zig_build_result.stderr});
                return error.RuntimeCompilationFailed;
            }
        },
        else => return error.RuntimeCompilationFailed,
    }

    // ── 7. Assemble context_switch.s → object ──
    const asm_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{asm_obj_path});
    defer allocator.free(asm_emit_arg);

    const asm_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/scheduler/context_switch.s", asm_emit_arg },
    });
    defer allocator.free(asm_build_result.stdout);
    defer allocator.free(asm_build_result.stderr);

    switch (asm_build_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("ASSEMBLY COMPILATION FAILED: {s}\n", .{asm_build_result.stderr});
                return error.AssemblyCompilationFailed;
            }
        },
        else => return error.AssemblyCompilationFailed,
    }

    // ── 8. Link everything → executable ──
    const link_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "cc", obj_file_path, rt_obj_path, asm_obj_path, "-o", exe_file_path },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    switch (link_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("LINK STDERR: {s}\n", .{link_result.stderr});
                return error.LinkFailed;
            }
        },
        else => return error.LinkFailed,
    }

    std.debug.print("=== Executable generated: {s} ===\n", .{exe_file_path});

    // ── 9. Execute and capture stdout ──
    const exec_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stderr);

    switch (exec_result.term) {
        .exited => |code| {
            if (code != 0) {
                std.debug.print("EXEC STDERR: {s}\nExit code: {d}\n", .{ exec_result.stderr, code });
                allocator.free(exec_result.stdout);
                return error.ExecutionFailed;
            }
        },
        else => {
            std.debug.print("EXEC terminated abnormally: {any}\n", .{exec_result.term});
            allocator.free(exec_result.stdout);
            return error.ExecutionFailed;
        },
    }

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{exec_result.stdout});

    // Caller owns stdout
    return exec_result.stdout;
}
