// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: Import/Module System End-to-End
//
// This test validates multi-file compilation and linking:
// Two source files → Parse → Lower → LLVM → Objects → Link → Execute

const std = @import("std");
const compat_fs = @import("compat_fs");
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
    const io = testing.io;
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


    const ir_path = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(ir_path);

    // Write IR file
    const ir_file = try std.fmt.allocPrint(allocator, "{s}.ll", .{module_name});
    defer allocator.free(ir_file);
    try tmp_dir.dir.writeFile(io, .{ .sub_path = ir_file, .data = llvm_ir });

    // Compile to object
    const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, ir_file });
    defer allocator.free(ir_file_path);

    const obj_file = try std.fmt.allocPrint(allocator, "{s}.o", .{module_name});
    const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, obj_file });
    defer allocator.free(obj_file);

    const llc_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "llc",  "-filetype=obj", ir_file_path, "-o", obj_file_path },
    });
    defer allocator.free(llc_result.stdout);
    defer allocator.free(llc_result.stderr);
    if (llc_result.term.exited != 0) {
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
    const io = testing.io;
    const ir_path = try tmp_dir.dir.realPathFileAlloc(io, ".", allocator);
    defer allocator.free(ir_path);

    // Compile runtime
    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ ir_path, "janus_rt.o" });
    defer allocator.free(rt_obj_path);

    const emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(emit_arg);

    const zig_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{ "zig", "build-obj", "runtime/janus_rt.zig", emit_arg, "-lc" },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);
    if (zig_build_result.term.exited != 0) {
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

    const link_result = try std.process.run(allocator, io, .{
        .argv = link_args.items,
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);
    if (link_result.term.exited != 0) {
        return error.LinkFailed;
    }

    // Execute
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


    // add(3, 4) = 7, multiply(5, 6) = 30
    try testing.expectEqualStrings("7\n30\n", output);

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


    // square(7) = 49, square(3) = 9
    try testing.expectEqualStrings("49\n9\n", output);

}

fn compileFileToObject(
    allocator: std.mem.Allocator,
    file_path: []const u8,
    module_name: []const u8,
    tmp_dir: std.testing.TmpDir,
) ![]const u8 {
    // Read file content
    const source = try compat_fs.readFileAlloc(allocator, file_path, 1024 * 1024);
    defer allocator.free(source);

    return compileToObject(allocator, source, module_name, tmp_dir);
}

fn extractImportsAndCompile(
    allocator: std.mem.Allocator,
    main_source: []const u8,
    search_dir: []const u8,
    tmp_dir: std.testing.TmpDir,
) !struct { main_obj: []const u8, dep_objs: std.ArrayListUnmanaged([]const u8) } {
    // Parse main to extract imports
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(main_source);
    defer snapshot.deinit();

    // Extract import statements from AST
    const unit = snapshot.core_snapshot.astdb.getUnitConst(@enumFromInt(0)) orelse return error.NoUnit;

    var dep_objs = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (dep_objs.items) |obj| allocator.free(obj);
        dep_objs.deinit(allocator);
    }

    for (unit.nodes, 0..) |node, i| {
        if (node.kind == .import_stmt) {
            // Get import path from children (identifiers)
            const node_id: astdb_core.NodeId = @enumFromInt(@as(u32, @intCast(i)));
            const children = snapshot.core_snapshot.getChildren(node_id);

            if (children.len > 0) {
                const child = snapshot.core_snapshot.getNode(children[0]) orelse continue;
                if (child.kind == .identifier) {
                    const token = snapshot.core_snapshot.getToken(child.first_token) orelse continue;
                    if (token.str) |str_id| {
                        const module_name = snapshot.core_snapshot.astdb.str_interner.getString(str_id);

                        // Build file path
                        const file_name = try std.fmt.allocPrint(allocator, "{s}.jan", .{module_name});
                        defer allocator.free(file_name);

                        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ search_dir, file_name });
                        defer allocator.free(full_path);


                        // Compile the dependency
                        const obj_path = try compileFileToObject(allocator, full_path, module_name, tmp_dir);
                        try dep_objs.append(allocator, obj_path);
                    }
                }
            }
        }
    }

    // Compile main
    const main_obj = try compileToObject(allocator, main_source, "main", tmp_dir);

    return .{ .main_obj = main_obj, .dep_objs = dep_objs };
}

