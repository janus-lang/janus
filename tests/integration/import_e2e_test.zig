// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Import/Module System End-to-End
//
// This test validates multi-file compilation and linking:
// Two source files → Parse → Lower → LLVM → Objects → Link → Execute

const std = @import("std");
const testing = std.testing;
const janus_parser = @import("janus_parser");
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

fn compileToObject(
    allocator: std.mem.Allocator,
    source: []const u8,
    module_name: []const u8,
    tmp_dir: std.testing.TmpDir,
) ![]const u8 {
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

    var emitter = try qtjir.llvm_emitter.LLVMEmitter.init(allocator, module_name);
    defer emitter.deinit();

    try emitter.emit(ir_graphs.items);

    const llvm_ir = try emitter.toString();
    defer allocator.free(llvm_ir);

    std.debug.print("\n=== LLVM IR ({s}) ===\n{s}\n", .{ module_name, llvm_ir });

    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    // Write IR file
    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{module_name});
    defer allocator.free(ir_file);
    try tmp_dir.dir.writeFile(.{ .sub_path = ir_file, .data = llvm_ir });

    // Compile to object
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{module_name});
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file);

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

    return obj_file_path;
}

fn linkAndRun(
    allocator: std.mem.Allocator,
    obj_files: []const []const u8,
    exe_name: []const u8,
    tmp_dir: std.testing.TmpDir,
) ![]u8 {
    const ir_path = try tmp_dir.dir.realpathAlloc(allocator, ".");
    defer allocator.free(ir_path);

    // Compile runtime
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
    if (zig_build_result.term.Exited != 0) {
        std.debug.print("RUNTIME COMPILE STDERR: {s}\n", .{zig_build_result.stderr});
        return error.RuntimeCompilationFailed;
    }

    // Build link command
    const exe_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, exe_name });
    defer allocator.free(exe_file_path);

    var link_args = std.ArrayListUnmanaged([]const u8){};
    defer link_args.deinit(allocator);

    try link_args.append(allocator, "cc");
    for (obj_files) |obj| {
        try link_args.append(allocator, obj);
    }
    try link_args.append(allocator, rt_obj_path);
    try link_args.append(allocator, "-o");
    try link_args.append(allocator, exe_file_path);

    const link_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = link_args.items,
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.Exited != 0) {
        std.debug.print("LINK STDERR: {s}\n", .{link_result.stderr});
        return error.LinkFailed;
    }

    // Execute
    const exec_result = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{exe_file_path},
    });
    defer allocator.free(exec_result.stderr);
    if (exec_result.term.Exited != 0) {
        std.debug.print("EXEC STDERR: {s}\n", .{exec_result.stderr});
        allocator.free(exec_result.stdout);
        return error.ExecutionFailed;
    }

    return exec_result.stdout;
}

test "Multi-file: Call function from another module" {
    const allocator = testing.allocator;

    // Library module with a helper function
    const lib_source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func multiply(a: i32, b: i32) -> i32 {
        \\    return a * b
        \\}
    ;

    // Main module that calls the library function
    const main_source =
        \\func main() {
        \\    let result = add(3, 4)
        \\    print_int(result)
        \\    let product = multiply(5, 6)
        \\    print_int(product)
        \\}
    ;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Compile both modules to objects
    const lib_obj = try compileToObject(allocator, lib_source, "mathlib", tmp_dir);
    defer allocator.free(lib_obj);

    const main_obj = try compileToObject(allocator, main_source, "main", tmp_dir);
    defer allocator.free(main_obj);

    // Link and run
    const obj_files = [_][]const u8{ main_obj, lib_obj };
    const output = try linkAndRun(allocator, &obj_files, "multifile_test", tmp_dir);
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // add(3, 4) = 7, multiply(5, 6) = 30
    try testing.expectEqualStrings("7\n30\n", output);

    std.debug.print("\n=== MULTI-FILE COMPILATION TEST PASSED ===\n", .{});
}

test "Multi-file: Shared utility function" {
    const allocator = testing.allocator;

    // Utility module
    const util_source =
        \\func square(x: i32) -> i32 {
        \\    return x * x
        \\}
    ;

    // Main uses utility
    const main_source =
        \\func main() {
        \\    print_int(square(7))
        \\    print_int(square(3))
        \\}
    ;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    const util_obj = try compileToObject(allocator, util_source, "util", tmp_dir);
    defer allocator.free(util_obj);

    const main_obj = try compileToObject(allocator, main_source, "main2", tmp_dir);
    defer allocator.free(main_obj);

    const obj_files = [_][]const u8{ main_obj, util_obj };
    const output = try linkAndRun(allocator, &obj_files, "util_test", tmp_dir);
    defer allocator.free(output);

    std.debug.print("\n=== EXECUTION OUTPUT ===\n{s}\n", .{output});

    // square(7) = 49, square(3) = 9
    try testing.expectEqualStrings("49\n9\n", output);

    std.debug.print("\n=== SHARED UTILITY TEST PASSED ===\n", .{});
}
