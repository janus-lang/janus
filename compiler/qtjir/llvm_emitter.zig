// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR → LLVM IR Emitter (Production LLVM-C API)

const std = @import("std");
const llvm = @import("llvm_bindings.zig");
const graph = @import("graph.zig");

const QTJIRGraph = graph.QTJIRGraph;
const IRNode = graph.IRNode;
const OpCode = graph.OpCode;

pub const LLVMEmitter = struct {
    allocator: std.mem.Allocator,
    context: llvm.Context,
    module: llvm.Module,
    builder: llvm.Builder,

    // Value mapping: QTJIR node ID → LLVM Value
    // Value mapping: QTJIR node ID → LLVM Value
    values: std.AutoHashMap(u32, llvm.Value),

    // Label mapping: QTJIR Label Node ID → LLVM BasicBlock
    label_blocks: std.AutoHashMap(u32, llvm.BasicBlock),

    // Track which basic block each node was defined in (for PHI incoming edges)
    node_blocks: std.AutoHashMap(u32, llvm.BasicBlock),

    // Deferred PHI nodes that need incoming edges resolved after all nodes are emitted
    deferred_phis: DeferredPhiList,

    // Current function being emitted
    current_function: llvm.Value,

    const DeferredPhi = struct {
        phi_value: llvm.Value,
        input_ids: []const u32,
    };

    const DeferredPhiList = std.ArrayList(DeferredPhi);

    pub fn init(allocator: std.mem.Allocator, module_name: []const u8) !LLVMEmitter {
        llvm.initializeNativeTarget();

        const ctx = llvm.contextCreate();

        // Create null-terminated module name
        const name_z = try allocator.dupeZ(u8, module_name);
        defer allocator.free(name_z);

        const mod = llvm.moduleCreateWithNameInContext(name_z.ptr, ctx);
        const builder = llvm.createBuilderInContext(ctx);

        return LLVMEmitter{
            .allocator = allocator,
            .context = ctx,
            .module = mod,
            .builder = builder,
            .values = std.AutoHashMap(u32, llvm.Value).init(allocator),
            .label_blocks = std.AutoHashMap(u32, llvm.BasicBlock).init(allocator),
            .node_blocks = std.AutoHashMap(u32, llvm.BasicBlock).init(allocator),
            .deferred_phis = .{},
            .current_function = undefined,
        };
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.values.deinit();
        self.label_blocks.deinit();
        self.node_blocks.deinit();
        for (self.deferred_phis.items) |phi| {
            self.allocator.free(phi.input_ids);
        }
        self.deferred_phis.deinit(self.allocator);
        llvm.disposeBuilder(self.builder);
        llvm.disposeModule(self.module);
        llvm.contextDispose(self.context);
    }

    /// Emit QTJIR graphs to LLVM Module
    pub fn emit(self: *LLVMEmitter, ir_graphs: []const QTJIRGraph) !void {
        // Emit all functions
        for (ir_graphs) |*g| {
            try self.emitFunction(g);
        }

        // Verify the module
        try llvm.verifyModule(self.module);
    }

    /// Get LLVM IR as text (for debugging)
    pub fn toString(self: *LLVMEmitter) ![]const u8 {
        const c_str = llvm.printModuleToString(self.module);
        defer llvm.disposeMessage(@constCast(c_str));

        const str = std.mem.span(c_str);
        return try self.allocator.dupe(u8, str);
    }

    fn emitFunction(self: *LLVMEmitter, ir_graph: *const QTJIRGraph) !void {
        // Create function name
        const func_name_z = try self.allocator.dupeZ(u8, ir_graph.function_name);
        defer self.allocator.free(func_name_z);

        // Check if this is the main function
        const is_main = std.mem.eql(u8, ir_graph.function_name, "main");

        // Create function type
        // Parameters
        var param_types = std.ArrayListUnmanaged(llvm.Type){};
        defer param_types.deinit(self.allocator);

        if (is_main) {
            // main() has no params for now
        } else {
            const i32_type = llvm.int32TypeInContext(self.context);
            for (ir_graph.parameters) |_| {
                try param_types.append(self.allocator, i32_type); // MVP: Assume i32
            }
        }

        // Return Type
        const ret_type = if (is_main or std.mem.eql(u8, ir_graph.return_type, "i32"))
            llvm.int32TypeInContext(self.context)
        else
            llvm.voidTypeInContext(self.context);

        const func_type = llvm.functionType(ret_type, param_types.items.ptr, @intCast(param_types.items.len), false);

        // Add function to module
        const function = llvm.addFunction(self.module, func_name_z.ptr, func_type);
        self.current_function = function;

        // Create entry basic block
        const entry_block = llvm.appendBasicBlockInContext(self.context, function, "entry");
        llvm.positionBuilderAtEnd(self.builder, entry_block);

        // Scan for labels and create BasicBlocks
        try self.scanLabels(ir_graph, function);

        // Clear deferred phis for this function
        for (self.deferred_phis.items) |phi| {
            self.allocator.free(phi.input_ids);
        }
        self.deferred_phis.clearRetainingCapacity();
        self.node_blocks.clearRetainingCapacity();

        // Emit all nodes, tracking which block each is in
        for (ir_graph.nodes.items) |*node| {
            try self.emitNode(node, ir_graph);
            // Track which block this node's value was defined in
            if (self.values.contains(node.id)) {
                const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
                if (current_block != null) {
                    try self.node_blocks.put(node.id, current_block);
                }
            }
        }

        // Resolve deferred PHI incoming edges
        try self.resolveDeferredPhis();

        // Add return statement
        if (is_main) {
            // main returns 0 (success)
            const i32_type = llvm.int32TypeInContext(self.context);
            const zero = llvm.constInt(i32_type, 0, false);
            _ = llvm.buildRet(self.builder, zero);
        } else {
            // Check implicit return
            if (ir_graph.nodes.items.len == 0 or
                ir_graph.nodes.items[ir_graph.nodes.items.len - 1].op != .Return)
            {
                if (ret_type == llvm.voidTypeInContext(self.context)) {
                    _ = llvm.buildRetVoid(self.builder);
                } else {
                    // If supposed to return i32 but didn't, return 0 or unreachable
                    const zero = llvm.constInt(llvm.int32TypeInContext(self.context), 0, false);
                    _ = llvm.buildRet(self.builder, zero);
                }
            }
        }
    }

    fn emitNode(self: *LLVMEmitter, node: *const IRNode, ir_graph: *const QTJIRGraph) !void {
        _ = ir_graph; // Will be used for more complex operations
        switch (node.op) {
            .Constant => try self.emitConstant(node),
            .Add => try self.emitBinaryOp(node, llvm.buildAdd),
            .Sub => try self.emitBinaryOp(node, llvm.buildSub),
            .Mul => try self.emitBinaryOp(node, llvm.buildMul),
            .Div => try self.emitBinaryOp(node, llvm.buildSDiv),
            .BitAnd => try self.emitBinaryOp(node, llvm.buildAnd),
            .BitOr => try self.emitBinaryOp(node, llvm.buildOr),
            .Equal => try self.emitCmpOp(node, llvm.c.LLVMIntEQ),
            .NotEqual => try self.emitCmpOp(node, llvm.c.LLVMIntNE),
            .Less => try self.emitCmpOp(node, llvm.c.LLVMIntSLT),
            .LessEqual => try self.emitCmpOp(node, llvm.c.LLVMIntSLE),
            .Greater => try self.emitCmpOp(node, llvm.c.LLVMIntSGT),
            .GreaterEqual => try self.emitCmpOp(node, llvm.c.LLVMIntSGE),
            .Argument => try self.emitArgument(node),
            .Call => try self.emitCall(node),
            .Return => try self.emitReturn(node),
            .Alloca => try self.emitAlloca(node),
            .Store => try self.emitStore(node),
            .Load => try self.emitLoad(node),
            .Label => try self.emitLabel(node),
            .Jump => try self.emitJump(node),
            .Branch => try self.emitBranch(node),
            .Phi => try self.emitPhi(node),
            .Array_Construct => try self.emitArrayConstruct(node),
            .Index => try self.emitIndex(node),
            // Tensor / Quantum (Placeholder)
            .Tensor_Contract => {
                std.debug.print("Warning: Unimplemented Tensor_Contract\n", .{});
            },
            .Quantum_Gate => {
                std.debug.print("Warning: Unimplemented Quantum_Gate\n", .{});
            },
            .Quantum_Measure => {
                std.debug.print("Warning: Unimplemented Quantum_Measure\n", .{});
            },
            else => {
                std.debug.print("Warning: Unimplemented opcode: {s}\n", .{@tagName(node.op)});
            },
        }
    }

    fn scanLabels(self: *LLVMEmitter, ir_graph: *const QTJIRGraph, function: llvm.Value) !void {
        self.label_blocks.clearRetainingCapacity();
        for (ir_graph.nodes.items) |*node| {
            if (node.op == .Label) {
                const name_buf = try std.fmt.allocPrint(self.allocator, "block_{d}", .{node.id});
                defer self.allocator.free(name_buf);
                const name_z = try self.allocator.dupeZ(u8, name_buf);
                defer self.allocator.free(name_z);

                const bb = llvm.appendBasicBlockInContext(self.context, function, name_z.ptr);
                try self.label_blocks.put(node.id, bb);
            }
        }
    }

    fn emitLabel(self: *LLVMEmitter, node: *const IRNode) !void {
        const bb = self.label_blocks.get(node.id) orelse return error.MissingLabel;

        // If the current block is not terminated, we must branch to this new block to maintain validity.
        // However, LLVM builders usually handle sequential block appending implicitly if no terminator is set.
        // BUT strict LLVM IR requires blocks to be terminated.
        // If the 'lowerer' did its job, the previous block should have ended with a Branch or Jump.
        // If it didn't (e.g. sequential flow), we should insert a 'br' to the new block.

        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator == null) {
                // Determine if we should fallthrough.
                // In standard lowering, Label usually follows Jump/Branch.
                // But for "Then" block entry, it might be sequential in emission order but branched to logic-wise.
                // Safest bet for 'fallthrough' from previous instructions is to branch to this label.
                _ = llvm.c.LLVMBuildBr(self.builder, bb);
            }
        }

        llvm.positionBuilderAtEnd(self.builder, bb);
    }

    fn emitJump(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const target_id = node.inputs.items[0];
        const target_bb = self.label_blocks.get(target_id) orelse return error.MissingLabel;

        // Check if current block already has a terminator
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return; // Already terminated, skip
        }

        _ = llvm.buildBr(self.builder, target_bb);
    }

    fn emitBranch(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 3) return error.MissingOperand;

        const cond_id = node.inputs.items[0];
        const true_target_id = node.inputs.items[1];
        const false_target_id = node.inputs.items[2];

        const cond_val = self.values.get(cond_id) orelse return error.MissingOperand;
        const true_bb = self.label_blocks.get(true_target_id) orelse return error.MissingLabel;
        const false_bb = self.label_blocks.get(false_target_id) orelse return error.MissingLabel;

        // Check if current block already has a terminator
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return; // Already terminated, skip
        }

        // Ensure condition is i1
        var cond_i1 = cond_val;
        const cond_type = llvm.c.LLVMTypeOf(cond_val);
        const i1_type = llvm.c.LLVMInt1TypeInContext(self.context);

        if (cond_type != i1_type) {
            // Assume i32, check != 0
            const zero = llvm.constInt(llvm.int32TypeInContext(self.context), 0, false);
            cond_i1 = llvm.buildICmp(self.builder, llvm.c.LLVMIntNE, cond_val, zero, "cond_cast");
        }

        _ = llvm.buildCondBr(self.builder, cond_i1, true_bb, false_bb);
    }

    fn emitPhi(self: *LLVMEmitter, node: *const IRNode) !void {
        // Create a PHI node with i32 type (most common for loop counters)
        const i32_type = llvm.int32TypeInContext(self.context);
        const phi = llvm.c.LLVMBuildPhi(self.builder, i32_type, "phi");

        // Register the value immediately so Store can use it
        try self.values.put(node.id, phi);

        // Defer incoming edge resolution - we don't know blocks yet
        // Copy input_ids since node might be invalidated
        const input_ids = try self.allocator.alloc(u32, node.inputs.items.len);
        @memcpy(input_ids, node.inputs.items);

        try self.deferred_phis.append(self.allocator, .{
            .phi_value = phi,
            .input_ids = input_ids,
        });
    }

    fn resolveDeferredPhis(self: *LLVMEmitter) !void {
        for (self.deferred_phis.items) |deferred| {
            const phi = deferred.phi_value;
            const input_ids = deferred.input_ids;

            // For each input, find the value and the block it came from
            for (input_ids) |input_id| {
                const val = self.values.get(input_id) orelse continue;
                const block = self.node_blocks.get(input_id) orelse continue;

                // LLVM C API: LLVMAddIncoming(phi, values*, blocks*, count)
                var values = [_]llvm.Value{val};
                var blocks = [_]llvm.BasicBlock{block};
                llvm.c.LLVMAddIncoming(phi, &values, &blocks, 1);
            }
        }
    }

    fn emitArgument(self: *LLVMEmitter, node: *const IRNode) !void {
        const index = node.data.integer; // Stored as i64 in ConstantValue
        const param = llvm.c.LLVMGetParam(self.current_function, @intCast(index));
        try self.values.put(node.id, param);
    }

    fn emitConstant(self: *LLVMEmitter, node: *const IRNode) !void {
        const value = switch (node.data) {
            .integer => |int_val| blk: {
                const i32_type = llvm.int32TypeInContext(self.context);
                break :blk llvm.constInt(i32_type, @intCast(int_val), true);
            },
            .float => |float_val| blk: {
                const f64_type = llvm.doubleTypeInContext(self.context);
                break :blk llvm.constReal(f64_type, float_val);
            },
            .boolean => |bool_val| blk: {
                const i1_type = llvm.int1TypeInContext(self.context);
                break :blk llvm.constInt(i1_type, if (bool_val) 1 else 0, false);
            },
            .string => |str_val| blk: {
                // Create global string constant
                const str_const = llvm.c.LLVMConstStringInContext(
                    self.context,
                    str_val.ptr,
                    @intCast(str_val.len),
                    0, // null terminate
                );

                // Create global variable for the string
                const global_name_tmp = try std.fmt.allocPrint(
                    self.allocator,
                    "str.{d}",
                    .{node.id},
                );
                defer self.allocator.free(global_name_tmp);
                const global_name = try self.allocator.dupeZ(u8, global_name_tmp);
                defer self.allocator.free(global_name);

                const global = llvm.c.LLVMAddGlobal(
                    self.module,
                    llvm.c.LLVMTypeOf(str_const),
                    global_name.ptr,
                );
                llvm.c.LLVMSetInitializer(global, str_const);
                llvm.c.LLVMSetGlobalConstant(global, 1);

                // Get pointer to the string
                const zero = llvm.constInt(llvm.int32TypeInContext(self.context), 0, false);
                const indices = [_]llvm.Value{ zero, zero };

                break :blk llvm.c.LLVMConstGEP2(
                    llvm.c.LLVMTypeOf(str_const),
                    global,
                    @constCast(&indices),
                    2,
                );
            },
        };

        try self.values.put(node.id, value);
    }

    fn emitBinaryOp(
        self: *LLVMEmitter,
        node: *const IRNode,
        build_fn: fn (llvm.Builder, llvm.Value, llvm.Value, [*:0]const u8) llvm.Value,
    ) !void {
        if (node.inputs.items.len < 2) return error.InvalidBinaryOp;

        const lhs = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const rhs = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        const result = build_fn(self.builder, lhs, rhs, "");
        try self.values.put(node.id, result);
    }

    fn emitCmpOp(self: *LLVMEmitter, node: *const IRNode, pred: llvm.c.LLVMIntPredicate) !void {
        if (node.inputs.items.len < 2) return error.InvalidBinaryOp;

        const lhs = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const rhs = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        const result_i1 = llvm.buildICmp(self.builder, pred, lhs, rhs, "");
        const result = llvm.buildZExt(self.builder, result_i1, llvm.int32TypeInContext(self.context), "");

        try self.values.put(node.id, result);
    }

    fn emitCall(self: *LLVMEmitter, node: *const IRNode) !void {
        const func_name = switch (node.data) {
            .string => |s| s,
            else => return error.InvalidCall,
        };

        if (std.mem.eql(u8, func_name, "janus_print") or std.mem.eql(u8, func_name, "janus_println") or std.mem.eql(u8, func_name, "janus_panic")) {
            if (node.inputs.items.len == 0) return error.MissingArgument; // Ensure there's an argument for print-like functions
            const arg = self.values.get(node.inputs.items[0]) orelse return error.MissingArgument;

            // Check argument type
            const arg_type = llvm.c.LLVMTypeOf(arg);
            // std.debug.print("DEBUG: janus_print arg type kind: {d}\n", .{type_kind});
            // LLVMDoubleTypeKind is 3

            const i32_type = llvm.int32TypeInContext(self.context);
            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

            if ((arg_type == i32_type or arg_type == i64_type) and !std.mem.eql(u8, func_name, "janus_panic")) {
                // Redirect to janus_print_int for integers (unless it's panic)
                // Runtime expects janus_print_int(i64)
                const void_type = llvm.voidTypeInContext(self.context);
                var param_types = [_]llvm.Type{i64_type};
                const print_type = llvm.functionType(void_type, &param_types, 1, false);

                var print_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_print_int");
                if (print_fn == null) {
                    print_fn = llvm.addFunction(self.module, "janus_print_int", print_type);
                }

                var cast_arg = arg;
                if (arg_type == i32_type) {
                    cast_arg = llvm.c.LLVMBuildSExt(self.builder, arg, i64_type, "cast_to_i64");
                }

                var args = [_]llvm.Value{cast_arg};
                _ = llvm.c.LLVMBuildCall2(self.builder, print_type, print_fn, &args, 1, "");
                return;
            }

            const f64_type = llvm.doubleTypeInContext(self.context);
            if (arg_type == f64_type and !std.mem.eql(u8, func_name, "janus_panic")) {
                const void_type = llvm.voidTypeInContext(self.context);
                var param_types = [_]llvm.Type{f64_type};
                const print_type = llvm.functionType(void_type, &param_types, 1, false);

                var print_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_print_float");
                if (print_fn == null) {
                    print_fn = llvm.addFunction(self.module, "janus_print_float", print_type);
                }

                var args = [_]llvm.Value{arg};
                _ = llvm.c.LLVMBuildCall2(self.builder, print_type, print_fn, &args, 1, "");
                return;
            }

            // Declare function: void @func_name(i8*)
            const void_type = llvm.voidTypeInContext(self.context);
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const i8_ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{i8_ptr_type};
            const print_type = llvm.functionType(void_type, &param_types, 1, false);

            const func_name_z = try self.allocator.dupeZ(u8, func_name);
            defer self.allocator.free(func_name_z);

            var print_fn = llvm.c.LLVMGetNamedFunction(self.module, func_name_z.ptr);
            if (print_fn == null) {
                print_fn = llvm.addFunction(self.module, func_name_z.ptr, print_type);
            }

            var args = [_]llvm.Value{arg};
            _ = llvm.c.LLVMBuildCall2(self.builder, print_type, print_fn, &args, 1, "");
        } else if (std.mem.eql(u8, func_name, "janus_print_int")) {
            const arg = self.values.get(node.inputs.items[0]) orelse return error.MissingArgument;

            const void_type = llvm.voidTypeInContext(self.context);
            const i32_type = llvm.int32TypeInContext(self.context);

            var param_types = [_]llvm.Type{i32_type};
            const print_type = llvm.functionType(void_type, &param_types, 1, false);

            var print_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_print_int");
            if (print_fn == null) {
                print_fn = llvm.addFunction(self.module, "janus_print_int", print_type);
            }

            var args = [_]llvm.Value{arg};
            _ = llvm.c.LLVMBuildCall2(self.builder, print_type, print_fn, &args, 1, "");
        } else if (std.mem.eql(u8, func_name, "janus_print_float")) {
            const arg = self.values.get(node.inputs.items[0]) orelse return error.MissingArgument;

            const void_type = llvm.voidTypeInContext(self.context);
            const f64_type = llvm.doubleTypeInContext(self.context);

            var param_types = [_]llvm.Type{f64_type};
            const print_type = llvm.functionType(void_type, &param_types, 1, false);

            var print_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_print_float");
            if (print_fn == null) {
                print_fn = llvm.addFunction(self.module, "janus_print_float", print_type);
            }

            var args = [_]llvm.Value{arg};
            _ = llvm.c.LLVMBuildCall2(self.builder, print_type, print_fn, &args, 1, "");
        } else if (std.mem.eql(u8, func_name, "std_array_create")) {
            // std_array_create(size, allocator) -> ptr
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const size_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const alloc_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i32_type = llvm.int32TypeInContext(self.context);
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            // Signature: ptr (i32, ptr)
            var param_types = [_]llvm.Type{ i32_type, ptr_type }; // size, allocator
            const func_type = llvm.functionType(ptr_type, &param_types, 2, false);

            const name_z = "std_array_create";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ size_arg, alloc_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "arr");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_len")) {
            // janus_string_len(string) -> i32
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const str_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i32_type = llvm.int32TypeInContext(self.context);
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{ptr_type};
            const func_type = llvm.functionType(i32_type, &param_types, 1, false);

            const name_z = "janus_string_len";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{str_arg};
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "len");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_concat")) {
            // janus_string_concat(string, string) -> string (ptr)
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const s1_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const s2_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{ ptr_type, ptr_type };
            const func_type = llvm.functionType(ptr_type, &param_types, 2, false);

            const name_z = "janus_string_concat";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ s1_arg, s2_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "concat_str");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_default_allocator")) {
            // janus_default_allocator() -> ptr
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            const func_type = llvm.functionType(ptr_type, &[_]llvm.Type{}, 0, false);
            const name_z = "janus_default_allocator";

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &[_]llvm.Value{}, 0, "alloc_handle");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_readFile")) {
            // janus_readFile(path: ptr, allocator: ptr) -> ptr
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const path_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const alloc_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            // Signature: ptr (ptr, ptr) - returns ptr to string or null on error
            var param_types = [_]llvm.Type{ ptr_type, ptr_type };
            const func_type = llvm.functionType(ptr_type, &param_types, 2, false);

            const name_z = "janus_readFile";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ path_arg, alloc_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "file_content");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_writeFile")) {
            // janus_writeFile(path: ptr, content: ptr, allocator: ptr) -> i32
            if (node.inputs.items.len < 3) return error.MissingArgument;
            const path_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const content_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;
            const alloc_arg = self.values.get(node.inputs.items[2]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i32_type = llvm.int32TypeInContext(self.context);

            // Signature: i32 (ptr, ptr, ptr) - returns 0 on success, -1 on error
            var param_types = [_]llvm.Type{ ptr_type, ptr_type, ptr_type };
            const func_type = llvm.functionType(i32_type, &param_types, 3, false);

            const name_z = "janus_writeFile";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ path_arg, content_arg, alloc_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 3, "write_status");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_create")) {
            // janus_string_create(str_data: ptr, len: i64, allocator: ptr) -> ptr
            if (node.inputs.items.len < 3) return error.MissingArgument;
            const str_data_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const len_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;
            const alloc_arg = self.values.get(node.inputs.items[2]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

            // Signature: ptr (ptr, i64, ptr)
            var param_types = [_]llvm.Type{ ptr_type, i64_type, ptr_type };
            const func_type = llvm.functionType(ptr_type, &param_types, 3, false);

            const name_z = "janus_string_create";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ str_data_arg, len_arg, alloc_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 3, "str_handle");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_handle_len")) {
            // janus_string_handle_len(string_handle: ptr) -> i64
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

            // Signature: i64 (ptr)
            var param_types = [_]llvm.Type{ptr_type};
            const func_type = llvm.functionType(i64_type, &param_types, 1, false);

            const name_z = "janus_string_handle_len";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{handle_arg};
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "str_len");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_eq")) {
            // janus_string_eq(s1_handle: ptr, s2_handle: ptr) -> i32 (0 for false, 1 for true)
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const s1_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const s2_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i32_type = llvm.int32TypeInContext(self.context);

            // Signature: i32 (ptr, ptr)
            var param_types = [_]llvm.Type{ ptr_type, ptr_type };
            const func_type = llvm.functionType(i32_type, &param_types, 2, false);

            const name_z = "janus_string_eq";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ s1_arg, s2_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "str_eq");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_print")) {
            // janus_string_print(string_handle: ptr) -> void
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const void_type = llvm.voidTypeInContext(self.context);

            // Signature: void (ptr)
            var param_types = [_]llvm.Type{ptr_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, false);

            const name_z = "janus_string_print";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{handle_arg};
            _ = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "");
        } else if (std.mem.eql(u8, func_name, "janus_string_free")) {
            // janus_string_free(string_handle: ptr, allocator_handle: ptr) -> void
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const alloc_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const void_type = llvm.voidTypeInContext(self.context);

            // Signature: void (ptr, ptr)
            var param_types = [_]llvm.Type{ ptr_type, ptr_type };
            const func_type = llvm.functionType(void_type, &param_types, 2, false);

            const name_z = "janus_string_free";
            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z, func_type);
            }

            var args = [_]llvm.Value{ handle_arg, alloc_arg };
            _ = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "");
        } else if (std.mem.eql(u8, func_name, "janus_vector_create")) {
            // vector_create(capacity: i64) -> ptr
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const capacity_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{i64_type};
            const func_type = llvm.functionType(ptr_type, &param_types, 1, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_vector_create");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_vector_create", func_type);
            }

            var args = [_]llvm.Value{capacity_arg};
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "vec_handle");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_vector_push")) {
            // vector_push(handle: ptr, value: f64) -> i32
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const value_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const f64_type = llvm.doubleTypeInContext(self.context);
            const i32_type = llvm.int32TypeInContext(self.context);

            var param_types = [_]llvm.Type{ ptr_type, f64_type };
            const func_type = llvm.functionType(i32_type, &param_types, 2, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_vector_push");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_vector_push", func_type);
            }

            var args = [_]llvm.Value{ handle_arg, value_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "push_status");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_vector_get")) {
            // vector_get(handle: ptr, index: i64) -> f64
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const index_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
            const f64_type = llvm.doubleTypeInContext(self.context);

            var param_types = [_]llvm.Type{ ptr_type, i64_type };
            const func_type = llvm.functionType(f64_type, &param_types, 2, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_vector_get");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_vector_get", func_type);
            }

            var args = [_]llvm.Value{ handle_arg, index_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "vec_val");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_vector_len")) {
            // vector_len(handle: ptr) -> i64
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);
            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

            var param_types = [_]llvm.Type{ptr_type};
            const func_type = llvm.functionType(i64_type, &param_types, 1, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_vector_len");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_vector_len", func_type);
            }

            var args = [_]llvm.Value{handle_arg};
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "vec_len");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_vector_free")) {
            // vector_free(handle: ptr) -> void
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const handle_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const void_type = llvm.voidTypeInContext(self.context);
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{ptr_type};
            const func_type = llvm.functionType(void_type, &param_types, 1, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_vector_free");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_vector_free", func_type);
            }

            var args = [_]llvm.Value{handle_arg};
            _ = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 1, "");
        } else if (std.mem.eql(u8, func_name, "janus_cast_i32_to_i64")) {
            // i32_to_i64(value: i32) -> i64  (sign extension)
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const value_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
            const result = llvm.c.LLVMBuildSExt(self.builder, value_arg, i64_type, "i64_val");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_cast_i32_to_f64")) {
            // i32_to_f64(value: i32) -> f64  (signed int to float)
            if (node.inputs.items.len < 1) return error.MissingArgument;
            const value_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

            const f64_type = llvm.doubleTypeInContext(self.context);
            const result = llvm.c.LLVMBuildSIToFP(self.builder, value_arg, f64_type, "f64_val");
            try self.values.put(node.id, result);
        } else if (std.mem.eql(u8, func_name, "janus_string_concat_cstr")) {
            // janus_string_concat_cstr(s1: ptr, s2: ptr) -> ptr
            if (node.inputs.items.len < 2) return error.MissingArgument;
            const s1_arg = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            const s2_arg = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            const ptr_type = llvm.c.LLVMPointerType(i8_type, 0);

            var param_types = [_]llvm.Type{ ptr_type, ptr_type };
            const func_type = llvm.functionType(ptr_type, &param_types, 2, false);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, "janus_string_concat_cstr");
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, "janus_string_concat_cstr", func_type);
            }

            var args = [_]llvm.Value{ s1_arg, s2_arg };
            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, &args, 2, "concat_cstr");
            try self.values.put(node.id, result);
        } else {
            // Generic Call Fallback: Assume i32 return, i32 args
            // This allows us to call other functions even if signatures are imperfect
            const i32_type = llvm.int32TypeInContext(self.context);
            var param_types = std.ArrayListUnmanaged(llvm.Type){};
            defer param_types.deinit(self.allocator);
            var args = std.ArrayListUnmanaged(llvm.Value){};
            defer args.deinit(self.allocator);

            for (node.inputs.items) |input_id| {
                const val = self.values.get(input_id) orelse return error.MissingOperand;
                try args.append(self.allocator, val);
                try param_types.append(self.allocator, i32_type); // Assume i32
            }

            const func_type = llvm.functionType(i32_type, param_types.items.ptr, @intCast(param_types.items.len), false);

            const name_z = try self.allocator.dupeZ(u8, func_name);
            defer self.allocator.free(name_z);

            var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z.ptr);
            if (func_fn == null) {
                func_fn = llvm.addFunction(self.module, name_z.ptr, func_type);
            }

            const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, args.items.ptr, @intCast(args.items.len), "");
            try self.values.put(node.id, result);
        }
    }

    fn emitAlloca(self: *LLVMEmitter, node: *const IRNode) !void {
        const i32_type = llvm.int32TypeInContext(self.context);

        // Get variable name from data if available
        var name: [:0]const u8 = "";
        var name_buf: ?[:0]u8 = null;
        defer if (name_buf) |buf| self.allocator.free(buf);

        switch (node.data) {
            .string => |s| {
                name_buf = try self.allocator.dupeZ(u8, s);
                name = name_buf.?;
            },
            else => {},
        }

        const alloca = llvm.c.LLVMBuildAlloca(self.builder, i32_type, name.ptr);
        try self.values.put(node.id, alloca);
    }

    fn emitStore(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 2) return error.MissingOperand;

        const ptr = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const val = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        _ = llvm.c.LLVMBuildStore(self.builder, val, ptr);
        // Store doesn't produce a value
    }

    fn emitLoad(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;

        const ptr = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const i32_type = llvm.int32TypeInContext(self.context);

        const val = llvm.c.LLVMBuildLoad2(self.builder, i32_type, ptr, "");
        try self.values.put(node.id, val);
    }

    fn emitReturn(self: *LLVMEmitter, node: *const IRNode) !void {
        // Check if current block already has a terminator
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return; // Already terminated, skip
        }

        if (node.inputs.items.len > 0) {
            const ret_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
            _ = llvm.buildRet(self.builder, ret_val);
        } else {
            _ = llvm.buildRetVoid(self.builder);
        }
    }
    fn emitArrayConstruct(self: *LLVMEmitter, node: *const IRNode) !void {
        const count = node.inputs.items.len;
        if (count == 0) return; // TODO: handle empty/zero-sized array

        // Infer type from first element
        const first_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const elem_type = llvm.typeof(first_val);

        // Create Array Type: [N x T]
        const array_type = llvm.arrayType(elem_type, @intCast(count));

        // Alloca
        // Note: For large arrays, we should call malloc/std value, but for literals/tests, stack is fine.
        const alloca_inst = llvm.buildAlloca(self.builder, array_type, "arr_lit");
        try self.values.put(node.id, alloca_inst);

        // Store elements
        const zero = llvm.constInt(llvm.int32TypeInContext(self.context), 0, false);

        for (node.inputs.items, 0..) |input_id, i| {
            const val = self.values.get(input_id) orelse return error.MissingOperand;
            const idx = llvm.constInt(llvm.int32TypeInContext(self.context), @intCast(i), false);

            // GEP: ptr -> array decays to pointer.
            // We use GEP(array_type, ptr, 0, i) to get pointer to element i.
            // Wait, for opaque pointers, we need the type of the OBJECT we are GEPing into.
            // If ptr is [N x T]*, we GEP [N x T] with 0, i.

            var indices = [_]llvm.Value{ zero, idx };
            const elem_ptr = llvm.buildInBoundsGEP2(self.builder, array_type, alloca_inst, &indices, 2, "elem_ptr");

            _ = llvm.buildStore(self.builder, val, elem_ptr);
        }
    }

    fn emitIndex(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 2) return error.MissingOperand;
        const array_ptr = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const index_val = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        // We assume array_ptr points to the array literal (alloca result).
        // Since we don't have the array type easily, and assume it's homogeneous i32 for Phase 1...
        // ...we can cheat slightly by GEPing i32 from base pointer if we assume it decays.
        // Or better: Assume i32 for now (Janus MVR limitation).

        const elem_type = llvm.int32TypeInContext(self.context);

        // GEP(i32, ptr, index) treats ptr as i32*.
        // Array address == First element address.
        // So this is valid for 1D arrays.

        var indices = [_]llvm.Value{index_val};
        const elem_ptr = llvm.buildInBoundsGEP2(self.builder, elem_type, array_ptr, &indices, 1, "elem_ptr");
        try self.values.put(node.id, elem_ptr);
    }
};
