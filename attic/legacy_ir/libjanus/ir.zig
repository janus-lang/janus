// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Parser = @import("janus_parser");
const Semantic = @import("libjanus_semantic.zig");
const astdb = @import("libjanus_astdb");
const astdb_core = @import("astdb_core");
const tensor_jir = @import("tensor_jir.zig");
const tensor_extractor = @import("tensor_extractor.zig");
const tensor_diag = @import("tensor_diagnostics.zig");
const tensor_compile = @import("tensor_compile.zig");
const api = @import("api.zig");

// Minimalist IR for Hello World subset
// Represents the simplest possible intermediate representation for:
// - Function definitions
// - String constants
// - Function calls

// IR Value types with capability support
pub const ValueType = enum {
    Void,
    String,
    Int,
    Float,
    Bool,
    Function,
    Capability, // Capability token type
    Address, // Address-like value for lvalues

    pub fn toString(self: ValueType) []const u8 {
        return switch (self) {
            .Void => "void",
            .String => "string",
            .Function => "function",
            .Int => "i32",
            .Float => "f64",
            .Bool => "bool",
            .Capability => "capability",
        };
    }
};

// IR Value representation
pub const Value = struct {
    id: u32,
    type: ValueType,
    name: []const u8, // For debugging and identification
};

// IR Instruction types with capability support
pub const InstructionKind = enum {
    FunctionDef, // Define a function
    StringConst, // String constant
    IntConst, // Integer constant
    FloatConst, // Float constant
    BoolConst, // Boolean constant
    // State management
    VarDecl, // Declare variable
    Assign, // LHS = RHS (high-level)
    Load, // Load from address
    Store, // Store to address
    AddressOf, // Compute address/path (field/index)
    UnaryOp, // Unary operation
    // Control flow
    Branch, // Unconditional branch to label
    CondBranch, // Conditional branch true/false to labels
    Label, // Basic block label
    // Operations
    BinaryOp, // Arithmetic/logical binary op
    CompareOp, // Comparison op
    Call, // Function call
    Return, // Return from function
    CapabilityCreate, // Create a capability token
    CapabilityInject, // Inject capability into function call
};

// Opcodes for BinaryOp/CompareOp
pub const BinaryOpcode = enum {
    Add,
    Sub,
    Mul,
    Div,
};

pub const CompareOpcode = enum {
    Eq,
    Neq,
    Lt,
    Le,
    Gt,
    Ge,
};

// IR Instruction
pub const UnaryOpcode = enum {
    Not,
    Neg,
    Plus,
};

// IR Instruction
pub const Instruction = struct {
    kind: InstructionKind,
    result: ?Value, // Result value (if any)
    operands: []Value, // Input operands
    metadata: []const u8, // Additional info (function name, string value, etc.)
    // Optional opcode tags for op instructions
    binop: ?BinaryOpcode = null,
    cmpop: ?CompareOpcode = null,
    unop: ?UnaryOpcode = null,
    // Explicit destination for store-like instructions
    dest: ?Value = null,
};

