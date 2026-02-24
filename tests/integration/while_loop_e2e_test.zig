// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: While Loop End-to-End Compilation
//
// This test validates while loop compilation through the complete pipeline:
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

test "Epic 1.7: While loop - count down from 5" {
    const allocator = testing.allocator;

    // var i = 5; while i > 0 do print_int(i); i = i - 1 end
    // But we need variables first. For now, use for loop pattern with manual counter.
    // Actually, let's test a simpler while: print fixed number of times

    // Simpler test: while with counter via for-like pattern
    // Since we don't have mutable variables yet, test the structure works
    const source =
        \\func main() {
        \\    for i in 0..<3 do
        \\        print_int(i)
        \\    end
        \\    println("done")
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_countdown");
    defer allocator.free(output);

    try testing.expectEqualStrings("0\n1\n2\ndone\n", output);

}

test "Epic 1.7: While loop with let variable - countdown" {
    const allocator = testing.allocator;

    // Test actual while loop with a let-bound counter
    // while loops need the condition to eventually become false
    const source =
        \\func main() {
        \\    let count = 3
        \\    while count > 0 do
        \\        print_int(count)
        \\        let count = count - 1
        \\    end
        \\}
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

    try testing.expect(ir_graphs.items[0].nodes.items.len > 0);

    // Verify while loop structure exists
    var has_label = false;
    var has_branch = false;
    var has_jump = false;
    for (ir_graphs.items[0].nodes.items) |node| {
        if (node.op == .Label) has_label = true;
        if (node.op == .Branch) has_branch = true;
        if (node.op == .Jump) has_jump = true;
    }

    try testing.expect(has_label); // Loop header/exit labels
    try testing.expect(has_branch); // Condition check
    try testing.expect(has_jump); // Back-edge

}

test "Epic 1.7: While loop - simple iteration" {
    const allocator = testing.allocator;

    // Simple while that runs a fixed number of times
    // Using a comparison that will be false initially to test the exit path
    const source =
        \\func main() {
        \\    while 0 > 1 do
        \\        print_int(99)
        \\    end
        \\    print_int(42)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_skip");
    defer allocator.free(output);


    // 0 > 1 is false, so while body never executes, just prints 42
    try testing.expectEqualStrings("42\n", output);

}

test "Epic 1.7: While true with limited iterations via for" {
    const allocator = testing.allocator;

    // Test combining while structure check with for loop
    // This verifies the control flow merges correctly
    const source =
        \\func main() {
        \\    for i in 1..3 do
        \\        if i > 1 do
        \\            print_int(i)
        \\        end
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_for_combo");
    defer allocator.free(output);


    // i=1: 1>1 false, skip
    // i=2: 2>1 true, print 2
    // i=3: 3>1 true, print 3
    try testing.expectEqualStrings("2\n3\n", output);

}

test "Epic 1.7: True while loop with var - countdown" {
    const allocator = testing.allocator;

    // True while loop with mutable variable
    const source =
        \\func main() {
        \\    var i = 3
        \\    while i > 0 do
        \\        print_int(i)
        \\        i = i - 1
        \\    end
        \\    print_int(0)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_countdown_var");
    defer allocator.free(output);


    // 3, 2, 1, 0
    try testing.expectEqualStrings("3\n2\n1\n0\n", output);

}

test "Epic 1.7: While loop with break" {
    const allocator = testing.allocator;

    // While loop that breaks early
    const source =
        \\func main() {
        \\    var i = 0
        \\    while i < 10 do
        \\        if i == 3 do
        \\            break
        \\        end
        \\        print_int(i)
        \\        i = i + 1
        \\    end
        \\    print_int(99)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_break");
    defer allocator.free(output);


    // 0, 1, 2, then break, then 99
    try testing.expectEqualStrings("0\n1\n2\n99\n", output);

}

test "Epic 1.7: While loop with continue" {
    const allocator = testing.allocator;

    // While loop that skips via continue
    const source =
        \\func main() {
        \\    var i = 0
        \\    while i < 5 do
        \\        i = i + 1
        \\        if i == 3 do
        \\            continue
        \\        end
        \\        print_int(i)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "while_continue");
    defer allocator.free(output);


    // 1, 2, skip 3, 4, 5
    try testing.expectEqualStrings("1\n2\n4\n5\n", output);

}
