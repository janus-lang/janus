// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Validation Engine - The Guardian of Language Rules
//!
//! This module implements comprehensive semantic validation including
//! profile-aware checking, definite assignment analysis, and language-
//! specific rule enforcement. It ensures semantic correctness across
//! all Janus language constructs and profiles.
//!
//! Key Features:
//! - Profile boundary enforcement (:core, :service, :cluster, :sovereign)
//! - Definite assignment analysis (use-before-definition detection)
//! - Unreachable code detection and dead code elimination hints
//! - Language-specific semantic rule validation
//! - Cross-module dependency validation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;

const astdb = @import("astdb");
const symbol_table = @import("symbol_table.zig");
const type_system = @import("type_system.zig");
const type_inference = @import("type_inference.zig");

const NodeId = astdb.NodeId;
const UnitId = astdb.UnitId;
const SymbolId = symbol_table.SymbolId;
const TypeId = type_system.TypeId;
const SymbolTable = symbol_table.SymbolTable;
const TypeSystem = type_system.TypeSystem;
const TypeInference = type_inference.TypeInference;
// Janus language profiles with feature gates
pub const Profile = enum {
    core, // :core - Foundational subset (6 types, pure basics)
    service, // :service - IO, error-handling, networking (formerly :go)
    cluster, // :cluster - Distributed systems (formerly :elixir)
    sovereign, // :sovereign - Full capability (formerly :full)

    /// Check if feature is available in this profile
    pub fn hasFeature(self: Profile, feature: Feature) bool {
        return switch (feature) {
            // Core features available in all profiles
            .basic_types, .functions, .variables, .control_flow, .error_handling => true,

            // :service profile and above
            .interfaces, .channels => switch (self) {
                .core => false,
                .service, .cluster, .sovereign => true,
            },

            // :cluster profile and above
            .pattern_matching, .actors, .supervision => switch (self) {
                .core, .service => false,
                .cluster, .sovereign => true,
            },

            // :sovereign profile only
            .effects, .comptime_eval, .metaprogramming, .unsafe_ops => switch (self) {
                .core, .service, .cluster => false,
                .sovereign => true,
            },
        };
    }
};

/// Language features with profile gates
pub const Feature = enum {
    // Core features (:min and above)
    basic_types,
    functions,
    variables,
    control_flow,

    // :go features
    error_handling,
    interfaces,
    channels,

    // :elixir features
    pattern_matching,
    actors,
    supervision,

    // :full features
    effects,
    comptime_eval,
    metaprogramming,
    unsafe_ops,
};

/// Semantic validation error types
pub const ValidationError = struct {
    kind: ErrorKind,
    message: []const u8,
    span: symbol_table.SourceSpan,
    suggestions: [][]const u8,
    related_info: []RelatedInfo,

    pub const ErrorKind = enum {
        // Profile violations (E20xx)
        profile_violation, // E2004
        feature_not_available, // E2009

        // Assignment analysis (E21xx)
        use_before_definition, // E2101
        uninitialized_variable, // E2102
        definite_assignment_fail, // E2103

        // Control flow (E22xx)
        unreachable_code, // E2201
        missing_return, // E2202
        dead_code, // E2203

        // Language rules (E23xx)
        immutable_assignment, // E2301
        invalid_operation, // E2302
        semantic_constraint, // E2303

        // Cross-module (E24xx)
        circular_dependency, // E2401 (E2005 alias)
        import_not_found, // E2402
        visibility_violation, // E2403
    };

    pub const RelatedInfo = struct {
        span: symbol_table.SourceSpan,
        message: []const u8,
    };
};

