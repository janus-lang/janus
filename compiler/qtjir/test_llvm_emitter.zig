// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// LLVM-C Emitter Tests

const std = @import("std");
const testing = std.testing;
const graph_mod = @import("graph.zig");
const LLVMEmitter = @import("llvm_emitter.zig").LLVMEmitter;

const VtableSpec = LLVMEmitter.VtableSpec;
const QTJIRGraph = graph_mod.QTJIRGraph;
const IRBuilder = graph_mod.IRBuilder;

test "LLVM Emitter: Hello World" {
    const allocator = testing.allocator;

    // Create QTJIR graph (main → returns i32 by default)
    var ir_graph = QTJIRGraph.initWithName(allocator, "main");
    defer ir_graph.deinit();

    var builder = IRBuilder.init(&ir_graph);

    // Create string constant — Sovereign Graph: dupe static literal
    const owned_str = try ir_graph.allocator.dupeZ(u8, "Hello, LLVM!");
    const str_node = try builder.createConstant(.{ .string = owned_str });

    // Create call to janus_println (must set data.string for emitCall dispatch)
    const call_node = try builder.createCall(&[_]u32{str_node});
    ir_graph.nodes.items[call_node].data = .{
        .string = try ir_graph.allocator.dupeZ(u8, "janus_println"),
    };

    // Create return (main returns i32, so return 0)
    const zero = try builder.createConstant(.{ .integer = 0 });
    _ = try builder.createReturn(zero);

    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "test");
    defer emitter.deinit();

    try emitter.emit(&[_]QTJIRGraph{ir_graph});

    // Get IR as string
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // main returns i32 (default convention)
    try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @main()") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "Hello, LLVM!") != null);
}

test "LLVM Emitter: Arithmetic" {
    const allocator = testing.allocator;

    // Create QTJIR graph for: 2 + 3
    var ir_graph = QTJIRGraph.initWithName(allocator, "add_test");
    defer ir_graph.deinit();

    var builder = IRBuilder.init(&ir_graph);

    // Create constants
    const lhs = try builder.createConstant(.{ .integer = 2 });
    const rhs = try builder.createConstant(.{ .integer = 3 });

    // Create add
    const add_node = try builder.createNode(.Add);
    var add_ir_node = &ir_graph.nodes.items[add_node];
    try add_ir_node.inputs.append(allocator, lhs);
    try add_ir_node.inputs.append(allocator, rhs);

    // Create return with add result
    const ret_node = try builder.createNode(.Return);
    var ret_ir_node = &ir_graph.nodes.items[ret_node];
    try ret_ir_node.inputs.append(allocator, add_node);

    // Emit to LLVM
    var emitter = try LLVMEmitter.init(allocator, "test");
    defer emitter.deinit();

    try emitter.emit(&[_]QTJIRGraph{ir_graph});

    // Get IR as string
    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Non-main functions with default return_type="i32" get i32 return
    try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @add_test()") != null);
}

test "LLVM Emitter: All Operations" {
    const allocator = testing.allocator;

    // Test Add, Sub, Mul, Div
    const ops = [_]graph_mod.OpCode{ .Add, .Sub, .Mul, .Div };

    for (ops) |op| {
        var ir_graph = QTJIRGraph.initWithName(allocator, "op_test");
        defer ir_graph.deinit();

        var builder = IRBuilder.init(&ir_graph);

        const lhs = try builder.createConstant(.{ .integer = 10 });
        const rhs = try builder.createConstant(.{ .integer = 5 });

        const op_node = try builder.createNode(op);
        var op_ir_node = &ir_graph.nodes.items[op_node];
        try op_ir_node.inputs.append(allocator, lhs);
        try op_ir_node.inputs.append(allocator, rhs);

        const ret_node = try builder.createNode(.Return);
        var ret_ir_node = &ir_graph.nodes.items[ret_node];
        try ret_ir_node.inputs.append(allocator, op_node);

        var emitter = try LLVMEmitter.init(allocator, "test");
        defer emitter.deinit();

        try emitter.emit(&[_]QTJIRGraph{ir_graph});

        const ir_str = try emitter.toString();
        defer allocator.free(ir_str);

        // Non-main functions get i32 return type by default
        try testing.expect(std.mem.indexOf(u8, ir_str, "define i32 @op_test()") != null);
    }
}

