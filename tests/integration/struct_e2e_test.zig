// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Struct Types End-to-End
//
// This test validates struct compilation through the complete pipeline:
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


    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(ir_path);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{test_name});
    defer allocator.free(ir_file);
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);
    const io = testing.io;
    try tmp_dir.dir.writeFile(io, .{ .sub_path = ir_file, .data = llvm_ir });

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{test_name});
    defer allocator.free(obj_file);
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "llc",  "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.exited != 0) {
        return error.LLCFailed;
    }

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, test_name });
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
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.exited != 0) {
        allocator.free(exec_result.stdout);
        return error.ExecutionFailed;
    }

    return exec_result.stdout;
}

test "Epic 3.1: Struct literal and field access" {
    const allocator = testing.allocator;

    // Simple struct literal with field access
    const source =
        \\func main() {
        \\    let p = Point { x: 10, y: 20 }
        \\    print_int(p.x)
        \\    print_int(p.y)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "struct_simple");
    defer allocator.free(output);


    // Should print 10 then 20
    try testing.expectEqualStrings("10\n20\n", output);

}

test "Epic 3.2: Struct field used in computation" {
    const allocator = testing.allocator;

    // Struct with computed field access
    const source =
        \\func main() {
        \\    let p = Point { x: 15, y: 25 }
        \\    let sum = p.x + p.y
        \\    print_int(sum)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "struct_compute");
    defer allocator.free(output);


    // 15 + 25 = 40
    try testing.expectEqualStrings("40\n", output);

}

test "Epic 3.3: Multiple struct instances" {
    const allocator = testing.allocator;

    // Multiple struct instances
    const source =
        \\func main() {
        \\    let a = Vec { x: 1, y: 2 }
        \\    let b = Vec { x: 3, y: 4 }
        \\    print_int(a.x)
        \\    print_int(b.y)
        \\    print_int(a.y + b.x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "struct_multi");
    defer allocator.free(output);


    // a.x=1, b.y=4, a.y+b.x = 2+3 = 5
    try testing.expectEqualStrings("1\n4\n5\n", output);

}

test "Epic 3.4: Struct field assignment" {
    const allocator = testing.allocator;

    // Mutable struct with field assignment
    const source =
        \\func main() {
        \\    var p = Point { x: 10, y: 20 }
        \\    print_int(p.x)
        \\    p.x = 99
        \\    print_int(p.x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "struct_assign");
    defer allocator.free(output);


    // Initial p.x=10, after assignment p.x=99
    try testing.expectEqualStrings("10\n99\n", output);

}

test "Epic 3.5: Nested struct field access" {
    const allocator = testing.allocator;

    // Nested struct access
    const source =
        \\func main() {
        \\    let inner = Inner { val: 42 }
        \\    let outer = Outer { a: 1, nested: inner, b: 2 }
        \\    print_int(outer.a)
        \\    print_int(outer.b)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "struct_nested");
    defer allocator.free(output);


    // outer.a=1, outer.b=2
    try testing.expectEqualStrings("1\n2\n", output);

}
