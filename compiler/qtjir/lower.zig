// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ASTDB → QTJIR Lowering

const std = @import("std");
const astdb = @import("astdb_core"); // Using the same name as in tests for now
const graph = @import("graph.zig");
const builtin_calls = @import("builtin_calls.zig");
const trace = @import("trace.zig");
const extern_registry = @import("extern_registry.zig");

// Defer System Types
const DeferredAction = struct {
    builtin_name: []const u8,
    args: std.ArrayListUnmanaged(u32),
};

const ScopeType = enum {
    Block,
    Loop,
    Function,
};

const ScopeLayer = struct {
    type: ScopeType,
    actions: std.ArrayListUnmanaged(DeferredAction),
};

const AstNode = astdb.AstNode;
const NodeKind = AstNode.NodeKind;
const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const Snapshot = astdb.Snapshot;

const QTJIRGraph = graph.QTJIRGraph;
const IRBuilder = graph.IRBuilder;
const OpCode = graph.OpCode;
const GateType = graph.GateType;

pub const LowerError = error{ InvalidToken, InvalidCall, InvalidNode, UnsupportedCall, InvalidBinaryExpr, OutOfMemory, UndefinedVariable };

pub const LoweringContext = struct {
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    unit_id: UnitId,
    builder: IRBuilder,

    // Map from AST NodeId to QTJIR Node ID (u32)
    node_map: std.AutoHashMap(NodeId, u32),

    // Map from variable name to Alloca Node ID (u32)
    scope: ScopeTracker,

    // Defer Stack
    defer_stack: std.ArrayListUnmanaged(ScopeLayer),

    // Loop depth counter (for break/continue patching)
    loop_depth: usize = 0,

    // Pending Break Jumps - holds (jump_node_id, loop_depth) pairs for patching
    pending_breaks: std.ArrayListUnmanaged(PendingJump),

    // Pending Continue Jumps - holds (jump_node_id, loop_depth) pairs for patching
    pending_continues: std.ArrayListUnmanaged(PendingJump),

    // Track which QTJIR nodes produce slice values (for proper slice indexing)
    slice_nodes: std.AutoHashMapUnmanaged(u32, void),

    // Track which QTJIR nodes produce optional values
    optional_nodes: std.AutoHashMapUnmanaged(u32, void),

    // Track which QTJIR nodes produce error union values
    error_union_nodes: std.AutoHashMapUnmanaged(u32, void),

    const PendingJump = struct {
        jump_id: u32,
        loop_depth: usize,
    };

    pub const ScopeTracker = struct {
        map: std.StringHashMap(u32),
        depth: usize = 0,
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) ScopeTracker {
            return .{
                .map = std.StringHashMap(u32).init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *ScopeTracker) void {
            self.map.deinit();
        }

        pub fn put(self: *ScopeTracker, key: []const u8, val: u32) !void {
            return self.map.put(key, val);
        }

        pub fn get(self: *ScopeTracker, key: []const u8) ?u32 {
            return self.map.get(key);
        }

        pub fn count(self: *ScopeTracker) usize {
            return self.map.count();
        }

        pub fn keyIterator(self: *ScopeTracker) std.StringHashMap(u32).KeyIterator {
            return self.map.keyIterator();
        }
    };

    pub fn init(allocator: std.mem.Allocator, snapshot: *const Snapshot, unit_id: UnitId, graph_ptr: *QTJIRGraph) LoweringContext {
        return .{
            .allocator = allocator,
            .snapshot = snapshot,
            .unit_id = unit_id,
            .builder = IRBuilder.init(graph_ptr),
            .node_map = std.AutoHashMap(NodeId, u32).init(allocator),
            .scope = ScopeTracker.init(allocator),
            .defer_stack = .{},
            .loop_depth = 0,
            .pending_breaks = .{},
            .pending_continues = .{},
            .slice_nodes = .{},
            .optional_nodes = .{},
            .error_union_nodes = .{},
        };
    }

    pub fn pushScope(self: *LoweringContext, type_: ScopeType) !void {
        // std.debug.print("PushScope: {s} (Stack size: {d})\n", .{ @tagName(type_), self.defer_stack.items.len });
        try self.defer_stack.append(self.allocator, ScopeLayer{
            .type = type_,
            .actions = .{},
        });
    }

    pub fn popScope(self: *LoweringContext) !std.ArrayListUnmanaged(DeferredAction) {
        if (self.defer_stack.items.len == 0) return .{};
        const layer = self.defer_stack.pop().?;
        // std.debug.print("PopScope: {s} (Actions: {d})\n", .{ @tagName(layer.type), layer.actions.items.len });
        return layer.actions;
    }

    pub fn registerDefer(self: *LoweringContext, action: DeferredAction) !void {
        if (self.defer_stack.items.len > 0) {
            // Must access by pointer to mutate the actions list in place!
            var layer = &self.defer_stack.items[self.defer_stack.items.len - 1];
            try layer.actions.append(self.allocator, action);
        }
    }

    pub fn emitDefersForScope(self: *LoweringContext, actions: *std.ArrayListUnmanaged(DeferredAction)) !void {

        // LIFO order
        // std.debug.print("Emitting {d} defers\n", .{actions.items.len});
        while (actions.items.len > 0) {
            var action = actions.pop().?; // Must be var to deinit args
            // Emit Call
            // std.debug.print("Emitting defer call: {s}\n", .{action.builtin_name});
            // We need to find the builtin opcode or just use Call with string literal data

            const call_id = try self.builder.createNode(.Call);
            var node = &self.builder.graph.nodes.items[call_id];

            // Set data to function name (Interpreter uses this)
            node.data = .{ .string = try self.dupeForGraph(action.builtin_name) };

            // Add inputs
            for (action.args.items) |arg| {
                try node.inputs.append(self.allocator, arg);
            }
            action.args.deinit(self.allocator);
            self.allocator.free(action.builtin_name);
        }
        actions.deinit(self.allocator);
    }

    pub fn deinit(self: *LoweringContext) void {
        self.node_map.deinit();
        self.scope.deinit();
        for (self.defer_stack.items) |*layer| {
            for (layer.actions.items) |*action| {
                action.args.deinit(self.allocator);
                self.allocator.free(action.builtin_name);
            }
            layer.actions.deinit(self.allocator);
        }
        self.defer_stack.deinit(self.allocator);
        self.pending_breaks.deinit(self.allocator);
        self.pending_continues.deinit(self.allocator);
        self.slice_nodes.deinit(self.allocator);
        self.optional_nodes.deinit(self.allocator);
        self.error_union_nodes.deinit(self.allocator);
    }

    /// Clone a string using the Graph's allocator for sovereign ownership.
    /// Per the Sovereign Graph doctrine: all strings in QTJIRGraph nodes
    /// must be owned by the graph, not borrowed from the interner.
    fn dupeForGraph(self: *LoweringContext, str: []const u8) ![:0]u8 {
        return self.builder.graph.allocator.dupeZ(u8, str);
    }
};

/// Result of lowering with external function registry
/// For native Zig integration during bootstrap phase
pub const LoweringResult = struct {
    graphs: std.ArrayListUnmanaged(QTJIRGraph),
    extern_registry: extern_registry.ExternRegistry,

    pub fn deinit(self: *LoweringResult, allocator: std.mem.Allocator) void {
        for (self.graphs.items) |*g| g.deinit();
        self.graphs.deinit(allocator);
        self.extern_registry.deinit();
    }
};

/// Lower a compilation unit to QTJIR with external function tracking
/// Returns graphs and an extern registry populated from `use zig` imports
pub fn lowerUnitWithExterns(allocator: std.mem.Allocator, snapshot: *const Snapshot, unit_id: UnitId, source_dir: ?[]const u8) !LoweringResult {
    var result = LoweringResult{
        .graphs = .{},
        .extern_registry = extern_registry.ExternRegistry.init(allocator),
    };
    errdefer result.deinit(allocator);

    const unit = snapshot.astdb.getUnitConst(unit_id) orelse return error.InvalidUnitId;

    // First pass: Process use_zig nodes to populate extern registry
    for (unit.nodes) |node| {
        if (node.kind == .use_zig) {
            try processUseZig(allocator, snapshot, &node, &result.extern_registry, source_dir);
        }
    }

    // Second pass: Lower function declarations
    for (unit.nodes, 0..) |node, i| {
        const node_id: NodeId = @enumFromInt(@as(u32, @intCast(i)));

        if (node.kind == .func_decl) {
            if (try lowerFunctionToGraph(allocator, snapshot, unit_id, node_id, &node)) |ir_graph| {
                try result.graphs.append(allocator, ir_graph);
            }
        } else if (node.kind == .test_decl) {
            if (try lowerTestToGraph(allocator, snapshot, unit_id, node_id, &node)) |ir_graph| {
                try result.graphs.append(allocator, ir_graph);
            }
        }
    }

    return result;
}

/// Lower a compilation unit to QTJIR
/// For now, this assumes a single main function and returns its graph
pub fn lowerUnit(allocator: std.mem.Allocator, snapshot: *const Snapshot, unit_id: UnitId) !std.ArrayListUnmanaged(QTJIRGraph) {
    var graphs = std.ArrayListUnmanaged(QTJIRGraph){};
    errdefer {
        for (graphs.items) |*g| g.deinit();
        graphs.deinit(allocator);
    }

    // Get unit
    const unit = snapshot.astdb.getUnitConst(unit_id) orelse return error.InvalidUnitId;

    // Iterate over top-level nodes
    for (unit.nodes, 0..) |node, i| {
        const node_id: NodeId = @enumFromInt(@as(u32, @intCast(i)));
        // We only care about function declarations for now
        if (node.kind == .func_decl) {
            // Create graph for this function
            // Get name mapping
            const children = snapshot.getChildren(node_id);
            if (children.len > 0) {
                const name_node = snapshot.getNode(children[0]);
                if (name_node != null and name_node.?.kind == .identifier) {
                    const token = snapshot.getToken(name_node.?.first_token);
                    const name = if (token != null and token.?.str != null) snapshot.astdb.str_interner.getString(token.?.str.?) else "anon";

                    var ir_graph = QTJIRGraph.initWithName(allocator, name);
                    var ctx = LoweringContext.init(allocator, snapshot, unit_id, &ir_graph);
                    defer ctx.deinit();

                    try ctx.pushScope(.Function); // Root scope
                    defer {
                        // Cleanup root scope if not empty (though should be handled by implicit return)
                        if (ctx.defer_stack.items.len > 0) {
                            var actions = ctx.defer_stack.pop().?.actions;
                            for (actions.items) |*a| {
                                a.args.deinit(ctx.allocator);
                                ctx.allocator.free(a.builtin_name);
                            }
                            actions.deinit(ctx.allocator);
                        }
                    }

                    try lowerFuncDecl(&ctx, node_id, &node);
                    try graphs.append(allocator, ir_graph);
                }
            }
        } else if (node.kind == .test_decl) {
            // Create graph for this test
            const children = snapshot.getChildren(node_id);
            if (children.len > 0) {
                const name_node = snapshot.getNode(children[0]);
                if (name_node != null and name_node.?.kind == .string_literal) {
                    const token = snapshot.getToken(name_node.?.first_token);
                    const raw_name = if (token != null and token.?.str != null) snapshot.astdb.str_interner.getString(token.?.str.?) else "anon";

                    // Prefix with "test:" to distinguish from functions
                    const name = try std.fmt.allocPrint(allocator, "test:{s}", .{raw_name});
                    // Note: name is owned by graph (technically leaked until JitRunner cleans it up)

                    var ir_graph = QTJIRGraph.initWithName(allocator, name);
                    var ctx = LoweringContext.init(allocator, snapshot, unit_id, &ir_graph);
                    defer ctx.deinit();

                    try ctx.pushScope(.Function);
                    defer {
                        if (ctx.defer_stack.items.len > 0) {
                            var actions = ctx.defer_stack.pop().?.actions;
                            for (actions.items) |*a| {
                                a.args.deinit(ctx.allocator);
                                ctx.allocator.free(a.builtin_name);
                            }
                            actions.deinit(ctx.allocator);
                        }
                    }

                    try lowerTestDecl(&ctx, node_id, &node);
                    try graphs.append(allocator, ir_graph);
                }
            }
        }
    }

    return graphs;
}

/// Process a `use zig "path.zig"` node and populate the extern registry
fn processUseZig(
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    node: *const AstNode,
    registry: *extern_registry.ExternRegistry,
    source_dir: ?[]const u8,
) !void {
    // Get the path string from the use_zig node's children
    // use_zig node has: [origin identifier "zig", string literal "path.zig"]
    const child_lo = node.child_lo;
    const child_hi = node.child_hi;

    // Find the string literal child (path to Zig file)
    var path_str: ?[]const u8 = null;
    var i: u32 = child_lo;
    while (i < child_hi) : (i += 1) {
        const child_id: NodeId = @enumFromInt(i);
        const child = snapshot.getNode(child_id) orelse continue;
        if (child.kind == .string_literal) {
            const token = snapshot.getToken(child.first_token) orelse continue;
            if (token.str) |str_id| {
                path_str = snapshot.astdb.str_interner.getString(str_id);
                break;
            }
        }
    }

    const raw_path = path_str orelse return;

    // Strip quotes from the path if present (string literals include quotes)
    const zig_path = if (raw_path.len >= 2 and raw_path[0] == '"' and raw_path[raw_path.len - 1] == '"')
        raw_path[1 .. raw_path.len - 1]
    else
        raw_path;

    // Resolve full path relative to source directory
    const relative_path = if (source_dir) |dir|
        try std.fs.path.join(allocator, &[_][]const u8{ dir, zig_path })
    else
        try allocator.dupe(u8, zig_path);
    defer allocator.free(relative_path);

    // Convert to absolute path for registry (so it works from any directory)
    const full_path = std.fs.cwd().realpathAlloc(allocator, relative_path) catch |err| {
        std.debug.print("Warning: Could not resolve Zig module path '{s}': {s}\n", .{ relative_path, @errorName(err) });
        return;
    };
    defer allocator.free(full_path);

    // Read the Zig file
    const zig_source = std.fs.cwd().readFileAlloc(
        allocator,
        full_path,
        10 * 1024 * 1024, // 10MB max
    ) catch |err| {
        std.debug.print("Warning: Could not read Zig module '{s}': {s}\n", .{ full_path, @errorName(err) });
        return;
    };
    defer allocator.free(zig_source);

    // Register functions from the Zig source
    const count = registry.registerZigSource(full_path, zig_source) catch |err| {
        std.debug.print("Warning: Could not parse Zig module '{s}': {s}\n", .{ full_path, @errorName(err) });
        return;
    };

    if (count > 0) {
        std.debug.print("Registered {d} functions from Zig module '{s}'\n", .{ count, zig_path });
    }
}

/// Lower a function declaration to a QTJIR graph
fn lowerFunctionToGraph(
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    unit_id: UnitId,
    node_id: NodeId,
    node: *const AstNode,
) !?QTJIRGraph {
    const children = snapshot.getChildren(node_id);
    if (children.len == 0) return null;

    const name_node = snapshot.getNode(children[0]) orelse return null;
    if (name_node.kind != .identifier) return null;

    const token = snapshot.getToken(name_node.first_token) orelse return null;
    const name = if (token.str) |str_id| snapshot.astdb.str_interner.getString(str_id) else return null;

    var ir_graph = QTJIRGraph.initWithName(allocator, name);
    var ctx = LoweringContext.init(allocator, snapshot, unit_id, &ir_graph);
    defer ctx.deinit();

    try ctx.pushScope(.Function);
    defer {
        if (ctx.defer_stack.items.len > 0) {
            var actions = ctx.defer_stack.pop().?.actions;
            for (actions.items) |*a| {
                a.args.deinit(ctx.allocator);
                ctx.allocator.free(a.builtin_name);
            }
            actions.deinit(ctx.allocator);
        }
    }

    try lowerFuncDecl(&ctx, node_id, node);
    return ir_graph;
}