// === VTABLE DYNAMIC DISPATCH TESTS (SPEC-025 Phase C Sprint 3) ===

/// Helper: create a minimal function graph that returns a constant i32
fn createImplGraph(allocator: std.mem.Allocator, name: []const u8, ret_val: i64) !QTJIRGraph {
    var g = QTJIRGraph.initWithName(allocator, name);
    var builder = IRBuilder.init(&g);
    const c_node = try builder.createConstant(.{ .integer = ret_val });
    _ = try builder.createReturn(c_node);
    return g;
}

test "VTABLE-001: Vtable globals emitted for trait impls" {
    const allocator = testing.allocator;

    // Two impl functions: Point_Drawable_draw returns 1, Circle_Drawable_draw returns 2
    var g_point = try createImplGraph(allocator, "Point_Drawable_draw", 1);
    defer g_point.deinit();
    var g_circle = try createImplGraph(allocator, "Circle_Drawable_draw", 2);
    defer g_circle.deinit();

    // Minimal main
    var g_main = QTJIRGraph.initWithName(allocator, "main");
    defer g_main.deinit();
    var main_builder = IRBuilder.init(&g_main);
    const zero = try main_builder.createConstant(.{ .integer = 0 });
    _ = try main_builder.createReturn(zero);

    // Vtable specs
    const point_methods = [_][]const u8{"Point_Drawable_draw"};
    const circle_methods = [_][]const u8{"Circle_Drawable_draw"};
    const specs = [_]VtableSpec{
        .{ .key = "Point_Drawable", .method_qualified_names = &point_methods },
        .{ .key = "Circle_Drawable", .method_qualified_names = &circle_methods },
    };

    var emitter = try LLVMEmitter.init(allocator, "test_vtable");
    defer emitter.deinit();
    emitter.setVtableSpecs(&specs);

    try emitter.emit(&[_]QTJIRGraph{ g_point, g_circle, g_main });

    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Verify vtable globals exist
    try testing.expect(std.mem.indexOf(u8, ir_str, "__vtable_Point_Drawable") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "__vtable_Circle_Drawable") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "private constant [1 x ptr]") != null);
}

test "VTABLE-002: Fat pointer construction via Vtable_Construct" {
    const allocator = testing.allocator;

    // Impl function
    var g_impl = try createImplGraph(allocator, "Point_Drawable_draw", 42);
    defer g_impl.deinit();

    // Main: alloca (data ptr), Vtable_Construct, return 0
    var g_main = QTJIRGraph.initWithName(allocator, "main");
    defer g_main.deinit();
    var builder = IRBuilder.init(&g_main);

    // Create alloca as data pointer
    const data_alloca = try builder.createNode(.Alloca);
    g_main.nodes.items[data_alloca].data = .{
        .string = try g_main.allocator.dupeZ(u8, "point_data"),
    };

    // Vtable_Construct: data.string = vtable key, inputs[0] = data
    const construct_node = try builder.createNode(.Vtable_Construct);
    g_main.nodes.items[construct_node].data = .{
        .string = try g_main.allocator.dupeZ(u8, "Point_Drawable"),
    };
    try g_main.nodes.items[construct_node].inputs.append(allocator, data_alloca);

    const zero = try builder.createConstant(.{ .integer = 0 });
    _ = try builder.createReturn(zero);

    // Vtable specs
    const methods = [_][]const u8{"Point_Drawable_draw"};
    const specs = [_]VtableSpec{
        .{ .key = "Point_Drawable", .method_qualified_names = &methods },
    };

    var emitter = try LLVMEmitter.init(allocator, "test_vtable");
    defer emitter.deinit();
    emitter.setVtableSpecs(&specs);

    try emitter.emit(&[_]QTJIRGraph{ g_impl, g_main });

    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Verify fat pointer construction
    try testing.expect(std.mem.indexOf(u8, ir_str, "insertvalue { ptr, ptr }") != null);
}

