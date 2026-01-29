// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// QTJIR → LLVM IR Emitter (Production LLVM-C API)

const std = @import("std");
const llvm = @import("llvm_bindings.zig");
const graph = @import("graph.zig");
const extern_reg = @import("extern_registry.zig");

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

    // Struct metadata: maps struct node_id -> (llvm_type, field_names)
    struct_info: std.AutoHashMap(u32, StructInfo),

    // Track which nodes are allocas (for pointer-based field access)
    alloca_types: std.AutoHashMap(u32, void),

    // Optional external function registry for native Zig integration
    extern_registry: ?*const extern_reg.ExternRegistry = null,

    // Function signature mapping: function_name -> return_type
    function_return_types: std.StringHashMap([]const u8),

    const DeferredPhi = struct {
        phi_value: llvm.Value,
        input_ids: []const u32,
    };

    const DeferredPhiList = std.ArrayList(DeferredPhi);

    const StructInfo = struct {
        llvm_type: llvm.Type,
        field_names: []const u8, // Comma-separated field names
    };

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
            .struct_info = std.AutoHashMap(u32, StructInfo).init(allocator),
            .alloca_types = std.AutoHashMap(u32, void).init(allocator),
            .function_return_types = std.StringHashMap([]const u8).init(allocator),
        };
    }

    /// Set the extern registry for native Zig function resolution
    /// This enables looking up function signatures from `use zig` imports
    pub fn setExternRegistry(self: *LLVMEmitter, registry: *const extern_reg.ExternRegistry) void {
        self.extern_registry = registry;
    }

    pub fn deinit(self: *LLVMEmitter) void {
        self.values.deinit();
        self.label_blocks.deinit();
        self.node_blocks.deinit();
        self.struct_info.deinit();
        self.alloca_types.deinit();
        self.function_return_types.deinit();
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
        // First pass: collect function signatures
        for (ir_graphs) |*g| {
            try self.function_return_types.put(g.function_name, g.return_type);
        }

        // Second pass: emit all functions
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
        const ret_type = if (is_main)
            llvm.int32TypeInContext(self.context)
        else if (std.mem.eql(u8, ir_graph.return_type, "error_union"))
            blk: {
                // Error union is struct { i8 is_error, i64 value }
                var fields = [_]llvm.Type{
                    llvm.c.LLVMInt8TypeInContext(self.context),  // is_error flag
                    llvm.c.LLVMInt64TypeInContext(self.context), // value (error code or payload)
                };
                break :blk llvm.structTypeInContext(self.context, &fields, fields.len, false);
            }
        else if (std.mem.eql(u8, ir_graph.return_type, "i32"))
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

        // Add return statement only if the current block doesn't already have a terminator
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        const existing_terminator = if (current_block != null)
            llvm.c.LLVMGetBasicBlockTerminator(current_block)
        else
            null;

        if (existing_terminator == null) {
            if (is_main) {
                // main returns 0 (success)
                const i32_type = llvm.int32TypeInContext(self.context);
                const zero = llvm.constInt(i32_type, 0, false);
                _ = llvm.buildRet(self.builder, zero);
            } else {
                if (ret_type == llvm.voidTypeInContext(self.context)) {
                    _ = llvm.buildRetVoid(self.builder);
                } else if (std.mem.eql(u8, ir_graph.return_type, "error_union")) {
                    // Error union functions must have explicit returns
                    // This is a lowering bug if we reach here
                    std.debug.print("ERROR: Error union function missing explicit return\n", .{});
                    return error.MissingReturn;
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
            .Mod => try self.emitBinaryOp(node, llvm.buildSRem),
            .Pow => try self.emitPow(node),
            .BitAnd => try self.emitBinaryOp(node, llvm.buildAnd),
            .BitOr => try self.emitBinaryOp(node, llvm.buildOr),
            .Xor => try self.emitBinaryOp(node, llvm.buildXor),
            .Shl => try self.emitBinaryOp(node, llvm.buildShl),
            .Shr => try self.emitBinaryOp(node, llvm.buildAShr),
            .BitNot => try self.emitUnaryOp(node, llvm.buildNot),
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
            .Slice => try self.emitSlice(node),
            .SliceIndex => try self.emitSliceIndex(node),
            .SliceLen => try self.emitSliceLen(node),
            .Struct_Construct => try self.emitStructConstruct(node),
            .Struct_Alloca => try self.emitStructAlloca(node),
            .Field_Access => try self.emitFieldAccess(node),
            .Field_Store => try self.emitFieldStore(node),
            // Optional types
            .Optional_None => try self.emitOptionalNone(node),
            .Optional_Some => try self.emitOptionalSome(node),
            .Optional_Unwrap => try self.emitOptionalUnwrap(node),
            .Optional_Is_Some => try self.emitOptionalIsSome(node),
            // Error unions (:core profile)
            .Error_Union_Construct => try self.emitErrorUnionConstruct(node),
            .Error_Fail_Construct => try self.emitErrorFailConstruct(node),
            .Error_Union_Is_Error => try self.emitErrorUnionIsError(node),
            .Error_Union_Unwrap => try self.emitErrorUnionUnwrap(node),
            .Error_Union_Get_Error => try self.emitErrorUnionGetError(node),
            // :service profile - Structured Concurrency (Blocking Model Phase 1)
            .Await => try self.emitAwait(node),
            .Spawn => try self.emitSpawn(node),
            .Nursery_Begin => try self.emitNurseryBegin(node),
            .Nursery_End => try self.emitNurseryEnd(node),
            .Async_Call => try self.emitAsyncCall(node),
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

    fn emitUnaryOp(
        self: *LLVMEmitter,
        node: *const IRNode,
        build_fn: fn (llvm.Builder, llvm.Value, [*:0]const u8) llvm.Value,
    ) !void {
        if (node.inputs.items.len < 1) return error.InvalidUnaryOp;

        const operand = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const result = build_fn(self.builder, operand, "");
        try self.values.put(node.id, result);
    }

    fn emitPow(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 2) return error.InvalidBinaryOp;

        const base = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const exp = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        // Call janus_pow runtime function
        const i32_type = llvm.int32TypeInContext(self.context);
        var param_types = [_]llvm.Type{ i32_type, i32_type };
        const func_type = llvm.functionType(i32_type, &param_types, 2, false);

        var func = llvm.c.LLVMGetNamedFunction(self.module, "janus_pow");
        if (func == null) {
            func = llvm.addFunction(self.module, "janus_pow", func_type);
        }

        var args = [_]llvm.Value{ base, exp };
        const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func, &args, 2, "");

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
            // Check extern registry for native Zig function signatures
            if (self.extern_registry) |registry| {
                if (registry.lookup(func_name)) |sig| {
                    return try self.emitExternCall(node, func_name, sig);
                }
            }

            // Generic Call Fallback: Look up function return type, assume i32 args
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

            // Look up return type from function signature map
            const return_type_str = self.function_return_types.get(func_name) orelse "i32";
            const return_type = if (std.mem.eql(u8, return_type_str, "error_union"))
                blk: {
                    // Error union is struct { i8 is_error, i64 value }
                    var fields = [_]llvm.Type{
                        llvm.c.LLVMInt8TypeInContext(self.context),
                        llvm.c.LLVMInt64TypeInContext(self.context),
                    };
                    break :blk llvm.structTypeInContext(self.context, &fields, fields.len, false);
                }
            else if (std.mem.eql(u8, return_type_str, "i32"))
                i32_type
            else
                llvm.voidTypeInContext(self.context);

            const func_type = llvm.functionType(return_type, param_types.items.ptr, @intCast(param_types.items.len), false);

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

    /// Emit a call to an external function with known signature from extern registry
    fn emitExternCall(self: *LLVMEmitter, node: *const IRNode, func_name: []const u8, sig: *const extern_reg.ExternFnSig) !void {
        // Convert LLVM type strings to actual LLVM types
        var param_types = std.ArrayListUnmanaged(llvm.Type){};
        defer param_types.deinit(self.allocator);
        var args = std.ArrayListUnmanaged(llvm.Value){};
        defer args.deinit(self.allocator);

        for (sig.param_types, 0..) |type_str, i| {
            const expected_type = self.llvmTypeFromStr(type_str);
            try param_types.append(self.allocator, expected_type);

            if (i < node.inputs.items.len) {
                var val = self.values.get(node.inputs.items[i]) orelse return error.MissingOperand;

                // Type conversion: extend or truncate if needed
                const val_type = llvm.c.LLVMTypeOf(val);
                if (val_type != expected_type) {
                    const val_kind = llvm.c.LLVMGetTypeKind(val_type);
                    const exp_kind = llvm.c.LLVMGetTypeKind(expected_type);

                    // Integer type conversions
                    if (val_kind == llvm.c.LLVMIntegerTypeKind and exp_kind == llvm.c.LLVMIntegerTypeKind) {
                        const val_width = llvm.c.LLVMGetIntTypeWidth(val_type);
                        const exp_width = llvm.c.LLVMGetIntTypeWidth(expected_type);

                        if (val_width < exp_width) {
                            // Sign-extend smaller int to larger
                            val = llvm.c.LLVMBuildSExt(self.builder, val, expected_type, "sext");
                        } else if (val_width > exp_width) {
                            // Truncate larger int to smaller
                            val = llvm.c.LLVMBuildTrunc(self.builder, val, expected_type, "trunc");
                        }
                    }
                    // Pointer to pointer is ok (opaque pointers)
                }

                try args.append(self.allocator, val);
            }
        }

        const return_type = self.llvmTypeFromStr(sig.return_type);
        const func_type = llvm.functionType(return_type, param_types.items.ptr, @intCast(param_types.items.len), false);

        const name_z = try self.allocator.dupeZ(u8, func_name);
        defer self.allocator.free(name_z);

        var func_fn = llvm.c.LLVMGetNamedFunction(self.module, name_z.ptr);
        if (func_fn == null) {
            func_fn = llvm.addFunction(self.module, name_z.ptr, func_type);
        }

        const is_void = std.mem.eql(u8, sig.return_type, "void");
        const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func_fn, args.items.ptr, @intCast(args.items.len), if (is_void) "" else "extern_result");

        if (!is_void) {
            try self.values.put(node.id, result);
        }
    }

    /// Convert LLVM type string to actual LLVM type
    fn llvmTypeFromStr(self: *LLVMEmitter, type_str: []const u8) llvm.Type {
        if (std.mem.eql(u8, type_str, "i32")) {
            return llvm.int32TypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "i64")) {
            return llvm.c.LLVMInt64TypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "float")) {
            return llvm.c.LLVMFloatTypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "double")) {
            return llvm.doubleTypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "i1")) {
            return llvm.c.LLVMInt1TypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "void")) {
            return llvm.voidTypeInContext(self.context);
        } else if (std.mem.eql(u8, type_str, "ptr")) {
            const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
            return llvm.c.LLVMPointerType(i8_type, 0);
        } else {
            // Default to i32 for unknown types
            return llvm.int32TypeInContext(self.context);
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

    /// Emit array slice: arr[start..end] or arr[start..<end]
    /// Returns a slice struct { ptr, len } - NO data copying!
    fn emitSlice(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 3) return error.MissingOperand;
        const array_ptr = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const start_val = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;
        const end_val = self.values.get(node.inputs.items[2]) orelse return error.MissingOperand;

        // Get inclusivity from node data (1 = inclusive, 0 = exclusive)
        const is_inclusive = switch (node.data) {
            .integer => |i| i == 1,
            else => false,
        };

        // Select the appropriate runtime function
        const func_name: [:0]const u8 = if (is_inclusive) "janus_make_slice_inclusive_i32" else "janus_make_slice_i32";

        // Define slice struct type: { ptr, usize }
        // JanusSliceI32 = extern struct { ptr: [*]const i32, len: usize }
        const i32_type = llvm.int32TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
        const ptr_type = llvm.c.LLVMPointerType(i32_type, 0);

        // Slice struct type: { i32*, i64 }
        var slice_member_types = [_]llvm.Type{ ptr_type, i64_type };
        const slice_struct_type = llvm.structTypeInContext(self.context, &slice_member_types, 2, false);

        // Function signature: (ptr, i32, i32) -> slice_struct
        var param_types = [_]llvm.Type{ ptr_type, i32_type, i32_type };
        const func_type = llvm.functionType(slice_struct_type, &param_types, 3, false);

        var func = llvm.c.LLVMGetNamedFunction(self.module, func_name.ptr);
        if (func == null) {
            func = llvm.addFunction(self.module, func_name, func_type);
        }

        // Call the slice function - returns slice struct by value
        var args = [_]llvm.Value{ array_ptr, start_val, end_val };
        const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func, &args, 3, "slice");
        try self.values.put(node.id, result);
    }

    /// Emit slice element access: slice[index]
    /// Calls runtime function janus_slice_get_i32(slice, index) -> i32
    fn emitSliceIndex(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 2) return error.MissingOperand;
        const slice_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;
        const index_val = self.values.get(node.inputs.items[1]) orelse return error.MissingOperand;

        // Define slice struct type: { ptr, usize }
        const i32_type = llvm.int32TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
        const ptr_type = llvm.c.LLVMPointerType(i32_type, 0);

        // Slice struct type: { i32*, i64 }
        var slice_member_types = [_]llvm.Type{ ptr_type, i64_type };
        const slice_struct_type = llvm.structTypeInContext(self.context, &slice_member_types, 2, false);

        // Function signature: (slice_struct, usize) -> i32
        // Note: The index is passed as i32 in our IR, convert to usize (i64)
        var param_types = [_]llvm.Type{ slice_struct_type, i64_type };
        const func_type = llvm.functionType(i32_type, &param_types, 2, false);

        const func_name: [:0]const u8 = "janus_slice_get_i32";
        var func = llvm.c.LLVMGetNamedFunction(self.module, func_name.ptr);
        if (func == null) {
            func = llvm.addFunction(self.module, func_name, func_type);
        }

        // Convert index from i32 to i64 (usize)
        const index_i64 = llvm.c.LLVMBuildZExt(self.builder, index_val, i64_type, "idx_ext");

        // Call the slice get function
        var args = [_]llvm.Value{ slice_val, index_i64 };
        const result = llvm.c.LLVMBuildCall2(self.builder, func_type, func, &args, 2, "slice_elem");
        try self.values.put(node.id, result);
    }

    /// Emit slice length extraction: slice.len
    /// Extracts the length (index 1) from the slice fat pointer struct
    fn emitSliceLen(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const slice_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        // Extract the length field (index 1) from slice struct { ptr, len }
        const len_val = llvm.c.LLVMBuildExtractValue(self.builder, slice_val, 1, "slice_len");
        try self.values.put(node.id, len_val);
    }

    // =========================================================================
    // Optional Type Operations
    // =========================================================================
    // Optional is represented as { i8, i64 } where:
    // - i8 is the tag: 0 = none/null, 1 = some
    // - i64 is the payload (value or undefined)

    /// Get the LLVM type for optional: { i8, i64 }
    fn getOptionalType(self: *LLVMEmitter) llvm.Type {
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
        var member_types = [_]llvm.Type{ i8_type, i64_type };
        return llvm.structTypeInContext(self.context, &member_types, 2, false);
    }

    /// Emit Optional_None: creates { 0, undef }
    fn emitOptionalNone(self: *LLVMEmitter, node: *const IRNode) !void {
        const opt_type = self.getOptionalType();
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

        // Create struct with tag=0, value=undef
        var opt_val = llvm.getUndef(opt_type);
        const zero = llvm.c.LLVMConstInt(i8_type, 0, 0);
        opt_val = llvm.c.LLVMBuildInsertValue(self.builder, opt_val, zero, 0, "opt_none_tag");
        const undef_val = llvm.getUndef(i64_type);
        opt_val = llvm.c.LLVMBuildInsertValue(self.builder, opt_val, undef_val, 1, "opt_none");

        try self.values.put(node.id, opt_val);
    }

    /// Emit Optional_Some: wraps value in { 1, value }
    fn emitOptionalSome(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const inner_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const opt_type = self.getOptionalType();
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

        // Convert inner value to i64 if needed
        const inner_type = llvm.c.LLVMTypeOf(inner_val);
        const payload = if (inner_type == i64_type)
            inner_val
        else if (llvm.c.LLVMGetTypeKind(inner_type) == llvm.c.LLVMIntegerTypeKind)
            llvm.c.LLVMBuildZExt(self.builder, inner_val, i64_type, "opt_payload")
        else
            llvm.c.LLVMBuildPtrToInt(self.builder, inner_val, i64_type, "opt_payload_ptr");

        // Create struct with tag=1, value=payload
        var opt_val = llvm.getUndef(opt_type);
        const one = llvm.c.LLVMConstInt(i8_type, 1, 0);
        opt_val = llvm.c.LLVMBuildInsertValue(self.builder, opt_val, one, 0, "opt_some_tag");
        opt_val = llvm.c.LLVMBuildInsertValue(self.builder, opt_val, payload, 1, "opt_some");

        try self.values.put(node.id, opt_val);
    }

    /// Emit Optional_Unwrap: extract value from optional (panics if none)
    fn emitOptionalUnwrap(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const opt_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const i32_type = llvm.int32TypeInContext(self.context);

        // Extract tag and check if it's 1 (some)
        const tag = llvm.c.LLVMBuildExtractValue(self.builder, opt_val, 0, "opt_tag");

        // TODO: Add panic if tag == 0 (requires control flow)
        // For now, just extract the value without checking
        _ = tag;

        // Extract payload and truncate to i32 (assuming i32 for now)
        const payload = llvm.c.LLVMBuildExtractValue(self.builder, opt_val, 1, "opt_payload");
        const result = llvm.c.LLVMBuildTrunc(self.builder, payload, i32_type, "unwrap");

        try self.values.put(node.id, result);
    }

    /// Emit Optional_Is_Some: returns tag == 1
    fn emitOptionalIsSome(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const opt_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);

        // Extract tag
        const tag = llvm.c.LLVMBuildExtractValue(self.builder, opt_val, 0, "opt_tag");

        // Compare tag == 1
        const one = llvm.c.LLVMConstInt(i8_type, 1, 0);
        const is_some = llvm.c.LLVMBuildICmp(self.builder, llvm.c.LLVMIntEQ, tag, one, "is_some");

        try self.values.put(node.id, is_some);
    }

    /// Emit struct literal: Point { x: 10, y: 20 }
    /// Creates LLVM struct type from values, builds using insertvalue
    fn emitStructConstruct(self: *LLVMEmitter, node: *const IRNode) !void {
        const count = node.inputs.items.len;
        if (count == 0) {
            // Empty struct - create empty struct type
            var empty_types: [0]llvm.Type = .{};
            const struct_type = llvm.structTypeInContext(self.context, &empty_types, 0, false);
            const undef_struct = llvm.getUndef(struct_type);
            try self.values.put(node.id, undef_struct);

            // Store struct info for field access
            const field_names = switch (node.data) {
                .string => |s| s,
                else => "",
            };
            try self.struct_info.put(node.id, .{
                .llvm_type = struct_type,
                .field_names = field_names,
            });
            return;
        }

        // Collect LLVM types from input values
        var elem_types = try self.allocator.alloc(llvm.Type, count);
        defer self.allocator.free(elem_types);

        for (node.inputs.items, 0..) |input_id, i| {
            const val = self.values.get(input_id) orelse return error.MissingOperand;
            elem_types[i] = llvm.typeof(val);
        }

        // Create anonymous struct type
        const struct_type = llvm.structTypeInContext(self.context, elem_types.ptr, @intCast(count), false);

        // Build struct using insertvalue chain
        var struct_val = llvm.getUndef(struct_type);
        for (node.inputs.items, 0..) |input_id, i| {
            const val = self.values.get(input_id) orelse return error.MissingOperand;
            struct_val = llvm.buildInsertValue(self.builder, struct_val, val, @intCast(i), "struct_field");
        }

        try self.values.put(node.id, struct_val);

        // Store struct info for field access
        const field_names = switch (node.data) {
            .string => |s| s,
            else => "",
        };
        try self.struct_info.put(node.id, .{
            .llvm_type = struct_type,
            .field_names = field_names,
        });
    }

    /// Emit field access: s.field
    /// Uses extractvalue for value-based structs, GEP+Load for alloca-based structs
    fn emitFieldAccess(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const struct_node_id = node.inputs.items[0];

        // Get field name from node data
        const field_name = switch (node.data) {
            .string => |s| s,
            else => return error.InvalidNode,
        };

        // Find field index by looking up struct info
        const info = self.struct_info.get(struct_node_id) orelse {
            std.debug.print("Warning: Struct info not found for node {d}\n", .{struct_node_id});
            return error.MissingOperand;
        };

        // Parse field names (comma-separated) and find index
        var field_idx: u32 = 0;
        var found = false;
        var iter = std.mem.splitScalar(u8, info.field_names, ',');
        while (iter.next()) |name| {
            if (std.mem.eql(u8, name, field_name)) {
                found = true;
                break;
            }
            field_idx += 1;
        }

        if (!found) {
            std.debug.print("Warning: Field '{s}' not found in struct\n", .{field_name});
            return error.InvalidNode;
        }

        // Check if this is a pointer-based struct (Struct_Alloca)
        const struct_val = self.values.get(struct_node_id) orelse return error.MissingOperand;
        const is_alloca = self.alloca_types.contains(struct_node_id);

        if (is_alloca) {
            // Pointer-based: GEP + Load
            const field_ptr = llvm.buildStructGEP2(self.builder, info.llvm_type, struct_val, field_idx, "field_ptr");

            // Get element type for load
            const elem_types = try self.allocator.alloc(llvm.Type, llvm.countStructElementTypes(info.llvm_type));
            defer self.allocator.free(elem_types);
            llvm.getStructElementTypes(info.llvm_type, elem_types.ptr);
            const field_type = elem_types[field_idx];

            const result = llvm.buildLoad2(self.builder, field_type, field_ptr, "field_val");
            try self.values.put(node.id, result);
        } else {
            // Value-based: extractvalue
            const result = llvm.buildExtractValue(self.builder, struct_val, field_idx, "field_val");
            try self.values.put(node.id, result);
        }
    }

    /// Emit struct alloca for mutable structs
    fn emitStructAlloca(self: *LLVMEmitter, node: *const IRNode) !void {
        const count = node.inputs.items.len;

        // Infer types from input values (same as Struct_Construct)
        var elem_types = try self.allocator.alloc(llvm.Type, count);
        defer self.allocator.free(elem_types);

        for (node.inputs.items, 0..) |input_id, i| {
            const val = self.values.get(input_id) orelse return error.MissingOperand;
            elem_types[i] = llvm.typeof(val);
        }

        // Create struct type
        const struct_type = llvm.structTypeInContext(self.context, elem_types.ptr, @intCast(count), false);

        // Alloca for the struct
        const alloca_val = llvm.buildAlloca(self.builder, struct_type, "struct_var");
        try self.values.put(node.id, alloca_val);

        // Mark this as an alloca for field access handling
        try self.alloca_types.put(node.id, {});

        // Store struct info for field access
        const field_names = switch (node.data) {
            .string => |s| s,
            else => "",
        };
        try self.struct_info.put(node.id, .{
            .llvm_type = struct_type,
            .field_names = field_names,
        });
    }

    /// Emit field store: returns GEP pointer for storing to a field
    fn emitFieldStore(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const struct_node_id = node.inputs.items[0];
        const struct_ptr = self.values.get(struct_node_id) orelse return error.MissingOperand;

        // Get field name from node data
        const field_name = switch (node.data) {
            .string => |s| s,
            else => return error.InvalidNode,
        };

        // Find struct info
        const info = self.struct_info.get(struct_node_id) orelse {
            std.debug.print("Warning: Struct info not found for Field_Store\n", .{});
            return error.MissingOperand;
        };

        // Parse field names and find index
        var field_idx: u32 = 0;
        var found = false;
        var iter = std.mem.splitScalar(u8, info.field_names, ',');
        while (iter.next()) |name| {
            if (std.mem.eql(u8, name, field_name)) {
                found = true;
                break;
            }
            field_idx += 1;
        }

        if (!found) {
            std.debug.print("Warning: Field '{s}' not found in struct for store\n", .{field_name});
            return error.InvalidNode;
        }

        // Create GEP to get field pointer
        const field_ptr = llvm.buildStructGEP2(self.builder, info.llvm_type, struct_ptr, field_idx, "field_ptr");
        try self.values.put(node.id, field_ptr);
    }

    // ========================================================================
    // Error Union Emission (:core profile)
    // ========================================================================
    // Error unions are represented as { i8 is_error, i64 value }
    // Similar to optionals but semantics are error handling, not nullability

    /// Get error union struct type: { i8 is_error, i64 value }
    fn getErrorUnionType(self: *LLVMEmitter) llvm.Type {
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);
        var member_types = [_]llvm.Type{ i8_type, i64_type };
        return llvm.structTypeInContext(self.context, &member_types, 2, false);
    }

    /// Emit Error_Union_Construct: creates { 0, value } (ok case)
    fn emitErrorUnionConstruct(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const payload_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const eu_type = self.getErrorUnionType();
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

        // Convert payload to i64 if needed
        const payload_type = llvm.c.LLVMTypeOf(payload_val);
        const value = if (payload_type == i64_type)
            payload_val
        else if (llvm.c.LLVMGetTypeKind(payload_type) == llvm.c.LLVMIntegerTypeKind)
            llvm.c.LLVMBuildZExt(self.builder, payload_val, i64_type, "eu_payload")
        else
            llvm.c.LLVMBuildPtrToInt(self.builder, payload_val, i64_type, "eu_payload_ptr");

        // Create struct with is_error=0, value=payload
        var eu_val = llvm.getUndef(eu_type);
        const zero = llvm.c.LLVMConstInt(i8_type, 0, 0);
        eu_val = llvm.c.LLVMBuildInsertValue(self.builder, eu_val, zero, 0, "eu_ok_tag");
        eu_val = llvm.c.LLVMBuildInsertValue(self.builder, eu_val, value, 1, "eu_ok");

        try self.values.put(node.id, eu_val);
    }

    /// Emit Error_Fail_Construct: creates { 1, error_val } (error case)
    fn emitErrorFailConstruct(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const error_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const eu_type = self.getErrorUnionType();
        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

        // Convert error to i64 if needed
        const error_type = llvm.c.LLVMTypeOf(error_val);
        const value = if (error_type == i64_type)
            error_val
        else if (llvm.c.LLVMGetTypeKind(error_type) == llvm.c.LLVMIntegerTypeKind)
            llvm.c.LLVMBuildZExt(self.builder, error_val, i64_type, "eu_error")
        else
            llvm.c.LLVMBuildPtrToInt(self.builder, error_val, i64_type, "eu_error_ptr");

        // Create struct with is_error=1, value=error
        var eu_val = llvm.getUndef(eu_type);
        const one = llvm.c.LLVMConstInt(i8_type, 1, 0);
        eu_val = llvm.c.LLVMBuildInsertValue(self.builder, eu_val, one, 0, "eu_fail_tag");
        eu_val = llvm.c.LLVMBuildInsertValue(self.builder, eu_val, value, 1, "eu_fail");

        try self.values.put(node.id, eu_val);
    }

    /// Emit Error_Union_Is_Error: returns is_error == 1
    fn emitErrorUnionIsError(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const eu_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const i8_type = llvm.c.LLVMInt8TypeInContext(self.context);

        // Extract is_error tag
        const tag = llvm.c.LLVMBuildExtractValue(self.builder, eu_val, 0, "eu_tag");

        // Compare tag == 1
        const one = llvm.c.LLVMConstInt(i8_type, 1, 0);
        const is_error = llvm.c.LLVMBuildICmp(self.builder, llvm.c.LLVMIntEQ, tag, one, "is_error");

        try self.values.put(node.id, is_error);
    }

    /// Emit Error_Union_Unwrap: extract payload (assumes not error)
    fn emitErrorUnionUnwrap(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const eu_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const i32_type = llvm.int32TypeInContext(self.context);

        // Extract tag and check if it's 0 (ok)
        const tag = llvm.c.LLVMBuildExtractValue(self.builder, eu_val, 0, "eu_tag");

        // TODO: Add panic if tag == 1 (error) - requires control flow
        // For now, just extract the value without checking
        _ = tag;

        // Extract payload and truncate to i32 (assuming i32 for now)
        const payload = llvm.c.LLVMBuildExtractValue(self.builder, eu_val, 1, "eu_payload");
        const result = llvm.c.LLVMBuildTrunc(self.builder, payload, i32_type, "unwrap");

        try self.values.put(node.id, result);
    }

    /// Emit Error_Union_Get_Error: extract error value (assumes is error)
    fn emitErrorUnionGetError(self: *LLVMEmitter, node: *const IRNode) !void {
        if (node.inputs.items.len < 1) return error.MissingOperand;
        const eu_val = self.values.get(node.inputs.items[0]) orelse return error.MissingOperand;

        const i32_type = llvm.int32TypeInContext(self.context);

        // Extract error value
        const error_val = llvm.c.LLVMBuildExtractValue(self.builder, eu_val, 1, "eu_error");
        const result = llvm.c.LLVMBuildTrunc(self.builder, error_val, i32_type, "error");

        try self.values.put(node.id, result);
    }

    // =========================================================================
    // :service Profile - Structured Concurrency (Blocking Model Phase 1)
    // =========================================================================
    //
    // Phase 1 implementation uses a BLOCKING MODEL where:
    // - async func = regular function (no actual suspension)
    // - await = pass-through (value already computed)
    // - spawn = immediate call (no actual concurrent execution)
    // - nursery = scope markers only
    //
    // This allows the full :service syntax to work end-to-end while
    // maintaining correct semantics for single-threaded execution.
    // Real concurrency will be added in Phase 2 using std.Thread or coroutines.
    // =========================================================================

    /// Emit Await: In blocking model, await just passes through the result
    /// The awaited expression (Async_Call) already produced the value synchronously
    fn emitAwait(self: *LLVMEmitter, node: *const IRNode) !void {
        // Await takes one input: the result of an async operation (Async_Call/Spawn)
        if (node.inputs.items.len < 1) {
            // No input means void await - just a no-op
            return;
        }

        // In blocking model, the async operation already completed and stored its result
        // We just pass through that result
        const awaited_value = self.values.get(node.inputs.items[0]) orelse {
            // If no value exists, this might be a void-returning async call
            return;
        };

        // Map this node's id to the awaited value
        try self.values.put(node.id, awaited_value);
    }

    /// Emit Spawn: Phase 2.3/2.4 - True parallel execution
    /// - No args: use janus_nursery_spawn_noarg (simple path)
    /// - With args: generate thunk that unpacks args and calls target
    fn emitSpawn(self: *LLVMEmitter, node: *const IRNode) !void {
        // Check if current block is already terminated
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return;
        }

        // Get function name from node data
        const func_name = switch (node.data) {
            .string => |s| s,
            else => {
                std.debug.print("Warning: Spawn node missing function name\n", .{});
                return;
            },
        };

        // Get the target function
        const target_func = llvm.c.LLVMGetNamedFunction(self.module, func_name.ptr);
        if (target_func == null) {
            std.debug.print("Warning: Spawn target function '{s}' not found\n", .{func_name});
            return;
        }

        const ptr_type = llvm.c.LLVMPointerTypeInContext(self.context, 0);
        const i32_type = llvm.c.LLVMInt32TypeInContext(self.context);

        // Check if we have arguments
        if (node.inputs.items.len == 0) {
            // No arguments - use simple spawn_noarg
            const spawn_fn = self.getOrDeclareExternFn(
                "janus_nursery_spawn_noarg",
                i32_type,
                &[_]llvm.Type{ptr_type},
            );

            var spawn_args = [_]llvm.Value{target_func};
            const spawn_result = llvm.c.LLVMBuildCall2(
                self.builder,
                llvm.c.LLVMGlobalGetValueType(spawn_fn),
                spawn_fn,
                &spawn_args,
                1,
                "spawn_result",
            );
            try self.values.put(node.id, spawn_result);
        } else {
            // With arguments - generate thunk and args struct
            try self.emitSpawnWithArgs(node, target_func, func_name);
        }
    }

    /// Emit spawn with arguments: generates thunk function and args struct
    fn emitSpawnWithArgs(
        self: *LLVMEmitter,
        node: *const IRNode,
        target_func: llvm.Value,
        func_name: [:0]const u8,
    ) !void {
        const ptr_type = llvm.c.LLVMPointerTypeInContext(self.context, 0);
        const i32_type = llvm.c.LLVMInt32TypeInContext(self.context);
        const i64_type = llvm.c.LLVMInt64TypeInContext(self.context);

        // Get argument LLVM values
        var arg_values: [16]llvm.Value = undefined; // Max 16 args for now
        var arg_types: [16]llvm.Type = undefined;
        const arg_count = @min(node.inputs.items.len, 16);

        for (node.inputs.items[0..arg_count], 0..) |input_id, i| {
            const val = self.values.get(input_id) orelse {
                std.debug.print("Warning: Spawn arg {d} not found\n", .{i});
                return;
            };
            arg_values[i] = val;
            arg_types[i] = llvm.c.LLVMTypeOf(val);
        }

        // Create args struct type: { arg0_type, arg1_type, ... }
        const args_struct_type = llvm.c.LLVMStructTypeInContext(
            self.context,
            @ptrCast(&arg_types),
            @intCast(arg_count),
            0, // not packed
        );

        // Allocate args struct on stack
        const args_alloca = llvm.c.LLVMBuildAlloca(self.builder, args_struct_type, "spawn_args");

        // Store each argument into the struct
        for (0..arg_count) |i| {
            const idx = llvm.c.LLVMConstInt(llvm.c.LLVMInt32TypeInContext(self.context), 0, 0);
            const field_idx = llvm.c.LLVMConstInt(llvm.c.LLVMInt32TypeInContext(self.context), @intCast(i), 0);
            var indices = [_]llvm.Value{ idx, field_idx };
            const field_ptr = llvm.c.LLVMBuildGEP2(
                self.builder,
                args_struct_type,
                args_alloca,
                &indices,
                2,
                "arg_ptr",
            );
            _ = llvm.c.LLVMBuildStore(self.builder, arg_values[i], field_ptr);
        }

        // Generate thunk function name using stack buffer
        var thunk_name_buf: [128]u8 = undefined;
        const thunk_name = std.fmt.bufPrintZ(&thunk_name_buf, "__spawn_thunk_{s}_{d}", .{ func_name, node.id }) catch "__spawn_thunk";

        // Create thunk function type: fn(ptr) -> i64
        var thunk_param_types = [_]llvm.Type{ptr_type};
        const thunk_func_type = llvm.c.LLVMFunctionType(i64_type, &thunk_param_types, 1, 0);

        // Create thunk function
        const thunk_func = llvm.c.LLVMAddFunction(self.module, thunk_name.ptr, thunk_func_type);
        llvm.c.LLVMSetLinkage(thunk_func, llvm.c.LLVMInternalLinkage);

        // Save current insert point
        const saved_block = llvm.c.LLVMGetInsertBlock(self.builder);
        const saved_func = self.current_function;

        // Build thunk body
        const thunk_entry = llvm.c.LLVMAppendBasicBlockInContext(self.context, thunk_func, "entry");
        llvm.c.LLVMPositionBuilderAtEnd(self.builder, thunk_entry);

        // Get args struct pointer (first parameter)
        const args_param = llvm.c.LLVMGetParam(thunk_func, 0);

        // Load each argument from the struct
        var call_args: [16]llvm.Value = undefined;
        for (0..arg_count) |i| {
            const idx = llvm.c.LLVMConstInt(llvm.c.LLVMInt32TypeInContext(self.context), 0, 0);
            const field_idx = llvm.c.LLVMConstInt(llvm.c.LLVMInt32TypeInContext(self.context), @intCast(i), 0);
            var indices = [_]llvm.Value{ idx, field_idx };
            const field_ptr = llvm.c.LLVMBuildGEP2(
                self.builder,
                args_struct_type,
                args_param,
                &indices,
                2,
                "arg_load_ptr",
            );
            call_args[i] = llvm.c.LLVMBuildLoad2(self.builder, arg_types[i], field_ptr, "arg");
        }

        // Call the target function with unpacked arguments
        const target_func_type = llvm.c.LLVMGlobalGetValueType(target_func);
        const call_result = llvm.c.LLVMBuildCall2(
            self.builder,
            target_func_type,
            target_func,
            @ptrCast(&call_args),
            @intCast(arg_count),
            "result",
        );

        // Convert result to i64 for TaskFn signature
        const target_ret_type = llvm.c.LLVMGetReturnType(target_func_type);
        const target_ret_kind = llvm.c.LLVMGetTypeKind(target_ret_type);

        const return_val = if (target_ret_kind == llvm.c.LLVMVoidTypeKind)
            llvm.c.LLVMConstInt(i64_type, 0, 0)
        else if (target_ret_kind == llvm.c.LLVMIntegerTypeKind)
            llvm.c.LLVMBuildSExt(self.builder, call_result, i64_type, "sext")
        else
            llvm.c.LLVMConstInt(i64_type, 0, 0);

        _ = llvm.c.LLVMBuildRet(self.builder, return_val);

        // Restore insert point
        llvm.c.LLVMPositionBuilderAtEnd(self.builder, saved_block);
        self.current_function = saved_func;

        // Call janus_nursery_spawn(thunk, args_ptr)
        const spawn_fn = self.getOrDeclareExternFn(
            "janus_nursery_spawn",
            i32_type,
            &[_]llvm.Type{ ptr_type, ptr_type },
        );

        var spawn_args = [_]llvm.Value{ thunk_func, args_alloca };
        const spawn_result = llvm.c.LLVMBuildCall2(
            self.builder,
            llvm.c.LLVMGlobalGetValueType(spawn_fn),
            spawn_fn,
            &spawn_args,
            2,
            "spawn_result",
        );

        try self.values.put(node.id, spawn_result);
    }

    /// Emit Nursery_Begin: Initialize nursery scope for structured concurrency
    /// Phase 2: Calls janus_nursery_create() to set up task tracking
    fn emitNurseryBegin(self: *LLVMEmitter, node: *const IRNode) !void {
        _ = node;

        // Check if current block is already terminated (e.g., by early return)
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return; // Block already terminated, skip
        }

        // Declare janus_nursery_create if not already declared
        const create_fn = self.getOrDeclareExternFn(
            "janus_nursery_create",
            llvm.c.LLVMPointerTypeInContext(self.context, 0), // returns ptr (opaque nursery handle)
            &[_]llvm.Type{}, // no params
        );

        // Call janus_nursery_create()
        const nursery_handle = llvm.c.LLVMBuildCall2(
            self.builder,
            llvm.c.LLVMGlobalGetValueType(create_fn),
            create_fn,
            null,
            0,
            "nursery",
        );

        // Store nursery handle for potential use (e.g., passing to spawn)
        // For now, we use thread-local stack in runtime, so handle is implicit
        _ = nursery_handle;
    }

    /// Emit Nursery_End: Wait for all tasks and cleanup
    /// Phase 2: Calls janus_nursery_await_all() to join all spawned tasks
    fn emitNurseryEnd(self: *LLVMEmitter, node: *const IRNode) !void {
        _ = node;

        // Check if current block is already terminated (e.g., by early return)
        const current_block = llvm.c.LLVMGetInsertBlock(self.builder);
        if (current_block != null) {
            const terminator = llvm.c.LLVMGetBasicBlockTerminator(current_block);
            if (terminator != null) return; // Block already terminated, skip
        }

        // Declare janus_nursery_await_all if not already declared
        const await_fn = self.getOrDeclareExternFn(
            "janus_nursery_await_all",
            llvm.c.LLVMInt64TypeInContext(self.context), // returns i64 (error code)
            &[_]llvm.Type{}, // no params (uses thread-local nursery stack)
        );

        // Call janus_nursery_await_all()
        _ = llvm.c.LLVMBuildCall2(
            self.builder,
            llvm.c.LLVMGlobalGetValueType(await_fn),
            await_fn,
            null,
            0,
            "nursery_result",
        );
    }

    /// Helper: Get or declare an external function
    fn getOrDeclareExternFn(
        self: *LLVMEmitter,
        name: [*:0]const u8,
        ret_type: llvm.Type,
        param_types: []const llvm.Type,
    ) llvm.Value {
        // Check if already declared
        const existing = llvm.c.LLVMGetNamedFunction(self.module, name);
        if (existing != null) return existing;

        // Declare the function
        const func_type = llvm.c.LLVMFunctionType(
            ret_type,
            @constCast(param_types.ptr),
            @intCast(param_types.len),
            0, // not variadic
        );
        return llvm.c.LLVMAddFunction(self.module, name, func_type);
    }

    /// Emit Async_Call: In blocking model, just emit a regular function call
    /// The function executes synchronously and returns its result immediately
    fn emitAsyncCall(self: *LLVMEmitter, node: *const IRNode) !void {
        // Async_Call behaves exactly like a regular Call in blocking model
        // The function name is stored in node.data.string
        // Arguments are in node.inputs

        const func_name = switch (node.data) {
            .string => |s| s,
            else => return error.InvalidAsyncCall,
        };

        // Check if it's a user-defined function (starts with "user_")
        if (std.mem.startsWith(u8, func_name, "user_")) {
            // User-defined function - emit direct call
            try self.emitUserAsyncCall(node, func_name);
        } else {
            // Intrinsic or extern function - emit as regular call
            // For now, just treat it like a regular Call
            try self.emitCall(node);
        }
    }

    /// Helper: Emit call to user-defined async function
    fn emitUserAsyncCall(self: *LLVMEmitter, node: *const IRNode, func_name: []const u8) !void {
        // Get the function from the module
        const func_name_z = try self.allocator.dupeZ(u8, func_name);
        defer self.allocator.free(func_name_z);

        const func = llvm.c.LLVMGetNamedFunction(self.module, func_name_z.ptr);
        if (func == null) {
            std.debug.print("Warning: Async function not found: {s}\n", .{func_name});
            return error.FunctionNotFound;
        }

        // Get the function type
        const func_type = llvm.c.LLVMGlobalGetValueType(func);

        // Build argument list
        var args: std.ArrayList(llvm.Value) = .empty;
        defer args.deinit(self.allocator);

        for (node.inputs.items) |input_id| {
            if (self.values.get(input_id)) |val| {
                try args.append(self.allocator, val);
            }
        }

        // Emit the call
        const result = llvm.c.LLVMBuildCall2(
            self.builder,
            func_type,
            func,
            args.items.ptr,
            @intCast(args.items.len),
            "async_call",
        );

        // Store the result if the function returns a value
        const return_type = llvm.c.LLVMGetReturnType(func_type);
        if (llvm.c.LLVMGetTypeKind(return_type) != llvm.c.LLVMVoidTypeKind) {
            try self.values.put(node.id, result);
        }
    }
};