/// Lower a test declaration to a QTJIR graph
fn lowerTestToGraph(
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,
    unit_id: UnitId,
    node_id: NodeId,
    node: *const AstNode,
) !?QTJIRGraph {
    const children = snapshot.getChildren(node_id);
    if (children.len == 0) return null;

    const name_node = snapshot.getNode(children[0]) orelse return null;
    if (name_node.kind != .string_literal) return null;

    const token = snapshot.getToken(name_node.first_token) orelse return null;
    const raw_name = if (token.str) |str_id| snapshot.astdb.str_interner.getString(str_id) else return null;

    const name = try std.fmt.allocPrint(allocator, "test:{s}", .{raw_name});

    var ir_graph = QTJIRGraph.initWithName(allocator, name);
    var ctx = LoweringContext.init(allocator, snapshot, unit_id, &ir_graph);
    defer ctx.deinit();

    try ctx.pushScope(.Function);
    defer {
        if (ctx.defer_stack.items.len > 0) {
            var actions = ctx.defer_stack.pop().?.actions;
            for (actions.items) |*a| {
                a.args.deinit(ctx.allocator);
                ctx.allocator.free(a.builtin_name);
            }
            actions.deinit(ctx.allocator);
        }
    }

    try lowerTestDecl(&ctx, node_id, node);
    return ir_graph;
}

// Lower a test declaration
// test "name" do ... end
fn lowerTestDecl(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) !void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return; // Need name and body

    // 0: Name (String Literal)
    // 1: Body (Block)

    // Tests take no arguments
    // Tests take no arguments

    // Iterate over statements (skipping name at 0)
    for (children[1..]) |stmt_id| {
        const stmt = ctx.snapshot.getNode(stmt_id) orelse continue;
        if (stmt.kind == .block_stmt) {
            try lowerBlock(ctx, stmt_id, stmt);
        } else {
            try lowerStatement(ctx, stmt_id, stmt);
        }
    }

    // Default return 0 (Success)
    const zero_const = try ctx.builder.createConstant(.{ .integer = 0 });
    const ret_node = try ctx.builder.createNode(.Return);
    try ctx.builder.graph.nodes.items[ret_node].inputs.append(ctx.allocator, zero_const);
}

fn lowerFuncDecl(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) !void {
    _ = node; // We use snapshot to get children
    // Expect: identifier (name) -> params... -> return_type/block
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len == 0) return;

    // Check if it's main function
    const name_node_id = children[0];
    const name_node = ctx.snapshot.getNode(name_node_id) orelse return;

    if (name_node.kind != .identifier) {
        return;
    }

    const token = ctx.snapshot.getToken(name_node.first_token) orelse return;
    _ = token;

    // Process Parameters
    var params = std.ArrayListUnmanaged(graph.Parameter){};
    errdefer params.deinit(ctx.allocator);

    var param_idx: i32 = 0;

    // Find block statement, error union return type, or process children directly
    var block_node_id: ?NodeId = null;
    var has_error_union_return = false;
    var has_return_type_annotation = false;

    for (children[1..]) |child_id| {
        const child = ctx.snapshot.getNode(child_id) orelse continue;

        if (child.kind == .block_stmt) {
            block_node_id = child_id;
            // Don't break - continue scanning for error_union_type
        }

        // Check for error union return type
        if (child.kind == .error_union_type) {
            has_error_union_return = true;
            has_return_type_annotation = true;
        }

        // Check for any type node as return type annotation
        if (child.kind == .primitive_type or child.kind == .named_type or
            child.kind == .pointer_type or child.kind == .array_type or
            child.kind == .slice_type or child.kind == .optional_type) {
            has_return_type_annotation = true;
        }

        if (child.kind == .parameter) {
            // std.debug.print("Found Parameter Node!\n", .{});
            // child should have name and type
            const p_children = ctx.snapshot.getChildren(child_id);
            // std.debug.print("Param Children Count: {d}\n", .{p_children.len});
            if (p_children.len >= 2) {
                const p_name_id = p_children[0];
                const p_type_id = p_children[1];
                _ = p_type_id; // Unused for now

                const p_name_node = ctx.snapshot.getNode(p_name_id);
                const p_token = if (p_name_node) |pn| ctx.snapshot.getToken(pn.first_token) else null;
                const p_name = if (p_token != null and p_token.?.str != null) ctx.snapshot.astdb.str_interner.getString(p_token.?.str.?) else "arg";

                // std.debug.print("Registering param: '{s}'\n", .{p_name});

                // Add to parameters list
                try params.append(ctx.allocator, .{ .name = try ctx.allocator.dupe(u8, p_name), .type_name = "i32" }); // Default type for MVP

                // Create Argument Node
                const arg_node_id = try ctx.builder.createNode(.Argument);
                ctx.builder.graph.nodes.items[arg_node_id].data = .{ .integer = param_idx };
                param_idx += 1;

                // Create Alloca + Store
                const alloca_id = try ctx.builder.createNode(.Alloca);
                ctx.builder.graph.nodes.items[alloca_id].data = .{ .string = try ctx.dupeForGraph(p_name) };

                try ctx.scope.put(p_name, alloca_id);

                const store_id = try ctx.builder.createNode(.Store);
                try ctx.builder.graph.nodes.items[store_id].inputs.append(ctx.allocator, alloca_id);
                try ctx.builder.graph.nodes.items[store_id].inputs.append(ctx.allocator, arg_node_id);

                // std.debug.print("Scope Size after put: {d}\n", .{ctx.scope.count()});
            } else {
                // Fallback: Scan tokens (Children count was 0)
                const first_tok = ctx.snapshot.getToken(child.first_token);
                const p_name = if (first_tok != null and first_tok.?.str != null) ctx.snapshot.astdb.str_interner.getString(first_tok.?.str.?) else "arg";

                // std.debug.print("Registering param (token scan): '{s}'\n", .{p_name});

                // Add to parameters list
                try params.append(ctx.allocator, .{ .name = try ctx.allocator.dupe(u8, p_name), .type_name = "i32" });

                // Create Argument Node
                const arg_node_id = try ctx.builder.createNode(.Argument);
                ctx.builder.graph.nodes.items[arg_node_id].data = .{ .integer = param_idx };
                param_idx += 1;

                // Create Alloca + Store
                const alloca_id = try ctx.builder.createNode(.Alloca);
                ctx.builder.graph.nodes.items[alloca_id].data = .{ .string = try ctx.dupeForGraph(p_name) };

                try ctx.scope.put(p_name, alloca_id);

                const store_id = try ctx.builder.createNode(.Store);
                try ctx.builder.graph.nodes.items[store_id].inputs.append(ctx.allocator, alloca_id);
                try ctx.builder.graph.nodes.items[store_id].inputs.append(ctx.allocator, arg_node_id);
            }
        }
    }

    // Assign parameters to graph
    ctx.builder.graph.parameters = try params.toOwnedSlice(ctx.allocator);

    // Set return type based on whether function returns error union
    if (has_error_union_return) {
        ctx.builder.graph.return_type = "error_union"; // Special marker for error union
    }

    if (block_node_id) |bid| {
        const block = ctx.snapshot.getNode(bid) orelse return;
        const block_children = ctx.snapshot.getChildren(bid);

        // Check if last statement is an expression (implicit return for error unions)
        const needs_implicit_return = has_error_union_return and
                                     block_children.len > 0 and
                                     blk: {
            const last_child = ctx.snapshot.getNode(block_children[block_children.len - 1]) orelse break :blk false;
            break :blk last_child.kind == .expr_stmt;
        };

        if (needs_implicit_return) {
            // Lower all but last statement
            try ctx.pushScope(.Block);
            for (block_children[0..block_children.len - 1]) |child_id| {
                const child = ctx.snapshot.getNode(child_id) orelse continue;
                try lowerStatement(ctx, child_id, child);
            }

            // Lower last expression and wrap in Error_Union_Construct
            const last_stmt_id = block_children[block_children.len - 1];
            const expr_children = ctx.snapshot.getChildren(last_stmt_id);
            if (expr_children.len > 0) {
                const expr_id = expr_children[0];
                const expr_node = ctx.snapshot.getNode(expr_id) orelse return;
                const expr_val = try lowerExpression(ctx, expr_id, expr_node);

                // Wrap in Error_Union_Construct (success case)
                const error_union_id = try ctx.builder.createNode(.Error_Union_Construct);
                try ctx.builder.graph.nodes.items[error_union_id].inputs.append(ctx.allocator, expr_val);
                try ctx.error_union_nodes.put(ctx.allocator, error_union_id, {});

                // Create implicit return
                _ = try ctx.builder.createReturn(error_union_id);
            }

            // Pop and Emit Defers
            var actions = try ctx.popScope();
            try ctx.emitDefersForScope(&actions);
        } else {
            // Normal block lowering
            try lowerBlock(ctx, bid, block);
        }
    } else {
        // Process children directly (parser flattened the block)
        // Check if last child is an expression that needs implicit return wrapping
        const func_children = children[1..];
        const needs_implicit_return = has_error_union_return and
                                     func_children.len > 0 and
                                     blk: {
            // Find last non-parameter/non-type child
            var last_stmt_child: ?NodeId = null;
            for (func_children) |child_id| {
                const child = ctx.snapshot.getNode(child_id) orelse continue;
                if (child.kind != .parameter and child.kind != .error_union_type) {
                    last_stmt_child = child_id;
                }
            }
            if (last_stmt_child) |child_id| {
                const child = ctx.snapshot.getNode(child_id) orelse break :blk false;
                break :blk child.kind == .expr_stmt;
            }
            break :blk false;
        };

        // Push Block Scope for the function body
        try ctx.pushScope(.Block);

        if (needs_implicit_return) {
            // Lower all but last statement
            var last_expr_id: ?NodeId = null;
            for (func_children) |child_id| {
                const child = ctx.snapshot.getNode(child_id) orelse continue;
                if (child.kind == .parameter or child.kind == .error_union_type) continue;

                // Check if this is the last statement
                const is_last = blk: {
                    var found_after = false;
                    var check_after = false;
                    for (func_children) |check_id| {
                        if (check_after) {
                            const check_node = ctx.snapshot.getNode(check_id) orelse continue;
                            if (check_node.kind != .parameter and check_node.kind != .error_union_type) {
                                found_after = true;
                                break;
                            }
                        }
                        if (@intFromEnum(check_id) == @intFromEnum(child_id)) {
                            check_after = true;
                        }
                    }
                    break :blk !found_after;
                };

                if (is_last and child.kind == .expr_stmt) {
                    last_expr_id = child_id;
                } else {
                    try lowerStatement(ctx, child_id, child);
                }
            }

            // Lower last expression and wrap in Error_Union_Construct
            if (last_expr_id) |expr_stmt_id| {
                const expr_children = ctx.snapshot.getChildren(expr_stmt_id);
                if (expr_children.len > 0) {
                    const expr_id = expr_children[0];
                    const expr_node = ctx.snapshot.getNode(expr_id) orelse return;
                    const expr_val = try lowerExpression(ctx, expr_id, expr_node);

                    // Wrap in Error_Union_Construct (success case)
                    const error_union_id = try ctx.builder.createNode(.Error_Union_Construct);
                    try ctx.builder.graph.nodes.items[error_union_id].inputs.append(ctx.allocator, expr_val);
                    try ctx.error_union_nodes.put(ctx.allocator, error_union_id, {});

                    // Create implicit return
                    _ = try ctx.builder.createReturn(error_union_id);
                }
            }
        } else {
            // Normal processing - check if last statement is expression (implicit return)
            // Only create implicit returns for functions with explicit return types
            var last_expr_stmt_id: ?NodeId = null;

            if (has_return_type_annotation and !has_error_union_return) {
                // Find last non-parameter/non-type statement
                for (func_children) |child_id| {
                    const child = ctx.snapshot.getNode(child_id) orelse continue;
                    if (child.kind != .parameter and child.kind != .error_union_type and child.kind != .type_annotation) {
                        if (child.kind == .expr_stmt) {
                            last_expr_stmt_id = child_id;
                        } else {
                            // Non-expression statement after this, so no implicit return
                            last_expr_stmt_id = null;
                        }
                    }
                }
            }

            // Lower all but potentially last expression
            for (func_children) |child_id| {
                const child = ctx.snapshot.getNode(child_id) orelse continue;
                if (child.kind == .parameter or child.kind == .error_union_type or child.kind == .type_annotation) continue;

                // If this is the last expr_stmt, handle it specially
                if (last_expr_stmt_id) |last_id| {
                    if (@intFromEnum(child_id) == @intFromEnum(last_id)) {
                        // This is the last expression - evaluate and create implicit return
                        const expr_children = ctx.snapshot.getChildren(child_id);
                        if (expr_children.len > 0) {
                            const expr_id = expr_children[0];
                            const expr_node = ctx.snapshot.getNode(expr_id) orelse continue;
                            const expr_val = try lowerExpression(ctx, expr_id, expr_node);
                            _ = try ctx.builder.createReturn(expr_val);
                        }
                        continue;
                    }
                }

                // Normal statement
                try lowerStatement(ctx, child_id, child);
            }
        }

        // Pop and Emit Defers
        var actions = try ctx.popScope();
        try ctx.emitDefersForScope(&actions);
    }
}

fn lowerBlock(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);

    // Push Block Scope
    try ctx.pushScope(.Block);

    for (children) |child_id| {
        const child = ctx.snapshot.getNode(child_id) orelse continue;
        try lowerStatement(ctx, child_id, child);
    }

    // Pop and Emit Defers
    var actions = try ctx.popScope();
    try ctx.emitDefersForScope(&actions);
}

fn lowerStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    switch (node.kind) {
        .expr_stmt => {
            const children = ctx.snapshot.getChildren(node_id);
            if (children.len > 0) {
                const expr = ctx.snapshot.getNode(children[0]) orelse return;
                _ = try lowerExpression(ctx, children[0], expr);
            }
        },

        .block_stmt => {
            try lowerBlock(ctx, node_id, node);
        },
        .fail_stmt => {
            try lowerFailStatement(ctx, node_id, node);
        },
        .return_stmt => {
            const children = ctx.snapshot.getChildren(node_id);
            var ret_val: u32 = 0;
            if (children.len > 0) {
                const expr = ctx.snapshot.getNode(children[0]) orelse return;
                ret_val = try lowerExpression(ctx, children[0], expr);
            } else {
                // Void return (0)
                ret_val = try ctx.builder.createConstant(.{ .integer = 0 });
            }

            // Emit all defers up to function root
            var i = ctx.defer_stack.items.len;
            while (i > 0) {
                i -= 1;
                // We must iterate in reverse (stack top to bottom), which matches popping
                // But we don't pop them definitively because 'return' might be conditional (inside if)
                // Actually, if we return, we redirect control flow. The code after return is dead.
                // But the defer_stack state must remain valid for other branches.
                // So we must CLONE the actions or iterate them without destroying.

                // Iterating current stack layer actions in reverse (LIFO)
                const layer = &ctx.defer_stack.items[i];
                var j = layer.actions.items.len;
                while (j > 0) {
                    j -= 1;
                    const action = layer.actions.items[j];

                    // Emit Call Copy
                    const call_id = try ctx.builder.createNode(.Call);
                    var node_def = &ctx.builder.graph.nodes.items[call_id];
                    node_def.data = .{ .string = try ctx.dupeForGraph(action.builtin_name) };
                    for (action.args.items) |arg| {
                        try node_def.inputs.append(ctx.allocator, arg);
                    }
                }
            }

            _ = try ctx.builder.createReturn(ret_val);
        },
        .defer_stmt => {
            try lowerDeferStatement(ctx, node_id, node);
        },
        .break_stmt => {
            try lowerBreakStatement(ctx, node_id, node);
        },
        .continue_stmt => {
            try lowerContinueStatement(ctx, node_id, node);
        },
        .let_stmt, .var_stmt => {
            _ = try lowerVarDecl(ctx, node_id, node);
        },
        .if_stmt => {
            try lowerIf(ctx, node_id, node);
        },
        .while_stmt => {
            try lowerWhile(ctx, node_id, node);
        },
        .for_stmt => {
            try lowerForStatement(ctx, node_id, node);
        },

        .match_stmt => {
            try lowerMatch(ctx, node_id, node);
        },
        .postfix_when => {
            try lowerPostfixWhen(ctx, node_id, node);
        },
        else => {},
    }
}

/// Helper: Check if the last emitted node is a terminator (Jump, Return, Branch)
fn lastNodeIsTerminator(ctx: *LoweringContext) bool {
    if (ctx.builder.graph.nodes.items.len == 0) return false;
    const last_op = ctx.builder.graph.nodes.items[ctx.builder.graph.nodes.items.len - 1].op;
    return last_op == .Jump or last_op == .Return or last_op == .Branch;
}

