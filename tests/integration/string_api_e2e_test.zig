// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: String API Intrinsics End-to-End
//
// Validates the 10 wired string intrinsics (str_contains, str_equals, etc.)
// through the complete pipeline: Source → Parser → QTJIR → LLVM → Binary → Execution

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

    const io = testing.io;
    const ir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ir_path);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{test_name});
    defer allocator.free(ir_file);
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(io, .{ .sub_path = ir_file, .data = llvm_ir });

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{test_name});
    defer allocator.free(obj_file);
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.exited != 0) return error.LLCFailed;

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

test "str_contains: match and mismatch" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    let text = "Hello, World!"
        \\    print_int(str_contains(text, "World"))
        \\    print_int(str_contains(text, "xyz"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_contains_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n0\n", output);
}

test "str_starts_with: match and mismatch" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    let s = "Hello, World!"
        \\    print_int(str_starts_with(s, "Hello"))
        \\    print_int(str_starts_with(s, "World"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_starts_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n0\n", output);
}

test "str_ends_with: match and mismatch" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    let s = "Hello, World!"
        \\    print_int(str_ends_with(s, "World!"))
        \\    print_int(str_ends_with(s, "Hello"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_ends_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n0\n", output);
}

test "str_equals: equal and unequal" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_equals("abc", "abc"))
        \\    print_int(str_equals("abc", "xyz"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_equals_test2");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n0\n", output);
}

test "str_compare: ordering" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_compare("abc", "abc"))
        \\    print_int(str_compare("abc", "def"))
        \\    print_int(str_compare("def", "abc"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_compare_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("0\n-1\n1\n", output);
}

test "str_index_of: found and not found" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_index_of("Hello, World!", "World"))
        \\    print_int(str_index_of("Hello, World!", "xyz"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_indexof_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("7\n-1\n", output);
}

test "str_length: byte length" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_length("Hello"))
        \\    print_int(str_length(""))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_length_test2");
    defer allocator.free(output);
    try testing.expectEqualStrings("5\n0\n", output);
}

test "str_is_empty: empty and non-empty" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_is_empty(""))
        \\    print_int(str_is_empty("x"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_isempty_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n0\n", output);
}

test "str_char_count: ASCII codepoints" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_char_count("Hello"))
        \\    print_int(str_char_count(""))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_charcount_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("5\n0\n", output);
}

test "str_is_valid_utf8: ASCII is valid" {
    const allocator = testing.allocator;
    const source =
        \\func main() {
        \\    print_int(str_is_valid_utf8("Hello, World!"))
        \\}
    ;
    const output = try compileAndRun(allocator, source, "str_validutf8_test");
    defer allocator.free(output);
    try testing.expectEqualStrings("1\n", output);
}
