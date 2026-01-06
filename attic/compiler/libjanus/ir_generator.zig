// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

const std = @import("std");
const astdb_core = @import("astdb_core");
const ArrayList = std.array_list.Managed;
const astdb = @import("libjanus_astdb");
const janus_parser = @import("janus_parser");
const AstDB = astdb_core.AstDB;
const Snapshot = janus_parser.Snapshot;
const NodeId = astdb_core.NodeId;
const DeclId = astdb_core.DeclId;
const ScopeId = astdb_core.ScopeId;
const UnitId = astdb_core.UnitId;
const StrId = astdb_core.StrId;
const AstNode = astdb_core.AstNode;
const Decl = astdb_core.Decl;
const Token = astdb_core.Token;

// Error types for IR generation
const IRGeneratorError = error{
    OutOfMemory,
    InvalidNode,
    MissingDeclaration,
    UnsupportedOperation,
    InvalidFunctionDecl,
    NotAFunction,
    InvalidFunctionNode,
    InvalidAst,
};

// Revolutionary IR Generation - The Transmutation Engine
// Task: Phase 4 - Implement Q.IROf - Convert semantic truth to executable reality
// Requirements: Transform validated ASTDB into backend-agnostic intermediate representation

/// Core IR for Janus functions - Backend-agnostic representation
pub const JanusIR = struct {
    function_id: DeclId,
    function_name: []const u8,
    parameters: []Parameter,
    return_type: TypeRef,
    basic_blocks: []BasicBlock,
    source_location: astdb_core.SourceSpan,

    pub const Parameter = struct {
        name: []const u8,
        type_ref: TypeRef,
        param_index: u32,
    };

    pub const TypeRef = struct {
        name: []const u8,
        size_bytes: u32,
        alignment: u32,
        is_primitive: bool,
    };

    pub const BasicBlock = struct {
        id: u32,
        label: []const u8,
        instructions: []Instruction,
        terminator: ?Terminator,
    };

    pub const Instruction = union(enum) {
        load_param: LoadParam,
        load_constant: LoadConstant,
        binary_op: BinaryOp,
        call: Call,
        store: Store,
        alloc_struct: AllocStruct,
        get_field: GetField,
        set_field: SetField,
        load_local: LoadLocal,
        alloca: Alloca,

        pub const LoadParam = struct {
            dest_reg: u32,
            param_index: u32,
        };

        pub const LoadConstant = struct {
            dest_reg: u32,
            value: ConstantValue,
        };

        pub const LoadLocal = struct {
            dest_reg: u32,
            local_index: u32,
        };

        pub const Alloca = struct {
            local_index: u32,
            type_size: u32,
        };

        pub const BinaryOp = struct {
            dest_reg: u32,
            op: BinaryOpKind,
            left_reg: u32,
            right_reg: u32,
        };

        pub const Call = struct {
            dest_reg: ?u32, // null for void functions
            function_name: []const u8,
            args: []u32, // register numbers
        };

        pub const Store = struct {
            source_reg: u32,
            dest_location: StoreLocation,
        };

        pub const StoreLocation = union(enum) {
            return_slot: void,
            local_var: u32,
        };

        pub const AllocStruct = struct {
            dest_reg: u32,
            struct_name: []const u8,
        };

        pub const GetField = struct {
            dest_reg: u32,
            struct_reg: u32,
            field_name: []const u8,
        };

        pub const SetField = struct {
            struct_reg: u32,
            field_name: []const u8,
            value_reg: u32,
        };
    };

    pub const ConstantValue = union(enum) {
        integer: i64,
        float: f64,
        string: []const u8,
        boolean: bool,
    };

    pub const BinaryOpKind = enum {
        add,
        sub,
        mul,
        div,
        mod,
        eq,
        ne,
        lt,
        le,
        gt,
        ge,
        logical_and,
        logical_or,
    };

    pub const Terminator = union(enum) {
        return_value: u32, // register containing return value
        return_void: void,
        branch: Branch,
        conditional_branch: ConditionalBranch,

        pub const Branch = struct {
            target_block: u32,
        };

        pub const ConditionalBranch = struct {
            condition_reg: u32,
            true_block: u32,
            false_block: u32,
        };
    };

    pub fn deinit(self: *JanusIR, allocator: std.mem.Allocator) void {
        allocator.free(self.parameters);
        for (self.basic_blocks) |*block| {
            allocator.free(block.instructions);
        }
        allocator.free(self.basic_blocks);
    }
};