fn lowerIf(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    // Format: condition -> then_block -> [else_block]
    if (children.len < 2) return error.InvalidNode;

    const cond_id = children[0];
    const then_id = children[1];
    const else_id = if (children.len > 2) children[2] else null;

    // 1. Evaluate condition
    const cond_node = ctx.snapshot.getNode(cond_id) orelse return error.InvalidNode;
    const cond_val = try lowerExpression(ctx, cond_id, cond_node);

    // 2. Create Branch node (placeholder targets)
    const branch_node_id = try ctx.builder.createNode(.Branch);
    // Inputs: [cond, true_target, false_target]
    var branch_node = &ctx.builder.graph.nodes.items[branch_node_id];
    try branch_node.inputs.append(ctx.allocator, cond_val);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder true
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder false

    // 3. Emit Then Block
    const true_label_id = try ctx.builder.createNode(.Label);

    // Backpatch true target
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[1] = true_label_id;

    // Lower then body
    if (ctx.snapshot.getNode(then_id)) |then_node| {
        if (then_node.kind == .block_stmt) {
            try lowerBlock(ctx, then_id, then_node);
        } else {
            try lowerStatement(ctx, then_id, then_node);
        }
    }

    // Only emit jump to merge if the body didn't already terminate (break/continue/return)
    var jump_from_true: ?u32 = null;
    if (!lastNodeIsTerminator(ctx)) {
        jump_from_true = try ctx.builder.createNode(.Jump);
        var jump_true_inputs = &ctx.builder.graph.nodes.items[jump_from_true.?].inputs;
        try jump_true_inputs.append(ctx.allocator, 0); // Placeholder merge
    }

    // 4. Emit Else Block (if exists) or just Fallthrough
    const false_label_id = try ctx.builder.createNode(.Label);

    // Backpatch false target
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[2] = false_label_id;

    if (else_id) |eid| {
        if (ctx.snapshot.getNode(eid)) |else_node| {
            if (else_node.kind == .block_stmt) {
                try lowerBlock(ctx, eid, else_node);
            } else {
                try lowerStatement(ctx, eid, else_node);
            }
        }
    }

    // Only emit jump to merge if else body didn't already terminate
    var jump_from_false: ?u32 = null;
    if (!lastNodeIsTerminator(ctx)) {
        jump_from_false = try ctx.builder.createNode(.Jump);
        var jump_false_inputs = &ctx.builder.graph.nodes.items[jump_from_false.?].inputs;
        try jump_false_inputs.append(ctx.allocator, 0); // Placeholder merge
    }

    // 5. Emit Merge Label
    const merge_label_id = try ctx.builder.createNode(.Label);

    // Backpatch jumps (only if they were created)
    if (jump_from_true) |jft| {
        ctx.builder.graph.nodes.items[jft].inputs.items[0] = merge_label_id;
    }
    if (jump_from_false) |jff| {
        ctx.builder.graph.nodes.items[jff].inputs.items[0] = merge_label_id;
    }
}

fn lowerWhile(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    const cond_id = children[0];
    const body_id = children[1];

    // Track loop depth for break/continue patching
    const loop_depth = ctx.loop_depth;
    ctx.loop_depth += 1;

    // 1. Header Label (for back-edge and continue)
    const header_label_id = try ctx.builder.createNode(.Label);

    // 2. Evaluate Condition
    const cond_node = ctx.snapshot.getNode(cond_id) orelse return error.InvalidNode;
    const cond_val = try lowerExpression(ctx, cond_id, cond_node);

    // 3. Conditional Branch
    const branch_node_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_node_id];
    try branch_node.inputs.append(ctx.allocator, cond_val);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder body (true)
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder exit (false)

    // 4. Loop Body
    const body_label_id = try ctx.builder.createNode(.Label);

    // Backpatch true target
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[1] = body_label_id;

    if (ctx.snapshot.getNode(body_id)) |body_node| {
        if (body_node.kind == .block_stmt) {
            try ctx.pushScope(.Loop);
            try lowerBlock(ctx, body_id, body_node);
            var LoopActions = try ctx.popScope();
            try ctx.emitDefersForScope(&LoopActions);
        } else {
            try lowerStatement(ctx, body_id, body_node);
        }
    }

    // Back-edge to Header
    const jump_back = try ctx.builder.createNode(.Jump);
    var jump_back_inputs = &ctx.builder.graph.nodes.items[jump_back].inputs;
    try jump_back_inputs.append(ctx.allocator, header_label_id);

    // 5. Exit Label (created AFTER body so it's in correct IR position)
    const exit_label_id = try ctx.builder.createNode(.Label);

    // Backpatch false target to exit
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[2] = exit_label_id;

    // Restore loop depth
    ctx.loop_depth -= 1;

    // Patch all pending breaks at this loop depth
    var i: usize = 0;
    while (i < ctx.pending_breaks.items.len) {
        const pb = ctx.pending_breaks.items[i];
        if (pb.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pb.jump_id].inputs.items[0] = exit_label_id;
            _ = ctx.pending_breaks.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Patch all pending continues at this loop depth (for while: jump to header)
    i = 0;
    while (i < ctx.pending_continues.items.len) {
        const pc = ctx.pending_continues.items[i];
        if (pc.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pc.jump_id].inputs.items[0] = header_label_id;
            _ = ctx.pending_continues.swapRemove(i);
        } else {
            i += 1;
        }
    }
}

fn lowerForStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    // Format: loop_var -> iterable -> body
    if (children.len < 3) return error.InvalidNode;

    const var_id = children[0];
    const iterable_id = children[1];
    const body_id = children[2];

    // 1. Lower Iterator Variable Name
    const var_node = ctx.snapshot.getNode(var_id) orelse return error.InvalidNode;
    const var_token = ctx.snapshot.getToken(var_node.first_token) orelse return error.InvalidToken;
    const var_name = if (var_token.str) |sid| ctx.snapshot.astdb.str_interner.getString(sid) else "it";

    // 2. Lower Iterable (Expect Range)
    // We need to inspect the iterable node type.
    const iterable_node = ctx.snapshot.getNode(iterable_id) orelse return error.InvalidNode;

    var start_val: u32 = 0;
    var end_val: u32 = 0;
    var is_inclusive = false;

    if (iterable_node.kind == .range_inclusive_expr or iterable_node.kind == .range_exclusive_expr) {
        // Deconstruct the range manually here instead of using lowerExpression
        // because lowerExpression returns a "Range" object, but for a canonical Phi loop
        // we need the raw start/end values to build our own CFG.
        // If we lowered it to a Range object, we'd need instructions to unpack it at runtime.
        // Optimization: Inlining the range logic directly into the loop structure.

        const range_children = ctx.snapshot.getChildren(iterable_id);
        if (range_children.len != 2) return error.InvalidNode;

        const start_node = ctx.snapshot.getNode(range_children[0]) orelse return error.InvalidNode;
        const end_node = ctx.snapshot.getNode(range_children[1]) orelse return error.InvalidNode;

        start_val = try lowerExpression(ctx, range_children[0], start_node);
        end_val = try lowerExpression(ctx, range_children[1], end_node);
        is_inclusive = (iterable_node.kind == .range_inclusive_expr);
    } else {
        // Try to lower as a slice/array iteration
        // For slice: iterate from 0 to len-1, using SliceIndex for access
        const iterable_val = try lowerExpression(ctx, iterable_id, iterable_node);

        // Check if this is a slice
        if (ctx.slice_nodes.contains(iterable_val)) {
            // Slice iteration: for x in slice
            return lowerSliceForStatement(ctx, var_name, iterable_val, body_id);
        }

        // Not a supported iterable type
        return error.UnsupportedCall;
    }

    // 3. Create Loop Scope (for iterator variable)
    try ctx.pushScope(.Loop);
    // We pop at the very end

    // 4. Header Label (Loop Start)
    // We jump to this from entry (Fallthrough) AND back-edge.
    const header_label_id = try ctx.builder.createNode(.Label);

    // 5. Phi Node for Iterator
    // Iter = Phi(Start, NextIter)
    const phi_id = try ctx.builder.createNode(.Phi);
    var phi_node = &ctx.builder.graph.nodes.items[phi_id];

    // This Phi needs two inputs:
    // [0] from Entry block (Start Val)
    // [1] from Latch block (Next Val) - We don't have Latch block yet!
    // We will append inputs later or use placeholders.
    // Standard practice: Add StartVal now.
    try phi_node.inputs.append(ctx.allocator, start_val);

    // Register iterator in scope
    // But wait, user code expects a variable they can read.
    // In our IR, variables are Allocas.
    // So we should:
    //   Alloca(var_name)
    //   Store(Phi, Alloca)
    // This makes it addressable and mutable (if they want, though loop vars are usually const).

    const alloca_id = try ctx.builder.createNode(.Alloca);
    ctx.builder.graph.nodes.items[alloca_id].data = .{ .string = try ctx.dupeForGraph(var_name) };
    try ctx.scope.put(var_name, alloca_id);

    const store_phi_id = try ctx.builder.createNode(.Store);
    var store_node = &ctx.builder.graph.nodes.items[store_phi_id];
    try store_node.inputs.append(ctx.allocator, alloca_id);
    try store_node.inputs.append(ctx.allocator, phi_id);

    // 6. Loop Condition (i < end) or (i <= end)
    const cond_op: OpCode = if (is_inclusive) .LessEqual else .Less;
    const cmp_id = try ctx.builder.createNode(cond_op);
    var cmp_node = &ctx.builder.graph.nodes.items[cmp_id];
    try cmp_node.inputs.append(ctx.allocator, phi_id);
    try cmp_node.inputs.append(ctx.allocator, end_val);

    // Track loop depth for break/continue patching
    const loop_depth = ctx.loop_depth;
    ctx.loop_depth += 1;

    // 7. Branch
    const branch_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_id];
    try branch_node.inputs.append(ctx.allocator, cmp_id);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder Body (True)
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder Exit (False)

    // 8. Body Block
    const body_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = body_label_id; // Patch True

    // Emit Body
    const body_node = ctx.snapshot.getNode(body_id) orelse return error.InvalidNode;
    if (body_node.kind == .block_stmt) {
        try lowerBlock(ctx, body_id, body_node);
    } else {
        try lowerStatement(ctx, body_id, body_node);
    }

    // 9. Latch Block (Increment & Jump)
    // For continue: we need to jump HERE, after the body, before increment
    const latch_label_id = try ctx.builder.createNode(.Label);

    const one_const = try ctx.builder.createConstant(.{ .integer = 1 });
    const add_id = try ctx.builder.createNode(.Add);
    var add_node = &ctx.builder.graph.nodes.items[add_id];
    try add_node.inputs.append(ctx.allocator, phi_id);
    try add_node.inputs.append(ctx.allocator, one_const);

    // Patch the Phi node's second input (Back-edge value)
    try ctx.builder.graph.nodes.items[phi_id].inputs.append(ctx.allocator, add_id);

    // Jump back to Header
    const jump_node_id = try ctx.builder.createNode(.Jump);
    try ctx.builder.graph.nodes.items[jump_node_id].inputs.append(ctx.allocator, header_label_id);

    // 10. Exit Label (created AFTER latch so it's in correct IR position)
    const exit_label_id = try ctx.builder.createNode(.Label);

    // Backpatch branch false target to exit
    ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = exit_label_id;

    // Restore loop depth
    ctx.loop_depth -= 1;

    // Patch all pending breaks at this loop depth
    var i: usize = 0;
    while (i < ctx.pending_breaks.items.len) {
        const pb = ctx.pending_breaks.items[i];
        if (pb.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pb.jump_id].inputs.items[0] = exit_label_id;
            _ = ctx.pending_breaks.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Patch all pending continues at this loop depth (for for-loop: jump to latch)
    i = 0;
    while (i < ctx.pending_continues.items.len) {
        const pc = ctx.pending_continues.items[i];
        if (pc.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pc.jump_id].inputs.items[0] = latch_label_id;
            _ = ctx.pending_continues.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Pop Loop Scope
    var actions = try ctx.popScope();
    try ctx.emitDefersForScope(&actions);
}

/// Lower a for-in loop over a slice
/// for x in slice { ... } compiles to:
///   len = SliceLen(slice)
///   i = 0
///   while i < len:
///     x = SliceIndex(slice, i)
///     body
///     i = i + 1
fn lowerSliceForStatement(ctx: *LoweringContext, var_name: []const u8, slice_val: u32, body_id: NodeId) LowerError!void {
    // 1. Get slice length
    const len_id = try ctx.builder.createNode(.SliceLen);
    var len_node = &ctx.builder.graph.nodes.items[len_id];
    try len_node.inputs.append(ctx.allocator, slice_val);

    // 2. Create loop scope
    try ctx.pushScope(.Loop);

    // 3. Header Label (Loop Start)
    const header_label_id = try ctx.builder.createNode(.Label);

    // 4. Phi Node for Index (starts at 0)
    const zero_const = try ctx.builder.createConstant(.{ .integer = 0 });
    const phi_id = try ctx.builder.createNode(.Phi);
    var phi_node = &ctx.builder.graph.nodes.items[phi_id];
    try phi_node.inputs.append(ctx.allocator, zero_const);
    // Second input (incremented value) added later

    // 5. Allocate loop variable for element
    const alloca_id = try ctx.builder.createNode(.Alloca);
    ctx.builder.graph.nodes.items[alloca_id].data = .{ .string = try ctx.dupeForGraph(var_name) };
    try ctx.scope.put(var_name, alloca_id);

    // 6. Get element at current index: SliceIndex(slice, i)
    const elem_id = try ctx.builder.createNode(.SliceIndex);
    var elem_node = &ctx.builder.graph.nodes.items[elem_id];
    try elem_node.inputs.append(ctx.allocator, slice_val);
    try elem_node.inputs.append(ctx.allocator, phi_id);

    // Store element in loop variable
    const store_id = try ctx.builder.createNode(.Store);
    var store_node = &ctx.builder.graph.nodes.items[store_id];
    try store_node.inputs.append(ctx.allocator, alloca_id);
    try store_node.inputs.append(ctx.allocator, elem_id);

    // 7. Loop Condition: i < len
    const cmp_id = try ctx.builder.createNode(.Less);
    var cmp_node = &ctx.builder.graph.nodes.items[cmp_id];
    try cmp_node.inputs.append(ctx.allocator, phi_id);
    try cmp_node.inputs.append(ctx.allocator, len_id);

    // Track loop depth for break/continue
    const loop_depth = ctx.loop_depth;
    ctx.loop_depth += 1;

    // 8. Branch
    const branch_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_id];
    try branch_node.inputs.append(ctx.allocator, cmp_id);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder Body (True)
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder Exit (False)

    // 9. Body Block
    const body_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = body_label_id;

    // Emit Body
    const body_node = ctx.snapshot.getNode(body_id) orelse return error.InvalidNode;
    if (body_node.kind == .block_stmt) {
        try lowerBlock(ctx, body_id, body_node);
    } else {
        try lowerStatement(ctx, body_id, body_node);
    }

    // 10. Latch Block (Increment & Jump)
    const latch_label_id = try ctx.builder.createNode(.Label);

    const one_const = try ctx.builder.createConstant(.{ .integer = 1 });
    const add_id = try ctx.builder.createNode(.Add);
    var add_node = &ctx.builder.graph.nodes.items[add_id];
    try add_node.inputs.append(ctx.allocator, phi_id);
    try add_node.inputs.append(ctx.allocator, one_const);

    // Patch the Phi node's second input (Back-edge value)
    try ctx.builder.graph.nodes.items[phi_id].inputs.append(ctx.allocator, add_id);

    // Jump back to Header
    const jump_node_id = try ctx.builder.createNode(.Jump);
    try ctx.builder.graph.nodes.items[jump_node_id].inputs.append(ctx.allocator, header_label_id);

    // 11. Exit Label
    const exit_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = exit_label_id;

    // Restore loop depth
    ctx.loop_depth -= 1;

    // Patch pending breaks
    var i: usize = 0;
    while (i < ctx.pending_breaks.items.len) {
        const pb = ctx.pending_breaks.items[i];
        if (pb.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pb.jump_id].inputs.items[0] = exit_label_id;
            _ = ctx.pending_breaks.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Patch pending continues
    i = 0;
    while (i < ctx.pending_continues.items.len) {
        const pc = ctx.pending_continues.items[i];
        if (pc.loop_depth == loop_depth) {
            ctx.builder.graph.nodes.items[pc.jump_id].inputs.items[0] = latch_label_id;
            _ = ctx.pending_continues.swapRemove(i);
        } else {
            i += 1;
        }
    }

    // Pop Loop Scope
    var actions = try ctx.popScope();
    try ctx.emitDefersForScope(&actions);
}

fn lowerArrayAccess(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, InvalidCall, InvalidNode, UnsupportedCall, InvalidBinaryExpr, OutOfMemory, UndefinedVariable }!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    const array_id = children[0];
    const index_id = children[1];

    const array_node = ctx.snapshot.getNode(array_id) orelse return error.InvalidNode;
    const index_node = ctx.snapshot.getNode(index_id) orelse return error.InvalidNode;

    const array_val = try lowerExpression(ctx, array_id, array_node);
    const index_val = try lowerExpression(ctx, index_id, index_node);

    // Check if the base is a slice (not an array)
    if (ctx.slice_nodes.contains(array_val)) {
        // Slice indexing: emit SliceIndex opcode (calls runtime function)
        const slice_idx_node_id = try ctx.builder.createNode(.SliceIndex);
        var slice_idx_node = &ctx.builder.graph.nodes.items[slice_idx_node_id];
        try slice_idx_node.inputs.append(ctx.allocator, array_val);
        try slice_idx_node.inputs.append(ctx.allocator, index_val);
        return slice_idx_node_id;
    }

    // Array indexing: Create Index node for single element access (GEP)
    const idx_node_id = try ctx.builder.createNode(.Index);
    var idx_node = &ctx.builder.graph.nodes.items[idx_node_id];
    try idx_node.inputs.append(ctx.allocator, array_val);
    try idx_node.inputs.append(ctx.allocator, index_val);

    return idx_node_id;
}

