// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Core Profile Code Generator - AST → QTJIR → LLVM
//!
//! Converts parsed Janus AST (from ASTDB) to QTJIR intermediate representation,
//! which is then emitted to LLVM IR for native code generation.
//!
//! Supported :core profile constructs:
//! - Functions (func)
//! - Variables (let, var)
//! - Control flow (if/else, while, for)
//! - Expressions (arithmetic, comparison, function calls)
//! - Literals (integers, floats, booleans, strings)

const std = @import("std");
const compat_fs = @import("compat_fs");
const astdb_core = @import("astdb_core");
const qtjir = @import("qtjir");

const AstDB = astdb_core.AstDB;
const AstNode = astdb_core.AstNode;
const NodeId = astdb_core.NodeId;
const NodeKind = AstNode.NodeKind;
const QTJIRGraph = qtjir.QTJIRGraph;
const IRBuilder = qtjir.IRBuilder;
const OpCode = qtjir.OpCode;
const ConstantValue = qtjir.ConstantValue;
const LLVMEmitter = qtjir.LLVMEmitter;

/// Code generation errors
pub const CodeGenError = error{
    UnsupportedNode,
    UnsupportedExpression,
    UndefinedVariable,
    UndefinedFunction,
    TypeMismatch,
    InvalidArity,
    OutOfMemory,
    InternalError,
};

