// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR → LLVM IR Emitter (Text-based for MVP, LLVM-C bindings for production)

const std = @import("std");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;
const ConstantValue = graph.ConstantValue;

pub const LLVMEmitter = struct {
    allocator: std.mem.Allocator,
    output: std.ArrayList(u8),
    string_constants: std.ArrayList(StringConstant),
    next_string_id: u32 = 0,

    const StringConstant = struct {
        id: u32,
        content: []const u8,
    };

    pub fn init(allocator: std.mem.Allocator) LLVMEmitter {
        return LLVMEmitter{
            .allocator = allocator,
            .output = std.ArrayList(u8){},
            .string_constants = std.ArrayList(StringConstant){},
        };
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.output.deinit(self.allocator);
        self.string_constants.deinit(self.allocator);
    }

    /// Append formatted text to output buffer. Replaces ArrayList.writer() removed in Zig 0.16.
    fn appendFmt(self: *LLVMEmitter, comptime fmt: []const u8, args: anytype) !void {
        const formatted = try std.fmt.allocPrint(self.allocator, fmt, args);
        defer self.allocator.free(formatted);
        try self.output.appendSlice(self.allocator, formatted);
    }

    /// Emit LLVM IR from QTJIR Graph
    pub fn emit(self: *LLVMEmitter, ir_graph: *const QTJIRGraph) ![]u8 {
        try self.emitHeader();
        try self.collectStringConstants(ir_graph);
        try self.emitStringConstants();
        try self.emitFunction(ir_graph);

        return try self.allocator.dupe(u8, self.output.items);
    }

    fn emitHeader(self: *LLVMEmitter) !void {
        try self.appendFmt("; Generated LLVM IR from QTJIR\n", .{});
        try self.appendFmt("target triple = \"x86_64-unknown-linux-gnu\"\n\n", .{});

        // Declare external functions
        try self.appendFmt("declare i32 @printf(i8*, ...)\n", .{});
        try self.appendFmt("declare i32 @puts(i8*)\n", .{});

        // NPU tensor runtime functions
        try self.appendFmt("declare i32 @npu_tensor_matmul(i32, i32)\n", .{});
        try self.appendFmt("declare i32 @npu_tensor_conv(i32, i32)\n", .{});
        try self.appendFmt("declare i32 @npu_tensor_reduce(i32)\n", .{});

        // QPU quantum runtime functions
        try self.appendFmt("declare void @qpu_apply_gate(i32, i32)\n", .{});
        try self.appendFmt("declare i32 @qpu_measure(i32)\n", .{});

        try self.appendFmt("\n", .{});
    }

    fn collectStringConstants(self: *LLVMEmitter, ir_graph: *const QTJIRGraph) !void {
        for (ir_graph.nodes.items) |node| {
            if (node.op == .Constant) {
                switch (node.data) {
                    .string => |str_value| {
                        // Check if already collected
                        var found = false;
                        for (self.string_constants.items) |str_const| {
                            if (std.mem.eql(u8, str_const.content, str_value)) {
                                found = true;
                                break;
                            }
                        }

                        if (!found) {
                            try self.string_constants.append(self.allocator, .{
                                .id = self.next_string_id,
                                .content = str_value,
                            });
                            self.next_string_id += 1;
                        }
                    },
                    else => {},
                }
            }
        }
    }

    fn emitStringConstants(self: *LLVMEmitter) !void {
        for (self.string_constants.items) |str_const| {
            // Remove quotes if present
            const clean_str = if (str_const.content.len >= 2 and
                str_const.content[0] == '"' and
                str_const.content[str_const.content.len - 1] == '"')
                str_const.content[1 .. str_const.content.len - 1]
            else
                str_const.content;

            try self.appendFmt("@str{d} = private unnamed_addr constant [{d} x i8] c\"{s}\\00\"\n", .{ str_const.id, clean_str.len + 1, clean_str });
        }

        if (self.string_constants.items.len > 0) {
            try self.appendFmt("\n", .{});
        }
    }

    fn emitFunction(self: *LLVMEmitter, ir_graph: *const QTJIRGraph) !void {
        // Function signature with parameters
        try self.appendFmt("define i32 @{s}(", .{ir_graph.function_name});

        // Emit parameters
        for (ir_graph.parameters, 0..) |param, i| {
            if (i > 0) try self.appendFmt(", ", .{});
            try self.appendFmt("{s} %{s}", .{ param.type_name, param.name });
        }

        try self.appendFmt(") {{\n", .{});
        try self.appendFmt("entry:\n", .{});

        // Emit instructions
        for (ir_graph.nodes.items) |node| {
            try self.emitNode(&node, ir_graph);
        }

        try self.appendFmt("}}\n", .{});
    }

    fn emitNode(self: *LLVMEmitter, node: *const IRNode, ir_graph: *const QTJIRGraph) !void {
        switch (node.op) {
            .Constant => {
                // Constants are emitted inline when used
            },
            .Phi => {
                // Emit phi node: %result = phi i32 [%val1, %label1], [%val2, %label2]
                if (node.inputs.items.len >= 2) {
                    try self.appendFmt("  %{d} = phi i32 ", .{node.id});

                    for (node.inputs.items, 0..) |input_id, i| {
                        if (i > 0) try self.appendFmt(", ", .{});

                        const input_node = &ir_graph.nodes.items[input_id];
                        var val_buf: [32]u8 = undefined;
                        const val = if (input_node.op == .Constant)
                            switch (input_node.data) {
                                .integer => |int_val| try std.fmt.bufPrint(&val_buf, "{d}", .{int_val}),
                                else => "0",
                            }
                        else
                            try std.fmt.bufPrint(&val_buf, "%{d}", .{input_node.id});

                        // Simplified: use entry block for all phi inputs (proper basic blocks later)
                        try self.appendFmt("[{s}, %entry]", .{val});
                    }

                    try self.appendFmt("\n", .{});
                }
            },
            .Load => {
                // Emit load: return parameter value directly
                // For parameters, we just reference them by name
                if (node.data == .integer) {
                    const param_idx = @as(usize, @intCast(node.data.integer));
                    if (param_idx < ir_graph.parameters.len) {
                        // Load is a no-op for parameters in LLVM - they're already in SSA form
                        // We'll handle this in Return emission by checking if input is Load
                    }
                }
            },
            .Add, .Sub, .Mul, .Div => {
                // Emit arithmetic operations: %result = op i32 %a, %b
                if (node.inputs.items.len >= 2) {
                    const a_node = &ir_graph.nodes.items[node.inputs.items[0]];
                    const b_node = &ir_graph.nodes.items[node.inputs.items[1]];

                    // Get operand values
                    var a_val: []const u8 = undefined;
                    var b_val: []const u8 = undefined;
                    var a_buf: [32]u8 = undefined;
                    var b_buf: [32]u8 = undefined;

                    if (a_node.op == .Constant) {
                        switch (a_node.data) {
                            .integer => |int_val| {
                                a_val = try std.fmt.bufPrint(&a_buf, "{d}", .{int_val});
                            },
                            else => a_val = "0",
                        }
                    } else {
                        a_val = try std.fmt.bufPrint(&a_buf, "%{d}", .{a_node.id});
                    }

                    if (b_node.op == .Constant) {
                        switch (b_node.data) {
                            .integer => |int_val| {
                                b_val = try std.fmt.bufPrint(&b_buf, "{d}", .{int_val});
                            },
                            else => b_val = "0",
                        }
                    } else {
                        b_val = try std.fmt.bufPrint(&b_buf, "%{d}", .{b_node.id});
                    }

                    // Determine operation name
                    const op_name = switch (node.op) {
                        .Add => "add",
                        .Sub => "sub",
                        .Mul => "mul",
                        .Div => "sdiv", // Signed division
                        else => unreachable,
                    };

                    try self.appendFmt("  %{d} = {s} i32 {s}, {s}\n", .{ node.id, op_name, a_val, b_val });
                }
            },
            .Call => {
                // Emit print call
                if (node.inputs.items.len > 0) {
                    const arg_node = &ir_graph.nodes.items[node.inputs.items[0]];

                    if (arg_node.op == .Constant) {
                        switch (arg_node.data) {
                            .string => |str_value| {
                                // Find string constant ID
                                var str_id: u32 = 0;
                                for (self.string_constants.items) |str_const| {
                                    const clean_str = if (str_value.len >= 2 and
                                        str_value[0] == '"' and
                                        str_value[str_value.len - 1] == '"')
                                        str_value[1 .. str_value.len - 1]
                                    else
                                        str_value;

                                    const clean_const = if (str_const.content.len >= 2 and
                                        str_const.content[0] == '"' and
                                        str_const.content[str_const.content.len - 1] == '"')
                                        str_const.content[1 .. str_const.content.len - 1]
                                    else
                                        str_const.content;

                                    if (std.mem.eql(u8, clean_const, clean_str)) {
                                        str_id = str_const.id;
                                        break;
                                    }
                                }

                                const clean_str = if (str_value.len >= 2 and
                                    str_value[0] == '"' and
                                    str_value[str_value.len - 1] == '"')
                                    str_value[1 .. str_value.len - 1]
                                else
                                    str_value;

                                try self.appendFmt("  %call{d} = call i32 @puts(i8* getelementptr inbounds ([{d} x i8], [{d} x i8]* @str{d}, i32 0, i32 0))\n", .{ node.id, clean_str.len + 1, clean_str.len + 1, str_id });
                            },
                            else => {},
                        }
                    }
                }
            },
            .Return => {
                if (node.inputs.items.len > 0) {
                    const value_node = &ir_graph.nodes.items[node.inputs.items[0]];

                    if (value_node.op == .Constant) {
                        switch (value_node.data) {
                            .integer => |int_value| {
                                try self.appendFmt("  ret i32 {d}\n", .{int_value});
                            },
                            else => {
                                try self.appendFmt("  ret i32 0\n", .{});
                            },
                        }
                    } else if (value_node.op == .Load) {
                        // Load node references a parameter - emit parameter name
                        if (value_node.data == .integer) {
                            const param_idx = @as(usize, @intCast(value_node.data.integer));
                            if (param_idx < ir_graph.parameters.len) {
                                const param_name = ir_graph.parameters[param_idx].name;
                                try self.appendFmt("  ret i32 %{s}\n", .{param_name});
                            } else {
                                try self.appendFmt("  ret i32 0\n", .{});
                            }
                        } else {
                            try self.appendFmt("  ret i32 0\n", .{});
                        }
                    } else {
                        // Return computed value (e.g., from Add, Phi operations)
                        try self.appendFmt("  ret i32 %{d}\n", .{value_node.id});
                    }
                } else {
                    try self.appendFmt("  ret i32 0\n", .{});
                }
            },
            .Tensor_Matmul => {
                // Emit NPU tensor matmul: %result = call i32 @npu_tensor_matmul(i32 %a, i32 %b)
                if (node.inputs.items.len >= 2) {
                    const a_node = &ir_graph.nodes.items[node.inputs.items[0]];
                    const b_node = &ir_graph.nodes.items[node.inputs.items[1]];

                    var a_buf: [32]u8 = undefined;
                    var b_buf: [32]u8 = undefined;

                    const a_val = if (a_node.op == .Constant)
                        switch (a_node.data) {
                            .integer => |int_val| try std.fmt.bufPrint(&a_buf, "{d}", .{int_val}),
                            else => "0",
                        }
                    else
                        try std.fmt.bufPrint(&a_buf, "%{d}", .{a_node.id});

                    const b_val = if (b_node.op == .Constant)
                        switch (b_node.data) {
                            .integer => |int_val| try std.fmt.bufPrint(&b_buf, "{d}", .{int_val}),
                            else => "0",
                        }
                    else
                        try std.fmt.bufPrint(&b_buf, "%{d}", .{b_node.id});

                    try self.appendFmt("  %{d} = call i32 @npu_tensor_matmul(i32 {s}, i32 {s})\n", .{ node.id, a_val, b_val });
                }
            },
            .Quantum_Gate => {
                // Emit QPU gate: call void @qpu_apply_gate(i32 %gate_type, i32 %qubit)
                if (node.quantum_metadata) |qm| {
                    const gate_type = @intFromEnum(qm.gate_type);
                    const qubit = if (qm.qubits.len > 0) qm.qubits[0] else 0;

                    try self.appendFmt("  call void @qpu_apply_gate(i32 {d}, i32 {d})\n", .{ gate_type, qubit });
                }
            },
            .Quantum_Measure => {
                // Emit QPU measurement: %result = call i32 @qpu_measure(i32 %qubit)
                if (node.quantum_metadata) |qm| {
                    const qubit = if (qm.qubits.len > 0) qm.qubits[0] else 0;

                    try self.appendFmt("  %{d} = call i32 @qpu_measure(i32 {d})\n", .{ node.id, qubit });
                }
            },
            .Label => {
                // Emit basic block label
                try self.appendFmt("lbl_{d}:\n", .{node.id});
            },
            .Jump => {
                // Emit unconditional branch
                if (node.inputs.items.len > 0) {
                    const target = node.inputs.items[0];
                    try self.appendFmt("  br label %lbl_{d}\n", .{target});
                }
            },
            .Branch => {
                // Emit conditional branch: br i1 %cond, label %true, label %false
                if (node.inputs.items.len >= 3) {
                    const cond_id = node.inputs.items[0];
                    const true_target = node.inputs.items[1];
                    const false_target = node.inputs.items[2];

                    // Get condition value
                    const cond_node = &ir_graph.nodes.items[cond_id];
                    var cond_buf: [32]u8 = undefined;
                    const cond_val = if (cond_node.op == .Constant)
                        switch (cond_node.data) {
                            .boolean => |b| if (b) "1" else "0",
                            .integer => |i| try std.fmt.bufPrint(&cond_buf, "{d}", .{i}),
                            else => "0",
                        }
                    else
                        try std.fmt.bufPrint(&cond_buf, "%{d}", .{cond_id});

                    try self.appendFmt("  br i1 {s}, label %lbl_{d}, label %lbl_{d}\n", .{ cond_val, true_target, false_target });
                }
            },
            .Equal, .NotEqual, .Less, .LessEqual, .Greater, .GreaterEqual => {
                // Emit comparison: %result = icmp <cond> i32 %a, %b
                if (node.inputs.items.len >= 2) {
                    const a_node = &ir_graph.nodes.items[node.inputs.items[0]];
                    const b_node = &ir_graph.nodes.items[node.inputs.items[1]];

                    var a_buf: [32]u8 = undefined;
                    var b_buf: [32]u8 = undefined;

                    const a_val = if (a_node.op == .Constant)
                        switch (a_node.data) {
                            .integer => |i| try std.fmt.bufPrint(&a_buf, "{d}", .{i}),
                            else => "0",
                        }
                    else
                        try std.fmt.bufPrint(&a_buf, "%{d}", .{a_node.id});

                    const b_val = if (b_node.op == .Constant)
                        switch (b_node.data) {
                            .integer => |i| try std.fmt.bufPrint(&b_buf, "{d}", .{i}),
                            else => "0",
                        }
                    else
                        try std.fmt.bufPrint(&b_buf, "%{d}", .{b_node.id});

                    const cmp_op = switch (node.op) {
                        .Equal => "eq",
                        .NotEqual => "ne",
                        .Less => "slt",
                        .LessEqual => "sle",
                        .Greater => "sgt",
                        .GreaterEqual => "sge",
                        else => unreachable,
                    };

                    try self.appendFmt("  %{d} = icmp {s} i32 {s}, {s}\n", .{ node.id, cmp_op, a_val, b_val });
                }
            },
            .Alloca, .Store => {
                // Alloca and Store are handled by the JIT interpreter
                // For LLVM IR, we emit them as standard IR
                // Skip for now - MVP focuses on simple paths
            },
            else => {
                // Unsupported operations are silently skipped for MVP
            },
        }
    }

    // compileToExecutable removed — use std.process.run() pipeline instead
};