/// Lower slice expression: arr[start..end] or arr[start..<end]
fn lowerSliceExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode, is_inclusive: bool) LowerError!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    // Format: array, start, end (3 children)
    if (children.len < 3) return error.InvalidNode;

    const array_id = children[0];
    const start_id = children[1];
    const end_id = children[2];

    const array_node = ctx.snapshot.getNode(array_id) orelse return error.InvalidNode;
    const start_node = ctx.snapshot.getNode(start_id) orelse return error.InvalidNode;
    const end_node = ctx.snapshot.getNode(end_id) orelse return error.InvalidNode;

    const array_val = try lowerExpression(ctx, array_id, array_node);
    const start_val = try lowerExpression(ctx, start_id, start_node);
    const end_val = try lowerExpression(ctx, end_id, end_node);

    // Create Slice node with inputs: [array, start, end]
    const slice_node_id = try ctx.builder.createNode(.Slice);
    var slice_node = &ctx.builder.graph.nodes.items[slice_node_id];
    try slice_node.inputs.append(ctx.allocator, array_val);
    try slice_node.inputs.append(ctx.allocator, start_val);
    try slice_node.inputs.append(ctx.allocator, end_val);

    // Store inclusivity in data field (1 = inclusive, 0 = exclusive)
    slice_node.data = .{ .integer = if (is_inclusive) 1 else 0 };

    // Mark this node as producing a slice value
    try ctx.slice_nodes.put(ctx.allocator, slice_node_id, {});

    return slice_node_id;
}

fn lowerExpression(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, InvalidCall, InvalidNode, UnsupportedCall, InvalidBinaryExpr, OutOfMemory, UndefinedVariable }!u32 {
    // Check cache
    if (ctx.node_map.get(node_id)) |id| return id;

    const result_id = switch (node.kind) {
        .string_literal => try lowerStringLiteral(ctx, node),
        .char_literal => try lowerCharLiteral(ctx, node),
        .null_literal => try lowerNullLiteral(ctx),
        .integer_literal => try lowerIntegerLiteral(ctx, node_id, node),
        .float_literal => try lowerFloatLiteral(ctx, node_id, node),
        .bool_literal => try lowerBoolLiteral(ctx, node_id, node),
        .call_expr => try lowerCallExpr(ctx, node_id, node),
        .unary_expr => try lowerUnaryExpr(ctx, node_id, node),
        .binary_expr => try lowerBinaryExpr(ctx, node_id, node),
        .identifier => try lowerIdentifier(ctx, node_id, node),
        .array_lit, .array_literal => try lowerArrayLiteral(ctx, node_id, node),
        .index_expr => blk: {
            const result = try lowerArrayAccess(ctx, node_id, node);
            // Check if this is a SliceIndex (returns value directly) or Index (returns pointer)
            const result_node = &ctx.builder.graph.nodes.items[result];
            if (result_node.op == .SliceIndex) {
                // SliceIndex calls runtime and returns value directly
                break :blk result;
            } else {
                // Array Index returns a pointer (GEP), we must Load it for R-Value usage
                break :blk try ctx.builder.buildLoad(ctx.allocator, result, "idx_load");
            }
        },
        .slice_inclusive_expr => try lowerSliceExpr(ctx, node_id, node, true),
        .slice_exclusive_expr => try lowerSliceExpr(ctx, node_id, node, false),
        .field_expr => try lowerFieldExpr(ctx, node_id),
        .struct_literal => try lowerStructLiteral(ctx, node_id),
        .range_inclusive_expr => try lowerRangeExpr(ctx, node_id, node, true),
        .range_exclusive_expr => try lowerRangeExpr(ctx, node_id, node, false),
        .catch_expr => try lowerCatchExpr(ctx, node_id, node),
        .try_expr => try lowerTryExpr(ctx, node_id, node),
        else => {
            trace.traceError("lowerExpression", error.UnsupportedCall, "unsupported node kind");
            return error.UnsupportedCall;
        },
    };

    try ctx.node_map.put(node_id, result_id);
    return result_id;
}

/// Lower float literal: 3.14
fn lowerFloatLiteral(
    ctx: *LoweringContext,
    node_id: NodeId,
    node: *const AstNode,
) !u32 {
    _ = node_id;
    // Get token and extract lexeme from source span (zero-copy tokenization)
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const unit = ctx.snapshot.astdb.getUnitConst(ctx.unit_id) orelse return error.InvalidToken;
    const lexeme = unit.source[token.span.start..token.span.end];

    const val = std.fmt.parseFloat(f64, lexeme) catch {
        return error.InvalidToken;
    };

    return try ctx.builder.createConstant(.{ .float = val });
}

fn lowerStringLiteral(ctx: *LoweringContext, node: *const AstNode) error{ InvalidToken, OutOfMemory }!u32 {
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const str = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

    // Remove quotes if present (handle both regular "" and multiline """)
    var content = str;
    if (content.len >= 6 and std.mem.startsWith(u8, content, "\"\"\"") and std.mem.endsWith(u8, content, "\"\"\"")) {
        content = content[3 .. content.len - 3];
    } else if (content.len >= 2 and content[0] == '"' and content[content.len - 1] == '"') {
        content = content[1 .. content.len - 1];
    }

    // Process escape sequences
    var processed = std.ArrayListUnmanaged(u8){};
    defer processed.deinit(ctx.allocator);

    var i: usize = 0;
    while (i < content.len) {
        if (content[i] == '\\' and i + 1 < content.len) {
            const escaped_char: u8 = switch (content[i + 1]) {
                'n' => '\n',
                't' => '\t',
                'r' => '\r',
                '0' => 0,
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                else => content[i + 1],
            };
            try processed.append(ctx.allocator, escaped_char);
            i += 2;
        } else {
            try processed.append(ctx.allocator, content[i]);
            i += 1;
        }
    }

    // Ensure we own the string for graph hygiene
    const owned_content = try ctx.dupeForGraph(processed.items);
    return try ctx.builder.createConstant(.{ .string = owned_content });
}

fn lowerNullLiteral(ctx: *LoweringContext) error{OutOfMemory}!u32 {
    // Null is represented as integer 0 (null pointer) by default
    // When assigned to optional type, it gets converted to Optional_None in lowerVarDecl
    return try ctx.builder.createConstant(.{ .integer = 0 });
}

fn lowerCharLiteral(ctx: *LoweringContext, node: *const AstNode) error{ InvalidToken, OutOfMemory }!u32 {
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const unit = ctx.snapshot.astdb.getUnitConst(ctx.unit_id) orelse return error.InvalidToken;
    const lexeme = unit.source[token.span.start..token.span.end];

    // Parse character value from lexeme (e.g., 'a' or '\n')
    // Remove quotes
    if (lexeme.len < 3) return error.InvalidToken;
    const content = lexeme[1 .. lexeme.len - 1]; // Strip 'quotes'

    const char_value: i64 = if (content.len == 1) blk: {
        // Simple character: 'a'
        break :blk @intCast(content[0]);
    } else if (content.len >= 2 and content[0] == '\\') blk: {
        // Escape sequence: '\n', '\t', etc.
        break :blk switch (content[1]) {
            'n' => '\n',
            't' => '\t',
            'r' => '\r',
            '0' => 0,
            '\\' => '\\',
            '\'' => '\'',
            '"' => '"',
            else => @intCast(content[1]),
        };
    } else blk: {
        // Fallback
        break :blk if (content.len > 0) @intCast(content[0]) else 0;
    };

    return try ctx.builder.createConstant(.{ .integer = char_value });
}

fn lowerIntegerLiteral(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, OutOfMemory }!u32 {
    _ = node_id;
    // Get token and extract lexeme from source span (zero-copy tokenization)
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const unit = ctx.snapshot.astdb.getUnitConst(ctx.unit_id) orelse return error.InvalidToken;
    const lexeme = unit.source[token.span.start..token.span.end];

    // Strip underscores from numeric literal (e.g., 1_000_000 -> 1000000)
    var stripped: [64]u8 = undefined;
    var stripped_len: usize = 0;
    for (lexeme) |c| {
        if (c != '_') {
            if (stripped_len < stripped.len) {
                stripped[stripped_len] = c;
                stripped_len += 1;
            }
        }
    }
    const clean_lexeme = stripped[0..stripped_len];

    // Detect base from prefix: 0x (hex), 0b (binary), 0o (octal)
    const val: i32 = blk: {
        if (clean_lexeme.len > 2) {
            if (clean_lexeme[0] == '0' and (clean_lexeme[1] == 'x' or clean_lexeme[1] == 'X')) {
                break :blk std.fmt.parseInt(i32, clean_lexeme[2..], 16) catch 0;
            } else if (clean_lexeme[0] == '0' and (clean_lexeme[1] == 'b' or clean_lexeme[1] == 'B')) {
                break :blk std.fmt.parseInt(i32, clean_lexeme[2..], 2) catch 0;
            } else if (clean_lexeme[0] == '0' and (clean_lexeme[1] == 'o' or clean_lexeme[1] == 'O')) {
                break :blk std.fmt.parseInt(i32, clean_lexeme[2..], 8) catch 0;
            }
        }
        break :blk std.fmt.parseInt(i32, clean_lexeme, 10) catch 0;
    };
    return try ctx.builder.createConstant(.{ .integer = val });
}

fn lowerBoolLiteral(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, OutOfMemory }!u32 {
    _ = node_id;
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const str = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "false";
    const val = std.mem.eql(u8, str, "true");
    return try ctx.builder.createConstant(.{ .boolean = val });
}

fn lowerCallExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, InvalidCall, InvalidNode, UnsupportedCall, InvalidBinaryExpr, OutOfMemory, UndefinedVariable }!u32 {
    const scope = trace.trace("lowerCallExpr", "");
    defer scope.end();

    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len == 0) {
        trace.traceError("lowerCallExpr", error.InvalidCall, "no children");
        return error.InvalidCall;
    }

    // First child is callee
    const callee_id = children[0];
    const callee = ctx.snapshot.getNode(callee_id) orelse {
        trace.traceError("lowerCallExpr", error.InvalidNode, "callee node not found");
        return error.InvalidNode;
    };

    // === Handle simple identifier calls (builtins and user functions) ===
    if (callee.kind == .identifier) {
        const token = ctx.snapshot.getToken(callee.first_token) orelse return error.InvalidToken;
        const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

        trace.dumpContext("lowerCallExpr", "Lowering call to '{s}'", .{name});

        // Try builtin registry first
        if (builtin_calls.findBuiltin(name)) |builtin| {
            return try lowerBuiltinCall(ctx, builtin, children);
        }

        // Check for Quantum Operations
        if (isQuantumOp(name)) {
            var args = std.ArrayListUnmanaged(u32){};
            defer args.deinit(ctx.allocator);
            for (children[1..]) |arg_id| {
                const arg = ctx.snapshot.getNode(arg_id) orelse continue;
                const arg_val = try lowerExpression(ctx, arg_id, arg);
                try args.append(ctx.allocator, arg_val);
            }
            return try lowerQuantumOp(ctx, name, args.items);
        }

        // Check for einsum (direct call, not field)
        if (std.mem.eql(u8, name, "einsum")) {
            var args = std.ArrayListUnmanaged(u32){};
            defer args.deinit(ctx.allocator);
            for (children[1..]) |arg_id| {
                const arg = ctx.snapshot.getNode(arg_id) orelse continue;
                const arg_val = try lowerExpression(ctx, arg_id, arg);
                try args.append(ctx.allocator, arg_val);
            }
            ctx.builder.current_tenancy = .NPU_Tensor;
            const tensor_node_id = try ctx.builder.createNode(.Tensor_Contract);
            var ir_node = &ctx.builder.graph.nodes.items[tensor_node_id];
            try ir_node.inputs.appendSlice(ctx.builder.graph.allocator, args.items);
            return tensor_node_id;
        }

        // Generic Function Call (User-defined or recursion)
        trace.dumpContext("lowerCallExpr", "User function call: '{s}'", .{name});
        return try lowerUserFunctionCall(ctx, name, children);
    }

    // === Handle field expressions (std.array.create, string.len, etc.) ===
    if (callee.kind == .field_expr) {
        return try lowerFieldCall(ctx, callee_id, children);
    }

    trace.traceError("lowerCallExpr", error.UnsupportedCall, "unsupported callee kind");
    return error.UnsupportedCall;
}

/// Lower assertion logic to branching instructions
fn lowerAssert(ctx: *LoweringContext, args: []const u32) !u32 {
    if (args.len < 1) return error.InvalidCall;
    const cond = args[0];

    // Branch cond, OK, FAIL
    const branch_id = try ctx.builder.createNode(.Branch);
    var branch = &ctx.builder.graph.nodes.items[branch_id];
    try branch.inputs.append(ctx.allocator, cond);
    try branch.inputs.append(ctx.allocator, 0); // Placeholder OK
    try branch.inputs.append(ctx.allocator, 0); // Placeholder FAIL

    // FAIL BLOCK
    const fail_label = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = fail_label;

    // Return 1 (Error)
    const c_1 = try ctx.builder.createConstant(.{ .integer = 1 });
    const ret_fail = try ctx.builder.createNode(.Return);
    try ctx.builder.graph.nodes.items[ret_fail].inputs.append(ctx.allocator, c_1);

    // OK BLOCK
    const ok_label = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = ok_label;

    // Return 0 (Success/Void)
    return try ctx.builder.createConstant(.{ .integer = 0 });
}