test "Import syntax: import mathlib with file resolution" {
    const allocator = testing.allocator;
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write mathlib.jan to temp directory
    const mathlib_source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func sub(a: i32, b: i32) -> i32 {
        \\    return a - b
        \\}
    ;
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "mathlib.jan", .data = mathlib_source });

    // Main module with import statement
    const main_source =
        \\import mathlib
        \\
        \\func main() {
        \\    let sum = add(10, 5)
        \\    print_int(sum)
        \\    let diff = sub(10, 5)
        \\    print_int(diff)
        \\}
    ;

    // Get the temp dir path for import resolution
    const search_dir = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(search_dir);

    // Extract imports and compile all modules
    var result = try extractImportsAndCompile(allocator, main_source, search_dir, tmp_dir);
    defer {
        allocator.free(result.main_obj);
        for (result.dep_objs.items) |obj| allocator.free(obj);
        result.dep_objs.deinit(allocator);
    }

    // Build list of all object files
    var all_objs = std.ArrayListUnmanaged([]const u8){};
    defer all_objs.deinit(allocator);

    try all_objs.append(allocator, result.main_obj);
    for (result.dep_objs.items) |obj| {
        try all_objs.append(allocator, obj);
    }

    // Link and run
    const output = try linkAndRun(allocator, all_objs.items, "import_test", tmp_dir);
    defer allocator.free(output);


    // add(10, 5) = 15, sub(10, 5) = 5
    try testing.expectEqualStrings("15\n5\n", output);

}

test "Selective import: use mathlib.{add, multiply}" {
    const allocator = testing.allocator;
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write mathlib.jan with multiple functions
    const mathlib_source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func multiply(a: i32, b: i32) -> i32 {
        \\    return a * b
        \\}
        \\
        \\func unused(x: i32) -> i32 {
        \\    return x
        \\}
    ;
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "mathlib.jan", .data = mathlib_source });

    // Main module with selective import
    const main_source =
        \\use mathlib.{add, multiply}
        \\
        \\func main() {
        \\    let sum = add(7, 3)
        \\    print_int(sum)
        \\    let product = multiply(4, 5)
        \\    print_int(product)
        \\}
    ;

    // Get the temp dir path for module resolution
    const search_dir = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(search_dir);

    // Extract use statements and compile
    var result = try extractUseSelectiveAndCompile(allocator, main_source, search_dir, tmp_dir);
    defer {
        allocator.free(result.main_obj);
        for (result.dep_objs.items) |obj| allocator.free(obj);
        result.dep_objs.deinit(allocator);
    }

    // Build list of all object files
    var all_objs = std.ArrayListUnmanaged([]const u8){};
    defer all_objs.deinit(allocator);

    try all_objs.append(allocator, result.main_obj);
    for (result.dep_objs.items) |obj| {
        try all_objs.append(allocator, obj);
    }

    // Link and run
    const output = try linkAndRun(allocator, all_objs.items, "selective_test", tmp_dir);
    defer allocator.free(output);


    // add(7, 3) = 10, multiply(4, 5) = 20
    try testing.expectEqualStrings("10\n20\n", output);

}

fn extractUseSelectiveAndCompile(
    allocator: std.mem.Allocator,
    main_source: []const u8,
    search_dir: []const u8,
    tmp_dir: std.testing.TmpDir,
) !struct { main_obj: []const u8, dep_objs: std.ArrayListUnmanaged([]const u8) } {
    // Parse main to extract use statements
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(main_source);
    defer snapshot.deinit();

    // Extract use_selective statements from AST
    const unit = snapshot.core_snapshot.astdb.getUnitConst(@enumFromInt(0)) orelse return error.NoUnit;

    var dep_objs = std.ArrayListUnmanaged([]const u8){};
    errdefer {
        for (dep_objs.items) |obj| allocator.free(obj);
        dep_objs.deinit(allocator);
    }

    for (unit.nodes, 0..) |node, i| {
        if (node.kind == .use_selective or node.kind == .use_stmt) {
            // Get module path from first child (identifier)
            const node_id: astdb_core.NodeId = @enumFromInt(@as(u32, @intCast(i)));
            const children = snapshot.core_snapshot.getChildren(node_id);

            if (children.len > 0) {
                // First child is the module name
                const child = snapshot.core_snapshot.getNode(children[0]) orelse continue;
                if (child.kind == .identifier) {
                    const token = snapshot.core_snapshot.getToken(child.first_token) orelse continue;
                    if (token.str) |str_id| {
                        const module_name = snapshot.core_snapshot.astdb.str_interner.getString(str_id);

                        // Build file path
                        const file_name = try std.fmt.allocPrint(allocator, "{s}.jan", .{module_name});
                        defer allocator.free(file_name);

                        const full_path = try std.fs.path.join(allocator, &[_][]const u8{ search_dir, file_name });
                        defer allocator.free(full_path);

                        // Compile the dependency
                        const obj_path = try compileFileToObject(allocator, full_path, module_name, tmp_dir);
                        try dep_objs.append(allocator, obj_path);
                    }
                }
            }
        }
    }

    // Compile main
    const main_obj = try compileToObject(allocator, main_source, "main", tmp_dir);

    return .{ .main_obj = main_obj, .dep_objs = dep_objs };
}