/// Core profile code generator
pub const CoreProfileCodeGen = struct {
    allocator: std.mem.Allocator,
    db: *AstDB,

    // Function graphs being built
    functions: std.StringHashMapUnmanaged(QTJIRGraph),

    // Current function context
    current_graph: ?*QTJIRGraph,
    current_builder: ?IRBuilder,

    // Variable mapping: name → QTJIR node ID
    variables: std.StringHashMapUnmanaged(u32),

    // Label counter for control flow
    label_counter: u32,

    pub fn init(allocator: std.mem.Allocator, db: *AstDB) CoreProfileCodeGen {
        return .{
            .allocator = allocator,
            .db = db,
            .functions = .{},
            .current_graph = null,
            .current_builder = null,
            .variables = .{},
            .label_counter = 0,
        };
    }

    pub fn deinit(self: *CoreProfileCodeGen) void {
        var it = self.functions.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
            self.allocator.free(entry.key_ptr.*);
        }
        self.functions.deinit(self.allocator);

        var var_it = self.variables.iterator();
        while (var_it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.variables.deinit(self.allocator);
    }

    /// Generate code for a compilation unit
    pub fn generateUnit(self: *CoreProfileCodeGen, unit_id: astdb_core.UnitId) CodeGenError!void {
        const snapshot = self.db.getSnapshot(unit_id) orelse return CodeGenError.InternalError;

        // Iterate through all top-level nodes (functions)
        const node_count = snapshot.nodeCount();
        var i: u32 = 0;
        while (i < node_count) : (i += 1) {
            const node_id = NodeId{ .index = i };
            if (snapshot.getNode(node_id)) |node| {
                if (node.kind == .func_decl) {
                    try self.generateFunction(snapshot, node_id, node);
                }
            }
        }
    }

    /// Generate QTJIR graph for a function
    fn generateFunction(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node_id: NodeId,
        node: *const AstNode,
    ) CodeGenError!void {
        _ = node_id;

        // Get function name
        const func_name = if (node.name_id) |name_id|
            self.db.getString(name_id) orelse "anonymous"
        else
            "anonymous";

        // Create a copy of the function name
        const func_name_copy = self.allocator.dupe(u8, func_name) catch return CodeGenError.OutOfMemory;
        errdefer self.allocator.free(func_name_copy);

        // Create QTJIR graph for this function
        var graph = QTJIRGraph.initWithName(self.allocator, func_name_copy);
        errdefer graph.deinit();

        // Set up context
        self.current_graph = &graph;
        self.current_builder = IRBuilder.init(&graph);
        self.variables.clearRetainingCapacity();

        // Process function body (children of func_decl)
        if (node.first_child_id) |first_child| {
            try self.generateStatements(snapshot, first_child);
        }

        // Ensure function has a return
        if (graph.nodes.items.len == 0 or
            graph.nodes.items[graph.nodes.items.len - 1].op != .Return)
        {
            // Add implicit return 0 for main, void return for others
            if (std.mem.eql(u8, func_name, "main")) {
                const zero = self.current_builder.?.createConstant(.{ .integer = 0 }) catch
                    return CodeGenError.OutOfMemory;
                _ = self.current_builder.?.createReturn(zero) catch
                    return CodeGenError.OutOfMemory;
            }
        }

        // Store the completed graph
        self.functions.put(self.allocator, func_name_copy, graph) catch
            return CodeGenError.OutOfMemory;

        self.current_graph = null;
        self.current_builder = null;
    }

    /// Generate code for a sequence of statements
    fn generateStatements(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        first_id: NodeId,
    ) CodeGenError!void {
        var current_id: ?NodeId = first_id;

        while (current_id) |id| {
            const node = snapshot.getNode(id) orelse break;
            try self.generateStatement(snapshot, node);
            current_id = node.next_sibling_id;
        }
    }

    /// Generate code for a single statement
    fn generateStatement(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        switch (node.kind) {
            .let_stmt, .var_stmt => try self.generateVarDecl(snapshot, node),
            .return_stmt => try self.generateReturn(snapshot, node),
            .if_stmt => try self.generateIf(snapshot, node),
            .while_stmt => try self.generateWhile(snapshot, node),
            .for_stmt => try self.generateFor(snapshot, node),
            .expr_stmt => try self.generateExprStmt(snapshot, node),
            .call_expr => _ = try self.generateCall(snapshot, node),
            .block => {
                if (node.first_child_id) |first_child| {
                    try self.generateStatements(snapshot, first_child);
                }
            },
            else => {
                // Try to generate as expression
                _ = self.generateExpression(snapshot, node) catch |err| {
                    if (err == CodeGenError.UnsupportedExpression) {
                        return CodeGenError.UnsupportedNode;
                    }
                    return err;
                };
            },
        }
    }

    /// Generate variable declaration (let/var)
    fn generateVarDecl(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        const builder = &self.current_builder.?;

        // Get variable name
        const var_name = if (node.name_id) |name_id|
            self.db.getString(name_id) orelse return CodeGenError.InternalError
        else
            return CodeGenError.InternalError;

        // Create alloca for the variable
        const alloca_id = builder.createAlloca() catch return CodeGenError.OutOfMemory;

        // If there's an initializer, generate it and store
        if (node.first_child_id) |init_id| {
            if (snapshot.getNode(init_id)) |init_node| {
                const value_id = try self.generateExpression(snapshot, init_node);
                _ = builder.createStore(value_id, alloca_id) catch return CodeGenError.OutOfMemory;
            }
        }

        // Store variable mapping
        const name_copy = self.allocator.dupe(u8, var_name) catch return CodeGenError.OutOfMemory;
        self.variables.put(self.allocator, name_copy, alloca_id) catch {
            self.allocator.free(name_copy);
            return CodeGenError.OutOfMemory;
        };
    }

    /// Generate return statement
    fn generateReturn(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        const builder = &self.current_builder.?;

        if (node.first_child_id) |value_id| {
            if (snapshot.getNode(value_id)) |value_node| {
                const result_id = try self.generateExpression(snapshot, value_node);
                _ = builder.createReturn(result_id) catch return CodeGenError.OutOfMemory;
                return;
            }
        }

        // Return void or 0
        const zero = builder.createConstant(.{ .integer = 0 }) catch return CodeGenError.OutOfMemory;
        _ = builder.createReturn(zero) catch return CodeGenError.OutOfMemory;
    }

    /// Generate if statement
    fn generateIf(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        const builder = &self.current_builder.?;

        // Get condition (first child)
        const cond_id = node.first_child_id orelse return CodeGenError.InternalError;
        const cond_node = snapshot.getNode(cond_id) orelse return CodeGenError.InternalError;

        // Generate condition
        const cond_value = try self.generateExpression(snapshot, cond_node);

        // Create labels
        const then_label = self.nextLabel();
        const else_label = self.nextLabel();
        const end_label = self.nextLabel();

        // Branch on condition
        _ = builder.createBranch(cond_value, then_label, else_label) catch return CodeGenError.OutOfMemory;

        // Then block
        _ = builder.createLabel(then_label) catch return CodeGenError.OutOfMemory;
        if (cond_node.next_sibling_id) |then_id| {
            if (snapshot.getNode(then_id)) |then_node| {
                try self.generateStatement(snapshot, then_node);

                // Check for else block
                if (then_node.next_sibling_id) |else_id| {
                    _ = builder.createJump(end_label) catch return CodeGenError.OutOfMemory;

                    // Else block
                    _ = builder.createLabel(else_label) catch return CodeGenError.OutOfMemory;
                    if (snapshot.getNode(else_id)) |else_node| {
                        try self.generateStatement(snapshot, else_node);
                    }
                } else {
                    _ = builder.createJump(end_label) catch return CodeGenError.OutOfMemory;
                    _ = builder.createLabel(else_label) catch return CodeGenError.OutOfMemory;
                }
            }
        }

        // End label
        _ = builder.createLabel(end_label) catch return CodeGenError.OutOfMemory;
    }

    /// Generate while loop
    fn generateWhile(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        const builder = &self.current_builder.?;

        // Create labels
        const cond_label = self.nextLabel();
        const body_label = self.nextLabel();
        const end_label = self.nextLabel();

        // Jump to condition
        _ = builder.createJump(cond_label) catch return CodeGenError.OutOfMemory;
        _ = builder.createLabel(cond_label) catch return CodeGenError.OutOfMemory;

        // Get and generate condition
        const cond_id = node.first_child_id orelse return CodeGenError.InternalError;
        const cond_node = snapshot.getNode(cond_id) orelse return CodeGenError.InternalError;
        const cond_value = try self.generateExpression(snapshot, cond_node);

        // Branch
        _ = builder.createBranch(cond_value, body_label, end_label) catch return CodeGenError.OutOfMemory;

        // Body
        _ = builder.createLabel(body_label) catch return CodeGenError.OutOfMemory;
        if (cond_node.next_sibling_id) |body_id| {
            if (snapshot.getNode(body_id)) |body_node| {
                try self.generateStatement(snapshot, body_node);
            }
        }

        // Loop back
        _ = builder.createJump(cond_label) catch return CodeGenError.OutOfMemory;

        // End
        _ = builder.createLabel(end_label) catch return CodeGenError.OutOfMemory;
    }

    /// Generate for loop (for-in style)
    fn generateFor(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        // For now, treat for loops as while loops with initialization
        // TODO: Implement proper iterator-based for loops
        _ = self;
        _ = snapshot;
        _ = node;

        // Placeholder - for loops are more complex
        return CodeGenError.UnsupportedNode;
    }

    /// Generate expression statement
    fn generateExprStmt(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!void {
        if (node.first_child_id) |expr_id| {
            if (snapshot.getNode(expr_id)) |expr_node| {
                _ = try self.generateExpression(snapshot, expr_node);
            }
        }
    }

    /// Generate expression, returns QTJIR node ID
    fn generateExpression(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!u32 {
        const builder = &self.current_builder.?;

        switch (node.kind) {
            .int_literal => {
                const value: i64 = @intCast(node.int_value orelse 0);
                return builder.createConstant(.{ .integer = value }) catch return CodeGenError.OutOfMemory;
            },
            .float_literal => {
                const value: f64 = node.float_value orelse 0.0;
                return builder.createConstant(.{ .float = value }) catch return CodeGenError.OutOfMemory;
            },
            .string_literal => {
                const str = if (node.name_id) |name_id|
                    self.db.getString(name_id) orelse ""
                else
                    "";
                // Create sentinel-terminated string for QTJIR
                const str_z = self.allocator.dupeZ(u8, str) catch return CodeGenError.OutOfMemory;
                return builder.createConstant(.{ .string = str_z }) catch return CodeGenError.OutOfMemory;
            },
            .bool_literal => {
                const value: i64 = if (node.bool_value orelse false) 1 else 0;
                return builder.createConstant(.{ .integer = value }) catch return CodeGenError.OutOfMemory;
            },
            .identifier => {
                // Load variable
                const name = if (node.name_id) |name_id|
                    self.db.getString(name_id) orelse return CodeGenError.UndefinedVariable
                else
                    return CodeGenError.UndefinedVariable;

                const alloca_id = self.variables.get(name) orelse return CodeGenError.UndefinedVariable;
                return builder.createLoad(alloca_id) catch return CodeGenError.OutOfMemory;
            },
            .binary_expr => return self.generateBinaryExpr(snapshot, node),
            .unary_expr => return self.generateUnaryExpr(snapshot, node),
            .call_expr => return self.generateCall(snapshot, node),
            .paren_expr => {
                if (node.first_child_id) |inner_id| {
                    if (snapshot.getNode(inner_id)) |inner_node| {
                        return self.generateExpression(snapshot, inner_node);
                    }
                }
                return CodeGenError.InternalError;
            },
            else => return CodeGenError.UnsupportedExpression,
        }
    }

    /// Generate binary expression
    fn generateBinaryExpr(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!u32 {
        const builder = &self.current_builder.?;

        // Get left operand (first child)
        const left_id = node.first_child_id orelse return CodeGenError.InternalError;
        const left_node = snapshot.getNode(left_id) orelse return CodeGenError.InternalError;
        const left_value = try self.generateExpression(snapshot, left_node);

        // Get right operand (next sibling of left)
        const right_id = left_node.next_sibling_id orelse return CodeGenError.InternalError;
        const right_node = snapshot.getNode(right_id) orelse return CodeGenError.InternalError;
        const right_value = try self.generateExpression(snapshot, right_node);

        // Get operator from node
        const op = node.operator orelse return CodeGenError.InternalError;

        // Map operator to QTJIR opcode
        const opcode: OpCode = switch (op) {
            .plus => .Add,
            .minus => .Sub,
            .star => .Mul,
            .slash => .Div,
            .equal_equal => .Equal,
            .bang_equal => .NotEqual,
            .less => .Less,
            .less_equal => .LessEqual,
            .greater => .Greater,
            .greater_equal => .GreaterEqual,
            .ampersand => .BitAnd,
            .pipe => .BitOr,
            .caret => .Xor,
            else => return CodeGenError.UnsupportedExpression,
        };

        return builder.createBinaryOp(opcode, left_value, right_value) catch return CodeGenError.OutOfMemory;
    }

    /// Generate unary expression
    fn generateUnaryExpr(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!u32 {
        const builder = &self.current_builder.?;

        // Get operand
        const operand_id = node.first_child_id orelse return CodeGenError.InternalError;
        const operand_node = snapshot.getNode(operand_id) orelse return CodeGenError.InternalError;
        const operand_value = try self.generateExpression(snapshot, operand_node);

        const op = node.operator orelse return CodeGenError.InternalError;

        switch (op) {
            .minus => {
                // Negate: 0 - operand
                const zero = builder.createConstant(.{ .integer = 0 }) catch return CodeGenError.OutOfMemory;
                return builder.createBinaryOp(.Sub, zero, operand_value) catch return CodeGenError.OutOfMemory;
            },
            .bang => {
                // Logical not: operand == 0
                const zero = builder.createConstant(.{ .integer = 0 }) catch return CodeGenError.OutOfMemory;
                return builder.createBinaryOp(.Equal, operand_value, zero) catch return CodeGenError.OutOfMemory;
            },
            .tilde => {
                return builder.createUnaryOp(.BitNot, operand_value) catch return CodeGenError.OutOfMemory;
            },
            else => return CodeGenError.UnsupportedExpression,
        }
    }

    /// Generate function call
    fn generateCall(
        self: *CoreProfileCodeGen,
        snapshot: *const astdb_core.Snapshot,
        node: *const AstNode,
    ) CodeGenError!u32 {
        const builder = &self.current_builder.?;

        // Get function name
        const func_name = if (node.name_id) |name_id|
            self.db.getString(name_id) orelse "unknown"
        else
            "unknown";

        // Collect arguments
        var args = std.ArrayListUnmanaged(u32){};
        defer args.deinit(self.allocator);

        if (node.first_child_id) |first_arg_id| {
            var arg_id: ?NodeId = first_arg_id;
            while (arg_id) |id| {
                const arg_node = snapshot.getNode(id) orelse break;
                const arg_value = try self.generateExpression(snapshot, arg_node);
                args.append(self.allocator, arg_value) catch return CodeGenError.OutOfMemory;
                arg_id = arg_node.next_sibling_id;
            }
        }

        // Map standard library calls
        const mapped_name = mapStdlibCall(func_name);

        return builder.createCallNamed(mapped_name, args.items) catch return CodeGenError.OutOfMemory;
    }

    /// Get next unique label ID
    fn nextLabel(self: *CoreProfileCodeGen) u32 {
        const label = self.label_counter;
        self.label_counter += 1;
        return label;
    }

    // =========================================================================
    // LLVM Emission
    // =========================================================================

    /// Emit all generated functions to LLVM IR
    pub fn emitLLVM(self: *CoreProfileCodeGen, module_name: []const u8) CodeGenError![]u8 {
        var emitter = LLVMEmitter.init(self.allocator, module_name) catch return CodeGenError.OutOfMemory;
        defer emitter.deinit();

        // Collect all graphs into a slice
        var graphs = std.ArrayListUnmanaged(QTJIRGraph){};
        defer graphs.deinit(self.allocator);

        var it = self.functions.iterator();
        while (it.next()) |entry| {
            graphs.append(self.allocator, entry.value_ptr.*) catch return CodeGenError.OutOfMemory;
        }

        // Emit
        emitter.emit(graphs.items) catch return CodeGenError.InternalError;

        return emitter.toString() catch return CodeGenError.OutOfMemory;
    }

    /// Emit to LLVM IR file
    pub fn emitToFile(self: *CoreProfileCodeGen, module_name: []const u8, output_path: []const u8) CodeGenError!void {
        const ir = try self.emitLLVM(module_name);
        defer self.allocator.free(ir);

        const file = compat_fs.createFile(output_path, .{}) catch return CodeGenError.InternalError;
        defer file.close();

        file.writeAll(ir) catch return CodeGenError.InternalError;
    }
};

/// Map Janus stdlib calls to runtime function names
fn mapStdlibCall(name: []const u8) []const u8 {
    // I/O functions
    if (std.mem.eql(u8, name, "print")) return "janus_print";
    if (std.mem.eql(u8, name, "println")) return "janus_println";

    // Conversion functions
    if (std.mem.eql(u8, name, "string")) return "janus_to_string";
    if (std.mem.eql(u8, name, "int")) return "janus_to_int";
    if (std.mem.eql(u8, name, "float")) return "janus_to_float";

    // Default: use as-is
    return name;
}

// =============================================================================
// TESTS
// =============================================================================

test "CoreProfileCodeGen: init and deinit" {
    const allocator = std.testing.allocator;

    var db = AstDB.init(allocator);
    defer db.deinit();

    var codegen = CoreProfileCodeGen.init(allocator, &db);
    defer codegen.deinit();
}

test "mapStdlibCall" {
    try std.testing.expectEqualStrings("janus_print", mapStdlibCall("print"));
    try std.testing.expectEqualStrings("janus_println", mapStdlibCall("println"));
    try std.testing.expectEqualStrings("my_func", mapStdlibCall("my_func"));
}
