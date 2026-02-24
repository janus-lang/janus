// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// MLIR Emitter - Production NPU Backend
// Purpose: Convert QTJIR to MLIR for TPU/NPU execution
// Doctrine: Trojan Horse Strategy - Leverage industry-standard IR

const std = @import("std");
const qtjir = @import("../qtjir.zig");
const Graph = qtjir.graph.QTJIRGraph;
const IRNode = qtjir.graph.IRNode;
const OpCode = qtjir.graph.OpCode;
const Tenancy = qtjir.graph.Tenancy;

/// MLIR emission result
pub const MLIRModule = struct {
    text: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *MLIRModule) void {
        self.allocator.free(self.text);
    }
};

/// MLIR Emitter - Converts QTJIR to MLIR Tensor/Linalg dialect
/// Doctrine: Revealed Complexity - Explicit IR-to-IR transformation
pub const MLIREmitter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    indent_level: usize,

    pub fn init(allocator: std.mem.Allocator) !MLIREmitter {
        return MLIREmitter{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .indent_level = 0,
        };
    }

    pub fn deinit(self: *MLIREmitter) void {
        self.output.deinit(self.allocator);
    }

    /// Append formatted text to output buffer. Replaces ArrayList.writer() removed in Zig 0.16.
    fn appendFmt(self: *MLIREmitter, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.output.appendSlice(self.allocator, formatted);
    }

    /// Emit QTJIR graph to MLIR text format
    /// Returns: MLIR module text (caller owns memory)
    /// Doctrine: Syntactic Honesty - Direct QTJIR → MLIR mapping
    pub fn emit(self: *MLIREmitter, graph: *Graph) !MLIRModule {
        // Reset output
        self.output.clearRetainingCapacity();
        self.indent_level = 0;

        // Emit MLIR module header
        try self.emitLine("module {");
        self.indent_level += 1;

        // Emit function wrapper (MLIR requires functions)
        try self.emitLine("func.func @janus_main() {");
        self.indent_level += 1;

        // Emit each QTJIR node as MLIR operation
        for (graph.nodes.items, 0..) |*node, i| {
            try self.emitNode(node, i);
        }

        // Emit function return
        try self.emitLine("return");

        self.indent_level -= 1;
        try self.emitLine("}");

        self.indent_level -= 1;
        try self.emitLine("}");

        // Return owned copy
        const text = try self.allocator.dupe(u8, self.output.items);
        return MLIRModule{
            .text = text,
            .allocator = self.allocator,
        };
    }

    /// Emit a single QTJIR node as MLIR operation
    /// Doctrine: Mechanism over Policy - Explicit operation mapping
    fn emitNode(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        switch (node.op) {
            // Tensor operations → MLIR linalg dialect
            .Tensor_Matmul => try self.emitTensorMatmul(node, node_id),
            .Tensor_Conv => try self.emitTensorConv(node, node_id),
            .Tensor_Relu => try self.emitTensorRelu(node, node_id),
            .Tensor_Softmax => try self.emitTensorSoftmax(node, node_id),
            .Tensor_Reduce => try self.emitTensorReduce(node, node_id),

            // SSM operations → Custom janus.ssm dialect
            .SSM_Scan => try self.emitSSMScan(node, node_id),
            .SSM_SelectiveScan => try self.emitSSMSelectiveScan(node, node_id),

            // Quantum operations → Custom janus.quantum dialect
            .Quantum_Gate => try self.emitQuantumGate(node, node_id),
            .Quantum_Measure => try self.emitQuantumMeasure(node, node_id),

            // Other operations (constants, calls, etc.)
            .Constant => try self.emitConstant(node, node_id),
            .Call => try self.emitCall(node, node_id),

            else => {
                // Unsupported operation - emit comment
                try self.emitComment(try std.fmt.allocPrint(self.allocator, "Unsupported operation: {s}", .{@tagName(node.op)}));
            },
        }
    }

    // ========================================================================
    // Tensor Operations → MLIR Linalg Dialect
    // ========================================================================

    fn emitTensorMatmul(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        // %result = linalg.matmul ins(%a, %b : tensor<?x?xf32>, tensor<?x?xf32>)
        //                         outs(%c : tensor<?x?xf32>) -> tensor<?x?xf32>

        const a_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;
        const b_id = if (node.inputs.items.len > 1) node.inputs.items[1] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = linalg.matmul ins(%{d}, %{d} : tensor<?x?xf32>, tensor<?x?xf32>) " ++
            "outs(%init : tensor<?x?xf32>) -> tensor<?x?xf32>\n", .{ node_id, a_id, b_id });
    }

    fn emitTensorConv(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const input_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;
        const kernel_id = if (node.inputs.items.len > 1) node.inputs.items[1] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = linalg.conv_2d ins(%{d}, %{d} : tensor<?x?x?x?xf32>, tensor<?x?x?x?xf32>) " ++
            "outs(%init : tensor<?x?x?x?xf32>) -> tensor<?x?x?x?xf32>\n", .{ node_id, input_id, kernel_id });
    }

    fn emitTensorRelu(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const input_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = linalg.generic {{indexing_maps = [affine_map<(d0) -> (d0)>, affine_map<(d0) -> (d0)>], " ++
            "iterator_types = [\"parallel\"]}} ins(%{d} : tensor<?xf32>) outs(%init : tensor<?xf32>) {{\n", .{ node_id, input_id });

        self.indent_level += 1;
        try self.emitLine("^bb0(%arg0: f32, %arg1: f32):");
        try self.emitIndent();
        try self.appendFmt("  %cst = arith.constant 0.0 : f32\n", .{});
        try self.emitIndent();
        try self.appendFmt("  %max = arith.maximumf %arg0, %cst : f32\n", .{});
        try self.emitIndent();
        try self.appendFmt("  linalg.yield %max : f32\n", .{});
        self.indent_level -= 1;

        try self.emitLine("} -> tensor<?xf32>");
    }

    fn emitTensorSoftmax(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const input_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = janus.tensor.softmax %{d} : tensor<?xf32> -> tensor<?xf32>\n", .{ node_id, input_id });
    }

    fn emitTensorReduce(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const input_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = linalg.reduce ins(%{d} : tensor<?xf32>) outs(%init : tensor<f32>) " ++
            "dimensions = [0]\n", .{ node_id, input_id });
    }

    // ========================================================================
    // SSM Operations → Custom Janus Dialect
    // ========================================================================

    fn emitSSMScan(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const a_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;
        const b_id = if (node.inputs.items.len > 1) node.inputs.items[1] else 0;
        const c_id = if (node.inputs.items.len > 2) node.inputs.items[2] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = janus.ssm.scan %{d}, %{d}, %{d} : " ++
            "(tensor<?x?xf32>, tensor<?x?xf32>, tensor<?x?xf32>) -> tensor<?xf32>\n", .{ node_id, a_id, b_id, c_id });
    }

    fn emitSSMSelectiveScan(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const a_id = if (node.inputs.items.len > 0) node.inputs.items[0] else 0;
        const b_id = if (node.inputs.items.len > 1) node.inputs.items[1] else 0;
        const c_id = if (node.inputs.items.len > 2) node.inputs.items[2] else 0;
        const delta_id = if (node.inputs.items.len > 3) node.inputs.items[3] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = janus.ssm.selective_scan %{d}, %{d}, %{d}, %{d} : " ++
            "(tensor<?x?xf32>, tensor<?x?xf32>, tensor<?x?xf32>, tensor<?xf32>) -> tensor<?xf32>\n", .{ node_id, a_id, b_id, c_id, delta_id });
    }

    // ========================================================================
    // Quantum Operations → Custom Janus Dialect
    // ========================================================================

    fn emitQuantumGate(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const metadata = node.quantum_metadata orelse return;

        try self.emitIndent();
        try self.appendFmt("%{d} = janus.quantum.gate \"{s}\" qubits=[", .{ node_id, @tagName(metadata.gate_type) });

        for (metadata.qubits, 0..) |qubit, i| {
            if (i > 0) try self.appendFmt(", ", .{});
            try self.appendFmt("{d}", .{qubit});
        }

        try self.appendFmt("] : !janus.qstate\n", .{});
    }

    fn emitQuantumMeasure(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const metadata = node.quantum_metadata orelse return;
        const qubit = if (metadata.qubits.len > 0) metadata.qubits[0] else 0;

        try self.emitIndent();
        try self.appendFmt("%{d} = janus.quantum.measure qubit={d} : !janus.qstate -> i1\n", .{ node_id, qubit });
    }

    // ========================================================================
    // Other Operations
    // ========================================================================

    fn emitConstant(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        switch (node.data) {
            .integer => |val| {
                try self.emitIndent();
                try self.appendFmt("%{d} = arith.constant {d} : i64\n", .{ node_id, val });
            },
            .float => |val| {
                try self.emitIndent();
                try self.appendFmt("%{d} = arith.constant {d} : f32\n", .{ node_id, val });
            },
            else => {
                try self.emitComment("Unsupported constant type");
            },
        }
    }

    fn emitCall(self: *MLIREmitter, node: *const IRNode, node_id: usize) !void {
        const func_name = switch (node.data) {
            .string => |s| s,
            else => "unknown",
        };

        try self.emitIndent();
        try self.appendFmt("%{d} = func.call @{s}(", .{ node_id, func_name });

        for (node.inputs.items, 0..) |input_id, i| {
            if (i > 0) try self.appendFmt(", ", .{});
            try self.appendFmt("%{d}", .{input_id});
        }

        try self.appendFmt(") : () -> ()\n", .{});
    }

    // ========================================================================
    // Utility Functions
    // ========================================================================

    fn emitLine(self: *MLIREmitter, line: []const u8) !void {
        try self.emitIndent();
        try self.output.appendSlice(self.allocator, line);
        try self.output.append(self.allocator, '\n');
    }

    fn emitComment(self: *MLIREmitter, comment: []const u8) !void {
        try self.emitIndent();
        try self.appendFmt("// {s}\n", .{comment});
    }

    fn emitIndent(self: *MLIREmitter) !void {
        for (0..self.indent_level) |_| {
            try self.output.appendSlice(self.allocator, "  ");
        }
    }
};