/// Semantic Validation Engine
pub const SemanticValidator = struct {
    allocator: Allocator,
    astdb: *astdb.ASTDBSystem,
    symbol_table: *SymbolTable,
    type_system: *TypeSystem,
    type_inference: *TypeInference,

    /// Current validation profile
    profile: Profile,

    /// Collected validation errors
    errors: ArrayList(ValidationError),

    /// Variable assignment tracking for definite assignment
    assignments: HashMap(SymbolId, AssignmentState),

    /// Control flow analysis state
    control_flow: ControlFlowAnalyzer,

    /// Validation statistics
    stats: ValidationStats = .{},

    const AssignmentState = struct {
        is_initialized: bool = false,
        assignment_spans: ArrayList(symbol_table.SourceSpan),
        usage_spans: ArrayList(symbol_table.SourceSpan),

        pub fn init(allocator: Allocator) AssignmentState {
            return AssignmentState{
                .assignment_spans = ArrayList(symbol_table.SourceSpan).init(allocator),
                .usage_spans = ArrayList(symbol_table.SourceSpan).init(allocator),
            };
        }

        pub fn deinit(self: *AssignmentState) void {
            self.assignment_spans.deinit();
            self.usage_spans.deinit();
        }
    };

    const ControlFlowAnalyzer = struct {
        reachable_nodes: HashMap(NodeId, bool),
        return_paths: ArrayList(NodeId),

        pub fn init(allocator: Allocator) ControlFlowAnalyzer {
            return ControlFlowAnalyzer{
                .reachable_nodes = HashMap(NodeId, bool).init(allocator),
                .return_paths = ArrayList(NodeId).init(allocator),
            };
        }

        pub fn deinit(self: *ControlFlowAnalyzer) void {
            self.reachable_nodes.deinit();
            self.return_paths.deinit();
        }
    };

    pub const ValidationStats = struct {
        nodes_validated: u32 = 0,
        profile_checks: u32 = 0,
        assignment_checks: u32 = 0,
        control_flow_checks: u32 = 0,
        errors_found: u32 = 0,
    };

    pub fn init(
        allocator: Allocator,
        astdb_instance: *astdb.ASTDBSystem,
        symbol_tbl: *SymbolTable,
        type_sys: *TypeSystem,
        type_inf: *TypeInference,
        validation_profile: Profile,
    ) !*SemanticValidator {
        const validator = try allocator.create(SemanticValidator);
        validator.* = SemanticValidator{
            .allocator = allocator,
            .astdb = astdb_instance,
            .symbol_table = symbol_tbl,
            .type_system = type_sys,
            .type_inference = type_inf,
            .profile = validation_profile,
            .errors = ArrayList(ValidationError).init(allocator),
            .assignments = HashMap(SymbolId, AssignmentState).init(allocator),
            .control_flow = ControlFlowAnalyzer.init(allocator),
        };
        return validator;
    }

    pub fn deinit(self: *SemanticValidator) void {
        // Clean up validation errors
        for (self.errors.items) |error_item| {
            self.allocator.free(error_item.message);
            for (error_item.suggestions) |suggestion| {
                self.allocator.free(suggestion);
            }
            self.allocator.free(error_item.suggestions);
            for (error_item.related_info) |info| {
                self.allocator.free(info.message);
            }
            self.allocator.free(error_item.related_info);
        }
        self.errors.deinit();

        // Clean up assignment tracking
        var assignment_iter = self.assignments.iterator();
        while (assignment_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.assignments.deinit();

        // Clean up control flow analyzer
        self.control_flow.deinit();

        self.allocator.destroy(self);
    }

    /// Validate an entire compilation unit
    pub fn validateUnit(self: *SemanticValidator, unit_id: UnitId) !void {
        // TODO: Implement getUnitRoot in ASTDBSystem
        const root_node = NodeId{ .id = 0 };

        // Phase 1: Profile-aware feature validation
        try self.validateProfileCompliance(root_node);

        // Phase 2: Definite assignment analysis
        try self.analyzeDefiniteAssignment(root_node);

        // Phase 3: Control flow analysis
        try self.analyzeControlFlow(root_node);

        // Phase 4: Language-specific semantic rules
        try self.validateSemanticRules(root_node);
    }

    /// Phase 1: Validate profile compliance and feature gates
    fn validateProfileCompliance(self: *SemanticValidator, node_id: NodeId) !void {
        const node = self.astdb.getNode(node_id);

        // Check if node represents a feature that requires profile validation
        const required_feature = self.getRequiredFeature(node.kind);
        if (required_feature) |feature| {
            self.stats.profile_checks += 1;

            if (!self.profile.hasFeature(feature)) {
                try self.reportProfileViolation(node_id, feature);
            }
        }

        // Recursively validate child nodes
        const children = self.astdb.getNodeChildren(node_id);
        for (children) |child_id| {
            try self.validateProfileCompliance(child_id);
        }

        self.stats.nodes_validated += 1;
    }

    /// Get required feature for AST node kind
    fn getRequiredFeature(self: *SemanticValidator, node_kind: astdb.NodeKind) ?Feature {
        _ = self;

        return switch (node_kind) {
            // Core features (available in all profiles)
            .literal_int, .literal_float, .literal_string, .literal_bool => .basic_types,
            .function_declaration, .function_call => .functions,
            .variable_declaration, .identifier => .variables,
            .if_statement, .while_loop, .for_loop => .control_flow,

            // :service features
            .error_handling, .error_type => .error_handling,
            .interface_declaration => .interfaces,
            .channel_type, .channel_send, .channel_receive => .channels,

            // :cluster features
            .match_expression, .pattern => .pattern_matching,
            .actor_declaration, .spawn_expression => .actors,
            .supervisor_declaration => .supervision,

            // :sovereign features
            .effect_declaration, .effect_handler => .effects,
            .comptime_expression, .comptime_block => .comptime_eval,
            .macro_declaration => .metaprogramming,
            .unsafe_block, .raw_pointer => .unsafe_ops,

            // No specific feature requirement
            else => null,
        };
    }

    /// Report profile violation error
    fn reportProfileViolation(self: *SemanticValidator, node_id: NodeId, feature: Feature) !void {
        const span = self.getNodeSpan(node_id);
        const feature_name = @tagName(feature);
        const profile_name = @tagName(self.profile);

        const message = try std.fmt.allocPrint(self.allocator, "Feature '{s}' is not available in profile ':{s}'. Use profile ':sovereign' or higher.", .{ feature_name, profile_name });

        const suggestions = try self.allocator.alloc([]const u8, 1);
        suggestions[0] = try std.fmt.allocPrint(self.allocator, "Add profile annotation: // profile: :sovereign");

        const error_item = ValidationError{
            .kind = .profile_violation,
            .message = message,
            .span = span,
            .suggestions = suggestions,
            .related_info = &.{},
        };

        try self.errors.append(error_item);
        self.stats.errors_found += 1;
    }

    /// Phase 2: Analyze definite assignment (use-before-definition)
    fn analyzeDefiniteAssignment(self: *SemanticValidator, node_id: NodeId) !void {
        const node = self.astdb.getNode(node_id);

        switch (node.kind) {
            .variable_declaration => try self.analyzeVariableDeclaration(node_id),
            .identifier => try self.analyzeIdentifierUsage(node_id),
            .assignment => try self.analyzeAssignment(node_id),
            else => {
                // Recursively analyze child nodes
                const children = self.astdb.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.analyzeDefiniteAssignment(child_id);
                }
            },
        }

        self.stats.assignment_checks += 1;
    }

    /// Analyze variable declaration for initialization
    fn analyzeVariableDeclaration(self: *SemanticValidator, node_id: NodeId) !void {
        const symbol_id = self.astdb.getNodeSymbol(node_id) orelse return;
        const initializer = self.astdb.getVariableInitializer(node_id);

        var assignment_state = AssignmentState.init(self.allocator);
        assignment_state.is_initialized = initializer != null;

        const span = self.getNodeSpan(node_id);
        try assignment_state.assignment_spans.append(span);

        try self.assignments.put(symbol_id, assignment_state);

        // Analyze initializer if present
        if (initializer) |init_node| {
            try self.analyzeDefiniteAssignment(init_node);
        }
    }

    /// Analyze identifier usage for definite assignment
    fn analyzeIdentifierUsage(self: *SemanticValidator, node_id: NodeId) !void {
        const symbol_id = self.astdb.getNodeSymbol(node_id) orelse return;

        if (self.assignments.getPtr(symbol_id)) |assignment_state| {
            const span = self.getNodeSpan(node_id);
            try assignment_state.usage_spans.append(span);

            if (!assignment_state.is_initialized) {
                try self.reportUseBeforeDefinition(node_id, symbol_id);
            }
        }
    }

    /// Analyze assignment statement
    fn analyzeAssignment(self: *SemanticValidator, node_id: NodeId) !void {
        const target = self.astdb.getAssignmentTarget(node_id) orelse return;
        const value = self.astdb.getAssignmentValue(node_id) orelse return;

        // Analyze value expression first
        try self.analyzeDefiniteAssignment(value);

        // Mark target as assigned
        if (self.astdb.getNodeSymbol(target)) |symbol_id| {
            if (self.assignments.getPtr(symbol_id)) |assignment_state| {
                assignment_state.is_initialized = true;
                const span = self.getNodeSpan(node_id);
                try assignment_state.assignment_spans.append(span);
            }
        }
    }

    /// Report use-before-definition error
    fn reportUseBeforeDefinition(self: *SemanticValidator, node_id: NodeId, symbol_id: SymbolId) !void {
        const span = self.getNodeSpan(node_id);
        const symbol = self.symbol_table.getSymbol(symbol_id) orelse return;
        const symbol_name = self.symbol_table.symbol_interner.getString(symbol.name);

        const message = try std.fmt.allocPrint(self.allocator, "Variable '{s}' used before initialization", .{symbol_name});

        const suggestions = try self.allocator.alloc([]const u8, 1);
        suggestions[0] = try std.fmt.allocPrint(self.allocator, "Initialize '{s}' before use or provide a default value", .{symbol_name});

        const related_info = try self.allocator.alloc(ValidationError.RelatedInfo, 1);
        related_info[0] = ValidationError.RelatedInfo{
            .span = symbol.declaration_span,
            .message = try std.fmt.allocPrint(self.allocator, "'{s}' declared here", .{symbol_name}),
        };

        const error_item = ValidationError{
            .kind = .use_before_definition,
            .message = message,
            .span = span,
            .suggestions = suggestions,
            .related_info = related_info,
        };

        try self.errors.append(error_item);
        self.stats.errors_found += 1;
    }

    /// Phase 3: Analyze control flow for unreachable code and missing returns
    fn analyzeControlFlow(self: *SemanticValidator, node_id: NodeId) !void {
        const node = self.astdb.getNode(node_id);

        // Mark node as reachable initially
        try self.control_flow.reachable_nodes.put(node_id, true);

        switch (node.kind) {
            .function_declaration => try self.analyzeFunctionControlFlow(node_id),
            .return_statement => try self.analyzeReturnStatement(node_id),
            .if_statement => try self.analyzeIfStatement(node_id),
            .while_loop => try self.analyzeWhileLoop(node_id),
            else => {
                // Recursively analyze child nodes
                const children = self.astdb.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.analyzeControlFlow(child_id);
                }
            },
        }

        self.stats.control_flow_checks += 1;
    }

    /// Analyze function for missing return statements
    fn analyzeFunctionControlFlow(self: *SemanticValidator, node_id: NodeId) !void {
        const return_type = self.astdb.getFunctionReturnType(node_id);
        const body = self.astdb.getFunctionBody(node_id);

        if (body) |body_node| {
            try self.analyzeControlFlow(body_node);

            // Check if function needs return statement
            if (return_type) |ret_type_node| {
                const ret_type_id = try self.resolveTypeAnnotation(ret_type_node);
                if (ret_type_id != self.type_system.primitives.void) {
                    if (!self.hasReturnPath(body_node)) {
                        try self.reportMissingReturn(node_id);
                    }
                }
            }
        }
    }

    /// Analyze return statement
    fn analyzeReturnStatement(self: *SemanticValidator, node_id: NodeId) !void {
        try self.control_flow.return_paths.append(node_id);

        // Mark subsequent statements as unreachable
        try self.markUnreachableAfter(node_id);

        // Analyze return value if present
        const return_value = self.astdb.getReturnValue(node_id);
        if (return_value) |value_node| {
            try self.analyzeControlFlow(value_node);
        }
    }

    /// Analyze if statement for control flow
    fn analyzeIfStatement(self: *SemanticValidator, node_id: NodeId) !void {
        const condition = self.astdb.getIfCondition(node_id) orelse return;
        const then_branch = self.astdb.getIfThenBranch(node_id) orelse return;
        const else_branch = self.astdb.getIfElseBranch(node_id);

        // Analyze condition
        try self.analyzeControlFlow(condition);

        // Analyze branches
        try self.analyzeControlFlow(then_branch);
        if (else_branch) |else_node| {
            try self.analyzeControlFlow(else_node);
        }
    }

    /// Analyze while loop for control flow
    fn analyzeWhileLoop(self: *SemanticValidator, node_id: NodeId) !void {
        const condition = self.astdb.getWhileCondition(node_id) orelse return;
        const body = self.astdb.getWhileBody(node_id) orelse return;

        // Analyze condition and body
        try self.analyzeControlFlow(condition);
        try self.analyzeControlFlow(body);
    }

    /// Check if node has return path
    fn hasReturnPath(self: *SemanticValidator, node_id: NodeId) bool {
        // TODO: Implement proper return path analysis
        _ = self;
        _ = node_id;
        return false; // Conservative: assume no return path
    }

    /// Mark statements after node as unreachable
    fn markUnreachableAfter(self: *SemanticValidator, node_id: NodeId) !void {
        // TODO: Implement unreachable code marking
        _ = self;
        _ = node_id;
    }

    /// Report missing return statement
    fn reportMissingReturn(self: *SemanticValidator, node_id: NodeId) !void {
        const span = self.getNodeSpan(node_id);

        const message = try std.fmt.allocPrint(self.allocator, "Function must return a value on all code paths");

        const suggestions = try self.allocator.alloc([]const u8, 1);
        suggestions[0] = try self.allocator.dupe(u8, "Add return statement or change return type to void");

        const error_item = ValidationError{
            .kind = .missing_return,
            .message = message,
            .span = span,
            .suggestions = suggestions,
            .related_info = &.{},
        };

        try self.errors.append(error_item);
        self.stats.errors_found += 1;
    }

    /// Phase 4: Validate language-specific semantic rules
    fn validateSemanticRules(self: *SemanticValidator, node_id: NodeId) !void {
        const node = self.astdb.getNode(node_id);

        switch (node.kind) {
            .assignment => try self.validateAssignmentRules(node_id),
            .binary_op => try self.validateBinaryOpRules(node_id),
            .function_call => try self.validateFunctionCallRules(node_id),
            else => {
                // Recursively validate child nodes
                const children = self.astdb.getNodeChildren(node_id);
                for (children) |child_id| {
                    try self.validateSemanticRules(child_id);
                }
            },
        }
    }

    /// Validate assignment semantic rules
    fn validateAssignmentRules(self: *SemanticValidator, node_id: NodeId) !void {
        const target = self.astdb.getAssignmentTarget(node_id) orelse return;
        const value = self.astdb.getAssignmentValue(node_id) orelse return;

        // Check if target is mutable
        if (self.astdb.getNodeSymbol(target)) |symbol_id| {
            if (self.symbol_table.getSymbol(symbol_id)) |symbol| {
                // TODO: Check mutability based on symbol metadata
                _ = symbol;
            }
        }

        // Validate value expression
        try self.validateSemanticRules(value);
    }

    /// Validate binary operation semantic rules
    fn validateBinaryOpRules(self: *SemanticValidator, node_id: NodeId) !void {
        const left = self.astdb.getBinaryOpLeft(node_id) orelse return;
        const right = self.astdb.getBinaryOpRight(node_id) orelse return;

        // Validate operands
        try self.validateSemanticRules(left);
        try self.validateSemanticRules(right);

        // TODO: Add operation-specific validation
    }

    /// Validate function call semantic rules
    fn validateFunctionCallRules(self: *SemanticValidator, node_id: NodeId) !void {
        const func_expr = self.astdb.getFunctionCallExpression(node_id) orelse return;
        const args = self.astdb.getFunctionCallArguments(node_id);

        // Validate function expression
        try self.validateSemanticRules(func_expr);

        // Validate arguments
        for (args) |arg_node| {
            try self.validateSemanticRules(arg_node);
        }

        // TODO: Add function-specific validation (purity, effects, etc.)
    }

    /// Helper methods
    fn getNodeSpan(self: *SemanticValidator, node_id: NodeId) symbol_table.SourceSpan {
        // TODO: Get actual source span from ASTDB
        _ = self;
        _ = node_id;

        return symbol_table.SourceSpan{
            .start_line = 0,
            .start_column = 0,
            .end_line = 0,
            .end_column = 0,
        };
    }

    fn resolveTypeAnnotation(self: *SemanticValidator, type_node: NodeId) !TypeId {
        // TODO: Resolve type annotation to TypeId
        _ = self;
        _ = type_node;
        return self.type_system.primitives.unknown;
    }

    /// Get collected validation errors
    pub fn getErrors(self: *SemanticValidator) []const ValidationError {
        return self.errors.items;
    }

    /// Get validation statistics
    pub fn getStatistics(self: *SemanticValidator) ValidationStats {
        return self.stats;
    }

    /// Clear errors for new validation
    pub fn clearErrors(self: *SemanticValidator) void {
        for (self.errors.items) |error_item| {
            self.allocator.free(error_item.message);
            for (error_item.suggestions) |suggestion| {
                self.allocator.free(suggestion);
            }
            self.allocator.free(error_item.suggestions);
            for (error_item.related_info) |info| {
                self.allocator.free(info.message);
            }
            self.allocator.free(error_item.related_info);
        }
        self.errors.clearRetainingCapacity();
        self.stats.errors_found = 0;
    }
};
