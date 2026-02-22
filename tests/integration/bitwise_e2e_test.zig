// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Bitwise Operators End-to-End
//
// Tests: & (and), | (or), ^ (xor), ~ (not), << (left shift), >> (right shift)

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

test "Epic 10.1: Bitwise AND" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = 12
        \\    let b = 10
        \\    let result = a & b
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_and");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 12 = 1100, 10 = 1010, AND = 1000 = 8
    try testing.expectEqualStrings("8\n", output);

    std.debug.print("\n=== BITWISE AND PASSED ===\n", .{});
}

test "Epic 10.2: Bitwise OR" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = 12
        \\    let b = 10
        \\    let result = a | b
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_or");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 12 = 1100, 10 = 1010, OR = 1110 = 14
    try testing.expectEqualStrings("14\n", output);

    std.debug.print("\n=== BITWISE OR PASSED ===\n", .{});
}

test "Epic 10.3: Bitwise XOR" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let a = 12
        \\    let b = 10
        \\    let result = a ^ b
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_xor");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 12 = 1100, 10 = 1010, XOR = 0110 = 6
    try testing.expectEqualStrings("6\n", output);

    std.debug.print("\n=== BITWISE XOR PASSED ===\n", .{});
}

test "Epic 10.4: Left shift" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 5
        \\    let result = x << 2
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_shl");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 5 << 2 = 5 * 4 = 20
    try testing.expectEqualStrings("20\n", output);

    std.debug.print("\n=== LEFT SHIFT PASSED ===\n", .{});
}

test "Epic 10.5: Right shift" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 20
        \\    let result = x >> 2
        \\    print_int(result)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_shr");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 20 >> 2 = 20 / 4 = 5
    try testing.expectEqualStrings("5\n", output);

    std.debug.print("\n=== RIGHT SHIFT PASSED ===\n", .{});
}

test "Epic 10.6: Combined bitwise operations" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let flags = 0
        \\    let flag_a = 1
        \\    let flag_b = 2
        \\    let combined = flag_a | flag_b
        \\    let has_a = combined & flag_a
        \\    print_int(combined)
        \\    print_int(has_a)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_combined");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // combined = 1 | 2 = 3, has_a = 3 & 1 = 1
    try testing.expectEqualStrings("3\n1\n", output);

    std.debug.print("\n=== COMBINED BITWISE PASSED ===\n", .{});
}

test "Epic 10.7: Bit flags pattern" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let READ = 1
        \\    let WRITE = 2
        \\    let EXEC = 4
        \\    let perms = READ | WRITE
        \\    if perms & READ != 0 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\    if perms & EXEC != 0 do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_flags");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // Has READ (prints 1), doesn't have EXEC (prints 0)
    try testing.expectEqualStrings("1\n0\n", output);

    std.debug.print("\n=== BIT FLAGS PATTERN PASSED ===\n", .{});
}

test "Epic 10.8: Shift and mask pattern" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let packed = 4660
        \\    let low_byte = packed & 255
        \\    let high_byte = packed >> 8 & 255
        \\    print_int(low_byte)
        \\    print_int(high_byte)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "bitwise_mask");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 4660 = 0x1234: low byte = 0x34 = 52, high byte = 0x12 = 18
    try testing.expectEqualStrings("52\n18\n", output);

    std.debug.print("\n=== SHIFT AND MASK PASSED ===\n", .{});
}