test "Module namespacing: mathlib.add() qualified calls" {
    const allocator = testing.allocator;
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Write mathlib.jan with functions
    const mathlib_source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func sub(a: i32, b: i32) -> i32 {
        \\    return a - b
        \\}
    ;
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "mathlib.jan", .data = mathlib_source });

    // Main module with qualified calls (mathlib.add instead of just add)
    const main_source =
        \\import mathlib
        \\
        \\func main() {
        \\    let sum = mathlib.add(8, 2)
        \\    print_int(sum)
        \\    let diff = mathlib.sub(8, 2)
        \\    print_int(diff)
        \\}
    ;

    // Get the temp dir path for import resolution
    const search_dir = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(search_dir);

    // Extract imports and compile all modules
    var result = try extractImportsAndCompile(allocator, main_source, search_dir, tmp_dir);
    defer {
        allocator.free(result.main_obj);
        for (result.dep_objs.items) |obj| allocator.free(obj);
        result.dep_objs.deinit(allocator);
    }

    // Build list of all object files
    var all_objs = std.ArrayListUnmanaged([]const u8){};
    defer all_objs.deinit(allocator);

    try all_objs.append(allocator, result.main_obj);
    for (result.dep_objs.items) |obj| {
        try all_objs.append(allocator, obj);
    }

    // Link and run
    const output = try linkAndRun(allocator, all_objs.items, "namespace_test", tmp_dir);
    defer allocator.free(output);


    // mathlib.add(8, 2) = 10, mathlib.sub(8, 2) = 6
    try testing.expectEqualStrings("10\n6\n", output);

}

test "Extern function: std.io module with extern func declarations" {
    const allocator = testing.allocator;
    const io = testing.io;

    var tmp_dir = testing.tmpDir(.{});
    defer tmp_dir.cleanup();

    // Create std directory
    try tmp_dir.dir.createDir(io, "std", .default_dir);

    // Write std/io.jan with extern function declarations
    const io_source =
        \\// std/io.jan - Minimal I/O module for :min profile
        \\
        \\extern func janus_print_int(x: i32)
        \\
        \\func print_int(x: i32) {
        \\    janus_print_int(x)
        \\}
    ;
    try tmp_dir.dir.writeFile(io, .{ .sub_path = "std/io.jan", .data = io_source });

    // Main module that imports std.io
    const main_source =
        \\import std.io
        \\
        \\func main() {
        \\    std.io.print_int(42)
        \\    std.io.print_int(100)
        \\}
    ;

    // Get the temp dir path for import resolution
    const search_dir = try tmp_dir.dir.realPathFileAlloc(testing.io, ".", allocator);
    defer allocator.free(search_dir);

    // Parse main to find imports
    var parser = janus_parser.Parser.init(allocator);
    defer parser.deinit();

    const snapshot = try parser.parseWithSource(main_source);
    defer snapshot.deinit();

    // Find the import statement and extract path components
    const unit = snapshot.core_snapshot.astdb.getUnitConst(@enumFromInt(0)) orelse return error.NoUnit;

    var dep_objs = std.ArrayListUnmanaged([]const u8){};
    defer {
        for (dep_objs.items) |obj| allocator.free(obj);
        dep_objs.deinit(allocator);
    }

    for (unit.nodes, 0..) |node, i| {
        if (node.kind == .import_stmt) {
            const node_id: astdb_core.NodeId = @enumFromInt(@as(u32, @intCast(i)));
            const children = snapshot.core_snapshot.getChildren(node_id);

            // Build path from all identifier children (e.g., std.io -> std/io)
            var path_parts = std.ArrayListUnmanaged([]const u8){};
            defer path_parts.deinit(allocator);

            for (children) |child_id| {
                const child = snapshot.core_snapshot.getNode(child_id) orelse continue;
                if (child.kind == .identifier) {
                    const token = snapshot.core_snapshot.getToken(child.first_token) orelse continue;
                    if (token.str) |str_id| {
                        const part = snapshot.core_snapshot.astdb.str_interner.getString(str_id);
                        try path_parts.append(allocator, part);
                    }
                }
            }

            if (path_parts.items.len > 0) {
                // Join path parts with /
                const module_name = try std.mem.join(allocator, "/", path_parts.items);
                defer allocator.free(module_name);

                const file_name = try std.fmt.allocPrint(allocator, "{s}.jan", .{module_name});
                defer allocator.free(file_name);

                const full_path = try std.fs.path.join(allocator, &[_][]const u8{ search_dir, file_name });
                defer allocator.free(full_path);


                // Compile the dependency (use last part as module name for LLVM)
                const llvm_module_name = path_parts.items[path_parts.items.len - 1];
                const obj_path = try compileFileToObject(allocator, full_path, llvm_module_name, tmp_dir);
                try dep_objs.append(allocator, obj_path);
            }
        }
    }

    // Compile main
    const main_obj = try compileToObject(allocator, main_source, "main", tmp_dir);
    defer allocator.free(main_obj);

    // Build list of all object files
    var all_objs = std.ArrayListUnmanaged([]const u8){};
    defer all_objs.deinit(allocator);

    try all_objs.append(allocator, main_obj);
    for (dep_objs.items) |obj| {
        try all_objs.append(allocator, obj);
    }

    // Link and run
    const output = try linkAndRun(allocator, all_objs.items, "std_io_test", tmp_dir);
    defer allocator.free(output);


    // std.io.print_int(42) and std.io.print_int(100)
    try testing.expectEqualStrings("42\n100\n", output);

}