/// Lower a builtin call using the registry
/// Doctrine: Table-driven dispatch with explicit tenancy for tensor/quantum/SSM operations
fn lowerBuiltinCall(
    ctx: *LoweringContext,
    builtin: *const builtin_calls.BuiltinCall,
    children: []const NodeId,
) !u32 {
    const scope = trace.trace("lowerBuiltinCall", builtin.janus_name);
    defer scope.end();

    // Collect arguments
    var args = std.ArrayListUnmanaged(u32){};
    defer args.deinit(ctx.allocator);

    for (children[1..]) |arg_id| {
        const arg = ctx.snapshot.getNode(arg_id) orelse continue;
        const arg_val = try lowerExpression(ctx, arg_id, arg);
        try args.append(ctx.allocator, arg_val);
    }

    // Validate argument count
    if (args.items.len < builtin.min_args) {
        trace.traceError("lowerBuiltinCall", error.InvalidCall, "too few arguments");
        return error.InvalidCall;
    }
    if (builtin.max_args) |max| {
        if (args.items.len > max) {
            trace.traceError("lowerBuiltinCall", error.InvalidCall, "too many arguments");
            return error.InvalidCall;
        }
    }

    // Dispatch based on operation category (prefix-based)
    // Doctrine: Mechanism over Policy - explicit categorization, no hidden magic

    // === Compiler Intrinsics ===
    if (std.mem.eql(u8, builtin.janus_name, "string_data_intrinsic")) {
        // Extract pointer from string literal constant
        // The argument should be a string literal (Constant with .string data)
        if (args.items.len != 1) return error.InvalidCall;

        const str_const_id = args.items[0];

        // The string constant already IS a pointer in LLVM (i8*)
        // We just return the constant ID directly
        return str_const_id;
    } else if (std.mem.eql(u8, builtin.janus_name, "string_len_intrinsic")) {
        // Get length of string literal at compile time
        if (args.items.len != 1) return error.InvalidCall;

        const str_const_id = args.items[0];
        const str_node = &ctx.builder.graph.nodes.items[str_const_id];

        // Extract length from the constant data
        const len: i32 = if (str_node.data == .string)
            @intCast(str_node.data.string.len)
        else
            0;

        return try ctx.builder.createConstant(.{ .integer = len });
    } else if (std.mem.startsWith(u8, builtin.janus_name, "tensor.")) {
        return try lowerTensorOp(ctx, builtin.janus_name, args.items);
    } else if (std.mem.startsWith(u8, builtin.janus_name, "quantum.")) {
        return try lowerQuantumBuiltin(ctx, builtin.janus_name, args.items);
    } else if (std.mem.startsWith(u8, builtin.janus_name, "ssm.")) {
        return try lowerSSMOp(ctx, builtin.janus_name, args.items);
    } else if (std.mem.eql(u8, builtin.janus_name, "assert")) {
        return try lowerAssert(ctx, args.items);
    }

    // Default: Standard runtime call (I/O, string, array, etc.)
    const call_node_id = try ctx.builder.createCall(args.items);
    ctx.builder.graph.nodes.items[call_node_id].data = .{ .string = try ctx.dupeForGraph(builtin.runtime_name) };

    trace.dumpContext("lowerBuiltinCall", "Created runtime call to '{s}' with {d} args", .{
        builtin.runtime_name,
        args.items.len,
    });

    return call_node_id;
}

/// Lower a user-defined or recursive function call
fn lowerUserFunctionCall(
    ctx: *LoweringContext,
    name: []const u8,
    children: []const NodeId,
) !u32 {
    const scope = trace.trace("lowerUserFunctionCall", name);
    defer scope.end();

    var args = std.ArrayListUnmanaged(u32){};
    defer args.deinit(ctx.allocator);

    for (children[1..]) |arg_id| {
        const arg = ctx.snapshot.getNode(arg_id) orelse continue;
        const arg_val = try lowerExpression(ctx, arg_id, arg);
        try args.append(ctx.allocator, arg_val);
    }

    const call_node_id = try ctx.builder.createCall(args.items);
    ctx.builder.graph.nodes.items[call_node_id].data = .{ .string = try ctx.dupeForGraph(name) };

    return call_node_id;
}

/// Lower field expression calls (e.g., std.array.create, string.len)
fn lowerFieldCall(
    ctx: *LoweringContext,
    callee_id: NodeId,
    children: []const NodeId,
) !u32 {
    const scope = trace.trace("lowerFieldCall", "");
    defer scope.end();

    // Resolve field path: e.g. std.array.create → "std.array.create"
    var path_buffer: [256]u8 = undefined;
    var fba = std.heap.FixedBufferAllocator.init(&path_buffer);
    const allocator = fba.allocator();

    if (try resolveFieldPath(ctx, callee_id, allocator)) |full_path| {
        trace.dumpContext("lowerFieldCall", "Resolved path: '{s}'", .{full_path});

        // Check builtin registry with full path
        if (builtin_calls.findBuiltin(full_path)) |builtin| {
            return try lowerBuiltinCall(ctx, builtin, children);
        }

        // Special cases not yet in registry
        if (std.mem.eql(u8, full_path, "einsum")) {
            var args = std.ArrayListUnmanaged(u32){};
            defer args.deinit(ctx.allocator);
            for (children[1..]) |arg_id| {
                const arg = ctx.snapshot.getNode(arg_id) orelse continue;
                const arg_val = try lowerExpression(ctx, arg_id, arg);
                try args.append(ctx.allocator, arg_val);
            }
            ctx.builder.current_tenancy = .NPU_Tensor;
            const tensor_node_id = try ctx.builder.createNode(.Tensor_Contract);
            var ir_node = &ctx.builder.graph.nodes.items[tensor_node_id];
            try ir_node.inputs.appendSlice(ctx.builder.graph.allocator, args.items);
            return tensor_node_id;
        }

        // Generic field call - extract just the function name (last component)
        // For module-qualified calls like mathlib.add, use just "add" since
        // at LLVM level there are no namespaces - functions are global symbols
        const func_name = if (std.mem.lastIndexOfScalar(u8, full_path, '.')) |dot_idx|
            full_path[dot_idx + 1 ..]
        else
            full_path;
        trace.dumpContext("lowerFieldCall", "Using function name: '{s}'", .{func_name});
        return try lowerUserFunctionCall(ctx, func_name, children);
    }

    return error.UnsupportedCall;
}

// --- QUANTUM HELPERS ---

fn isQuantumOp(name: []const u8) bool {
    return std.mem.eql(u8, name, "hadamard") or
        std.mem.eql(u8, name, "cnot") or
        std.mem.eql(u8, name, "measure") or
        std.mem.eql(u8, name, "pauli_x") or
        std.mem.eql(u8, name, "pauli_y") or
        std.mem.eql(u8, name, "pauli_z") or
        std.mem.eql(u8, name, "phase") or
        std.mem.eql(u8, name, "t_gate") or
        std.mem.eql(u8, name, "cz") or
        std.mem.eql(u8, name, "swap") or
        std.mem.eql(u8, name, "toffoli") or
        std.mem.eql(u8, name, "fredkin") or
        std.mem.eql(u8, name, "rx") or
        std.mem.eql(u8, name, "ry") or
        std.mem.eql(u8, name, "rz");
}

fn lowerQuantumOp(ctx: *LoweringContext, name: []const u8, args: []const u32) !u32 {
    ctx.builder.current_tenancy = .QPU_Quantum;

    // Handle measurement
    if (std.mem.eql(u8, name, "measure")) {
        const node_id = try ctx.builder.createNode(.Quantum_Measure);
        var node = &ctx.builder.graph.nodes.items[node_id];

        // Extract qubit index from args (assuming constant for now)
        var qubits = try ctx.builder.graph.allocator.alloc(usize, 1);
        if (args.len > 0) {
            qubits[0] = try resolveQubitIndex(ctx, args[0]);
        } else {
            qubits[0] = 0;
        }

        node.quantum_metadata = .{
            .gate_type = .Hadamard, // Placeholder/Irrelevant for Measure
            .qubits = qubits,
            .parameters = &.{},
        };

        // Add dependency on previous quantum state (simplified)
        if (args.len > 0) {
            try node.inputs.append(ctx.builder.graph.allocator, args[0]);
        }

        return node_id;
    }

    // Handle gates
    const node_id = try ctx.builder.createNode(.Quantum_Gate);
    var node = &ctx.builder.graph.nodes.items[node_id];

    var gate_type: GateType = .Hadamard;
    var param_count: usize = 0;

    if (std.mem.eql(u8, name, "hadamard")) gate_type = .Hadamard;
    if (std.mem.eql(u8, name, "cnot")) gate_type = .CNOT;
    if (std.mem.eql(u8, name, "pauli_x")) gate_type = .PauliX;
    if (std.mem.eql(u8, name, "pauli_y")) gate_type = .PauliY;
    if (std.mem.eql(u8, name, "pauli_z")) gate_type = .PauliZ;
    if (std.mem.eql(u8, name, "phase")) gate_type = .Phase;
    if (std.mem.eql(u8, name, "t_gate")) gate_type = .T;
    if (std.mem.eql(u8, name, "cz")) gate_type = .CZ;
    if (std.mem.eql(u8, name, "swap")) gate_type = .SWAP;
    if (std.mem.eql(u8, name, "toffoli")) gate_type = .Toffoli;
    if (std.mem.eql(u8, name, "fredkin")) gate_type = .Fredkin;
    if (std.mem.eql(u8, name, "rx")) {
        gate_type = .RX;
        param_count = 1;
    }
    if (std.mem.eql(u8, name, "ry")) {
        gate_type = .RY;
        param_count = 1;
    }
    if (std.mem.eql(u8, name, "rz")) {
        gate_type = .RZ;
        param_count = 1;
    }

    // Extract qubits (args start after potential implicit ctx? No, args are direct here)
    // Args layout: [qubit0, qubit1, ..., param0, param1, ...]
    if (args.len < param_count) return error.InvalidCall; // Sanity check
    const qubit_count = args.len - param_count;

    var qubits = try ctx.builder.graph.allocator.alloc(usize, qubit_count);
    for (0..qubit_count) |i| {
        qubits[i] = try resolveQubitIndex(ctx, args[i]);
    }

    // Extract parameters
    var params = try ctx.builder.graph.allocator.alloc(f64, param_count);
    for (0..param_count) |i| {
        params[i] = try resolveParameter(ctx, args[qubit_count + i]);
    }

    node.quantum_metadata = .{
        .gate_type = gate_type,
        .qubits = qubits,
        .parameters = params,
    };

    // Add dependencies
    try node.inputs.appendSlice(ctx.builder.graph.allocator, args);

    return node_id;
}

fn resolveQubitIndex(ctx: *LoweringContext, node_id: u32) !usize {
    // Simplified: assume node is a Constant Integer
    const node = &ctx.builder.graph.nodes.items[node_id];
    if (node.op == .Constant) {
        return @as(usize, @intCast(node.data.integer));
    }
    return 0; // Fallback
}

fn resolveParameter(ctx: *LoweringContext, node_id: u32) !f64 {
    // Simplified: assume node is a Constant Float or Integer
    const node = &ctx.builder.graph.nodes.items[node_id];
    if (node.op == .Constant) {
        switch (node.data) {
            .float => |f| return f,
            .integer => |i| return @as(f64, @floatFromInt(i)),
            else => return 0.0,
        }
    }
    return 0.0;
}

// ============================================================================
// Specialized Lowering Functions - Tensor/Quantum/SSM Operations
// Doctrine: Explicit Hardware Tenancy + Clean Table-Driven Dispatch
// ============================================================================

/// Lower tensor operations to QTJIR with NPU_Tensor tenancy
/// Doctrine: Revealed Complexity - explicit hardware assignment, no hidden magic
fn lowerTensorOp(ctx: *LoweringContext, name: []const u8, args: []const u32) !u32 {
    const scope = trace.trace("lowerTensorOp", name);
    defer scope.end();

    // Set hardware tenancy for tensor operations
    ctx.builder.current_tenancy = .NPU_Tensor;

    // Map operation name to IR OpCode
    const op_code: OpCode = blk: {
        if (std.mem.eql(u8, name, "tensor.matmul")) break :blk .Tensor_Matmul;
        if (std.mem.eql(u8, name, "tensor.conv2d")) break :blk .Tensor_Conv;
        if (std.mem.eql(u8, name, "tensor.relu")) break :blk .Tensor_Relu;
        if (std.mem.eql(u8, name, "tensor.softmax")) break :blk .Tensor_Softmax;
        if (std.mem.eql(u8, name, "tensor.reduce_sum")) break :blk .Tensor_Reduce;
        if (std.mem.eql(u8, name, "tensor.reduce_max")) break :blk .Tensor_Reduce;

        // Fallback: treat as generic call (should not happen with proper registry)
        trace.traceError("lowerTensorOp", error.UnsupportedCall, "unknown tensor operation");
        return error.UnsupportedCall;
    };

    // Create IR node with proper OpCode
    const node_id = try ctx.builder.createNode(op_code);
    var node = &ctx.builder.graph.nodes.items[node_id];

    // Attach inputs
    try node.inputs.appendSlice(ctx.builder.graph.allocator, args);

    trace.dumpContext("lowerTensorOp", "Created {s} node with {d} inputs", .{
        @tagName(op_code),
        args.len,
    });

    return node_id;
}

/// Lower quantum operations from builtin registry (quantum.hadamard, quantum.cnot, etc.)
/// Doctrine: Explicit QPU tenancy with proper gate metadata
fn lowerQuantumBuiltin(ctx: *LoweringContext, name: []const u8, args: []const u32) !u32 {
    const scope = trace.trace("lowerQuantumBuiltin", name);
    defer scope.end();

    // Set hardware tenancy for quantum operations
    ctx.builder.current_tenancy = .QPU_Quantum;

    // Map operation name to gate type
    const gate_type: GateType = blk: {
        if (std.mem.eql(u8, name, "quantum.hadamard")) break :blk .Hadamard;
        if (std.mem.eql(u8, name, "quantum.cnot")) break :blk .CNOT;
        if (std.mem.eql(u8, name, "quantum.pauli_x")) break :blk .PauliX;
        if (std.mem.eql(u8, name, "quantum.pauli_y")) break :blk .PauliY;
        if (std.mem.eql(u8, name, "quantum.pauli_z")) break :blk .PauliZ;

        // Measurement is special case
        if (std.mem.eql(u8, name, "quantum.measure")) {
            const node_id = try ctx.builder.createNode(.Quantum_Measure);
            var node = &ctx.builder.graph.nodes.items[node_id];

            // Extract qubit index
            var qubits = try ctx.builder.graph.allocator.alloc(usize, 1);
            if (args.len > 0) {
                qubits[0] = try resolveQubitIndex(ctx, args[0]);
            } else {
                qubits[0] = 0;
            }

            node.quantum_metadata = .{
                .gate_type = .Hadamard, // Placeholder for measure
                .qubits = qubits,
                .parameters = &.{},
            };

            if (args.len > 0) {
                try node.inputs.append(ctx.builder.graph.allocator, args[0]);
            }

            trace.dumpContext("lowerQuantumBuiltin", "Created Quantum_Measure node", .{});
            return node_id;
        }

        trace.traceError("lowerQuantumBuiltin", error.UnsupportedCall, "unknown quantum operation");
        return error.UnsupportedCall;
    };

    // Create quantum gate node
    const node_id = try ctx.builder.createNode(.Quantum_Gate);
    var node = &ctx.builder.graph.nodes.items[node_id];

    // Extract qubits (all args are qubit indices for non-parameterized gates)
    var qubits = try ctx.builder.graph.allocator.alloc(usize, args.len);
    for (0..args.len) |i| {
        qubits[i] = try resolveQubitIndex(ctx, args[i]);
    }

    node.quantum_metadata = .{
        .gate_type = gate_type,
        .qubits = qubits,
        .parameters = &.{}, // No parameters for these gates
    };

    // Add dependencies
    try node.inputs.appendSlice(ctx.builder.graph.allocator, args);

    trace.dumpContext("lowerQuantumBuiltin", "Created Quantum_Gate ({s}) with {d} qubits", .{
        @tagName(gate_type),
        qubits.len,
    });

    return node_id;
}

/// Lower SSM (State Space Model) operations to QTJIR with NPU_Tensor tenancy
/// Doctrine: Mamba-3 inspired primitives for long-sequence modeling
fn lowerSSMOp(ctx: *LoweringContext, name: []const u8, args: []const u32) !u32 {
    const scope = trace.trace("lowerSSMOp", name);
    defer scope.end();

    // Set hardware tenancy for SSM operations (tensor-like)
    ctx.builder.current_tenancy = .NPU_Tensor;

    // Map operation name to IR OpCode
    const op_code: OpCode = blk: {
        if (std.mem.eql(u8, name, "ssm.scan")) break :blk .SSM_Scan;
        if (std.mem.eql(u8, name, "ssm.selective_scan")) break :blk .SSM_SelectiveScan;

        trace.traceError("lowerSSMOp", error.UnsupportedCall, "unknown SSM operation");
        return error.UnsupportedCall;
    };

    // Create IR node with proper OpCode
    const node_id = try ctx.builder.createNode(op_code);
    var node = &ctx.builder.graph.nodes.items[node_id];

    // Attach inputs (A, B, C matrices for scan; A, B, C, delta for selective_scan)
    try node.inputs.appendSlice(ctx.builder.graph.allocator, args);

    trace.dumpContext("lowerSSMOp", "Created {s} node with {d} inputs (A, B, C matrices)", .{
        @tagName(op_code),
        args.len,
    });

    return node_id;
}

