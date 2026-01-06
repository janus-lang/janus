// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// End-to-End QTJIR Compilation Test

const std = @import("std");
const testing = std.testing;
const graph_mod = @import("graph.zig");
const LLVMEmitter = @import("llvm_emitter.zig").LLVMEmitter;

const QTJIRGraph = graph_mod.QTJIRGraph;
const IRBuilder = graph_mod.IRBuilder;

test "E2E: Compile and link Hello World" {
    const allocator = testing.allocator;
    
    // Create QTJIR graph for: print("Hello, Janus!")
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();
    
    var builder = IRBuilder.init(&ir_graph);
    
    // Create string constant
    const str_node = try builder.createConstant(.{ .string = "Hello, Janus!" });
    
    // Create call to janus_print
    _ = try builder.createCall(&[_]u32{str_node});
    
    // Create return
    _ = try builder.createReturn(0);
    
    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "hello");
    defer emitter.deinit();
    
    try emitter.emit(&ir_graph);
    
    // Get LLVM IR
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);
    
    // Write IR to file
    const cwd = std.fs.cwd();
    const ir_file = try cwd.createFile("test_hello.ll", .{});
    defer ir_file.close();
    defer cwd.deleteFile("test_hello.ll") catch {};
    
    try ir_file.writeAll(ir_str);
    
    std.debug.print("\n=== Generated LLVM IR ===\n{s}\n", .{ir_str});
    std.debug.print("IR written to test_hello.ll\n", .{});
    
    // Verify IR contains our function call
    try testing.expect(std.mem.indexOf(u8, ir_str, "janus_print") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "Hello, Janus!") != null);
}