// IR Module - contains all instructions for a compilation unit
pub const Module = struct {
    instructions: std.ArrayList(Instruction),
    values: std.ArrayList(Value),
    metadata_strings: std.ArrayList([]const u8), // Store owned metadata strings
    next_value_id: u32,
    allocator: std.mem.Allocator,
    // Optional: attached tensor graph (J-IR) when :npu extraction is active
    tensor_graph: ?*const tensor_jir.Graph = null,
    tensor_diagnostics: ?*tensor_diag.TensorDiagnostics = null,

    pub fn init(allocator: std.mem.Allocator) Module {
        return Module{
            .instructions = std.ArrayList(Instruction){},
            .values = std.ArrayList(Value){},
            .metadata_strings = std.ArrayList([]const u8){},
            .next_value_id = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Module) void {
        // Clean up operand arrays
        for (self.instructions.items) |instruction| {
            self.allocator.free(instruction.operands);
        }
        // Clean up metadata strings
        for (self.metadata_strings.items) |metadata| {
            self.allocator.free(metadata);
        }
        self.instructions.deinit(self.allocator);
        self.values.deinit(self.allocator);
        self.metadata_strings.deinit(self.allocator);

        // If a tensor graph was attached, own and free it
        if (self.tensor_graph) |gconst| {
            const g = @constCast(gconst);
            g.deinit();
            self.allocator.destroy(g);
            self.tensor_graph = null;
        }
        if (self.tensor_diagnostics) |diag_ptr| {
            diag_ptr.deinit();
            self.allocator.destroy(diag_ptr);
            self.tensor_diagnostics = null;
        }
    }

    pub fn setTensorGraph(self: *Module, g: *const tensor_jir.Graph) void {
        self.tensor_graph = g;
    }

    pub fn getTensorGraph(self: *const Module) ?*const tensor_jir.Graph {
        return self.tensor_graph;
    }

    pub fn setTensorDiagnostics(self: *Module, diags: *tensor_diag.TensorDiagnostics) void {
        if (self.tensor_diagnostics) |existing| {
            existing.deinit();
            self.allocator.destroy(existing);
        }
        self.tensor_diagnostics = diags;
    }

    pub fn getTensorDiagnostics(self: *const Module) ?*const tensor_diag.TensorDiagnostics {
        return self.tensor_diagnostics;
    }

    pub fn createValue(self: *Module, value_type: ValueType, name: []const u8) !Value {
        const value = Value{
            .id = self.next_value_id,
            .type = value_type,
            .name = name,
        };
        self.next_value_id += 1;
        try self.values.append(self.allocator, value);
        return value;
    }

    pub fn addInstruction(self: *Module, kind: InstructionKind, result: ?Value, operands: []const Value, metadata: []const u8) !void {
        // Copy operands to owned slice
        const owned_operands = try self.allocator.dupe(Value, operands);

        // Always copy metadata to ensure we own it and can safely free it
        const owned_metadata = if (metadata.len > 0)
            try self.allocator.dupe(u8, metadata)
        else
            metadata;

        if (owned_metadata.len > 0) {
            try self.metadata_strings.append(self.allocator, owned_metadata);
        }

        const instruction = Instruction{
            .kind = kind,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
            .binop = null,
            .cmpop = null,
        };

        try self.instructions.append(self.allocator, instruction);
    }

    pub fn addBinary(self: *Module, opcode: BinaryOpcode, result: ?Value, operands: []const Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, operands);
        const owned_metadata = if (metadata.len > 0) try self.allocator.dupe(u8, metadata) else metadata;
        if (owned_metadata.len > 0) try self.metadata_strings.append(self.allocator, owned_metadata);
        const instr = Instruction{
            .kind = .BinaryOp,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
            .binop = opcode,
            .cmpop = null,
        };
        try self.instructions.append(self.allocator, instr);
    }

    pub fn addCompare(self: *Module, opcode: CompareOpcode, result: ?Value, operands: []const Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, operands);
        const owned_metadata = if (metadata.len > 0) try self.allocator.dupe(u8, metadata) else metadata;
        if (owned_metadata.len > 0) try self.metadata_strings.append(self.allocator, owned_metadata);
        const instr = Instruction{
            .kind = .CompareOp,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
            .binop = null,
            .cmpop = opcode,
        };
        try self.instructions.append(self.allocator, instr);
    }

    pub fn addUnary(self: *Module, opcode: UnaryOpcode, result: Value, operand: Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, &[_]Value{operand});
        const owned_metadata = if (metadata.len > 0) try self.allocator.dupe(u8, metadata) else metadata;
        if (owned_metadata.len > 0) try self.metadata_strings.append(self.allocator, owned_metadata);
        const instr = Instruction{
            .kind = .UnaryOp,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
            .unop = opcode,
        };
        try self.instructions.append(self.allocator, instr);
    }

    pub fn addStore(self: *Module, dest: Value, src: Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, &[_]Value{src});
        const owned_metadata = if (metadata.len > 0) try self.allocator.dupe(u8, metadata) else metadata;
        if (owned_metadata.len > 0) try self.metadata_strings.append(self.allocator, owned_metadata);
        const instr = Instruction{
            .kind = .Store,
            .result = null,
            .operands = owned_operands,
            .metadata = owned_metadata,
            .dest = dest,
        };
        try self.instructions.append(self.allocator, instr);
    }

    pub fn addAddressOf(self: *Module, result: Value, operands: []const Value, metadata: []const u8) !void {
        const owned_operands = try self.allocator.dupe(Value, operands);
        const owned_metadata = if (metadata.len > 0) try self.allocator.dupe(u8, metadata) else metadata;
        if (owned_metadata.len > 0) try self.metadata_strings.append(self.allocator, owned_metadata);
        const instr = Instruction{
            .kind = .AddressOf,
            .result = result,
            .operands = owned_operands,
            .metadata = owned_metadata,
        };
        try self.instructions.append(self.allocator, instr);
    }

    pub fn print(self: *Module, writer: anytype) !void {
        try writer.print("; IR Module\n", .{});
        for (self.instructions.items) |instruction| {
            if (instruction.result) |result| {
                try writer.print("{} = ", .{result.id});
            }
            try writer.print("{s}", .{@tagName(instruction.kind)});
            if (instruction.binop) |b| {
                try writer.print(" {s}", .{@tagName(b)});
            } else if (instruction.cmpop) |c| {
                try writer.print(" {s}", .{@tagName(c)});
            } else if (instruction.unop) |u| {
                try writer.print(" {s}", .{@tagName(u)});
            }
            if (instruction.dest) |d| {
                try writer.print(" dest:{}", .{d.id});
            }
            for (instruction.operands) |operand| {
                try writer.print(" {}", .{operand.id});
            }
            if (instruction.metadata.len > 0) {
                try writer.print("; {s}", .{instruction.metadata});
            }
            try writer.print("\n", .{});
        }
    }

    /// Stateless IR verifier for CLI and fuzzing
    pub fn verify(self: *Module, allocator: std.mem.Allocator) !void {
        var labels = std.StringHashMap(bool).init(allocator);
        defer labels.deinit();
        for (self.instructions.items) |instr| {
            if (instr.kind == .Label and instr.metadata.len > 0) {
                _ = try labels.put(instr.metadata, true);
            }
        }
        const Term = struct {
            fn is(k: InstructionKind) bool {
                return k == .Branch or k == .CondBranch or k == .Return;
            }
        };
        var in_block = false;
        var last_kind: ?InstructionKind = null;
        for (self.instructions.items) |instr| {
            switch (instr.kind) {
                .CondBranch => {
                    if (instr.operands.len != 1) return error.IRVerifyCondBranchOperands;
                    if (instr.operands[0].type != .Bool) return error.IRVerifyCondBranchType;
                    const tp = std.mem.indexOf(u8, instr.metadata, "then:") orelse return error.IRVerifyCondBranchTargets;
                    const ep = std.mem.indexOf(u8, instr.metadata, " else:") orelse return error.IRVerifyCondBranchTargets;
                    const tn = std.mem.trim(u8, instr.metadata[tp + 5 .. ep], " ");
                    const en = std.mem.trim(u8, instr.metadata[ep + 6 ..], " ");
                    if (labels.get(tn) == null or labels.get(en) == null) return error.IRVerifyBranchTargetMissing;
                },
                .Branch => {
                    if (instr.metadata.len == 0) return error.IRVerifyBranchTargetMissing;
                    if (labels.get(instr.metadata) == null) return error.IRVerifyBranchTargetMissing;
                },
                .Store => {
                    const d = instr.dest orelse return error.IRVerifyStoreNoDest;
                    if (d.type != .Address) return error.IRVerifyStoreDestType;
                },
                .Load => {
                    if (instr.operands.len != 1) return error.IRVerifyLoadOperands;
                    if (instr.operands[0].type != .Address) return error.IRVerifyLoadOperandType;
                    if (instr.result) |r| {
                        if (r.type == .Address) return error.IRVerifyLoadResultType;
                    } else return error.IRVerifyLoadNoResult;
                },
                .AddressOf => {
                    if (instr.result) |r| {
                        if (r.type != .Address) return error.IRVerifyAddressOfResultType;
                    } else return error.IRVerifyAddressOfNoResult;
                    if (instr.operands.len != 2) return error.IRVerifyAddressOfOperands;
                    if (instr.operands[0].type != .Address) return error.IRVerifyAddressOfBaseType;
                    if (instr.metadata.len > 0 and std.mem.eql(u8, instr.metadata, "index")) {
                        if (instr.operands[1].type != .Int) return error.IRVerifyIndexOperandType;
                    } else {
                        if (instr.operands[1].type != .String) return error.IRVerifyFieldOperandType;
                    }
                },
                else => {},
            }
            if (instr.kind == .FunctionDef or instr.kind == .Label) {
                if (in_block) if (last_kind) |lk| if (!Term.is(lk)) return error.IRVerifyMissingTerminator;
                in_block = true;
                last_kind = instr.kind;
                continue;
            }
            if (in_block) last_kind = instr.kind;
        }
        if (in_block) if (last_kind) |lk| if (!Term.is(lk)) return error.IRVerifyMissingTerminator;
    }
};

