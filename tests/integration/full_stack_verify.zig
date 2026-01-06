// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

test "Full Stack Verification: Variables, Loops, Conditionals" {
    const allocator = testing.allocator;

    // Source Code: Calculate Sum of 0..10 using while loop
    //
    //     func main() {
    //         var total = 0
    //         var i = 0
    //         while i < 10 {
    //             total = total + i
    //             i = i + 1
    //         }
    //         if total == 45 {
    //             println("SUCCESS: 45")
    //         } else {
    //             println("FAILURE")
    //         }
    //     }
    //
    const source =
        \\func main() {
        \\    var total = 0
        \\    var i = 0
        \\    while i < 10 {
        \\        total = total + i
        \\        i = i + 1
        \\    }
        \\    if total == 45 {
        \\        println("SUCCESS: 45")
        \\    } else {
        \\        println("FAILURE")
        \\    }
        \\}
    ;

    // 1. MOUNT: Parser & ASTDB
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(source);
    defer snapshot.deinit();
    try testing.expect(snapshot.nodeCount() > 0);

    // 2. FORGE: Lower to QTJIR
    const unit_id: astdb_core.UnitId = @enumFromInt(0);
    var ir_graphs = try qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id);
    defer {
        for (ir_graphs.items) |*g| g.deinit();
        ir_graphs.deinit(allocator);
    }

    // Debug: Inspect Graph
    const graph = &ir_graphs.items[0];
    std.debug.print("\n=== QTJIR Graph Nodes: {d} ===\n", .{graph.nodes.items.len});
    for (graph.nodes.items, 0..) |node, i| {
        std.debug.print("[{d}] {s}\n", .{ i, @tagName(node.op) });
    }

    // 3. EMIT: Generate LLVM IR
    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, "verify_stack");
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);
    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);
    std.debug.print("\n=== LLVM IR ===\n{s}\n", .{llvm_ir});

    // 4. ASSEMBLE: Compile & Run
    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);
    const ir_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "verify.ll" });
    defer allocator.free(ir_file);
    const obj_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "verify.o" });
    defer allocator.free(obj_file);
    const exe_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "verify" });
    defer allocator.free(exe_file);
    const runtime_c_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "runtime.c" });
    defer allocator.free(runtime_c_file);
    const runtime_o_file = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "runtime.o" });
    defer allocator.free(runtime_o_file);

    try tmp_dir.dir.writeFile(.{ .sub_path = "verify.ll", .data = llvm_ir });

    // Write Runtime C implementation
    const runtime_c =
        \\#include <stdio.h>
        \\#include <stdint.h>
        \\
        \\void janus_println(char* str) {
        \\    printf("%s\n", str);
        \\    fflush(stdout);
        \\}
        \\
        \\void janus_print_int(int64_t val) {
        \\    printf("%ld\n", val);
        \\    fflush(stdout);
        \\}
    ;
    try tmp_dir.dir.writeFile(.{ .sub_path = "runtime.c", .data = runtime_c });

    // GCC/Clang: Compile Runtime
    const cc_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "clang", "-c", runtime_c_file, "-o", runtime_o_file },
    });
    defer allocator.free(cc_res.stdout);
    defer allocator.free(cc_res.stderr);
    if (cc_res.term != .Exited or cc_res.term.Exited != 0) {
        std.debug.print("Runtime Compile Error: {s}\n", .{cc_res.stderr});
        return error.RuntimeCompilationFailed;
    }

    // LLC (IR -> Object)
    const llc_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file, "-o", obj_file },
    });
    defer allocator.free(llc_res.stdout);
    defer allocator.free(llc_res.stderr);
    if (llc_res.term != .Exited or llc_res.term.Exited != 0) {
        std.debug.print("LLC Error: {s}\n", .{llc_res.stderr});
        // Dump IR for debugging
        std.debug.print("LLVM IR causing error:\n{s}\n", .{llvm_ir});
        return error.CompilationFailed;
    }

    // CLANG (Link -> Exe)
    const clang_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "clang", obj_file, runtime_o_file, "-o", exe_file, "-no-pie" },
    });
    defer allocator.free(clang_res.stdout);
    defer allocator.free(clang_res.stderr);
    if (clang_res.term != .Exited or clang_res.term.Exited != 0) {
        std.debug.print("Clang Link Error: {s}\n", .{clang_res.stderr});
        return error.LinkingFailed;
    }

    // RUN
    const run_res = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file},
    });
    defer allocator.free(run_res.stdout);
    defer allocator.free(run_res.stderr);

    std.debug.print("\n=== OUTPUT ===\n{s}\n", .{run_res.stdout});

    try testing.expect(std.mem.indexOf(u8, run_res.stdout, "SUCCESS: 45") != null);
}
