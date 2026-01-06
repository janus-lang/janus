// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Licensed under the European Union Public License, Version 1.2 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://joinup.ec.europa.eu/collection/eupl/eupl-text-eupl-12
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the license is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const std = @import("std");
const astdb = @import("astdb");
const lexer = @import("lexer");
const parser = @import("janus_parser");

const capabilities = @import("capabilities");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// Forward declarations for structs defined later
const FunctionInfo = struct {
    name: []const u8,
    parameters: []const ParameterInfo,
    return_type: []const u8,
    min_profile_params: u8 = 0,
    go_profile_params: u8 = 0,
    full_profile_params: u8 = 0,
};

const ParameterInfo = struct {
    name: []const u8,
    type_name: []const u8,
};

const StdLibFunction = struct {
    name: []const u8,
    s0_profile_params: u8,
    core_profile_params: u8,
    service_profile_params: u8,
    sovereign_profile_params: u8,
    // Type information for :core profile
    param_types: []const []const u8, // Parameter types (e.g. ["string", "Allocator"])
    return_type: []const u8, // Return type (e.g. "void")
};

pub const SemanticAnalysisInfo = struct {
    function_calls: std.ArrayList(FunctionCallInfo),
    variable_declarations: std.ArrayList(VariableDeclarationInfo),
    function_signatures: std.StringHashMap(FunctionInfo),
    allocator: Allocator,

    // Holds a reference to the current analysis info for lookup during type inference
    current_analysis_info: ?*SemanticAnalysisInfo = null,

    pub const FunctionCallInfo = struct {
        function_name: []const u8,
        caller_line: u32,
        caller_column: u32,
        resolved_function: ?*const FunctionInfo = null,
        stdlib_function: ?*const StdLibFunction = null,
        profile_compatible: bool = true, // TODO: Implement proper profile validation
        argument_count: u32 = 0, // TODO: Implement proper argument counting
        profile: SemanticAnalyzer.Profile = .core, // TODO: Implement proper profile tracking
        status: CallStatus = .ok, // TODO: Implement proper status tracking
        node_id: ?astdb.NodeId = null, // TODO: Implement proper node tracking

        pub const CallStatus = enum {
            ok,
            invalid_arity,
            type_mismatch,
            capability_missing,
        };
    };

    pub const VariableDeclarationInfo = struct {
        variable_name: []const u8,
        type_name: []const u8,
        line: u32,
        column: u32,
    };

    pub fn deinit(self: *SemanticAnalysisInfo) void {
        self.function_calls.deinit(self.allocator);
        self.variable_declarations.deinit(self.allocator);
        self.function_signatures.deinit();
    }
};