test "VTABLE-003: Full vtable dispatch — construct + lookup + indirect call" {
    const allocator = testing.allocator;

    // Helper: heap-allocate parameters for Sovereign Graph compliance
    const point_params = try allocator.alloc(graph_mod.Parameter, 1);
    point_params[0] = .{ .name = try allocator.dupe(u8, "x"), .type_name = "i32" };
    const circle_params = try allocator.alloc(graph_mod.Parameter, 1);
    circle_params[0] = .{ .name = try allocator.dupe(u8, "x"), .type_name = "i32" };

    // Two impl functions that take an i32 parameter and return i32
    var g_point = QTJIRGraph.initWithName(allocator, "Point_Drawable_draw");
    defer g_point.deinit();
    g_point.parameters = point_params;
    {
        var b = IRBuilder.init(&g_point);
        const arg = try b.createNode(.Argument);
        g_point.nodes.items[arg].data = .{ .integer = 0 };
        _ = try b.createReturn(arg);
    }

    var g_circle = QTJIRGraph.initWithName(allocator, "Circle_Drawable_draw");
    defer g_circle.deinit();
    g_circle.parameters = circle_params;
    {
        var b = IRBuilder.init(&g_circle);
        const arg = try b.createNode(.Argument);
        g_circle.nodes.items[arg].data = .{ .integer = 0 };
        _ = try b.createReturn(arg);
    }

    // Main: alloca, Vtable_Construct, Vtable_Lookup(slot=0, fat_ptr, arg), return result
    var g_main = QTJIRGraph.initWithName(allocator, "main");
    defer g_main.deinit();
    var builder = IRBuilder.init(&g_main);

    // Data pointer (alloca)
    const data_alloca = try builder.createNode(.Alloca);
    g_main.nodes.items[data_alloca].data = .{
        .string = try g_main.allocator.dupeZ(u8, "point_data"),
    };

    // Vtable_Construct
    const construct_node = try builder.createNode(.Vtable_Construct);
    g_main.nodes.items[construct_node].data = .{
        .string = try g_main.allocator.dupeZ(u8, "Point_Drawable"),
    };
    try g_main.nodes.items[construct_node].inputs.append(allocator, data_alloca);

    // Argument to pass through vtable call
    const arg_val = try builder.createConstant(.{ .integer = 7 });

    // Vtable_Lookup: slot 0, fat_ptr, arg
    const lookup_node = try builder.createNode(.Vtable_Lookup);
    g_main.nodes.items[lookup_node].data = .{ .integer = 0 }; // slot 0
    try g_main.nodes.items[lookup_node].inputs.append(allocator, construct_node);
    try g_main.nodes.items[lookup_node].inputs.append(allocator, arg_val);

    // Return the indirect call result
    _ = try builder.createReturn(lookup_node);

    // Vtable specs
    const point_methods = [_][]const u8{"Point_Drawable_draw"};
    const circle_methods = [_][]const u8{"Circle_Drawable_draw"};
    const specs = [_]VtableSpec{
        .{ .key = "Point_Drawable", .method_qualified_names = &point_methods },
        .{ .key = "Circle_Drawable", .method_qualified_names = &circle_methods },
    };

    var emitter = try LLVMEmitter.init(allocator, "test_vtable");
    defer emitter.deinit();
    emitter.setVtableSpecs(&specs);

    try emitter.emit(&[_]QTJIRGraph{ g_point, g_circle, g_main });

    const ir_str = try emitter.toString();
    defer allocator.free(ir_str);

    // Verify vtable globals
    try testing.expect(std.mem.indexOf(u8, ir_str, "__vtable_Point_Drawable") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "__vtable_Circle_Drawable") != null);

    // Verify fat pointer construction
    try testing.expect(std.mem.indexOf(u8, ir_str, "insertvalue { ptr, ptr }") != null);

    // Verify vtable lookup: GEP + load + indirect call
    try testing.expect(std.mem.indexOf(u8, ir_str, "getelementptr inbounds [1 x ptr]") != null);
    try testing.expect(std.mem.indexOf(u8, ir_str, "load ptr") != null);
    // Indirect call returns i32 (name "dyn.call")
    try testing.expect(std.mem.indexOf(u8, ir_str, "call i32") != null);

    // VTABLE-004: Verify self data pointer extraction from fat pointer
    // extractvalue { ptr, ptr } for index 0 = data pointer
    try testing.expect(std.mem.indexOf(u8, ir_str, "self.ptr") != null);
    // ptrtoint conversion for MVP i32 self parameter
    try testing.expect(std.mem.indexOf(u8, ir_str, "ptrtoint") != null);
}