fn resolveFieldPath(ctx: *LoweringContext, node_id: NodeId, allocator: std.mem.Allocator) !?[]const u8 {
    const node = ctx.snapshot.getNode(node_id) orelse return null;

    if (node.kind == .identifier) {
        const token = ctx.snapshot.getToken(node.first_token) orelse return null;
        if (token.str) |str_id| {
            return try allocator.dupe(u8, ctx.snapshot.astdb.str_interner.getString(str_id));
        }
        return null;
    } else if (node.kind == .field_expr) {
        const children = ctx.snapshot.getChildren(node_id);
        if (children.len != 2) return null;

        const left_path = try resolveFieldPath(ctx, children[0], allocator) orelse return null;
        const right_name = try resolveFieldPath(ctx, children[1], allocator) orelse return null;

        return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ left_path, right_name });
    }

    return null;
}

fn lowerVarDecl(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    // Child 0: Identifier
    const name_id = children[0];
    const name_node = ctx.snapshot.getNode(name_id) orelse return error.InvalidNode;
    if (name_node.kind != .identifier) return error.InvalidNode;

    const token = ctx.snapshot.getToken(name_node.first_token) orelse return error.InvalidToken;
    const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

    // Determine initializer index and check for optional type
    // If 3 children: [Name, Type, Init]
    // If 2 children: [Name, Init]
    var is_optional_type = false;
    const init_id = if (children.len == 3) blk: {
        // Check if type annotation is optional
        const type_id = children[1];
        const type_node = ctx.snapshot.getNode(type_id);
        if (type_node != null and type_node.?.kind == .optional_type) {
            is_optional_type = true;
        }
        break :blk children[2];
    } else children[1];

    // Lower initializer
    const init_node = ctx.snapshot.getNode(init_id) orelse return error.InvalidNode;
    var init_val = try lowerExpression(ctx, init_id, init_node);

    // If assigning to optional type, handle wrapping
    if (is_optional_type) {
        // Check if init is null literal - convert to Optional_None
        if (init_node.kind == .null_literal) {
            const none_id = try ctx.builder.createNode(.Optional_None);
            try ctx.optional_nodes.put(ctx.allocator, none_id, {});
            init_val = none_id;
        } else if (!ctx.optional_nodes.contains(init_val)) {
            // Wrap non-optional value in Optional_Some
            const some_id = try ctx.builder.createNode(.Optional_Some);
            var some_node = &ctx.builder.graph.nodes.items[some_id];
            try some_node.inputs.append(ctx.allocator, init_val);
            try ctx.optional_nodes.put(ctx.allocator, some_id, {});
            init_val = some_id;
        }
    }

    // Create alloca ONLY if mutable (var_stmt)
    if (node.kind == .var_stmt) {
        // Check if initializer is a struct (Struct_Construct node)
        const init_ir_node = &ctx.builder.graph.nodes.items[init_val];
        if (init_ir_node.op == .Struct_Construct) {
            // Create Struct_Alloca with struct metadata
            const struct_alloca = try ctx.builder.createNode(.Struct_Alloca);
            var alloca_node = &ctx.builder.graph.nodes.items[struct_alloca];
            // Duplicate field names string (can't share with Struct_Construct)
            const field_names_str = switch (init_ir_node.data) {
                .string => |s| try ctx.dupeForGraph(s),
                else => try ctx.dupeForGraph(""),
            };
            alloca_node.data = .{ .string = field_names_str };
            // Store struct value input for type inference
            try alloca_node.inputs.appendSlice(ctx.allocator, init_ir_node.inputs.items);

            // Create Store to put struct value into alloca
            const store_id = try ctx.builder.createNode(.Store);
            var store_node = &ctx.builder.graph.nodes.items[store_id];
            try store_node.inputs.append(ctx.allocator, struct_alloca);
            try store_node.inputs.append(ctx.allocator, init_val);

            try ctx.scope.put(name, struct_alloca);
            return struct_alloca;
        } else {
            // Regular scalar alloca
            const alloca_inst = try ctx.builder.buildAlloca(ctx.allocator, .i32, name);
            _ = try ctx.builder.buildStore(ctx.allocator, init_val, alloca_inst);
            try ctx.scope.put(name, alloca_inst);
            return alloca_inst;
        }
    } else {
        // Immutable (let_stmt): Direct Alias / Register Promotion
        try ctx.scope.put(name, init_val);
        return init_val;
    }
}

fn lowerIdentifier(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    _ = node_id;
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

    if (ctx.scope.get(name)) |target_id| {
        const target_node = &ctx.builder.graph.nodes.items[target_id];
        if (target_node.op == .Alloca) {
            const load_id = try ctx.builder.buildLoad(ctx.allocator, target_id, name);
            return load_id;
        } else {
            return target_id;
        }
    } else {
        return error.UndefinedVariable;
    }
}

/// Lower an expression as an L-Value (Address/Pointer)
fn lowerLValue(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    switch (node.kind) {
        .identifier => {
            const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
            const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

            if (ctx.scope.get(name)) |target_id| {
                const target_node = &ctx.builder.graph.nodes.items[target_id];
                if (target_node.op == .Alloca or target_node.op == .Struct_Alloca) {
                    return target_id; // Return address
                } else {
                    return error.InvalidCall; // Cannot assign to non-alloca
                }
            } else {
                return error.UndefinedVariable;
            }
        },
        .index_expr => {
            // lowerArrayAccess returns the GEP node (Pointer)
            return try lowerArrayAccess(ctx, node_id, node);
        },
        .field_expr => {
            // Field assignment: s.field = value
            // Create Field_Store node that returns the field address
            const children = ctx.snapshot.getChildren(node_id);
            if (children.len < 2) return error.InvalidNode;

            const struct_id = children[0];
            const field_id = children[1];

            const struct_node = ctx.snapshot.getNode(struct_id) orelse return error.InvalidNode;
            const field_node = ctx.snapshot.getNode(field_id) orelse return error.InvalidNode;

            // Get the struct alloca (must be mutable)
            const struct_val = try lowerLValue(ctx, struct_id, struct_node);

            // Get field name
            const token = ctx.snapshot.getToken(field_node.first_token) orelse return error.InvalidToken;
            const field_name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

            // Create Field_Store node (acts as field pointer for store)
            const store_node = try ctx.builder.createNode(.Field_Store);
            var ir_node = &ctx.builder.graph.nodes.items[store_node];
            try ir_node.inputs.append(ctx.allocator, struct_val);
            ir_node.data = .{ .string = try ctx.dupeForGraph(field_name) };

            return store_node;
        },
        else => return error.InvalidBinaryExpr, // Not an L-Value
    }
}

fn lowerRangeExpr(
    ctx: *LoweringContext,
    node_id: NodeId,
    node: *const AstNode,
    inclusive: bool,
) LowerError!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len != 2) return error.InvalidNode;

    const start_node = ctx.snapshot.getNode(children[0]) orelse return error.InvalidNode;
    const end_node = ctx.snapshot.getNode(children[1]) orelse return error.InvalidNode;

    const start_val = try lowerExpression(ctx, children[0], start_node);
    const end_val = try lowerExpression(ctx, children[1], end_node);

    const range_node = try ctx.builder.createNode(.Range);
    var ir_node = &ctx.builder.graph.nodes.items[range_node];

    // Store inclusivity in data payload
    ir_node.data = .{ .boolean = inclusive };

    try ir_node.inputs.append(ctx.allocator, start_val);
    try ir_node.inputs.append(ctx.allocator, end_val);

    return range_node;
}

fn lowerBinaryExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) error{ InvalidToken, InvalidCall, InvalidNode, UnsupportedCall, InvalidBinaryExpr, OutOfMemory, UndefinedVariable }!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len != 2) return error.InvalidBinaryExpr;

    const lhs_id = children[0];
    const rhs_id = children[1];

    const lhs = ctx.snapshot.getNode(lhs_id) orelse return error.InvalidNode;
    const rhs = ctx.snapshot.getNode(rhs_id) orelse return error.InvalidNode;

    // Determine opcode from token kind
    // Scan tokens between LHS and RHS to find the operator
    var op_token_idx = @intFromEnum(lhs.last_token) + 1;
    const end_idx = @intFromEnum(rhs.first_token);

    var op_token_kind: astdb.Token.TokenKind = .invalid;

    while (op_token_idx < end_idx) : (op_token_idx += 1) {
        const token = ctx.snapshot.getToken(@enumFromInt(op_token_idx)) orelse return error.InvalidToken;

        switch (token.kind) {
            .newline, .whitespace, .line_comment, .block_comment, .left_paren, .right_paren => continue,
            else => {
                op_token_kind = token.kind;
                break;
            },
        }
    }

    if (op_token_kind == .invalid) return error.InvalidBinaryExpr;

    // Handle Assignment
    if (op_token_kind == .assign) { // .assign is mapped from .equal by parser
        // LHS must be L-Value (Address)
        const lhs_addr = try lowerLValue(ctx, lhs_id, lhs);
        const rhs_val = try lowerExpression(ctx, rhs_id, rhs);

        // Create Store(rhs_val, lhs_addr)
        _ = try ctx.builder.buildStore(ctx.allocator, rhs_val, lhs_addr);

        // Assignment evaluates to RHS value
        return rhs_val;
    }

    // Handle Compound Assignment (+=, -=, *=, /=, %=, &=, |=, ^=, <<=, >>=)
    // Desugaring: x op= y  =>  x = x op y
    const compound_op: ?OpCode = switch (op_token_kind) {
        .plus_assign => .Add,
        .minus_assign => .Sub,
        .star_assign => .Mul,
        .slash_assign => .Div,
        .percent_assign => .Mod,
        .ampersand_assign => .BitAnd,
        .pipe_assign => .BitOr,
        .xor_assign => .Xor,
        .left_shift_assign => .Shl,
        .right_shift_assign => .Shr,
        else => null,
    };

    if (compound_op) |op| {
        // LHS must be L-Value (Address)
        const lhs_addr = try lowerLValue(ctx, lhs_id, lhs);

        // Load current value from LHS
        const lhs_val = try ctx.builder.buildLoad(ctx.allocator, lhs_addr, "compound_lhs");

        // Evaluate RHS
        const rhs_val = try lowerExpression(ctx, rhs_id, rhs);

        // Perform the operation
        const op_node = try ctx.builder.createNode(op);
        var ir_node = &ctx.builder.graph.nodes.items[op_node];
        try ir_node.inputs.append(ctx.allocator, lhs_val);
        try ir_node.inputs.append(ctx.allocator, rhs_val);

        // Store result back to LHS
        _ = try ctx.builder.buildStore(ctx.allocator, op_node, lhs_addr);

        // Compound assignment evaluates to the new value
        return op_node;
    }

    // Handle Logical Operators (Short-circuiting)
    // Note: .and_ and .or_ are the keyword tokens, .logical_and/.logical_or are alternative forms
    if (op_token_kind == .logical_and or op_token_kind == .logical_or or
        op_token_kind == .and_ or op_token_kind == .or_)
    {
        const is_and = (op_token_kind == .logical_and or op_token_kind == .and_);

        // Create a result variable to store the final boolean value
        // This avoids complex PHI node handling with proper block tracking
        const result_alloca = try ctx.builder.buildAlloca(ctx.allocator, .i32, "logical_result");

        // Store the short-circuit default value
        const short_circuit_val = try ctx.builder.createConstant(.{ .integer = if (is_and) 0 else 1 });
        _ = try ctx.builder.buildStore(ctx.allocator, short_circuit_val, result_alloca);

        // LHS evaluation
        const lhs_val = try lowerExpression(ctx, lhs_id, lhs);

        // Branch Node: Branch(cond, true_label, false_label)
        const branch_node_id = try ctx.builder.createNode(.Branch);
        var branch_node = &ctx.builder.graph.nodes.items[branch_node_id];
        try branch_node.inputs.append(ctx.allocator, lhs_val);
        try branch_node.inputs.append(ctx.allocator, 0); // Placeholder True
        try branch_node.inputs.append(ctx.allocator, 0); // Placeholder False

        // RHS Label (Entry to RHS evaluation)
        const rhs_label_id = try ctx.builder.createNode(.Label);

        // RHS Evaluation
        const rhs_val = try lowerExpression(ctx, rhs_id, rhs);

        // Convert RHS boolean to i32 (0 or 1) and store
        // For AND: result = rhs (if we got here, lhs was true)
        // For OR: result = rhs (if we got here, lhs was false)
        _ = try ctx.builder.buildStore(ctx.allocator, rhs_val, result_alloca);

        // Jump to Merge (after RHS)
        const jump_node_id = try ctx.builder.createNode(.Jump);
        ctx.builder.graph.nodes.items[jump_node_id].inputs = .{};
        try ctx.builder.graph.nodes.items[jump_node_id].inputs.append(ctx.allocator, 0); // Placeholder Merge

        // Merge Label
        const merge_label_id = try ctx.builder.createNode(.Label);

        // Backpatch Jump
        ctx.builder.graph.nodes.items[jump_node_id].inputs.items[0] = merge_label_id;

        // Backpatch Branch
        if (is_and) {
            // AND: True -> RHS (evaluate second operand), False -> Merge (short circuit with 0)
            ctx.builder.graph.nodes.items[branch_node_id].inputs.items[1] = rhs_label_id;
            ctx.builder.graph.nodes.items[branch_node_id].inputs.items[2] = merge_label_id;
        } else {
            // OR: True -> Merge (short circuit with 1), False -> RHS (evaluate second operand)
            ctx.builder.graph.nodes.items[branch_node_id].inputs.items[1] = merge_label_id;
            ctx.builder.graph.nodes.items[branch_node_id].inputs.items[2] = rhs_label_id;
        }

        // Load and return the result
        const result_load = try ctx.builder.buildLoad(ctx.allocator, result_alloca, "logical_result");
        return result_load;
    }

    const lhs_val = try lowerExpression(ctx, lhs_id, lhs);
    const rhs_val = try lowerExpression(ctx, rhs_id, rhs);

    const op: OpCode = switch (op_token_kind) {
        .plus => .Add,
        .minus => .Sub,
        .star => .Mul,
        .star_star => .Pow,
        .slash => .Div,
        .percent => .Mod,
        .equal_equal => .Equal,
        .not_equal => .NotEqual,
        .less => .Less,
        .less_equal => .LessEqual,
        .greater => .Greater,
        .greater_equal => .GreaterEqual,
        // Bitwise
        .bitwise_and, .ampersand => .BitAnd,
        .bitwise_or, .pipe => .BitOr,
        .bitwise_xor, .caret => .Xor,
        .left_shift => .Shl,
        .right_shift => .Shr,

        .at_sign => blk: {
            ctx.builder.current_tenancy = .NPU_Tensor;
            break :blk OpCode.Tensor_Matmul;
        },
        else => return error.InvalidBinaryExpr,
    };

    const op_node = try ctx.builder.createNode(op);
    var ir_node = &ctx.builder.graph.nodes.items[op_node];
    try ir_node.inputs.append(ctx.allocator, lhs_val);
    try ir_node.inputs.append(ctx.allocator, rhs_val);

    return op_node;
}

fn lowerUnaryExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    const token = ctx.snapshot.getToken(node.first_token) orelse return error.InvalidToken;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len != 1) return error.InvalidNode;

    // Lower operand
    const operand_id = children[0];
    const operand_node = ctx.snapshot.getNode(operand_id) orelse return error.InvalidNode;
    const operand_val = try lowerExpression(ctx, operand_id, operand_node);

    const op: OpCode = switch (token.kind) {
        .minus => {
            // Negation: 0 - x
            const zero = try ctx.builder.createConstant(.{ .integer = 0 });

            const sub = try ctx.builder.createNode(.Sub);
            var sub_node = &ctx.builder.graph.nodes.items[sub];
            try sub_node.inputs.append(ctx.allocator, zero);
            try sub_node.inputs.append(ctx.allocator, operand_val);
            return sub;
        },
        .exclamation, .logical_not, .not_ => {
            // Logical Not: x == false (x XOR true for booleans)
            const false_val = try ctx.builder.createConstant(.{ .boolean = false });

            const eq = try ctx.builder.createNode(.Equal);
            var eq_node = &ctx.builder.graph.nodes.items[eq];
            try eq_node.inputs.append(ctx.allocator, operand_val);
            try eq_node.inputs.append(ctx.allocator, false_val);
            return eq;
        },
        .tilde, .bitwise_not => .BitNot,
        else => return error.InvalidNode,
    };

    // For simple ops like BitNot (not blocks)
    if (op != .Sub and op != .Equal) { // Already returned for Block-likes
        const node_idx = try ctx.builder.createNode(op);
        var ir_node = &ctx.builder.graph.nodes.items[node_idx];
        try ir_node.inputs.append(ctx.allocator, operand_val);
        return node_idx;
    }

    // Should not reach here
    return error.InvalidNode;
}