// Revolutionary IR Generator - converts semantic graph to capability-aware IR
const Generator = struct {
    module: *Module,
    semantic_graph: *const Semantic.SemanticGraph,
    allocator: std.mem.Allocator,
    arena: std.heap.ArenaAllocator,
    capability_values: std.AutoHashMap(Semantic.Type, Value), // Map capability types to IR values
    snapshot: ?*const astdb.Snapshot = null,
    string_cache: std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    int_cache: std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    bool_cache: std.HashMap(bool, Value, std.hash_map.AutoContext(bool), std.hash_map.default_max_load_percentage),
    float_cache: std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    // Worklist and indices
    func_by_name: std.HashMap([]const u8, astdb.NodeId, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    generated_funcs: std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    worklist: std.ArrayList(astdb.NodeId),
    // Locals for current function: name -> slot value (address-like placeholder)
    locals: std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage),
    tmp_counter: u32 = 0,
    label_counter: u32 = 0,
    // Loop context for break/continue
    loop_start_label: ?[]u8 = null,
    loop_end_label: ?[]u8 = null,

    pub fn init(module: *Module, semantic_graph: *const Semantic.SemanticGraph, allocator: std.mem.Allocator) Generator {
        return Generator{
            .module = module,
            .semantic_graph = semantic_graph,
            .allocator = allocator,
            .arena = std.heap.ArenaAllocator.init(allocator),
            .capability_values = std.AutoHashMap(Semantic.Type, Value).init(allocator),
            .string_cache = std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .int_cache = std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .bool_cache = std.HashMap(bool, Value, std.hash_map.AutoContext(bool), std.hash_map.default_max_load_percentage).init(allocator),
            .float_cache = std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .func_by_name = std.HashMap([]const u8, astdb.NodeId, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .generated_funcs = std.HashMap([]const u8, bool, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .worklist = std.ArrayList(astdb.NodeId){},
            .locals = std.HashMap([]const u8, Value, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator),
            .tmp_counter = 0,
            .label_counter = 0,
            .loop_start_label = null,
            .loop_end_label = null,
        };
    }

    pub fn deinit(self: *Generator) void {
        self.arena.deinit();
        self.capability_values.deinit();
        self.string_cache.deinit();
        self.int_cache.deinit();
        self.bool_cache.deinit();
        self.float_cache.deinit();
        self.func_by_name.deinit();
        self.generated_funcs.deinit();
        self.worklist.deinit(self.allocator);
        self.locals.deinit();
    }

    pub fn generateFromASTDB(self: *Generator, snapshot: *const astdb.Snapshot) anyerror!void {
        // First, generate capability creation instructions for all required capabilities
        try self.generateCapabilityCreation();

        // Then generate from ASTDB snapshot
        self.snapshot = snapshot;
        try self.generateFromSnapshot(snapshot);
    }

    fn generateCapabilityCreation(self: *Generator) anyerror!void {
        const required_caps = self.semantic_graph.getRequiredCapabilities();

        for (required_caps) |cap_type| {
            // Create a capability value
            const cap_name = switch (cap_type) {
                .StdoutWriteCapability => "stdout_cap",
                .StderrWriteCapability => "stderr_cap",
                else => "unknown_cap",
            };

            const cap_value = try self.module.createValue(.Capability, cap_name);

            // Generate capability creation instruction
            const cap_metadata = switch (cap_type) {
                .StdoutWriteCapability => "create StdoutWriteCapability",
                .StderrWriteCapability => "create StderrWriteCapability",
                else => "create UnknownCapability",
            };

            try self.module.addInstruction(.CapabilityCreate, cap_value, &[_]Value{}, cap_metadata);

            // Store the capability value for later use
            try self.capability_values.put(cap_type, cap_value);
        }
    }

    fn generateFromSnapshot(self: *Generator, snapshot: *const astdb.Snapshot) anyerror!void {
        // Build function index name -> node id
        try self.buildFunctionIndex(snapshot);
        // Seed worklist with main
        if (self.func_by_name.get("main")) |mid| {
            try self.worklist.append(self.allocator, mid);
        }
        // Process worklist
        while (self.worklist.items.len > 0) {
            const cur = self.worklist.pop();
            if (cur) |valid_cur| {
                if (snapshot.getNode(valid_cur)) |n| {
                    if (self.extractFuncName(snapshot, n.*)) |fname| {
                        if (self.generated_funcs.get(fname) != null) continue;
                        _ = try self.generated_funcs.put(fname, true);
                    }
                    try self.generateNode(valid_cur, n.*);
                }
            }
        }
    }

    fn buildFunctionIndex(self: *Generator, ss: *const astdb.Snapshot) !void {
        const cnt = ss.nodeCount();
        var i: u32 = 0;
        while (i < cnt) : (i += 1) {
            const nid: astdb.NodeId = @enumFromInt(i);
            if (ss.getNode(nid)) |n| {
                if (n.kind == .func_decl) {
                    if (self.extractFuncName(ss, n.*)) |name| {
                        // name bytes are owned by interner, safe to store as key
                        _ = try self.func_by_name.put(name, nid);
                    }
                }
            }
        }
    }

    fn generateNode(self: *Generator, node_id: astdb.NodeId, node: astdb.NodeRow) anyerror!void {
        // Revolutionary ASTDB node processing
        switch (node.kind) {
            .func_decl => {
                try self.generateFunctionFromNode(node);
            },
            .call_expr => {
                _ = try self.generateCallFromNode(node_id, node);
            },
            .string_literal => {
                _ = try self.generateStringFromNode(node);
            },
            else => {
                // TODO: Implement other node types as needed
            },
        }
    }

    fn generateFunctionFromNode(self: *Generator, node: astdb.NodeRow) anyerror!void {
        // Extract function name from first child identifier
        const ss = self.snapshot orelse return; // snapshot required
        const func_name = self.extractFuncName(ss, node) orelse "anon";

        // Create function value
        const func_value = try self.module.createValue(.Function, func_name);

        // Add function definition instruction
        try self.module.addInstruction(.FunctionDef, func_value, &[_]Value{}, func_name);

        // Reset per-function state
        self.locals.clearRetainingCapacity();
        self.tmp_counter = 0;
        self.label_counter = 0;
        self.loop_start_label = null;
        self.loop_end_label = null;
        // Reset arena for function-scoped allocations (temp names, etc.)
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);
        // Reset arena for this function
        self.arena.deinit();
        self.arena = std.heap.ArenaAllocator.init(self.allocator);

        // Traverse body if present: look for block_stmt among children
        const kids = node.children(ss);
        var bi: usize = 0;
        while (bi < kids.len) : (bi += 1) {
            if (ss.getNode(kids[bi])) |child| {
                if (child.kind == .block_stmt) {
                    try self.generateBlock(child.*);
                    break;
                }
            }
        }
    }

    fn generateBlock(self: *Generator, block: astdb.NodeRow) anyerror!void {
        const ss = self.snapshot orelse return;
        const stmts = block.children(ss);
        for (stmts) |sid| {
            if (ss.getNode(sid)) |stmt| {
                try self.generateStatement(sid, stmt.*);
            }
        }
    }

    fn generateStatement(self: *Generator, node_id: astdb.NodeId, stmt: astdb.NodeRow) anyerror!void {
        const ss = self.snapshot orelse return;
        switch (stmt.kind) {
            .var_stmt, .let_stmt => {
                // Extract declared name from tokens between first/last
                if (self.findFirstIdentifierBetween(ss, stmt.first_token, stmt.last_token)) |var_name| {
                    // Create a slot for the local and remember it
                    const slot = try self.module.createValue(.Address, var_name);
                    try self.module.addInstruction(.VarDecl, slot, &[_]Value{}, var_name);
                    _ = try self.locals.put(var_name, slot);

                    // If initializer exists as child expression, evaluate and store
                    const kids = stmt.children(ss);
                    if (kids.len > 0) {
                        if (ss.getNode(kids[kids.len - 1])) |init_node| {
                            if (try self.evaluateExpr(@enumFromInt(@intFromEnum(kids[kids.len - 1])), init_node.*)) |rhs| {
                                try self.module.addStore(slot, rhs, var_name);
                            }
                        }
                    }
                }
            },
            .binary_expr => {
                // Decode using operator token at last_token and emit op with materialized operands
                if (ss.getToken(stmt.last_token)) |op_tok| {
                    const kids = stmt.children(ss);
                    if (kids.len == 2) {
                        const lhs_id = kids[0];
                        const rhs_id = kids[1];
                        const lhs_node = ss.getNode(lhs_id) orelse return;
                        const rhs_node = ss.getNode(rhs_id) orelse return;

                        // Assignment: store rhs into lhs (identifier/field/index)
                        if (op_tok.kind == .assign or op_tok.kind == .walrus_assign or op_tok.kind == .equal) {
                            // Evaluate RHS
                            if (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) |rhs_val| {
                                if (try self.evaluateAddress(lhs_id, lhs_node.*)) |dest_addr| {
                                    const meta_name = self.nameForLhs(ss, lhs_node.*) orelse "assign";
                                    try self.module.addStore(dest_addr, rhs_val, meta_name);
                                }
                            }
                        } else switch (op_tok.kind) {
                            .plus, .minus, .star, .slash => {
                                const lhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(lhs_id)), lhs_node.*)) orelse return;
                                const rhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) orelse return;
                                const ty = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(node_id))) orelse .Int;
                                const tmp = try self.newTemp(ty);
                                const opcode: BinaryOpcode = switch (op_tok.kind) {
                                    .plus => .Add,
                                    .minus => .Sub,
                                    .star => .Mul,
                                    .slash => .Div,
                                    else => .Add,
                                };
                                try self.module.addBinary(opcode, tmp, &[_]Value{ lhs_val, rhs_val }, "binop");
                            },
                            .equal_equal, .not_equal, .less, .less_equal, .greater, .greater_equal => {
                                const lhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(lhs_id)), lhs_node.*)) orelse return;
                                const rhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) orelse return;
                                const tmp = try self.newTemp(.Bool);
                                const cop: CompareOpcode = switch (op_tok.kind) {
                                    .equal_equal => .Eq,
                                    .not_equal => .Neq,
                                    .less => .Lt,
                                    .less_equal => .Le,
                                    .greater => .Gt,
                                    .greater_equal => .Ge,
                                    else => .Eq,
                                };
                                try self.module.addCompare(cop, tmp, &[_]Value{ lhs_val, rhs_val }, "cmp");
                            },
                            else => {
                                // Fallback
                                try self.module.addInstruction(.BinaryOp, null, &[_]Value{}, "op");
                            },
                        }
                    }
                }
            },
            .return_stmt => {
                // Emit Return with optional value metadata
                try self.module.addInstruction(.Return, null, &[_]Value{}, "return");
            },
            .expr_stmt => {
                // If it contains a call_expr, generate it
                const kids = stmt.children(ss);
                for (kids) |cid| {
                    if (ss.getNode(cid)) |n| {
                        if (n.kind == .call_expr) {
                            _ = try self.generateCallFromNode(cid, n.*);
                        }
                    }
                }
            },
            .if_stmt => {
                // children: cond, then_block, optional else (block or if_stmt)
                const kids = stmt.children(ss);
                if (kids.len < 2) return; // malformed
                const cond_id = kids[0];
                const then_id = kids[1];
                const cond_node = ss.getNode(cond_id) orelse return;
                const then_node = ss.getNode(then_id) orelse return;
                const cond_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(cond_id)), cond_node.*)) orelse return;

                const then_label = try self.freshLabel("then");
                defer self.allocator.free(then_label);
                const else_label = try self.freshLabel("else");
                defer self.allocator.free(else_label);
                const end_label = try self.freshLabel("endif");
                defer self.allocator.free(end_label);

                const cond_meta = try std.fmt.allocPrint(self.allocator, "then: {s} else: {s}", .{ then_label, else_label });
                defer self.allocator.free(cond_meta);
                try self.module.addInstruction(.CondBranch, null, &[_]Value{cond_val}, cond_meta);

                // then label and body
                try self.module.addInstruction(.Label, null, &[_]Value{}, then_label);
                if (then_node.kind == .block_stmt) {
                    try self.generateBlock(then_node.*);
                } else {
                    try self.generateStatement(then_id, then_node.*);
                }
                // branch to end
                try self.module.addInstruction(.Branch, null, &[_]Value{}, end_label);

                // else label and body if present
                try self.module.addInstruction(.Label, null, &[_]Value{}, else_label);
                if (kids.len >= 3) {
                    const else_id = kids[2];
                    if (ss.getNode(else_id)) |enode| {
                        if (enode.kind == .block_stmt) {
                            try self.generateBlock(enode.*);
                        } else if (enode.kind == .if_stmt) {
                            // else-if chain: lower recursively
                            try self.generateStatement(else_id, enode.*);
                        } else {
                            try self.generateStatement(else_id, enode.*);
                        }
                    }
                }

                // end label
                try self.module.addInstruction(.Label, null, &[_]Value{}, end_label);
            },
            .while_stmt => {
                // children: cond, body
                const kids = stmt.children(ss);
                if (kids.len < 2) return;
                const start_label = try self.freshLabel("loop");
                defer self.allocator.free(start_label);
                const end_label = try self.freshLabel("endloop");
                defer self.allocator.free(end_label);
                const body_label = try self.freshLabel("body");
                defer self.allocator.free(body_label);

                // start label
                try self.module.addInstruction(.Label, null, &[_]Value{}, start_label);

                // evaluate condition
                const cond_id = kids[0];
                const cond_node = ss.getNode(cond_id) orelse return;
                const cond_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(cond_id)), cond_node.*)) orelse return;

                // If cond true -> body, else -> end
                const meta = try std.fmt.allocPrint(self.allocator, "then: {s} else: {s}", .{ body_label, end_label });
                defer self.allocator.free(meta);
                try self.module.addInstruction(.CondBranch, null, &[_]Value{cond_val}, meta);

                // body
                const body_id = kids[1];
                // body label
                try self.module.addInstruction(.Label, null, &[_]Value{}, body_label);
                // set loop context for break/continue
                const saved_start = self.loop_start_label;
                const saved_end = self.loop_end_label;
                self.loop_start_label = start_label;
                self.loop_end_label = end_label;
                if (ss.getNode(body_id)) |bnode| {
                    if (bnode.kind == .block_stmt) {
                        try self.generateBlock(bnode.*);
                    } else {
                        try self.generateStatement(body_id, bnode.*);
                    }
                }
                // restore loop context
                self.loop_start_label = saved_start;
                self.loop_end_label = saved_end;
                // jump back to start
                try self.module.addInstruction(.Branch, null, &[_]Value{}, start_label);
                // end label
                try self.module.addInstruction(.Label, null, &[_]Value{}, end_label);
            },
            .break_stmt => {
                if (self.loop_end_label) |lbl| {
                    try self.module.addInstruction(.Branch, null, &[_]Value{}, lbl);
                }
            },
            .continue_stmt => {
                if (self.loop_start_label) |lbl| {
                    try self.module.addInstruction(.Branch, null, &[_]Value{}, lbl);
                }
            },
            else => {},
        }
        // node_id currently unused for bookkeeping
    }

    fn generateCallFromNode(self: *Generator, node_id: astdb.NodeId, node: astdb.NodeRow) anyerror!?Value {
        // Extract callee function name from first child identifier
        const call_ss = self.snapshot orelse return null;
        const function_name = self.extractCallName(call_ss, node) orelse "unknown";

        var args = std.ArrayList(Value){};
        defer args.deinit(self.allocator);

        // Use normalized positional args from semantic graph if available
        const core_call_id: astdb_core.NodeId = @enumFromInt(@intFromEnum(node_id));
        if (@constCast(self.semantic_graph).getCallArgs(core_call_id)) |arg_ids| {
            if (self.snapshot) |ss2| {
                // Materialize IR values for recognized arg node kinds
                for (arg_ids) |aid| {
                    if (ss2.getNode(@enumFromInt(@intFromEnum(aid)))) |anode| {
                        if (try self.generateValueForArg(ss2, @enumFromInt(@intFromEnum(aid)), anode.*)) |v| {
                            try args.append(self.allocator, v);
                        }
                    }
                }
            }
            const meta = try std.fmt.allocPrint(self.allocator, "call {s} with {d} args", .{ function_name, arg_ids.len });
            defer self.allocator.free(meta);
            try self.module.addInstruction(.Call, null, args.items, meta);
            return null;
        }

        // Enqueue callee function for generation if known
        if (self.func_by_name.get(function_name)) |fid| {
            try self.worklist.append(self.allocator, fid);
        }
        // Prototype fall-through: simple print handling as stub
        if (std.mem.eql(u8, function_name, "print")) {
            // Generate call to janus_print function
            const call_metadata = try std.fmt.allocPrint(self.allocator, "call janus_print(\"{s}\")", .{"Hello, Janus!"});
            defer self.allocator.free(call_metadata);

            // Create string argument
            const string_arg = try self.module.createValue(.String, "Hello, Janus!");
            try args.append(self.allocator, string_arg);

            try self.module.addInstruction(.Call, null, args.items, call_metadata);

            // Also inject capabilities for future profiles
            if (self.capability_values.get(Semantic.Type.StdoutWriteCapability)) |cap_value| {
                try self.module.addInstruction(.CapabilityInject, null, &[_]Value{cap_value}, "inject StdoutWriteCapability for print");
            }
        }

        return null;
    }

    fn extractFuncName(self: *Generator, ss: *const astdb.Snapshot, node: astdb.NodeRow) ?[]const u8 {
        // Temporarily disable name extraction to avoid interner mismatch
        _ = self;
        _ = ss;
        _ = node;
        return null;
    }

    fn extractCallName(self: *Generator, ss: *const astdb.Snapshot, node: astdb.NodeRow) ?[]const u8 {
        _ = self;
        _ = ss;
        _ = node;
        return null;
    }

    fn generateValueForArg(self: *Generator, ss: *const astdb.Snapshot, arg_id: astdb.NodeId, arg_node: astdb.NodeRow) anyerror!?Value {
        switch (arg_node.kind) {
            .string_literal => {
                // Fetch token and string bytes via semantic graph's interner
                const tok = ss.getToken(arg_node.first_token) orelse return null;
                if (tok.str) |sid| {
                    const text = @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid);
                    if (self.string_cache.get(text)) |existing| return existing;
                    const v = try self.module.createValue(.String, text);
                    try self.module.addInstruction(.StringConst, v, &[_]Value{}, text);
                    try self.string_cache.put(text, v);
                    return v;
                } else {
                    const text: []const u8 = "";
                    if (self.string_cache.get(text)) |existing2| return existing2;
                    const v2 = try self.module.createValue(.String, text);
                    try self.module.addInstruction(.StringConst, v2, &[_]Value{}, text);
                    try self.string_cache.put(text, v2);
                    return v2;
                }
            },
            .identifier => {
                // Load from local if known, otherwise create a symbolic value of inferred type
                if (ss.getToken(arg_node.first_token)) |tok| {
                    const name = if (tok.str) |sid| @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid) else "id";
                    // Try locals map
                    if (self.locals.get(name)) |slot| {
                        // Infer type from semantic graph
                        const ty = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(arg_id))) orelse .Int;
                        const tmp = try self.newTemp(ty);
                        try self.module.addInstruction(.Load, tmp, &[_]Value{slot}, name);
                        return tmp;
                    }
                }
                // Fallback: create value of inferred type without load
                const core_id: astdb_core.NodeId = @enumFromInt(@intFromEnum(arg_id));
                const ty = if (@constCast(self.semantic_graph).type_of.get(core_id)) |t| t else .Unknown;
                const vt: ValueType = switch (ty) {
                    .String => .String,
                    .Int => .Int,
                    .Float => .Float,
                    .Bool => .Bool,
                    else => .String,
                };
                const v = try self.module.createValue(vt, "id");
                return v;
            },
            .field_expr, .index_expr => {
                // Produce rvalue by address + load
                if (try self.evaluateAddress(arg_id, arg_node)) |addr| {
                    const ty = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(arg_id))) orelse .Int;
                    const tmp = try self.newTemp(ty);
                    try self.module.addInstruction(.Load, tmp, &[_]Value{addr}, "load");
                    return tmp;
                }
                return null;
            },
            else => {
                // Fallback via token kind for numeric/bool with dedupe
                if (ss.getToken(arg_node.first_token)) |tok| {
                    switch (tok.kind) {
                        .integer_literal => {
                            const key = if (tok.str) |sid| @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid) else "";
                            if (self.int_cache.get(key)) |existing| return existing;
                            const name = if (key.len > 0) key else "arg_int";
                            const v = try self.module.createValue(.Int, name);
                            try self.module.addInstruction(.IntConst, v, &[_]Value{}, name);
                            try self.int_cache.put(name, v);
                            return v;
                        },
                        .float_literal => {
                            const key = if (tok.str) |sid| @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid) else "";
                            if (self.float_cache.get(key)) |existing| return existing;
                            const name = if (key.len > 0) key else "arg_float";
                            const v = try self.module.createValue(.Float, name);
                            try self.module.addInstruction(.FloatConst, v, &[_]Value{}, name);
                            try self.float_cache.put(name, v);
                            return v;
                        },
                        .bool_literal => {
                            // Map token string to bool if available
                            var b: bool = false;
                            if (tok.str) |sid| {
                                const s = @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid);
                                b = std.mem.eql(u8, s, "true");
                            }
                            if (self.bool_cache.get(b)) |existing_b| return existing_b;
                            const v = try self.module.createValue(.Bool, if (b) "true" else "false");
                            try self.module.addInstruction(.BoolConst, v, &[_]Value{}, if (b) "true" else "false");
                            try self.bool_cache.put(b, v);
                            return v;
                        },
                        else => return null,
                    }
                }
                return null;
            },
        }
    }

    fn generateStringFromNode(self: *Generator, node: astdb.NodeRow) anyerror!?Value {
        // Create string constant from ASTDB node
        _ = node; // TODO: Extract string value from ASTDB node
        const string_value = "Hello, Revolutionary Janus!"; // TODO: Extract from ASTDB

        const str_value = try self.module.createValue(.String, string_value);
        try self.module.addInstruction(.StringConst, str_value, &[_]Value{}, string_value);

        return str_value;
    }

    fn findFirstIdentifierBetween(self: *Generator, ss: *const astdb.Snapshot, first_tok: astdb.TokenId, last_tok: astdb.TokenId) ?[]const u8 {
        const start: u32 = @intFromEnum(first_tok) + 1;
        const end: u32 = @intFromEnum(last_tok);
        var i: u32 = start;
        while (i <= end) : (i += 1) {
            const tid: astdb.TokenId = @enumFromInt(i);
            if (ss.getToken(tid)) |t| {
                if (t.kind == .identifier) {
                    return self.semantic_graph.astdb_system.str_interner.getString(t.str.?);
                }
            }
        }
        return null;
    }

    fn newTemp(self: *Generator, vt: ValueType) !Value {
        const name = try std.fmt.allocPrint(self.arena.allocator(), "tmp.{d}", .{self.tmp_counter});
        self.tmp_counter += 1;
        return self.module.createValue(vt, name);
    }

    fn inferValueTypeForNode(self: *Generator, node_id: astdb_core.NodeId) ?ValueType {
        if (@constCast(self.semantic_graph).type_of.get(node_id)) |ty| {
            return switch (ty) {
                .String => .String,
                .Int => .Int,
                .Float => .Float,
                .Bool => .Bool,
                .Void => .Void,
                else => .Int,
            };
        }
        return null;
    }

    fn getBoolConst(self: *Generator, b: bool) !Value {
        if (self.bool_cache.get(b)) |existing| return existing;
        const v = try self.module.createValue(.Bool, if (b) "true" else "false");
        try self.module.addInstruction(.BoolConst, v, &[_]Value{}, if (b) "true" else "false");
        try self.bool_cache.put(b, v);
        return v;
    }

    fn getZeroConst(self: *Generator, vt: ValueType) !Value {
        switch (vt) {
            .Int => {
                const key: []const u8 = "0";
                if (self.int_cache.get(key)) |existing| return existing;
                const v = try self.module.createValue(.Int, key);
                try self.module.addInstruction(.IntConst, v, &[_]Value{}, key);
                try self.int_cache.put(key, v);
                return v;
            },
            .Float => {
                const key: []const u8 = "0.0";
                if (self.float_cache.get(key)) |existing| return existing;
                const v = try self.module.createValue(.Float, key);
                try self.module.addInstruction(.FloatConst, v, &[_]Value{}, key);
                try self.float_cache.put(key, v);
                return v;
            },
            else => return self.getBoolConst(false),
        }
    }

    fn nameForLhs(self: *Generator, ss: *const astdb.Snapshot, node: astdb.NodeRow) ?[]const u8 {
        switch (node.kind) {
            .identifier => {
                if (ss.getToken(node.first_token)) |tok| {
                    if (tok.str) |sid| return self.semantic_graph.astdb_system.str_interner.getString(sid);
                }
                return null;
            },
            .field_expr => {
                if (ss.getToken(node.last_token)) |tok| {
                    if (tok.str) |sid| return self.semantic_graph.astdb_system.str_interner.getString(sid);
                }
                return "field";
            },
            .index_expr => return "index",
            else => return null,
        }
    }

    fn evaluateAddress(self: *Generator, _: astdb.NodeId, node: astdb.NodeRow) anyerror!?Value {
        const ss = self.snapshot orelse return null;
        switch (node.kind) {
            .identifier => {
                if (ss.getToken(node.first_token)) |tok| {
                    const name = if (tok.str) |sid| self.semantic_graph.astdb_system.str_interner.getString(sid) else "_";
                    if (self.locals.get(name)) |slot| return slot;
                    // Create if not present
                    const s = try self.module.createValue(.Address, name);
                    _ = try self.locals.put(name, s);
                    try self.module.addInstruction(.VarDecl, s, &[_]Value{}, name);
                    return s;
                }
                return null;
            },
            .field_expr => {
                const kids = node.children(ss);
                if (kids.len == 0) return null;
                const base_id = kids[0];
                const base_node = ss.getNode(base_id) orelse return null;
                const base_addr = (try self.evaluateAddress(@enumFromInt(@intFromEnum(base_id)), base_node.*)) orelse return null;
                // Extract actual field name from last_token
                const field_name = blk: {
                    if (ss.getToken(node.last_token)) |tok| {
                        if (tok.str) |sid| break :blk self.semantic_graph.astdb_system.str_interner.getString(sid);
                    }
                    break :blk "field";
                };
                const result = try self.module.createValue(.Address, field_name);
                // Attach field name as string operand too for richer paths
                const fname_val = try self.module.createValue(.String, field_name);
                try self.module.addInstruction(.StringConst, fname_val, &[_]Value{}, field_name);
                try self.module.addAddressOf(result, &[_]Value{ base_addr, fname_val }, field_name);
                return result;
            },
            .index_expr => {
                const kids = node.children(ss);
                if (kids.len < 2) return null;
                const base_id = kids[0];
                const idx_id = kids[1];
                const base_node = ss.getNode(base_id) orelse return null;
                const idx_node = ss.getNode(idx_id) orelse return null;
                const base_addr = (try self.evaluateAddress(@enumFromInt(@intFromEnum(base_id)), base_node.*)) orelse return null;
                const idx_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(idx_id)), idx_node.*)) orelse return null;
                const result = try self.module.createValue(.Address, "addr.index");
                try self.module.addAddressOf(result, &[_]Value{ base_addr, idx_val }, "index");
                return result;
            },
            else => return null,
        }
    }

    fn freshLabel(self: *Generator, prefix: []const u8) ![]u8 {
        const name = try std.fmt.allocPrint(self.arena.allocator(), "{s}_{d}", .{ prefix, self.label_counter });
        self.label_counter += 1;
        return name;
    }

    // Lightweight IR verifier enforcing basic invariants
    fn verify(self: *Generator) !void {
        // Collect labels
        var labels = std.StringHashMap(bool).init(self.allocator);
        defer labels.deinit();
        for (self.module.instructions.items) |instr| {
            if (instr.kind == .Label) {
                if (instr.metadata.len > 0) {
                    _ = try labels.put(instr.metadata, true);
                }
            }
        }

        // Helpers
        const is_terminator = struct {
            fn check(k: InstructionKind) bool {
                return k == .Branch or k == .CondBranch or k == .Return;
            }
        };

        // Check branches and stores; also basic block termination
        var in_block = false;
        var last_kind: ?InstructionKind = null;
        for (self.module.instructions.items, 0..) |instr, idx| {
            _ = idx;
            // CondBranch operand/type and target labels
            switch (instr.kind) {
                .CondBranch => {
                    if (instr.operands.len != 1) return error.IRVerifyCondBranchOperands;
                    const op = instr.operands[0];
                    if (op.type != .Bool) return error.IRVerifyCondBranchType;
                    // metadata should be "then:X else:Y" and both labels must exist
                    if (!(instr.metadata.len > 0)) return error.IRVerifyCondBranchTargets;
                    if (!(std.mem.indexOf(u8, instr.metadata, "then:") != null and std.mem.indexOf(u8, instr.metadata, "else:") != null))
                        return error.IRVerifyCondBranchTargets;
                    // best-effort parse
                    const then_pos = std.mem.indexOf(u8, instr.metadata, "then:") orelse return error.IRVerifyCondBranchTargets;
                    const else_pos = std.mem.indexOf(u8, instr.metadata, " else:") orelse return error.IRVerifyCondBranchTargets;
                    const then_name = std.mem.trim(u8, instr.metadata[then_pos + 5 .. else_pos], " ");
                    const else_name = std.mem.trim(u8, instr.metadata[else_pos + 6 ..], " ");
                    if (labels.get(then_name) == null or labels.get(else_name) == null) return error.IRVerifyBranchTargetMissing;
                },
                .Branch => {
                    if (!(instr.metadata.len > 0)) return error.IRVerifyBranchTargetMissing;
                    if (labels.get(instr.metadata) == null) return error.IRVerifyBranchTargetMissing;
                },
                .Store => {
                    // dest must exist and be Address
                    const d = instr.dest orelse return error.IRVerifyStoreNoDest;
                    if (d.type != .Address) return error.IRVerifyStoreDestType;
                },
                .Load => {
                    if (instr.operands.len != 1) return error.IRVerifyLoadOperands;
                    if (instr.operands[0].type != .Address) return error.IRVerifyLoadOperandType;
                    if (instr.result) |r| {
                        if (r.type == .Address) return error.IRVerifyLoadResultType;
                    } else return error.IRVerifyLoadNoResult;
                },
                .AddressOf => {
                    if (instr.result) |r| {
                        if (r.type != .Address) return error.IRVerifyAddressOfResultType;
                    } else return error.IRVerifyAddressOfNoResult;

                    if (instr.operands.len != 2) return error.IRVerifyAddressOfOperands;
                    if (instr.operands[0].type != .Address) return error.IRVerifyAddressOfBaseType;

                    // Field vs index by metadata
                    if (instr.metadata.len > 0 and std.mem.eql(u8, instr.metadata, "index")) {
                        if (instr.operands[1].type != .Int) return error.IRVerifyIndexOperandType;
                    } else {
                        if (instr.operands[1].type != .String) return error.IRVerifyFieldOperandType;
                    }
                },
                else => {},
            }

            // Track blocks
            if (instr.kind == .FunctionDef or instr.kind == .Label) {
                // starting a new block; ensure previous (if any and had content) ended with terminator
                if (in_block) {
                    if (last_kind) |lk| {
                        if (!is_terminator.check(lk)) return error.IRVerifyMissingTerminator;
                    }
                }
                in_block = true;
                last_kind = instr.kind;
                continue;
            }
            if (in_block) {
                last_kind = instr.kind;
            }
        }
        // Final block terminator check
        if (in_block) {
            if (last_kind) |lk| {
                if (!is_terminator.check(lk)) return error.IRVerifyMissingTerminator;
            }
        }
    }

    fn evaluateExpr(self: *Generator, node_id: astdb.NodeId, node: astdb.NodeRow) anyerror!?Value {
        const ss = self.snapshot orelse return null;
        switch (node.kind) {
            .identifier, .string_literal, .integer_literal, .float_literal, .bool_literal => {
                return try self.generateValueForArg(ss, node_id, node);
            },
            .call_expr => {
                return try self.generateCallFromNode(node_id, node);
            },
            .field_expr, .index_expr => {
                const vt = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(node_id))) orelse .Int;
                if (try self.evaluateAddress(node_id, node)) |addr| {
                    const tmp = try self.newTemp(vt);
                    try self.module.addInstruction(.Load, tmp, &[_]Value{addr}, "load");
                    return tmp;
                }
                return null;
            },
            .unary_expr => {
                // Lower logical_not and numeric negation
                const kids = node.children(ss);
                if (kids.len == 0) return null;
                const op_tok = ss.getToken(node.first_token) orelse return null;
                const inner_id = kids[0];
                const inner_node = ss.getNode(inner_id) orelse return null;
                const val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(inner_id)), inner_node.*)) orelse return null;
                switch (op_tok.kind) {
                    .logical_not => {
                        const tmp = try self.newTemp(.Bool);
                        try self.module.addUnary(.Not, tmp, val, "not");
                        return tmp;
                    },
                    .minus => {
                        const res_ty = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(node_id))) orelse .Int;
                        const tmp = try self.newTemp(res_ty);
                        try self.module.addUnary(.Neg, tmp, val, "neg");
                        return tmp;
                    },
                    .plus => {
                        // Unary plus is a no-op
                        return val;
                    },
                    else => return val,
                }
            },
            .binary_expr => {
                if (ss.getToken(node.last_token)) |op_tok| {
                    const kids = node.children(ss);
                    if (kids.len == 2) {
                        const lhs_id = kids[0];
                        const rhs_id = kids[1];
                        const lhs_node = ss.getNode(lhs_id) orelse return null;
                        const rhs_node = ss.getNode(rhs_id) orelse return null;

                        if (op_tok.kind == .assign or op_tok.kind == .walrus_assign or op_tok.kind == .equal) {
                            if (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) |rhs_val| {
                                if (lhs_node.kind == .identifier) {
                                    if (ss.getToken(lhs_node.first_token)) |ltok| {
                                        const name = if (ltok.str) |sid| @constCast(self.semantic_graph).astdb_system.str_interner.getString(sid) else "_";
                                        const slot = blk: {
                                            if (self.locals.get(name)) |s| break :blk s;
                                            const s = try self.module.createValue(.Address, name);
                                            _ = try self.locals.put(name, s);
                                            try self.module.addInstruction(.VarDecl, s, &[_]Value{}, name);
                                            break :blk s;
                                        };
                                        try self.module.addStore(slot, rhs_val, name);
                                        return rhs_val;
                                    }
                                }
                            }
                            return null;
                        }

                        // Arithmetic
                        if (op_tok.kind == .plus or op_tok.kind == .minus or op_tok.kind == .star or op_tok.kind == .slash) {
                            const lhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(lhs_id)), lhs_node.*)) orelse return null;
                            const rhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) orelse return null;
                            const ty = self.inferValueTypeForNode(@enumFromInt(@intFromEnum(node_id))) orelse .Int;
                            const tmp = try self.newTemp(ty);
                            const opcode: BinaryOpcode = switch (op_tok.kind) {
                                .plus => .Add,
                                .minus => .Sub,
                                .star => .Mul,
                                .slash => .Div,
                                else => .Add,
                            };
                            try self.module.addBinary(opcode, tmp, &[_]Value{ lhs_val, rhs_val }, "binop");
                            return tmp;
                        }

                        // Comparisons
                        if (op_tok.kind == .equal_equal or op_tok.kind == .not_equal or op_tok.kind == .less or op_tok.kind == .less_equal or op_tok.kind == .greater or op_tok.kind == .greater_equal) {
                            const lhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(lhs_id)), lhs_node.*)) orelse return null;
                            const rhs_val = (try self.evaluateExpr(@enumFromInt(@intFromEnum(rhs_id)), rhs_node.*)) orelse return null;
                            const tmp = try self.newTemp(.Bool);
                            const cop: CompareOpcode = switch (op_tok.kind) {
                                .equal_equal => .Eq,
                                .not_equal => .Neq,
                                .less => .Lt,
                                .less_equal => .Le,
                                .greater => .Gt,
                                .greater_equal => .Ge,
                                else => .Eq,
                            };
                            try self.module.addCompare(cop, tmp, &[_]Value{ lhs_val, rhs_val }, "cmp");
                            return tmp;
                        }
                    }
                }
                return null;
            },
            else => return null,
        }
    }

    // Legacy AST methods removed - now using revolutionary ASTDB architecture
};

