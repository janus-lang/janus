// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Logical Operators End-to-End
//
// Per SPEC-017-syntax.md:
//   logic_or  <- logic_and ( 'or' logic_and )*
//   logic_and <- equality ( 'and' equality )*
//
// Valid: x and y, x or y (short-circuit evaluation)
// Invalid: x && y, x || y (use keywords instead)

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
        .argv = &[_][]const u8{ "llc", "-opaque-pointers", "-filetype=obj", ir_file_path, "-o", obj_file_path },
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

test "Epic 8.1: Logical AND - both true" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = true
        \\    let b = true
        \\    if a and b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_and_tt");
    defer allocator.free(output);


    // true and true = true, then branch prints 1
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.2: Logical AND - first false (short-circuit)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = false
        \\    let b = true
        \\    if a and b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_and_ft");
    defer allocator.free(output);


    // false and true = false (short-circuits), else branch prints 0
    try testing.expectEqualStrings("0\n", output);

}

test "Epic 8.3: Logical AND - second false" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = true
        \\    let b = false
        \\    if a and b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_and_tf");
    defer allocator.free(output);


    // true and false = false, else branch prints 0
    try testing.expectEqualStrings("0\n", output);

}

test "Epic 8.4: Logical OR - both false" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = false
        \\    let b = false
        \\    if a or b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_or_ff");
    defer allocator.free(output);


    // false or false = false, else branch prints 0
    try testing.expectEqualStrings("0\n", output);

}

test "Epic 8.5: Logical OR - first true (short-circuit)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = true
        \\    let b = false
        \\    if a or b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_or_tf");
    defer allocator.free(output);


    // true or false = true (short-circuits), then branch prints 1
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.6: Logical OR - second true" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = false
        \\    let b = true
        \\    if a or b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_or_ft");
    defer allocator.free(output);


    // false or true = true, then branch prints 1
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.7: Combined AND and OR" {
    const allocator = testing.allocator;

    // Test operator precedence: and binds tighter than or
    // a or b and c = a or (b and c)
    const source =
        \\func main() {
        \\    let a = true
        \\    let b = false
        \\    let c = true
        \\    if a or b and c do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_combined");
    defer allocator.free(output);


    // true or (false and true) = true or false = true
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.8: AND with comparison" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 5
        \\    let y = 10
        \\    if x > 0 and y > 0 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_and_cmp");
    defer allocator.free(output);


    // (5 > 0) and (10 > 0) = true and true = true
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.9: OR with comparison" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = -5
        \\    let y = 10
        \\    if x > 0 or y > 0 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_or_cmp");
    defer allocator.free(output);


    // (-5 > 0) or (10 > 0) = false or true = true
    try testing.expectEqualStrings("1\n", output);

}

test "Epic 8.10: NOT with AND" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = true
        \\    let b = false
        \\    if not a and b do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "logical_not_and");
    defer allocator.free(output);


    // (not true) and false = false and false = false
    try testing.expectEqualStrings("0\n", output);

}
