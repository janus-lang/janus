// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: String Literals End-to-End
//
// This test validates string literal compilation through the complete pipeline:
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

    std.debug.print("\n=== LLVM IR ===\n{s}\n", .{llvm_ir});

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{test_name});
    defer allocator.free(ir_file);
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);
    try tmp_dir.dir.writeFile(.{ .sub_path = ir_file, .data = llvm_ir });

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{test_name});
    defer allocator.free(obj_file);
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file_path);

    const llc_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "llc", "-opaque-pointers", "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.Exited != 0) {
        std.debug.print("LLC STDERR: {s}\n", .{llc_result.stderr});
        return error.LLCFailed;
    }

    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, test_name });
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
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) {
        allocator.free(exec_result.stdout);
        return error.ExecutionFailed;
    }

    return exec_result.stdout;
}

test "Epic 4.1: Simple string println" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    println("Hello, World!")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_hello");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("Hello, World!\n", output);

    std.debug.print("\n=== SIMPLE STRING PRINTLN PASSED ===\n", .{});
}

test "Epic 4.2: Multiple string prints" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    println("First")
        \\    println("Second")
        \\    println("Third")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_multi");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("First\nSecond\nThird\n", output);

    std.debug.print("\n=== MULTIPLE STRING PRINTS PASSED ===\n", .{});
}

test "Epic 4.3: String with print (no newline)" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("Hello")
        \\    print(" ")
        \\    println("World")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_print");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("Hello World\n", output);

    std.debug.print("\n=== STRING PRINT NO NEWLINE PASSED ===\n", .{});
}

test "Epic 4.4: Mixed string and int output" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    println("The answer is:")
        \\    print_int(42)
        \\    println("done")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_mixed");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("The answer is:\n42\ndone\n", output);

    std.debug.print("\n=== MIXED STRING AND INT PASSED ===\n", .{});
}

test "Epic 4.5: String in conditional" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 5
        \\    if x > 3 do
        \\        println("greater")
        \\    else do
        \\        println("smaller")
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_cond");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("greater\n", output);

    std.debug.print("\n=== STRING IN CONDITIONAL PASSED ===\n", .{});
}

test "Epic 4.6: String in loop" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    for i in 1..3 do
        \\        println("loop")
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_loop");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("loop\nloop\nloop\n", output);

    std.debug.print("\n=== STRING IN LOOP PASSED ===\n", .{});
}

test "Epic 4.7: String escape newline" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("Hello\nWorld")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_escape_nl");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("Hello\nWorld", output);

    std.debug.print("\n=== STRING ESCAPE NEWLINE PASSED ===\n", .{});
}

test "Epic 4.8: String escape tab" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("Col1\tCol2\tCol3")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_escape_tab");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("Col1\tCol2\tCol3", output);

    std.debug.print("\n=== STRING ESCAPE TAB PASSED ===\n", .{});
}

test "Epic 4.9: String escape quote" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("She said \"hello\"")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_escape_quote");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("She said \"hello\"", output);

    std.debug.print("\n=== STRING ESCAPE QUOTE PASSED ===\n", .{});
}

test "Epic 4.10: String escape backslash" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("path\\to\\file")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "string_escape_backslash");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("path\\to\\file", output);

    std.debug.print("\n=== STRING ESCAPE BACKSLASH PASSED ===\n", .{});
}

test "Epic 4.11: Multiline string" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    print("""Line 1
        \\Line 2
        \\Line 3""")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "multiline_string");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    try testing.expectEqualStrings("Line 1\nLine 2\nLine 3", output);

    std.debug.print("\n=== MULTILINE STRING PASSED ===\n", .{});
}

test "Epic 4.12: Null literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = null
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "null_literal");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // null is represented as 0
    try testing.expectEqualStrings("0\n", output);

    std.debug.print("\n=== NULL LITERAL PASSED ===\n", .{});
}