/// IR Generation Engine - The Transmutation Core
pub const IRGenerator = struct {
    allocator: std.mem.Allocator,
    snapshot: *Snapshot,
    astdb: *AstDB,

    // IR generation state
    next_register: u32,
    next_block_id: u32,
    current_block_id: u32,
    current_block_label: []const u8,
    current_instructions: ArrayList(JanusIR.Instruction),
    current_blocks: ArrayList(JanusIR.BasicBlock),
    variable_map: std.AutoHashMap(StrId, u32),
    next_local_index: u32,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        snapshot: *Snapshot,
        database: *AstDB,
    ) !Self {
        return Self{
            .allocator = allocator,
            .snapshot = snapshot,
            .astdb = database,
            .next_register = 0,
            .next_block_id = 0,
            .current_block_id = 0,
            .current_block_label = "entry",
            .current_instructions = ArrayList(JanusIR.Instruction).init(allocator),
            .current_blocks = ArrayList(JanusIR.BasicBlock).init(allocator),
            .variable_map = std.AutoHashMap(StrId, u32).init(allocator),
            .next_local_index = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.current_instructions.deinit();
        self.current_blocks.deinit();
        self.variable_map.deinit();
    }

    /// Q.IROf - The Creator Query
    /// Transmutes a validated function declaration into executable IR
    pub fn generateIR(self: *Self, unit_id: UnitId, function_decl_id: DeclId) IRGeneratorError!JanusIR {
        // Reset generation state
        self.next_register = 0;
        self.next_block_id = 1; // entry is 0, so next starts at 1
        self.current_block_id = 0;
        self.current_block_label = "entry";
        self.current_instructions.clearRetainingCapacity();
        self.current_blocks.clearRetainingCapacity();
        self.variable_map.clearRetainingCapacity();
        self.next_local_index = 0;

        // Get function declaration from ASTDB
        const function_decl = self.snapshot.core_snapshot.getDecl(unit_id, function_decl_id) orelse {
            return error.InvalidFunctionDecl;
        };

        if (function_decl.kind != .function) {
            return error.NotAFunction;
        }

        // Get function node
        const function_node = self.snapshot.getNode(function_decl.node) orelse {
            return error.InvalidFunctionNode;
        };

        // Extract function information
        const function_name = self.astdb.getString(function_decl.name);

        // Generate parameters
        const parameters = try self.generateParameters(function_node);

        // Generate function body
        try self.generateFunctionBody(function_node);

        // Finalize the last block (could be entry or a merge block)
        try self.terminateBlock(JanusIR.Terminator{ .return_void = {} });

        // Create source location
        const source_location = astdb_core.SourceSpan{
            .start = 0, // TODO: Get actual span from ASTDB
            .end = 0,
            .line = 1,
            .column = 1,
        };

        return JanusIR{
            .function_id = function_decl_id,
            .function_name = function_name,
            .parameters = parameters,
            .return_type = JanusIR.TypeRef{
                .name = "void", // TODO: Extract actual return type
                .size_bytes = 0,
                .alignment = 1,
                .is_primitive = true,
            },
            .basic_blocks = try self.current_blocks.toOwnedSlice(),
            .source_location = source_location,
        };
    }

    /// Generate parameter list from function node
    fn generateParameters(self: *Self, function_node: *const AstNode) IRGeneratorError![]JanusIR.Parameter {
        var parameters = ArrayList(JanusIR.Parameter).init(self.allocator);
        defer parameters.deinit();

        // Find parameter list in function node children
        const children = function_node.children(&self.snapshot.core_snapshot);
        for (children) |child_id| {
            const child_node = self.snapshot.getNode(child_id) orelse continue;

            if (child_node.kind == .parameter) {
                const param = try self.generateParameter(child_node, @intCast(parameters.items.len));
                try parameters.append(param);
            }
        }

        return try parameters.toOwnedSlice();
    }

    /// Generate a single parameter
    fn generateParameter(self: *Self, param_node: *const AstNode, index: u32) IRGeneratorError!JanusIR.Parameter {
        // Extract parameter name (first child should be identifier)
        var param_name: []const u8 = "param";

        const param_children = param_node.children(&self.snapshot.core_snapshot);
        if (param_children.len > 0) {
            const name_node = self.snapshot.getNode(param_children[0]);
            if (name_node) |node| {
                if (node.kind == .identifier) {
                    const token = self.snapshot.core_snapshot.getToken(node.first_token);
                    if (token) |tok| {
                        if (tok.str) |str_id| {
                            param_name = self.astdb.getString(str_id);
                        }
                    }
                }
            }
        }

        return JanusIR.Parameter{
            .name = param_name,
            .type_ref = JanusIR.TypeRef{
                .name = "i32", // TODO: Extract actual type
                .size_bytes = 4,
                .alignment = 4,
                .is_primitive = true,
            },
            .param_index = index,
        };
    }

    /// Generate IR for function body
    fn generateFunctionBody(self: *Self, function_node: *const AstNode) IRGeneratorError!void {
        const children = function_node.children(&self.snapshot.core_snapshot);
        for (children) |child_id| {
            const child_node = self.snapshot.getNode(child_id) orelse continue;

            // Skip parameters as they are handled in generateParameters
            if (child_node.kind == .parameter) continue;

            // Generate statement
            try self.generateStatement(child_node);
        }
    }

    /// Generate IR for a block statement
    fn generateBlock(self: *Self, block_node: *const AstNode) IRGeneratorError!void {
        // Process each statement in the block
        const children = block_node.children(&self.snapshot.core_snapshot);
        for (children) |stmt_id| {
            const stmt_node = self.snapshot.getNode(stmt_id) orelse continue;
            try self.generateStatement(stmt_node);
        }
    }

    /// Generate IR for a statement
    fn generateStatement(self: *Self, stmt_node: *const AstNode) IRGeneratorError!void {
        switch (stmt_node.kind) {
            .return_stmt => try self.generateReturnStatement(stmt_node),
            .expr_stmt => try self.generateExpressionStatement(stmt_node),
            .let_stmt, .var_stmt => try self.generateVariableDeclaration(stmt_node),
            .if_stmt => try self.generateIfStatement(stmt_node),
            .while_stmt => try self.generateWhileStatement(stmt_node),
            .identifier => {}, // Skip function name or other identifiers at block level
            else => {
                // Skip unsupported statement types for now
            },
        }
    }

    /// Generate IR for return statement
    fn generateReturnStatement(self: *Self, return_node: *const AstNode) IRGeneratorError!void {
        const return_children = return_node.children(&self.snapshot.core_snapshot);
        if (return_children.len > 0) {
            // Return with value
            const expr_node = self.snapshot.getNode(return_children[0]) orelse return;
            const result_reg = try self.generateExpression(expr_node);

            // Terminate current block with return_value
            try self.terminateBlock(JanusIR.Terminator{
                .return_value = result_reg,
            });
        } else {
            // Return void
            try self.terminateBlock(JanusIR.Terminator{
                .return_void = {},
            });
        }

        // Start a new block for any subsequent unreachable code
        // This prevents 'instruction after terminator' errors
        const next_id = self.allocateBlockId();
        try self.startBlock(next_id, "unreachable");
    }

    /// Generate IR for expression statement
    fn generateExpressionStatement(self: *Self, expr_stmt_node: *const AstNode) IRGeneratorError!void {
        const expr_stmt_children = expr_stmt_node.children(&self.snapshot.core_snapshot);
        if (expr_stmt_children.len > 0) {
            const expr_node = self.snapshot.getNode(expr_stmt_children[0]) orelse return;
            _ = try self.generateExpression(expr_node);
        }
    }

    /// Generate IR for variable declaration
    fn generateVariableDeclaration(self: *Self, var_decl_node: *const AstNode) IRGeneratorError!void {
        const children = var_decl_node.children(&self.snapshot.core_snapshot);
        if (children.len < 2) return error.InvalidAst; // Need Identifier and Initializer

        const id_node = self.snapshot.getNode(children[0]) orelse return error.InvalidAst;
        const init_node = self.snapshot.getNode(children[1]) orelse return error.InvalidAst;

        if (id_node.kind != .identifier) return error.InvalidAst;

        // 1. Generate initializer expression
        const init_reg = try self.generateExpression(init_node);

        // 2. Allocate local index
        const local_index = self.next_local_index;
        self.next_local_index += 1;

        // 3. Register variable mapping
        // Extract StrId from identifier token
        const token = self.snapshot.core_snapshot.getToken(id_node.first_token) orelse return error.InvalidAst;
        const str_id = token.str orelse return error.InvalidAst;

        try self.variable_map.put(str_id, local_index);

        // 4. Emit alloca instruction
        try self.current_instructions.append(JanusIR.Instruction{
            .alloca = JanusIR.Instruction.Alloca{
                .local_index = local_index,
                .type_size = 8, // Assuming 64-bit for now
            },
        });

        // 5. Emit store instruction
        try self.current_instructions.append(JanusIR.Instruction{
            .store = JanusIR.Instruction.Store{
                .source_reg = init_reg,
                .dest_location = JanusIR.Instruction.StoreLocation{ .local_var = local_index },
            },
        });
    }

    /// Generate IR for if statement
    fn generateIfStatement(self: *Self, if_node: *const AstNode) IRGeneratorError!void {
        const children = if_node.children(&self.snapshot.core_snapshot);
        if (children.len < 2) return error.InvalidAst;

        const cond_node = self.snapshot.getNode(children[0]) orelse return error.InvalidAst;
        const then_node = self.snapshot.getNode(children[1]) orelse return error.InvalidAst;

        // Generate condition
        const cond_reg = try self.generateExpression(cond_node);

        // Create block IDs
        const then_block_id = self.next_block_id;
        self.next_block_id += 1;

        var else_block_id: ?u32 = null;
        var merge_block_id: u32 = 0;

        const has_else = children.len >= 3;
        if (has_else) {
            else_block_id = self.next_block_id;
            self.next_block_id += 1;
        }

        merge_block_id = self.next_block_id;
        self.next_block_id += 1;

        // Terminate current block with conditional branch
        try self.terminateBlock(JanusIR.Terminator{
            .conditional_branch = JanusIR.Terminator.ConditionalBranch{
                .condition_reg = cond_reg,
                .true_block = then_block_id,
                .false_block = if (else_block_id) |id| id else merge_block_id,
            },
        });

        // Generate THEN block
        try self.startBlock(then_block_id, "if_then");
        if (then_node.kind == .block_stmt) {
            try self.generateBlock(then_node);
        } else {
            try self.generateStatement(then_node);
        }

        // Terminate THEN block (if not already terminated explicitly, e.g. by return)
        // verify if the block already has a terminator?
        // For now, we assume simple control flow without early returns in branches for this MVP
        try self.terminateBlock(JanusIR.Terminator{
            .branch = JanusIR.Terminator.Branch{ .target_block = merge_block_id },
        });

        // Generate ELSE block if present
        if (has_else) {
            if (else_block_id) |id| {
                const else_node = self.snapshot.getNode(children[2]) orelse return error.InvalidAst;
                try self.startBlock(id, "if_else");
                if (else_node.kind == .block_stmt) {
                    try self.generateBlock(else_node);
                } else {
                    try self.generateStatement(else_node);
                }
                try self.terminateBlock(JanusIR.Terminator{
                    .branch = JanusIR.Terminator.Branch{ .target_block = merge_block_id },
                });
            }
        }

        // Start MERGE block
        try self.startBlock(merge_block_id, "if_merge");
    }

    /// Generate IR for while statement
    fn generateWhileStatement(self: *Self, while_node: *const AstNode) IRGeneratorError!void {
        const children = while_node.children(&self.snapshot.core_snapshot);
        if (children.len < 2) return error.InvalidAst;

        const cond_node = self.snapshot.getNode(children[0]) orelse return error.InvalidAst;
        const body_node = self.snapshot.getNode(children[1]) orelse return error.InvalidAst;

        // Create block IDs
        const header_block_id = self.allocateBlockId();
        const body_block_id = self.allocateBlockId();
        const exit_block_id = self.allocateBlockId();

        // Terminate current block with jump to header
        try self.terminateBlock(JanusIR.Terminator{
            .branch = JanusIR.Terminator.Branch{ .target_block = header_block_id },
        });

        // Generate HEADER block (condition evaluation)
        try self.startBlock(header_block_id, "while_header");
        const cond_reg = try self.generateExpression(cond_node);
        try self.terminateBlock(JanusIR.Terminator{
            .conditional_branch = JanusIR.Terminator.ConditionalBranch{
                .condition_reg = cond_reg,
                .true_block = body_block_id,
                .false_block = exit_block_id,
            },
        });

        // Generate BODY block
        try self.startBlock(body_block_id, "while_body");
        if (body_node.kind == .block_stmt) {
            try self.generateBlock(body_node);
        } else {
            try self.generateStatement(body_node);
        }
        // Back-edge: Jump back to header
        try self.terminateBlock(JanusIR.Terminator{
            .branch = JanusIR.Terminator.Branch{ .target_block = header_block_id },
        });

        // Start EXIT block
        try self.startBlock(exit_block_id, "while_exit");
    }

    /// Start a new basic block
    fn startBlock(self: *Self, id: u32, label: []const u8) !void {
        self.current_block_id = id;
        self.current_block_label = label;
        self.current_instructions.clearRetainingCapacity();
    }

    /// Terminate current basic block
    fn terminateBlock(self: *Self, terminator: JanusIR.Terminator) !void {
        // If instructions is empty and this isn't the first block, we might want to elide?
        // But for MVP, just emit.

        const block = JanusIR.BasicBlock{
            .id = self.current_block_id,
            .label = self.current_block_label,
            .instructions = try self.current_instructions.toOwnedSlice(),
            .terminator = terminator,
        };
        try self.current_blocks.append(block);

        // Prepare for next block (cleanup happens in startBlock or init)
        self.current_instructions.clearRetainingCapacity();
    }

    /// Generate IR for an expression, returns the register containing the result
    fn generateExpression(self: *Self, expr_node: *const AstNode) IRGeneratorError!u32 {
        switch (expr_node.kind) {
            .integer_literal => return try self.generateIntegerLiteral(expr_node),
            .identifier => return try self.generateIdentifier(expr_node),
            .binary_expr => return try self.generateBinaryExpression(expr_node),
            .call_expr => return try self.generateFunctionCall(expr_node),
            .struct_literal => return try self.generateStructLiteral(expr_node),
            .field_expr => return try self.generateFieldAccess(expr_node),
            else => {
                std.debug.print("Unsupported expression type: {}\n", .{expr_node.kind});
                return self.allocateRegister();
            },
        }
    }

    /// Generate IR for integer literal
    fn generateIntegerLiteral(self: *Self, literal_node: *const AstNode) IRGeneratorError!u32 {
        const dest_reg = self.allocateRegister();

        // Extract integer value (simplified - assumes valid integer)
        const token = self.snapshot.core_snapshot.getToken(literal_node.first_token);
        const value: i64 = if (token) |tok| blk: {
            if (tok.str) |str_id| {
                const literal_str = self.astdb.getString(str_id);
                break :blk std.fmt.parseInt(i64, literal_str, 10) catch 0;
            } else {
                break :blk 0;
            }
        } else 0;

        try self.current_instructions.append(JanusIR.Instruction{
            .load_constant = JanusIR.Instruction.LoadConstant{
                .dest_reg = dest_reg,
                .value = JanusIR.ConstantValue{ .integer = value },
            },
        });

        return dest_reg;
    }

    /// Generate IR for identifier (variable/parameter reference)
    fn generateIdentifier(self: *Self, identifier_node: *const AstNode) IRGeneratorError!u32 {
        const dest_reg = self.allocateRegister();

        // 1. Get Identifier StrId
        const token = self.snapshot.core_snapshot.getToken(identifier_node.first_token) orelse return error.InvalidAst;
        const str_id = token.str orelse return error.InvalidAst;

        // 2. Check Local Variables
        if (self.variable_map.get(str_id)) |local_index| {
            try self.current_instructions.append(JanusIR.Instruction{
                .load_local = JanusIR.Instruction.LoadLocal{
                    .dest_reg = dest_reg,
                    .local_index = local_index,
                },
            });
            return dest_reg;
        }

        // 3. Fallback to parameters (Simplified: Assume all other identifiers are param 0 or specific params if we tracked them)
        // For now, if not local, treat as param 0 (Legacy/Test behavior) or we could try to look up generic parameters.
        try self.current_instructions.append(JanusIR.Instruction{
            .load_param = JanusIR.Instruction.LoadParam{
                .dest_reg = dest_reg,
                .param_index = 0,
            },
        });

        return dest_reg;
    }

    /// Generate IR for binary expression
    fn generateBinaryExpression(self: *Self, binary_node: *const AstNode) IRGeneratorError!u32 {
        const binary_children = binary_node.children(&self.snapshot.core_snapshot);
        if (binary_children.len < 2) return self.allocateRegister();

        const left_node = self.snapshot.getNode(binary_children[0]) orelse return self.allocateRegister();
        const right_node = self.snapshot.getNode(binary_children[1]) orelse return self.allocateRegister();

        const left_reg = try self.generateExpression(left_node);
        const right_reg = try self.generateExpression(right_node);
        const dest_reg = self.allocateRegister();

        // Determine operation type (simplified)
        const op_kind = JanusIR.BinaryOpKind.add; // TODO: Extract actual operator

        try self.current_instructions.append(JanusIR.Instruction{
            .binary_op = JanusIR.Instruction.BinaryOp{
                .dest_reg = dest_reg,
                .op = op_kind,
                .left_reg = left_reg,
                .right_reg = right_reg,
            },
        });

        return dest_reg;
    }

    /// Generate IR for function call
    fn generateFunctionCall(self: *Self, call_node: *const AstNode) IRGeneratorError!u32 {
        const dest_reg = self.allocateRegister();

        // Extract function name (first child should be identifier)
        var function_name: []const u8 = "unknown";
        const call_children = call_node.children(&self.snapshot.core_snapshot);
        if (call_children.len > 0) {
            const name_node = self.snapshot.getNode(call_children[0]);
            if (name_node) |node| {
                if (node.kind == .identifier) {
                    const token = self.snapshot.core_snapshot.getToken(node.first_token);
                    if (token) |tok| {
                        if (tok.str) |str_id| {
                            function_name = self.astdb.getString(str_id);
                        }
                    }
                }
            }
        }

        // Generate arguments (simplified - no arguments for now)
        const args = try self.allocator.alloc(u32, 0);

        try self.current_instructions.append(JanusIR.Instruction{
            .call = JanusIR.Instruction.Call{
                .dest_reg = dest_reg,
                .function_name = function_name,
                .args = args,
            },
        });

        return dest_reg;
    }

    /// Generate IR for struct literal
    fn generateStructLiteral(self: *Self, struct_node: *const AstNode) IRGeneratorError!u32 {
        const dest_reg = self.allocateRegister();

        // extract struct name (first child)
        const children = struct_node.children(&self.snapshot.core_snapshot);
        if (children.len == 0) return error.InvalidNode;

        var struct_name: []const u8 = "Anonymous";
        const name_node = self.snapshot.getNode(children[0]) orelse return error.InvalidNode;
        if (name_node.kind == .identifier) {
            const token = self.snapshot.core_snapshot.getToken(name_node.first_token);
            if (token) |tok| {
                if (tok.str) |str_id| {
                    struct_name = self.astdb.getString(str_id);
                }
            }
        }

        // Emit AllocStruct
        try self.current_instructions.append(JanusIR.Instruction{
            .alloc_struct = JanusIR.Instruction.AllocStruct{
                .dest_reg = dest_reg,
                .struct_name = struct_name,
            },
        });

        // Initialize fields
        // Children layout: [NameNode, FieldName1, Val1, FieldName2, Val2...]
        var i: usize = 1;
        while (i < children.len) : (i += 2) {
            if (i + 1 >= children.len) break;
            const field_name_node = self.snapshot.getNode(children[i]) orelse continue;
            const val_node = self.snapshot.getNode(children[i + 1]) orelse continue;

            // Extract field name
            var field_name: []const u8 = "";
            const token = self.snapshot.core_snapshot.getToken(field_name_node.first_token);
            if (token) |tok| {
                if (tok.str) |str_id| {
                    field_name = self.astdb.getString(str_id);
                }
            }

            // Generate value
            const val_reg = try self.generateExpression(val_node);

            // Emit SetField
            try self.current_instructions.append(JanusIR.Instruction{
                .set_field = JanusIR.Instruction.SetField{
                    .struct_reg = dest_reg,
                    .field_name = field_name,
                    .value_reg = val_reg,
                },
            });
        }

        return dest_reg;
    }

    /// Generate IR for field access (dot)
    fn generateFieldAccess(self: *Self, field_expr: *const AstNode) IRGeneratorError!u32 {
        const children = field_expr.children(&self.snapshot.core_snapshot);
        if (children.len < 2) return error.InvalidNode;

        // Left side (struct instance)
        const left_node = self.snapshot.getNode(children[0]) orelse return error.InvalidNode;
        const struct_reg = try self.generateExpression(left_node);

        // Right side (field identifier)
        const field_node = self.snapshot.getNode(children[1]) orelse return error.InvalidNode;
        var field_name: []const u8 = "";
        const token = self.snapshot.core_snapshot.getToken(field_node.first_token);
        if (token) |tok| {
            if (tok.str) |str_id| {
                field_name = self.astdb.getString(str_id);
            }
        }

        const dest_reg = self.allocateRegister();

        try self.current_instructions.append(JanusIR.Instruction{
            .get_field = JanusIR.Instruction.GetField{
                .dest_reg = dest_reg,
                .struct_reg = struct_reg,
                .field_name = field_name,
            },
        });

        return dest_reg;
    }

    /// Allocate a new virtual register
    fn allocateRegister(self: *Self) u32 {
        const reg = self.next_register;
        self.next_register += 1;
        return reg;
    }

    /// Allocate a new block ID
    fn allocateBlockId(self: *Self) u32 {
        const id = self.next_block_id;
        self.next_block_id += 1;
        return id;
    }
};