fn lowerArrayLiteral(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);

    // Lower all elements first to ensure they precede the array constructor in the graph
    var elements = std.ArrayListUnmanaged(u32){};
    defer elements.deinit(ctx.allocator);

    for (children) |child_id| {
        const child = ctx.snapshot.getNode(child_id) orelse return error.InvalidNode;
        const val_id = try lowerExpression(ctx, child_id, child);
        try elements.append(ctx.allocator, val_id);
    }

    // Create Array_Construct node
    const op_node = try ctx.builder.createNode(.Array_Construct);
    var ir_node = &ctx.builder.graph.nodes.items[op_node];

    // Add input edges
    try ir_node.inputs.appendSlice(ctx.allocator, elements.items);

    return op_node;
}

/// Lower struct literal: Point { x: 10, y: 20 }
/// Parser produces children as interleaved [name1, value1, name2, value2, ...]
fn lowerStructLiteral(ctx: *LoweringContext, node_id: NodeId) LowerError!u32 {
    const children = ctx.snapshot.getChildren(node_id);

    // Collect field names and values (interleaved: name, value, name, value)
    var field_names = std.ArrayListUnmanaged([]const u8){};
    defer field_names.deinit(ctx.allocator);
    var values = std.ArrayListUnmanaged(u32){};
    defer values.deinit(ctx.allocator);

    var i: usize = 1;
    while (i + 1 < children.len) {
        const name_id = children[i];
        const value_id = children[i + 1];

        // Get field name from identifier node
        const name_node = ctx.snapshot.getNode(name_id) orelse {
            i += 2;
            continue;
        };
        const token = ctx.snapshot.getToken(name_node.first_token) orelse {
            i += 2;
            continue;
        };
        const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";
        // try field_names.append(ctx.allocator, name); (Already in original?)
        try field_names.append(ctx.allocator, name);

        // Lower the value expression
        const val_node = ctx.snapshot.getNode(value_id) orelse {
            i += 2;
            continue;
        };

        const val_ir = try lowerExpression(ctx, value_id, val_node);
        try values.append(ctx.allocator, val_ir);

        i += 2;
    }

    // Create Struct_Construct node
    const struct_node = try ctx.builder.createNode(.Struct_Construct);
    var ir_node = &ctx.builder.graph.nodes.items[struct_node];

    // Store field names as comma-separated string in data
    var name_buf = std.ArrayListUnmanaged(u8){};
    defer name_buf.deinit(ctx.allocator);
    for (field_names.items, 0..) |name, j| {
        if (j > 0) try name_buf.append(ctx.allocator, ',');
        try name_buf.appendSlice(ctx.allocator, name);
    }
    const names_str = try ctx.dupeForGraph(name_buf.items);
    ir_node.data = .{ .string = names_str };

    // Add value inputs
    try ir_node.inputs.appendSlice(ctx.allocator, values.items);

    return struct_node;
}

/// Lower field expression: s.field
/// Special case: ErrorType.Variant (error variant access)
fn lowerFieldExpr(ctx: *LoweringContext, node_id: NodeId) LowerError!u32 {
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    // First child is struct expression (or error type), second is field name (or variant)
    const struct_id = children[0];
    const field_id = children[1];

    const struct_node = ctx.snapshot.getNode(struct_id) orelse return error.InvalidNode;
    const field_node = ctx.snapshot.getNode(field_id) orelse return error.InvalidNode;

    // Check if this might be an error variant access (ErrorType.Variant)
    // If left side is an identifier that's not in scope, check if it's an error type
    if (struct_node.kind == .identifier) {
        const token = ctx.snapshot.getToken(struct_node.first_token) orelse return error.InvalidToken;
        const error_type_name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

        // Check if this identifier is in scope (variables, parameters, etc.)
        if (ctx.scope.get(error_type_name) == null) {
            // Not in scope - might be an error type
            // Search AST for error declaration with this name
            if (try findErrorVariantIndex(ctx, error_type_name, field_node)) |variant_index| {
                // This is an error variant access - return variant index as constant
                return try ctx.builder.createConstant(.{ .integer = @intCast(variant_index) });
            }
            // If not found as error variant, fall through to regular field access
            // which will fail with UndefinedVariable (correct behavior)
        }
    }

    // Regular struct field access
    const struct_val = try lowerExpression(ctx, struct_id, struct_node);

    // Get field name
    const token = ctx.snapshot.getToken(field_node.first_token) orelse return error.InvalidToken;
    const field_name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

    // Create Field_Access node
    const access_node = try ctx.builder.createNode(.Field_Access);
    var ir_node = &ctx.builder.graph.nodes.items[access_node];

    // Struct is input, field name is in data
    try ir_node.inputs.append(ctx.allocator, struct_val);
    ir_node.data = .{ .string = try ctx.dupeForGraph(field_name) };

    return access_node;
}

/// Find error variant index in AST
/// Returns variant's ordinal position within the error type declaration
fn findErrorVariantIndex(ctx: *LoweringContext, error_type_name: []const u8, variant_node: *const AstNode) !?usize {
    const unit = ctx.snapshot.astdb.getUnitConst(ctx.unit_id) orelse return null;

    // Get variant name
    const variant_token = ctx.snapshot.getToken(variant_node.first_token) orelse return null;
    const variant_name = if (variant_token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

    // Search for error declaration with matching name
    for (unit.nodes, 0..) |node, i| {
        if (node.kind != .error_decl) continue;

        const error_node_id: NodeId = @enumFromInt(@as(u32, @intCast(i)));
        const error_children = ctx.snapshot.getChildren(error_node_id);
        if (error_children.len == 0) continue;

        // First child is error type name
        const name_node = ctx.snapshot.getNode(error_children[0]) orelse continue;
        const name_token = ctx.snapshot.getToken(name_node.first_token) orelse continue;
        const decl_name = if (name_token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

        // Check if this is the error type we're looking for
        if (std.mem.eql(u8, decl_name, error_type_name)) {
            // Found the error type - search for variant
            // Variants are children[1..] of the error declaration
            for (error_children[1..], 0..) |variant_id, variant_idx| {
                const var_node = ctx.snapshot.getNode(variant_id) orelse continue;
                if (var_node.kind != .variant) continue;

                const var_token = ctx.snapshot.getToken(var_node.first_token) orelse continue;
                const var_name = if (var_token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";

                if (std.mem.eql(u8, var_name, variant_name)) {
                    // Found the variant - return its index
                    return variant_idx;
                }
            }
        }
    }

    return null;
}

fn lowerDeferStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    // std.debug.print("Lowering defer statement!\n", .{});
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len == 0) return error.InvalidNode;

    // Child is expression (usually call_expr)
    // We expect a call expression for now
    const expr_id = children[0];
    const expr_node = ctx.snapshot.getNode(expr_id) orelse return error.InvalidNode;

    if (expr_node.kind != .call_expr) {
        // We only support deferring calls for now
        return error.UnsupportedCall;
    }

    const call_children = ctx.snapshot.getChildren(expr_id);
    if (call_children.len == 0) return error.InvalidCall;

    // Get Callee Name
    const callee_id = call_children[0];
    const callee = ctx.snapshot.getNode(callee_id) orelse return error.InvalidNode;

    var name: []const u8 = "";
    if (callee.kind == .identifier) {
        const token = ctx.snapshot.getToken(callee.first_token) orelse return error.InvalidToken;
        name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";
    } else {
        return error.UnsupportedCall; // Only identifier calls supported for defer
    }

    // Capture Arguments
    var args = std.ArrayListUnmanaged(u32){};
    errdefer args.deinit(ctx.allocator);

    for (call_children[1..]) |arg_id| {
        const arg = ctx.snapshot.getNode(arg_id) orelse continue;
        const arg_val = try lowerExpression(ctx, arg_id, arg);
        try args.append(ctx.allocator, arg_val);
    }

    // Resolve builtin name if applicable
    var final_name = name;
    if (builtin_calls.findBuiltin(name)) |builtin| {
        final_name = builtin.runtime_name;
    }

    // Register Defer
    try ctx.registerDefer(.{
        .builtin_name = try ctx.allocator.dupe(u8, final_name),
        .args = args,
    });
}

fn lowerBreakStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node_id;
    _ = node;

    if (ctx.loop_depth == 0) {
        return error.InvalidNode; // Break outside loop
    }

    const target_depth = ctx.loop_depth - 1;

    // Emit Defers up to nearest Loop scope
    var i = ctx.defer_stack.items.len;
    while (i > 0) {
        i -= 1;
        const layer = &ctx.defer_stack.items[i];

        if (layer.type == .Loop) {
            break;
        }

        var j = layer.actions.items.len;
        while (j > 0) {
            j -= 1;
            const action = layer.actions.items[j];

            const call_id = try ctx.builder.createNode(.Call);
            var node_def = &ctx.builder.graph.nodes.items[call_id];
            node_def.data = .{ .string = try ctx.dupeForGraph(action.builtin_name) };
            for (action.args.items) |arg| {
                try node_def.inputs.append(ctx.allocator, arg);
            }
        }
    }

    // Emit Jump with placeholder target (will be patched when loop ends)
    const jump_id = try ctx.builder.createNode(.Jump);
    try ctx.builder.graph.nodes.items[jump_id].inputs.append(ctx.allocator, 0); // Placeholder

    // Register for patching
    try ctx.pending_breaks.append(ctx.allocator, .{
        .jump_id = jump_id,
        .loop_depth = target_depth,
    });
}

fn lowerContinueStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node_id;
    _ = node;

    if (ctx.loop_depth == 0) {
        return error.InvalidNode; // Continue outside loop
    }

    const target_depth = ctx.loop_depth - 1;

    // Emit Defers up to nearest Loop scope (same as break)
    var i = ctx.defer_stack.items.len;
    while (i > 0) {
        i -= 1;
        const layer = &ctx.defer_stack.items[i];

        if (layer.type == .Loop) {
            break;
        }

        var j = layer.actions.items.len;
        while (j > 0) {
            j -= 1;
            const action = layer.actions.items[j];

            const call_id = try ctx.builder.createNode(.Call);
            var node_def = &ctx.builder.graph.nodes.items[call_id];
            node_def.data = .{ .string = try ctx.dupeForGraph(action.builtin_name) };
            for (action.args.items) |arg| {
                try node_def.inputs.append(ctx.allocator, arg);
            }
        }
    }

    // Emit Jump with placeholder target (will be patched when loop ends)
    const jump_id = try ctx.builder.createNode(.Jump);
    try ctx.builder.graph.nodes.items[jump_id].inputs.append(ctx.allocator, 0); // Placeholder

    // Register for patching
    try ctx.pending_continues.append(ctx.allocator, .{
        .jump_id = jump_id,
        .loop_depth = target_depth,
    });
}

fn lowerMatch(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    const scrutinee_id = children[0];
    const scrutinee_node = ctx.snapshot.getNode(scrutinee_id) orelse return error.InvalidNode;
    const scrutinee_val = try lowerExpression(ctx, scrutinee_id, scrutinee_node);

    // We will generate a chain of if-else blocks (linear scan)
    // We will generate a chain of if-else blocks (linear scan)
    // Structure:
    // Arm1 Check -> True: Arm1 Body -> Jump End
    //            -> False: Arm2 Check ...
    // ...
    // Default/End Label

    // Track jumps that need to target the end label
    var jumps_to_end = std.ArrayListUnmanaged(u32){};
    defer jumps_to_end.deinit(ctx.allocator);

    // Iterate over arms (skipping scrutinee at 0)
    for (children[1..]) |arm_id| {
        const arm_node = ctx.snapshot.getNode(arm_id) orelse continue;
        if (arm_node.kind != .match_arm) continue;

        const arm_children = ctx.snapshot.getChildren(arm_id);
        if (arm_children.len < 3) continue;

        const pattern_id = arm_children[0];
        const guard_id = arm_children[1];
        const body_id = arm_children[arm_children.len - 1];

        const pattern_node = ctx.snapshot.getNode(pattern_id) orelse continue;
        var pattern_matches_val: u32 = 0;

        // Check if pattern is wildcard "_" (represented as identifier "_")
        var is_wildcard = false;
        if (pattern_node.kind == .identifier) {
            const token = ctx.snapshot.getToken(pattern_node.first_token) orelse return error.InvalidToken;
            const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";
            if (std.mem.eql(u8, name, "_")) {
                is_wildcard = true;
            }
        }

        if (is_wildcard) {
            // Always matches
            pattern_matches_val = try ctx.builder.createConstant(.{ .boolean = true });
        } else if (pattern_node.kind == .unary_expr) {
            // Check for negation pattern: !value means scrutinee != value
            const pattern_token = ctx.snapshot.getToken(pattern_node.first_token) orelse return error.InvalidToken;
            const is_negation = pattern_token.kind == .exclamation or
                pattern_token.kind == .logical_not or
                pattern_token.kind == .not_;

            if (is_negation) {
                // Negation pattern: !value -> scrutinee != value
                const pattern_children = ctx.snapshot.getChildren(pattern_id);
                if (pattern_children.len != 1) return error.InvalidNode;
                const inner_pattern_id = pattern_children[0];
                const inner_pattern_node = ctx.snapshot.getNode(inner_pattern_id) orelse return error.InvalidNode;
                const inner_val = try lowerExpression(ctx, inner_pattern_id, inner_pattern_node);

                const neq_node_id = try ctx.builder.createNode(.NotEqual);
                var neq_node = &ctx.builder.graph.nodes.items[neq_node_id];
                try neq_node.inputs.append(ctx.allocator, scrutinee_val);
                try neq_node.inputs.append(ctx.allocator, inner_val);
                pattern_matches_val = neq_node_id;
            } else {
                // Other unary expr - evaluate and compare
                const pattern_val = try lowerExpression(ctx, pattern_id, pattern_node);
                const eq_node_id = try ctx.builder.createNode(.Equal);
                var eq_node = &ctx.builder.graph.nodes.items[eq_node_id];
                try eq_node.inputs.append(ctx.allocator, scrutinee_val);
                try eq_node.inputs.append(ctx.allocator, pattern_val);
                pattern_matches_val = eq_node_id;
            }
        } else {
            // Equality check: scrutinee == pattern_val
            const pattern_val = try lowerExpression(ctx, pattern_id, pattern_node);
            const eq_node_id = try ctx.builder.createNode(.Equal);
            var eq_node = &ctx.builder.graph.nodes.items[eq_node_id];
            try eq_node.inputs.append(ctx.allocator, scrutinee_val);
            try eq_node.inputs.append(ctx.allocator, pattern_val);
            pattern_matches_val = eq_node_id;
        }

        // 2. Lower Guard Check (if match)
        var final_cond_val = pattern_matches_val;
        const guard_node = ctx.snapshot.getNode(guard_id);

        if (guard_node != null and guard_node.?.kind != .null_literal) {
            const guard_val = try lowerExpression(ctx, guard_id, guard_node.?);
            const and_node_id = try ctx.builder.createNode(.BitAnd);
            var and_node = &ctx.builder.graph.nodes.items[and_node_id];
            try and_node.inputs.append(ctx.allocator, pattern_matches_val);
            try and_node.inputs.append(ctx.allocator, guard_val);
            final_cond_val = and_node_id;
        }

        // 3. Branch
        const branch_id = try ctx.builder.createNode(.Branch);
        var branch_node = &ctx.builder.graph.nodes.items[branch_id];
        try branch_node.inputs.append(ctx.allocator, final_cond_val);
        try branch_node.inputs.append(ctx.allocator, 0); // Placeholder True (Body)
        try branch_node.inputs.append(ctx.allocator, 0); // Placeholder False (Next Arm)

        // 4. Body
        const body_label_id = try ctx.builder.createNode(.Label);
        // Backpatch True
        ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = body_label_id;

        const body = ctx.snapshot.getNode(body_id) orelse continue;
        if (body.kind == .block_stmt) {
            try lowerBlock(ctx, body_id, body);
        } else if (body.kind == .expr_stmt) {
            try lowerStatement(ctx, body_id, body);
        } else {
            // Body is an expression, lower it directly
            _ = try lowerExpression(ctx, body_id, body);
        }

        // Jump to End (ID TBD)
        const jump_end = try ctx.builder.createNode(.Jump);
        try ctx.builder.graph.nodes.items[jump_end].inputs.append(ctx.allocator, 0); // Placeholder
        try jumps_to_end.append(ctx.allocator, jump_end);

        // 5. Next Arm Label (for False path)
        const next_arm_label_id = try ctx.builder.createNode(.Label);
        // Backpatch False
        ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = next_arm_label_id;
    }

    // Default Fallthrough (if no arm matched)
    // Implicitly falls through to here if last arm False target is this label.
    // For MVP, just jump to end (do nothing).
    // Note: If last arm branches to next_arm_label_id, we are currently AT next_arm_label_id.

    // Create End Label HERE (physically after all arms)
    const end_label_id = try ctx.builder.createNode(.Label);

    // Backpatch all Jumps to End
    for (jumps_to_end.items) |jump_id| {
        ctx.builder.graph.nodes.items[jump_id].inputs.items[0] = end_label_id;
    }
    // But we needed the ID to backpatch jumps.

    // We use backpatching to handle forward jumps to the end label.

    // For the merge label, it creates it at the end: `const merge_label_id = try ctx.builder.createNode(.Label);`
    // And THEN it backpatches the jumps: `ctx.builder.graph.nodes.items[jump_from_true].inputs.items[0] = merge_label_id;`

    // So we should follow that pattern.
    // We need to track all "Jump to End" nodes.

    // var scope_jumps = std.ArrayList(u32).init(ctx.allocator);
    // defer scope_jumps.deinit();

    // Re-doing the loop logic briefly to correct the "End Label" issue:
    // We CAN'T create end_label_id at the start.
    // We will collect jumps and patch them later.

    // Also, we need valid 'false' targets for each arm to point to the NEXT arm.
    // The loop structure:
    // Loop {
    //    Branch(..., ..., NextLabelPlaceholder)
    //    Body...
    //    Jump(EndPlaceholder) -> collect
    //    NextLabelNode (Create HERE) -> Update prev Branch
    // }

    // Let's refine the loop above. Since I can't rewrite the loop I just wrote easily without messy edits,
    // I will rewrite the whole function body in the replacement.

    // (See replacement content below)
}

