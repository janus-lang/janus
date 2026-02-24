// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Modulo Operator End-to-End
//
// Per SPEC-017-syntax.md:
//   mul <- unary ( ('*' | '/' | '%') unary )*
//
// Valid: x % y (remainder/modulo)

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

test "Epic 9.1: Basic modulo operation" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let result = 17 % 5
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_basic");
    defer allocator.free(output);


    // 17 % 5 = 2
    try testing.expectEqualStrings("2\n", output);

}

test "Epic 9.2: Modulo with zero remainder" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let result = 20 % 5
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_zero");
    defer allocator.free(output);


    // 20 % 5 = 0
    try testing.expectEqualStrings("0\n", output);

}

test "Epic 9.3: Modulo with variables" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 23
        \\    let y = 7
        \\    let result = x % y
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_vars");
    defer allocator.free(output);


    // 23 % 7 = 2
    try testing.expectEqualStrings("2\n", output);

}

test "Epic 9.4: Modulo in expression" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let result = 10 + (17 % 5)
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_expr");
    defer allocator.free(output);


    // 10 + (17 % 5) = 10 + 2 = 12
    try testing.expectEqualStrings("12\n", output);

}

test "Epic 9.5: Modulo for even/odd check" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let n = 7
        \\    if n % 2 == 1 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_odd");
    defer allocator.free(output);


    // 7 is odd (7 % 2 == 1), prints 1
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 9.6: Modulo in loop (find multiples)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    var count = 0
        \\    for i in 1..<10 do
        \\        if i % 3 == 0 do
        \\            count = count + 1
        \\        end
        \\    end
        \\    print_int(count)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_loop");
    defer allocator.free(output);


    // Multiples of 3 in 1..9: 3, 6, 9 = 3 numbers
    try testing.expectEqualStrings("3\n", output);

}

test "Epic 9.7: Chained modulo and division" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let n = 100
        \\    let tens = n / 10 % 10
        \\    print_int(tens)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_chain");
    defer allocator.free(output);


    // 100 / 10 = 10, 10 % 10 = 0
    try testing.expectEqualStrings("0\n", output);

}

test "Epic 9.8: Extract digit using modulo" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let n = 12345
        \\    let ones = n % 10
        \\    let tens = n / 10 % 10
        \\    let hundreds = n / 100 % 10
        \\    print_int(ones)
        \\    print_int(tens)
        \\    print_int(hundreds)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "modulo_digits");
    defer allocator.free(output);


    // ones = 5, tens = 4, hundreds = 3
    try testing.expectEqualStrings("5\n4\n3\n", output);

}
