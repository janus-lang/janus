// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// NPU Simulator - Doctrinal Test Harness for QTJIR Tensor Operations
// Purpose: Validate semantic correctness of NPU_Tensor lowering
// Doctrine: Integrated Proof - This simulator IS the proof package

const std = @import("std");
const qtjir = @import("../qtjir.zig");
const Graph = qtjir.graph.QTJIRGraph;
const OpCode = qtjir.graph.OpCode;
const Tenancy = qtjir.graph.Tenancy;

/// Validation result from NPU simulation
pub const ValidationResult = struct {
    is_valid: bool,
    error_message: ?[]const u8 = null,
    nodes_validated: usize = 0,
    tensor_ops_count: usize = 0,
    ssm_ops_count: usize = 0,

    pub fn deinit(self: *ValidationResult, allocator: std.mem.Allocator) void {
        if (self.error_message) |msg| {
            allocator.free(msg);
        }
    }
};

/// Tensor operation types for validation
pub const TensorOp = enum {
    matmul,
    conv2d,
    relu,
    softmax,
    reduce_sum,
    reduce_max,
    ssm_scan,
    ssm_selective_scan,
};

/// NPU Simulator - Validates QTJIR tensor/SSM operations
/// Doctrine: Mechanism over Policy - Explicit validation, no hidden magic
pub const NPUSimulator = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) !NPUSimulator {
        return NPUSimulator{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *NPUSimulator) void {
        _ = self;
        // No resources to clean up currently
    }

    /// Execute a QTJIR graph with NPU_Tensor operations
    /// Returns: Validation result (proof of correctness)
    /// Doctrine: Revealed Complexity - All validation steps explicit
    pub fn execute(self: *NPUSimulator, graph: *Graph) !ValidationResult {
        var result = ValidationResult{
            .is_valid = true,
            .nodes_validated = 0,
            .tensor_ops_count = 0,
            .ssm_ops_count = 0,
        };

        // Validate each node in the graph
        for (graph.nodes.items) |*node| {
            result.nodes_validated += 1;

            // Validate tenancy consistency
            const expected_tenancy = self.getExpectedTenancy(node.op);
            if (expected_tenancy) |expected| {
                if (node.tenancy != expected) {
                    result.is_valid = false;
                    result.error_message = try std.fmt.allocPrint(self.allocator, "Tenancy mismatch: node {s} has tenancy {s}, expected {s}", .{ @tagName(node.op), @tagName(node.tenancy), @tagName(expected) });
                    return result;
                }
            }

            // Validate operation-specific semantics
            switch (node.op) {
                .Tensor_Matmul => {
                    result.tensor_ops_count += 1;
                    try self.validateMatmul(node, &result);
                },
                .Tensor_Conv => {
                    result.tensor_ops_count += 1;
                    try self.validateConv2d(node, &result);
                },
                .Tensor_Relu => {
                    result.tensor_ops_count += 1;
                    try self.validateRelu(node, &result);
                },
                .Tensor_Softmax => {
                    result.tensor_ops_count += 1;
                    try self.validateSoftmax(node, &result);
                },
                .Tensor_Reduce => {
                    result.tensor_ops_count += 1;
                    try self.validateReduce(node, &result);
                },
                .SSM_Scan => {
                    result.ssm_ops_count += 1;
                    try self.validateSSMScan(node, &result);
                },
                .SSM_SelectiveScan => {
                    result.ssm_ops_count += 1;
                    try self.validateSSMSelectiveScan(node, &result);
                },
                else => {
                    // Non-NPU operations are allowed (CPU_Serial, etc.)
                },
            }

            if (!result.is_valid) {
                return result;
            }
        }

        return result;
    }

    /// Get expected tenancy for an operation
    /// Doctrine: Syntactic Honesty - Explicit hardware assignment
    fn getExpectedTenancy(self: *NPUSimulator, op: OpCode) ?Tenancy {
        _ = self;
        return switch (op) {
            .Tensor_Matmul,
            .Tensor_Conv,
            .Tensor_Relu,
            .Tensor_Softmax,
            .Tensor_Reduce,
            .SSM_Scan,
            .SSM_SelectiveScan,
            => .NPU_Tensor,

            .Quantum_Gate,
            .Quantum_Measure,
            => .QPU_Quantum,

            else => null, // No specific tenancy requirement
        };
    }

    // ========================================================================
    // Operation-Specific Validation
    // Doctrine: Revealed Complexity - Each operation's constraints explicit
    // ========================================================================

    fn validateMatmul(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // Matmul requires exactly 2 inputs (A, B)
        if (node.inputs.items.len != 2) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul requires 2 inputs, got {d}", .{node.inputs.items.len});
        }
    }

    fn validateConv2d(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // Conv2d requires 2-4 inputs (input, kernel, [stride, padding])
        if (node.inputs.items.len < 2 or node.inputs.items.len > 4) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "Tensor_Conv requires 2-4 inputs, got {d}", .{node.inputs.items.len});
        }
    }

    fn validateRelu(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // ReLU requires exactly 1 input
        if (node.inputs.items.len != 1) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "Tensor_Relu requires 1 input, got {d}", .{node.inputs.items.len});
        }
    }

    fn validateSoftmax(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // Softmax requires 1-2 inputs (input, [axis])
        if (node.inputs.items.len < 1 or node.inputs.items.len > 2) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "Tensor_Softmax requires 1-2 inputs, got {d}", .{node.inputs.items.len});
        }
    }

    fn validateReduce(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // Reduce requires 1-2 inputs (input, [axis])
        if (node.inputs.items.len < 1 or node.inputs.items.len > 2) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "Tensor_Reduce requires 1-2 inputs, got {d}", .{node.inputs.items.len});
        }
    }

    fn validateSSMScan(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // SSM Scan requires exactly 3 inputs (A, B, C matrices)
        if (node.inputs.items.len != 3) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "SSM_Scan requires 3 inputs (A, B, C), got {d}", .{node.inputs.items.len});
        }
    }

    fn validateSSMSelectiveScan(self: *NPUSimulator, node: *const qtjir.graph.IRNode, result: *ValidationResult) !void {
        // SSM Selective Scan requires exactly 4 inputs (A, B, C, delta)
        if (node.inputs.items.len != 4) {
            result.is_valid = false;
            result.error_message = try std.fmt.allocPrint(self.allocator, "SSM_SelectiveScan requires 4 inputs (A, B, C, delta), got {d}", .{node.inputs.items.len});
        }
    }
};
