// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Numeric Literals End-to-End
//
// Tests hex (0x), binary (0b), and octal (0o) literals

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
        .argv = &[_][]const u8{ "llc", "-filetype=obj", ir_file_path, "-o", obj_file_path },
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

test "Epic 11.1: Hex literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 0xFF
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "hex_literal");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0xFF = 255
    try testing.expectEqualStrings("255\n", output);

    std.debug.print("\n=== HEX LITERAL PASSED ===\n", .{});
}

test "Epic 11.2: Hex literal lowercase" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 0x1a2b
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "hex_lower");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0x1a2b = 6699
    try testing.expectEqualStrings("6699\n", output);

    std.debug.print("\n=== HEX LOWERCASE PASSED ===\n", .{});
}

test "Epic 11.3: Binary literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 0b1010
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "binary_literal");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b1010 = 10
    try testing.expectEqualStrings("10\n", output);

    std.debug.print("\n=== BINARY LITERAL PASSED ===\n", .{});
}

test "Epic 11.4: Binary literal byte" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 0b11111111
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "binary_byte");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b11111111 = 255
    try testing.expectEqualStrings("255\n", output);

    std.debug.print("\n=== BINARY BYTE PASSED ===\n", .{});
}

test "Epic 11.5: Octal literal" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let x = 0o777
        \\    print_int(x)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "octal_literal");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0o777 = 511
    try testing.expectEqualStrings("511\n", output);

    std.debug.print("\n=== OCTAL LITERAL PASSED ===\n", .{});
}

test "Epic 11.6: Hex in expression" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let mask = 0xFF
        \\    let value = 0x1234
        \\    let low_byte = value & mask
        \\    print_int(low_byte)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "hex_expr");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0x1234 & 0xFF = 0x34 = 52
    try testing.expectEqualStrings("52\n", output);

    std.debug.print("\n=== HEX IN EXPRESSION PASSED ===\n", .{});
}

test "Epic 11.7: Binary flags" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let READ = 0b001
        \\    let WRITE = 0b010
        \\    let EXEC = 0b100
        \\    let perms = READ | WRITE | EXEC
        \\    print_int(perms)
        \\}
    ;

    const output = try compileAndRun(allocator, source, "binary_flags");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // 0b001 | 0b010 | 0b100 = 0b111 = 7
    try testing.expectEqualStrings("7\n", output);

    std.debug.print("\n=== BINARY FLAGS PASSED ===\n", .{});
}

test "Epic 11.8: Mixed bases" {
    const allocator = testing.allocator;

    const source =
        \\func main() {
        \\    let dec = 100
        \\    let hex = 0x64
        \\    let bin = 0b1100100
        \\    let oct = 0o144
        \\    if dec == hex and hex == bin and bin == oct do
        \\        print_int(1)
        \\    else do
        \\        print_int(0)
        \\    end
        \\}
    ;

    const output = try compileAndRun(allocator, source, "mixed_bases");
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // All represent 100, should print 1
    try testing.expectEqualStrings("1\n", output);

    std.debug.print("\n=== MIXED BASES PASSED ===\n", .{});
}