fn lowerPostfixWhen(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    const cond_id = children[0];
    const stmt_id = children[1];

    // Desugars to: if cond { stmt }

    // 1. Evaluate Condition
    const cond_node = ctx.snapshot.getNode(cond_id) orelse return error.InvalidNode;
    const cond_val = try lowerExpression(ctx, cond_id, cond_node);

    // 2. Branch
    const branch_node_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_node_id];
    try branch_node.inputs.append(ctx.allocator, cond_val);
    try branch_node.inputs.append(ctx.allocator, 0); // True (Body)
    try branch_node.inputs.append(ctx.allocator, 0); // False (Merge)

    // 3. Body
    const body_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[1] = body_label_id;

    if (ctx.snapshot.getNode(stmt_id)) |stmt| {
        if (stmt.kind == .block_stmt) {
            try lowerBlock(ctx, stmt_id, stmt);
        } else {
            try lowerStatement(ctx, stmt_id, stmt);
        }
    }

    // 4. Merge Label
    const merge_label_id = try ctx.builder.createNode(.Label);

    // Backpatch False target (skips body)
    ctx.builder.graph.nodes.items[branch_node_id].inputs.items[2] = merge_label_id;

    // Body flows into merge (implicit fallthrough or if we want explicit jumps?)
    // In our linear IR, body nodes are followed by merge_label_id node.
    // So execution just flows. No jump needed from body end.
}

// Redefinition of lowerMatch to fix the label issue
fn lowerMatchCorrected(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 2) return error.InvalidNode;

    const scrutinee_id = children[0];
    const scrutinee_node = ctx.snapshot.getNode(scrutinee_id) orelse return error.InvalidNode;
    const scrutinee_val = try lowerExpression(ctx, scrutinee_id, scrutinee_node);

    var end_jumps = std.ArrayList(u32).init(ctx.allocator);
    defer end_jumps.deinit();

    // Iterate over arms
    for (children[1..]) |arm_id| {
        const arm_node = ctx.snapshot.getNode(arm_id) orelse continue;
        if (arm_node.kind != .match_arm) continue;

        const arm_children = ctx.snapshot.getChildren(arm_id);
        if (arm_children.len < 3) continue;

        const pattern_id = arm_children[0];
        const guard_id = arm_children[1];
        const body_id = arm_children[arm_children.len - 1];

        // 1. Lower Pattern
        const pattern_node = ctx.snapshot.getNode(pattern_id) orelse continue;
        var pattern_matches_val: u32 = 0;
        var is_wildcard = false;

        if (pattern_node.kind == .identifier) {
            const token = ctx.snapshot.getToken(pattern_node.first_token) orelse return error.InvalidToken;
            const name = if (token.str) |str_id| ctx.snapshot.astdb.str_interner.getString(str_id) else "";
            if (std.mem.eql(u8, name, "_")) {
                is_wildcard = true;
            }
        }

        if (is_wildcard) {
            pattern_matches_val = try ctx.builder.createConstant(.{ .boolean = true });
        } else {
            const pattern_val = try lowerExpression(ctx, pattern_id, pattern_node);
            const eq_node_id = try ctx.builder.createNode(.Eq);
            var eq_node = &ctx.builder.graph.nodes.items[eq_node_id];
            try eq_node.inputs.append(ctx.allocator, scrutinee_val);
            try eq_node.inputs.append(ctx.allocator, pattern_val);
            pattern_matches_val = eq_node_id;
        }

        // 2. Guard
        var final_cond_val = pattern_matches_val;
        const guard_node = ctx.snapshot.getNode(guard_id);
        if (guard_node != null and guard_node.?.kind != .null_literal) {
            const guard_val = try lowerExpression(ctx, guard_id, guard_node.?);
            const and_node_id = try ctx.builder.createNode(.Logic_And);
            var and_node = &ctx.builder.graph.nodes.items[and_node_id];
            try and_node.inputs.append(ctx.allocator, pattern_matches_val);
            try and_node.inputs.append(ctx.allocator, guard_val);
            final_cond_val = and_node_id;
        }

        // 3. Branch
        const branch_id = try ctx.builder.createNode(.Branch);
        var branch_node = &ctx.builder.graph.nodes.items[branch_id];
        try branch_node.inputs.append(ctx.allocator, final_cond_val);
        try branch_node.inputs.append(ctx.allocator, 0); // True (Body)
        try branch_node.inputs.append(ctx.allocator, 0); // False (Next Arm placeholder)

        // 4. Body
        const body_label_id = try ctx.builder.createNode(.Label);
        ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = body_label_id;

        const body = ctx.snapshot.getNode(body_id) orelse continue;
        if (body.kind == .block_stmt) {
            try lowerBlock(ctx, body_id, body);
        } else {
            try lowerStatement(ctx, body_id, body);
        }

        // Jump to End
        const jump_end = try ctx.builder.createNode(.Jump);
        try jump_end_inputs_append(&ctx.builder.graph.nodes.items[jump_end], ctx.allocator, 0); // Placeholder
        try end_jumps.append(jump_end);

        // 5. Next Arm Label (Implicitly created by next iteration or final)
        const next_arm_label_id = try ctx.builder.createNode(.Label);
        ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = next_arm_label_id;
    }

    // End Label
    const end_label_id = try ctx.builder.createNode(.Label);

    // Backpatch End Jumps
    for (end_jumps.items) |jump_id| {
        ctx.builder.graph.nodes.items[jump_id].inputs.items[0] = end_label_id;
    }
}

// ============================================================================
// Error Handling Lowering (:core profile)
// ============================================================================

/// Lower fail statement: fail ErrorType.Variant
/// Creates an error union value and returns it (propagates error up)
fn lowerFailStatement(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!void {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len == 0) return error.InvalidNode;

    // 1. Lower error value expression (e.g., ErrorType.Variant)
    const error_expr_id = children[0];
    const error_expr_node = ctx.snapshot.getNode(error_expr_id) orelse return error.InvalidNode;
    const error_val = try lowerExpression(ctx, error_expr_id, error_expr_node);

    // 2. Create error union from error value
    // Error_Fail_Construct: { err: error_val, is_error: 1 }
    const error_union_id = try ctx.builder.createNode(.Error_Fail_Construct);
    var error_union_node = &ctx.builder.graph.nodes.items[error_union_id];
    try error_union_node.inputs.append(ctx.allocator, error_val);

    // Track this as an error union value
    try ctx.error_union_nodes.put(ctx.allocator, error_union_id, {});

    // 3. Emit all defers up to function root (same as return statement)
    var i = ctx.defer_stack.items.len;
    while (i > 0) {
        i -= 1;
        const layer = &ctx.defer_stack.items[i];
        var j = layer.actions.items.len;
        while (j > 0) {
            j -= 1;
            const action = layer.actions.items[j];
            const call_id = try ctx.builder.createNode(.Call);
            var node_def = &ctx.builder.graph.nodes.items[call_id];
            node_def.data = .{ .string = try ctx.dupeForGraph(action.builtin_name) };
            for (action.args.items) |arg| {
                try node_def.inputs.append(ctx.allocator, arg);
            }
        }
    }

    // 4. Return the error union
    _ = try ctx.builder.createReturn(error_union_id);
}

/// Lower catch expression: expr catch err { block }
/// Branches based on error flag, executes block if error, unwraps if ok
fn lowerCatchExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len < 1) return error.InvalidNode;

    // children[0] = expression that returns error union
    // children[1..] = catch block statements

    // 1. Lower the expression
    const expr_id = children[0];
    const expr_node = ctx.snapshot.getNode(expr_id) orelse return error.InvalidNode;
    const expr_val = try lowerExpression(ctx, expr_id, expr_node);

    // 2. Check if error: Error_Union_Is_Error
    const is_error_id = try ctx.builder.createNode(.Error_Union_Is_Error);
    var is_error_node = &ctx.builder.graph.nodes.items[is_error_id];
    try is_error_node.inputs.append(ctx.allocator, expr_val);

    // 3. Create branch: if is_error { catch_block } else { unwrap }
    const branch_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_id];
    try branch_node.inputs.append(ctx.allocator, is_error_id);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder for error path
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder for ok path

    // 4. Error path: execute catch block
    const error_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = error_label_id;

    // TODO: Bind error variable if provided (catch |err|)
    // For now, just execute the block statements

    // Execute catch block statements
    if (children.len > 1) {
        for (children[1..]) |stmt_id| {
            const stmt_node = ctx.snapshot.getNode(stmt_id) orelse continue;
            try lowerStatement(ctx, stmt_id, stmt_node);
        }
    }

    // Check if error path terminates and create jump if needed
    var jump_from_error: ?u32 = null;
    var error_result_val: ?u32 = null;
    if (!lastNodeIsTerminator(ctx)) {
        // Error path continues - create default value and jump
        error_result_val = try ctx.builder.createConstant(.{ .integer = 0 });
        jump_from_error = try ctx.builder.createNode(.Jump);
        try ctx.builder.graph.nodes.items[jump_from_error.?].inputs.append(ctx.allocator, 0); // Placeholder
    }

    // 5. Ok path: unwrap payload
    const ok_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = ok_label_id;

    const unwrap_id = try ctx.builder.createNode(.Error_Union_Unwrap);
    var unwrap_node = &ctx.builder.graph.nodes.items[unwrap_id];
    try unwrap_node.inputs.append(ctx.allocator, expr_val);

    // Check if ok path terminates and create jump if needed
    var jump_from_ok: ?u32 = null;
    if (!lastNodeIsTerminator(ctx)) {
        jump_from_ok = try ctx.builder.createNode(.Jump);
        try ctx.builder.graph.nodes.items[jump_from_ok.?].inputs.append(ctx.allocator, 0); // Placeholder
    }

    // 6. Merge point - only create if BOTH paths continue
    if (jump_from_error != null and jump_from_ok != null) {
        // Both paths continue - create merge label and Phi
        const merge_label_id = try ctx.builder.createNode(.Label);

        // Backpatch both jumps to merge label
        ctx.builder.graph.nodes.items[jump_from_error.?].inputs.items[0] = merge_label_id;
        ctx.builder.graph.nodes.items[jump_from_ok.?].inputs.items[0] = merge_label_id;

        // Phi node: selects between error_result_val and unwrap_id
        const phi_id = try ctx.builder.createNode(.Phi);
        var phi_node = &ctx.builder.graph.nodes.items[phi_id];
        try phi_node.inputs.append(ctx.allocator, error_result_val.?);
        try phi_node.inputs.append(ctx.allocator, unwrap_id);
        return phi_id;
    } else if (jump_from_error != null) {
        // Only error path continues - remove jump, continue linearly
        _ = ctx.builder.graph.nodes.pop();
        return error_result_val.?;
    } else if (jump_from_ok != null) {
        // Only ok path continues - remove jump, continue linearly
        _ = ctx.builder.graph.nodes.pop();
        return unwrap_id;
    } else {
        // Both paths terminated - return dummy
        const dummy = try ctx.builder.createConstant(.{ .integer = 0 });
        return dummy;
    }
}

/// Lower try operator: expr?
/// Checks for error, propagates if error, unwraps if ok
fn lowerTryExpr(ctx: *LoweringContext, node_id: NodeId, node: *const AstNode) LowerError!u32 {
    _ = node;
    const children = ctx.snapshot.getChildren(node_id);
    if (children.len == 0) return error.InvalidNode;

    // 1. Lower the expression
    const expr_id = children[0];
    const expr_node = ctx.snapshot.getNode(expr_id) orelse return error.InvalidNode;
    const expr_val = try lowerExpression(ctx, expr_id, expr_node);

    // 2. Check if error: Error_Union_Is_Error
    const is_error_id = try ctx.builder.createNode(.Error_Union_Is_Error);
    var is_error_node = &ctx.builder.graph.nodes.items[is_error_id];
    try is_error_node.inputs.append(ctx.allocator, expr_val);

    // 3. Create branch: if is_error { return expr_val } else { unwrap }
    const branch_id = try ctx.builder.createNode(.Branch);
    var branch_node = &ctx.builder.graph.nodes.items[branch_id];
    try branch_node.inputs.append(ctx.allocator, is_error_id);
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder for error path
    try branch_node.inputs.append(ctx.allocator, 0); // Placeholder for ok path

    // 4. Error path: propagate error (return it)
    const error_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[1] = error_label_id;

    // Emit defers before returning
    var i = ctx.defer_stack.items.len;
    while (i > 0) {
        i -= 1;
        const layer = &ctx.defer_stack.items[i];
        var j = layer.actions.items.len;
        while (j > 0) {
            j -= 1;
            const action = layer.actions.items[j];
            const call_id = try ctx.builder.createNode(.Call);
            var node_def = &ctx.builder.graph.nodes.items[call_id];
            node_def.data = .{ .string = try ctx.dupeForGraph(action.builtin_name) };
            for (action.args.items) |arg| {
                try node_def.inputs.append(ctx.allocator, arg);
            }
        }
    }

    // Return the error union (propagate)
    _ = try ctx.builder.createReturn(expr_val);

    // 5. Ok path: unwrap payload and continue
    const ok_label_id = try ctx.builder.createNode(.Label);
    ctx.builder.graph.nodes.items[branch_id].inputs.items[2] = ok_label_id;

    const unwrap_id = try ctx.builder.createNode(.Error_Union_Unwrap);
    var unwrap_node = &ctx.builder.graph.nodes.items[unwrap_id];
    try unwrap_node.inputs.append(ctx.allocator, expr_val);

    return unwrap_id;
}

// Helper wrapper to avoid generic method call issue in tricky contexts if any
fn jump_end_inputs_append(node: *graph.QTJIRNode, allocator: std.mem.Allocator, val: u32) !void {
    try node.inputs.append(allocator, val);
}
