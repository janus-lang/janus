// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// JFind Hello World Compilation Test

const std = @import("std");
const testing = std.testing;
const graph_mod = @import("graph.zig");
const LLVMEmitter = @import("llvm_emitter.zig").LLVMEmitter;

const QTJIRGraph = graph_mod.QTJIRGraph;
const IRBuilder = graph_mod.IRBuilder;

test "JFind: Compile hello.jan" {
    const allocator = testing.allocator;
    
    // Read hello.jan content
    // In a real scenario we'd parse this, but for now we'll manually construct the QTJIR
    // that corresponds to hello.jan to verify the backend pipeline first
    
    // hello.jan:
    // func main() -> i32 {
    //     print("Hello from Janus!")
    //     return 0
    // }
    
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();
    
    var builder = IRBuilder.init(&ir_graph);
    
    // 1. Create string constant "Hello from Janus!"
    const str_node = try builder.createConstant(.{ .string = "Hello from Janus!" });
    
    // 2. Create call to print (mapped to janus_print)
    _ = try builder.createCall(&[_]u32{str_node});
    
    // 3. Create return 0
    const zero = try builder.createConstant(.{ .integer = 0 });
    // Note: Our current emitter ignores the return value and returns void
    // This is fine for now as we're just testing the pipeline
    _ = try builder.createReturn(zero);
    
    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "hello");
    defer emitter.deinit();
    
    try emitter.emit(&ir_graph);
    
    // Get LLVM IR
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);
    
    // Write IR to file
    const cwd = std.fs.cwd();
    const ir_file = try cwd.createFile("hello.ll", .{});
    defer ir_file.close();
    
    try ir_file.writeAll(ir_str);
    
    std.debug.print("\n=== Generated LLVM IR for hello.jan ===\n{s}\n", .{ir_str});
    
    // Verify IR contains expected elements
    try testing.expect(std.mem.indexOf(u8, ir_str, "janus_print") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "Hello from Janus!") != null);
    
    // Compile runtime
    // zig build-obj src/runtime/io.zig -femit-bin=runtime.o
    const zig_exe = "zig";
    
    const runtime_path = try std.fs.path.join(allocator, &[_][]const u8{ "src", "runtime", "io.zig" });
    defer allocator.free(runtime_path);
    
    // Compile runtime to object file
    var runtime_cmd = std.process.Child.init(&[_][]const u8{
        zig_exe, "build-obj", runtime_path, "-femit-bin=runtime.o", "-O", "Debug"
    }, allocator);
    _ = try runtime_cmd.spawnAndWait();
    
    // Compile LLVM IR to object file
    // clang -c hello.ll -o hello.o
    // We can use zig cc for this
    var ir_cmd = std.process.Child.init(&[_][]const u8{
        zig_exe, "cc", "-c", "hello.ll", "-o", "hello.o"
    }, allocator);
    _ = try ir_cmd.spawnAndWait();
    
    // Link everything
    // zig cc hello.o runtime.o -o hello
    var link_cmd = std.process.Child.init(&[_][]const u8{
        zig_exe, "cc", "hello.o", "runtime.o", "-o", "hello"
    }, allocator);
    _ = try link_cmd.spawnAndWait();
    
    // Run the executable
    var run_cmd = std.process.Child.init(&[_][]const u8{ "./hello" }, allocator);
    run_cmd.stdout_behavior = .Pipe;
    run_cmd.stderr_behavior = .Pipe;
    try run_cmd.spawn();
    
    const stdout = try run_cmd.stdout.?.readToEndAlloc(allocator, 1024);
    defer allocator.free(stdout);
    const stderr = try run_cmd.stderr.?.readToEndAlloc(allocator, 1024);
    defer allocator.free(stderr);
    _ = try run_cmd.wait();
    
    std.debug.print("Output (stdout): {s}\n", .{stdout});
    std.debug.print("Output (stderr): {s}\n", .{stderr});
    
    // Check either stdout or stderr for the string
    const found = (std.mem.indexOf(u8, stdout, "Hello from Janus!") != null) or 
                  (std.mem.indexOf(u8, stderr, "Hello from Janus!") != null);
                  
    try testing.expect(found);
    
    // Cleanup
    try cwd.deleteFile("hello.ll");
    try cwd.deleteFile("hello.o");
    try cwd.deleteFile("runtime.o");
    try cwd.deleteFile("hello");
}