// Revolutionary IR generation entry point with ASTDB and capability injection
pub fn generateIR(snapshot: *const astdb.Snapshot, semantic_graph: *const Semantic.SemanticGraph, allocator: std.mem.Allocator) !Module {
    var module = Module.init(allocator);
    errdefer module.deinit();

    var generator = Generator.init(&module, semantic_graph, allocator);
    defer generator.deinit();

    try generator.generateFromASTDB(snapshot);
    // Verify IR invariants after generation
    try generator.verify();

    // Optional: attempt to extract J-IR tensor graph and attach for downstream consumers
    if (maybeExtractTensorGraph(snapshot, semantic_graph, allocator)) |result| {
        module.setTensorGraph(result.graph);
        if (result.diagnostics) |diags| {
            module.setTensorDiagnostics(diags);
        }
    }
    return module;
}

const TensorGraphResult = struct {
    graph: *const tensor_jir.Graph,
    diagnostics: ?*tensor_diag.TensorDiagnostics,
};

fn maybeExtractTensorGraph(
    snapshot: *const astdb.Snapshot,
    semantic_graph: *const Semantic.SemanticGraph,
    allocator: std.mem.Allocator,
) ?TensorGraphResult {
    // Gate under :npu via API config
    if (!api.isNpuEnabled()) return null;

    // Minimal starter: synthesize a tiny graph; replace with real extraction later
    const g = tensor_extractor.extractMinimalGraph(@ptrCast(snapshot), @ptrCast(semantic_graph), allocator) catch return null;

    var compile_diag = tensor_compile.CompileDiagnostics.init(allocator, .{});
    _ = compile_diag.analyzeGraph(g) catch {};
    var owned_diags = compile_diag.releaseDiagnostics();
    compile_diag.deinit();

    var diag_ptr: ?*tensor_diag.TensorDiagnostics = null;
    if (owned_diags.all().len > 0) {
        const ptr = allocator.create(tensor_diag.TensorDiagnostics) catch {
            owned_diags.deinit();
            return TensorGraphResult{ .graph = g, .diagnostics = null };
        };
        ptr.* = owned_diags;
        diag_ptr = ptr;
    } else {
        owned_diags.deinit();
    }

    return TensorGraphResult{ .graph = g, .diagnostics = diag_ptr };
}