/// IR Query Interface - The Transmutation API
pub const IRQueries = struct {
    ir_generator: *IRGenerator,

    const Self = @This();

    pub fn init(ir_generator: *IRGenerator) Self {
        return Self{
            .ir_generator = ir_generator,
        };
    }

    /// Q.IROf - The Creator Query
    /// Generate IR for a function declaration
    pub fn irOf(self: *Self, unit_id: UnitId, function_decl_id: DeclId) !JanusIR {
        return try self.ir_generator.generateIR(unit_id, function_decl_id);
    }

    /// Q.IROfByName - Convenience query for IR generation by function name
    pub fn irOfByName(self: *Self, unit_id: UnitId, function_name: []const u8, scope_id: ScopeId) !?JanusIR {
        _ = self;
        _ = unit_id;
        _ = function_name;
        _ = scope_id;
        // TODO: Implement name resolution in new ASTDB system
        return null;
    }

    /// Q.ValidateIR - Validate generated IR for correctness
    pub fn validateIR(self: *Self, ir: *const JanusIR) !bool {
        _ = self;

        // Basic validation checks
        if (ir.basic_blocks.len == 0) return false;
        if (ir.function_name.len == 0) return false;

        // Validate each basic block
        for (ir.basic_blocks) |block| {
            if (block.instructions.len == 0 and block.terminator == null) {
                return false; // Empty block without terminator
            }
        }

        return true;
    }
};