pub const SemanticAnalyzer = struct {
    allocator: Allocator,
    astdb_instance: *astdb.AstDB,
    profile: Profile,

    // Context for type inference
    current_analysis_info: ?*SemanticAnalysisInfo = null,
    current_function_name: []const u8 = "",

    const Profile = enum {
        core, // Foundational subset (formerly :min)
        s0, // Alias for core (S0 bootstrap profile)
        script, // Fluid mode for core profile
        service, // IO/Networking (formerly :go)
        cluster, // Distributed/Actors (formerly :elixir)
        compute, // HPC/Tensors (formerly :npu)
        sovereign, // Full capability (formerly :full)
    };

    const STDLIB_FUNCTIONS = [_]StdLibFunction{
        // I/O functions
        .{
            .name = "print",
            .s0_profile_params = 1,
            .core_profile_params = 2,
            .service_profile_params = 2,
            .sovereign_profile_params = 2,
            .param_types = &[_][]const u8{ "string", "Allocator" },
            .return_type = "void",
        },
        .{
            .name = "println",
            .s0_profile_params = 1,
            .core_profile_params = 2,
            .service_profile_params = 2,
            .sovereign_profile_params = 2,
            .param_types = &[_][]const u8{ "string", "Allocator" },
            .return_type = "void",
        },
        .{
            .name = "panic",
            .s0_profile_params = 1,
            .core_profile_params = 1,
            .service_profile_params = 1,
            .sovereign_profile_params = 1,
            .param_types = &[_][]const u8{"string"},
            .return_type = "void",
        },
        .{
            .name = "print_int",
            .s0_profile_params = 1,
            .core_profile_params = 1,
            .service_profile_params = 1,
            .sovereign_profile_params = 1,
            .param_types = &[_][]const u8{"i32"},
            .return_type = "void",
        },
        // Allocator functions
        .{ .name = "Allocator.create", .s0_profile_params = 1, .core_profile_params = 1, .service_profile_params = 1, .sovereign_profile_params = 1, .param_types = &[_][]const u8{}, .return_type = "Allocator" },
        .{ .name = "Allocator.default_allocator", .s0_profile_params = 0, .core_profile_params = 0, .service_profile_params = 0, .sovereign_profile_params = 0, .param_types = &[_][]const u8{}, .return_type = "Allocator" },
        .{ .name = "Allocator.allocate", .s0_profile_params = 2, .core_profile_params = 2, .service_profile_params = 2, .sovereign_profile_params = 2, .param_types = &[_][]const u8{}, .return_type = "[]u8" },
        .{ .name = "Allocator.free", .s0_profile_params = 2, .core_profile_params = 2, .service_profile_params = 2, .sovereign_profile_params = 2, .param_types = &[_][]const u8{}, .return_type = "void" },
        // Region functions
        .{ .name = "region", .s0_profile_params = 0, .core_profile_params = 0, .service_profile_params = 0, .sovereign_profile_params = 0, .param_types = &[_][]const u8{}, .return_type = "Region" },
        // Using functions
        .{ .name = "using", .s0_profile_params = 0, .core_profile_params = 0, .service_profile_params = 0, .sovereign_profile_params = 0, .param_types = &[_][]const u8{}, .return_type = "void" },
        // String API
        .{ .name = "string.len", .s0_profile_params = 1, .core_profile_params = 1, .service_profile_params = 1, .sovereign_profile_params = 1, .param_types = &[_][]const u8{"string"}, .return_type = "i32" },
        .{ .name = "string.concat", .s0_profile_params = 2, .core_profile_params = 2, .service_profile_params = 2, .sovereign_profile_params = 2, .param_types = &[_][]const u8{ "string", "string" }, .return_type = "string" },
    };

    pub fn init(allocator: Allocator, astdb_param: *astdb.AstDB, profile: Profile) SemanticAnalyzer {
        // S0 gate: force :core profile when bootstrap S0 is enabled
        const bootstrap_s0 = @import("bootstrap_s0");
        const effective_profile = if (bootstrap_s0.isEnabled()) .core else profile;

        return .{
            .allocator = allocator,
            .astdb_instance = astdb_param,
            .profile = effective_profile,
        };
    }

    pub fn analyze(self: *SemanticAnalyzer, unit_id: astdb.UnitId) !SemanticAnalysisInfo {
        // Get the compilation unit - ASTDB should have parsed AST
        const unit = self.astdb_instance.getUnit(unit_id) orelse return error.InvalidUnitId;

        var analysis_info = SemanticAnalysisInfo{
            .function_calls = .{},
            .variable_declarations = .{},
            .function_signatures = std.StringHashMap(FunctionInfo).init(self.allocator),
            .allocator = self.allocator,
        };
        // expose analysis info for identifier lookup during inference
        self.current_analysis_info = &analysis_info;
        errdefer analysis_info.deinit();
        // Reset after analysis (will be cleared at end of function)
        defer self.current_analysis_info = null;

        // Walk all ASTDB nodes
        for (unit.nodes, 0..) |node, i| {
            const node_id: astdb.NodeId = @enumFromInt(@as(u32, @intCast(i)));
            try self.analyzeNode(node_id, &node, &analysis_info);
        }

        // Profile validation
        try self.validateProfileWithAstdb(&analysis_info, unit);

        return analysis_info;
    }

    /// Analyze a single ASTDB node
    fn analyzeNode(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        switch (node.kind) {
            .func_decl => try self.analyzeFunctionDecl(node_id, node, analysis_info),
            .var_stmt, .let_stmt => try self.analyzeVarDecl(node_id, node, analysis_info),
            .call_expr => try self.analyzeFunctionCall(node_id, node, analysis_info),
            .range_inclusive_expr, .range_exclusive_expr => try self.analyzeRangeExpr(node_id, node, analysis_info),
            .array_lit => try self.analyzeArrayLit(node_id, node, analysis_info),
            else => {},
        }
    }

    /// Analyze function declaration
    fn analyzeFunctionDecl(
        self: *SemanticAnalyzer,
        _: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        // Expect first child to be function name identifier
        const unit = self.astdb_instance.units.items[0];
        const children = unit.edges[node.child_lo..node.child_hi];
        if (children.len == 0) return;
        const name_node = &unit.nodes[@intFromEnum(children[0])];
        if (name_node.kind != .identifier) return;
        const name_token = &unit.tokens[@intFromEnum(name_node.first_token)];
        const func_name = if (name_token.str) |str_id| self.astdb_instance.str_interner.getString(str_id) else return;

        // Parse parameters (children[1..] until we hit a return type or block)
        var params: std.ArrayList(ParameterInfo) = .{};
        var return_type: []const u8 = "void"; // default
        var i: usize = 1;
        while (i < children.len) : (i += 1) {
            const child_id = children[i];
            const child_node = &unit.nodes[@intFromEnum(child_id)];
            switch (child_node.kind) {
                .parameter => {
                    // Parameter children: identifier then type
                    const param_children = unit.edges[child_node.child_lo..child_node.child_hi];
                    if (param_children.len >= 2) {
                        const param_name_node = &unit.nodes[@intFromEnum(param_children[0])];
                        const param_type_node = &unit.nodes[@intFromEnum(param_children[1])];
                        const pn_tok = &unit.tokens[@intFromEnum(param_name_node.first_token)];
                        const pt_tok = &unit.tokens[@intFromEnum(param_type_node.first_token)];
                        const param_name = if (pn_tok.str) |sid| self.astdb_instance.str_interner.getString(sid) else "";
                        const param_type = if (pt_tok.str) |sid| self.astdb_instance.str_interner.getString(sid) else "";
                        params.append(self.allocator, .{ .name = param_name, .type_name = param_type }) catch {};
                    }
                },
                .named_type => {
                    // Return type
                    const rt_tok = &unit.tokens[@intFromEnum(child_node.first_token)];
                    return_type = if (rt_tok.str) |sid| self.astdb_instance.str_interner.getString(sid) else "void";
                    // Stop processing further children (function body follows)
                    break;
                },
                .block_stmt => {
                    // No explicit return type, body follows
                    break;
                },
                else => {},
            }
        }
        const func_info = FunctionInfo{
            .name = func_name,
            .parameters = try params.toOwnedSlice(self.allocator),
            .return_type = return_type,
        };
        // Insert into the function signatures map
        _ = analysis_info.function_signatures.put(func_name, func_info) catch {};
        // Clean up params list (slice now owned by func_info)
        // Note: params buffer is now owned, no need to deinit
    }

    /// Analyze range expression
    fn analyzeRangeExpr(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        _ = analysis_info;
        const unit = self.astdb_instance.units.items[0];
        const children = unit.edges[node.child_lo..node.child_hi];
        if (children.len != 2) return error.SemanticError;

        const left_node = &unit.nodes[@intFromEnum(children[0])];
        const right_node = &unit.nodes[@intFromEnum(children[1])];

        const left_type = try self.inferExpressionType(node_id, left_node);
        const right_type = try self.inferExpressionType(node_id, right_node);

        // Enforce integer bounds for now
        // TODO: Support other types that support ranges
        if (!std.mem.eql(u8, left_type, "i32") and !std.mem.eql(u8, left_type, "unknown")) {
            return error.SemanticError;
        }
        if (!std.mem.eql(u8, right_type, "i32") and !std.mem.eql(u8, right_type, "unknown")) {
            return error.SemanticError;
        }
    }

    /// Analyze array literal
    fn analyzeArrayLit(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        _ = analysis_info;
        const unit = self.astdb_instance.units.items[0];
        const children = unit.edges[node.child_lo..node.child_hi];

        if (children.len == 0) {
            // Empty array literal [], type is usually []unknown until inferred from context
            // For now, valid.
            return;
        }

        // Homogeneity Check
        // Infer type of first element
        const first_node = &unit.nodes[@intFromEnum(children[0])];
        const expected_type = try self.inferExpressionType(node_id, first_node);

        for (children[1..]) |child_id| {
            const child_node = &unit.nodes[@intFromEnum(child_id)];
            const child_type = try self.inferExpressionType(node_id, child_node);

            if (!std.mem.eql(u8, expected_type, child_type) and
                !std.mem.eql(u8, expected_type, "unknown") and
                !std.mem.eql(u8, child_type, "unknown"))
            {
                // Mismatch
                return error.SemanticError;
            }
        }
    }

    /// Infer type of an expression node
    fn inferExpressionType(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
    ) ![]const u8 {
        switch (node.kind) {
            .string_literal => return "string",
            .integer_literal => return "i32",
            .bool_literal => return "bool",
            .identifier => return self.lookupIdentifierType(node_id, node),
            .call_expr => return self.inferCallExpressionType(node_id, node),
            .range_inclusive_expr, .range_exclusive_expr => return "Range", // Simplified type
            .array_lit => return "Array", // Simplified type for now
            else => return "unknown",
        }
    }

    fn inferCallExpressionType(
        self: *SemanticAnalyzer,
        _: astdb.NodeId,
        node: *const astdb.AstNode,
    ) ![]const u8 {
        // The call expression node's first child is the callee identifier
        const unit = self.astdb_instance.units.items[0];
        const children = unit.edges[node.child_lo..node.child_hi];
        if (children.len == 0) return "unknown";
        const callee_node = &unit.nodes[@intFromEnum(children[0])];
        if (callee_node.kind != .identifier) return "unknown";
        const name_token = &unit.tokens[@intFromEnum(callee_node.first_token)];
        const func_name = if (name_token.str) |str_id| self.astdb_instance.str_interner.getString(str_id) else "unknown";
        // First try stdlib functions
        for (STDLIB_FUNCTIONS) |stdlib_fn| {
            if (std.mem.eql(u8, stdlib_fn.name, func_name)) {
                return stdlib_fn.return_type;
            }
        }
        // Then try user‑defined functions from the symbol table
        if (self.current_analysis_info) |info| {
            if (info.function_signatures.get(func_name)) |func_info| {
                // Record resolved function for later use (e.g., return‑type checks)
                // Note: we cannot modify call_info here; the caller will resolve again if needed
                return func_info.return_type;
            }
        }
        // Unknown function
        return "unknown";
    }

    // Extend identifier type lookup to check parameters and variables using current_analysis_info
    fn lookupIdentifierType(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
    ) ![]const u8 {
        _ = node_id;
        const unit = self.astdb_instance.units.items[0];
        const token_idx = @intFromEnum(node.first_token);
        if (token_idx >= unit.tokens.len) return "unknown";
        const token = &unit.tokens[token_idx];
        if (token.str) |str_id| {
            const name = self.astdb_instance.str_interner.getString(str_id);
            // 1) Check parameters of the current function
            if (self.current_function_name.len > 0) {
                if (self.current_analysis_info) |info| {
                    if (info.function_signatures.get(self.current_function_name)) |func_info| {
                        for (func_info.parameters) |param| {
                            if (std.mem.eql(u8, param.name, name)) {
                                return param.type_name;
                            }
                        }
                    }
                }
            }
            // 2) Check variable declarations (flat list)
            if (self.current_analysis_info) |info| {
                for (info.variable_declarations.items) |var_decl| {
                    if (std.mem.eql(u8, var_decl.variable_name, name)) {
                        return var_decl.type_name;
                    }
                }
            }
            // 3) Temporary hack for allocator identifier
            if (std.mem.eql(u8, name, "allocator")) {
                return "Allocator";
            }
        }
        return "unknown";
    }

    /// Analyze variable declaration
    fn analyzeVarDecl(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        _ = self;
        _ = node_id;
        _ = node;
        _ = analysis_info;
        // TODO: Track variable declarations
    }

    /// Analyze function call (critical for s0_smoke test)
    fn analyzeFunctionCall(
        self: *SemanticAnalyzer,
        node_id: astdb.NodeId,
        node: *const astdb.AstNode,
        analysis_info: *SemanticAnalysisInfo,
    ) !void {
        // Extract function name and argument count from ASTDB
        const unit = self.astdb_instance.units.items[0]; // TODO: Track current unit properly
        const children = unit.edges[node.child_lo..node.child_hi];

        // First child should be function name (identifier)
        if (children.len == 0) return;

        // Extract function name from ASTDB
        const name_node = &unit.nodes[@intFromEnum(children[0])];

        // Only analyze direct function calls (identifier callee)
        // Method calls (field_expr) are skipped for now as they don't match STDLIB_FUNCTIONS
        if (name_node.kind != .identifier) {
            return;
        }

        const name_token = &unit.tokens[@intFromEnum(name_node.first_token)];
        const function_name = if (name_token.str) |str_id|
            self.astdb_instance.str_interner.getString(str_id)
        else
            return;

        // Skip constructor calls (PascalCase) - e.g. ArrayList
        if (function_name.len > 0 and std.ascii.isUpper(function_name[0])) {
            return;
        }
        // Skip 'init' method calls (common constructor pattern)
        if (std.mem.eql(u8, function_name, "init")) {
            return;
        }

        // Count arguments (remaining children after function name)
        const arg_count: u32 = @intCast(children.len - 1);

        const bootstrap_s0 = @import("bootstrap_s0");
        var call_info = SemanticAnalysisInfo.FunctionCallInfo{
            .function_name = function_name,
            .caller_line = name_token.span.line,
            .caller_column = name_token.span.column,
            .argument_count = arg_count,
            // In S0 bootstrap mode, report calls as .s0 even if analyzer is .min
            .profile = if (bootstrap_s0.isEnabled()) .s0 else self.profile,
            .profile_compatible = true, // TODO: Check compatibility
            .node_id = node_id,
        };
        // Resolve stdlib function if any
        var matched_fn: ?StdLibFunction = null;
        for (STDLIB_FUNCTIONS) |stdlib_fn| {
            if (std.mem.eql(u8, stdlib_fn.name, function_name)) {
                matched_fn = stdlib_fn;
                break;
            }
        }
        // Type‑check arguments if we have a known stdlib function
        if (matched_fn) |stdlib_fn| {
            var arg_index: usize = 0;
            for (children[1..]) |arg_node_id| {
                const arg_node = &unit.nodes[@intFromEnum(arg_node_id)];
                const inferred_type = try self.inferExpressionType(node_id, arg_node);
                const expected_type = stdlib_fn.param_types[arg_index];
                if (!std.mem.eql(u8, inferred_type, expected_type)) {
                    call_info.status = .type_mismatch;
                    return error.SemanticError;
                }
                arg_index += 1;
            }
        } else {
            // Try to resolve user‑defined function for return‑type checking
            if (self.current_analysis_info) |info| {
                if (info.function_signatures.getPtr(function_name)) |func_ptr| {
                    // Record resolved function for later use (e.g., return‑type checks)
                    call_info.resolved_function = func_ptr;
                } else {
                    // Unknown function
                    call_info.status = .invalid_arity; // or a new status if desired
                }
            }
        }
        // Track function call
        try analysis_info.function_calls.append(self.allocator, call_info);

        // Check against stdlib functions for arity

        for (STDLIB_FUNCTIONS) |stdlib_fn| {
            if (std.mem.eql(u8, stdlib_fn.name, function_name)) {
                // S0 bootstrap mode is more permissive - accepts both S0 and min arity
                if (bootstrap_s0.isEnabled() and stdlib_fn.s0_profile_params != stdlib_fn.core_profile_params) {
                    // Accept either S0 arity (1) or core arity (2) for print
                    const min_arity = @min(stdlib_fn.s0_profile_params, stdlib_fn.core_profile_params);
                    const max_arity = @max(stdlib_fn.s0_profile_params, stdlib_fn.core_profile_params);
                    if (arg_count < min_arity or arg_count > max_arity) {
                        return error.SemanticError;
                    }
                } else {
                    // Normal profile-specific arity check
                    const expected_params = switch (self.profile) {
                        .s0, .core => stdlib_fn.core_profile_params,
                        .service => stdlib_fn.service_profile_params,
                        else => stdlib_fn.sovereign_profile_params,
                    };

                    if (arg_count != expected_params) {
                        return error.SemanticError;
                    }
                }
            }
        }
    }

    /// Validate profile compliance with ASTDB nodes
    fn validateProfileWithAstdb(
        self: *SemanticAnalyzer,
        analysis_info: *SemanticAnalysisInfo,
        unit: *astdb.CompilationUnit,
    ) !void {
        _ = analysis_info;

        switch (self.profile) {
            .core, .s0 => {
                for (unit.nodes) |node| {
                    switch (node.kind) {
                        .using_decl => {
                            // "using" is forbidden in :core
                            return error.ProfileViolation;
                        },
                        .import_stmt => {
                            // "import" is forbidden in :core (use :service or higher)
                            return error.ProfileViolation;
                        },
                        .use_stmt => {
                            // "use" / "graft" is forbidden in :core
                            return error.ProfileViolation;
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }
    }

    fn analyzeAst(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateMinProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateScriptProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateGoProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateElixirProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateFullProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn validateNpuProfile(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn detectRegionEscapes(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) !void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }

    fn trackAllocationEffects(self: *SemanticAnalyzer, analysis_info: *SemanticAnalysisInfo, ast: parser.Ast) !void {
        _ = self;
        _ = analysis_info;
        _ = ast;
    }
};
