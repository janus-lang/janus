// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Using Statement AST Node
//! Task 1.1 - AST and semantic analysis infrastructure
//!
//! This module implements the AST representation for Janus's `using` statement,
//! which provides deterministic resource management through "honest sugar" that
//! desugars to visible defer mechanisms.

const std = @import("std");
const Allocator = std.mem.Allocator;
const astdb = @import("astdb.zig");
const NodeId = astdb.NodeId;
const CID = astdb.CID;
const Span = astdb.Span;

/// AST node for `using` statements
///
/// Syntax: `using [shared] binding [: type] = open_expr { block }`
///
/// Examples:
/// - `using file = open("data.txt") { ... }`
/// - `using shared conn: Connection = connect() { ... }`
/// - `using lock = mutex.acquire() { ... }`
pub const UsingStmt = struct {
    /// Base ASTDB node ID
    node_id: NodeId,

    /// Flags for using statement variants
    flags: UsingFlags,

    /// Variable binding for the resource
    binding: Binding,

    /// Optional explicit type annotation
    type_annotation: ?TypeAnnotation,

    /// Expression that opens/acquires the resource
    open_expr: CID,

    /// Block of code that uses the resource
    block: CID,

    /// Semantic analysis results (populated during sema)
    semantic_info: ?SemanticInfo = null,

    const UsingFlags = struct {
        /// Whether this is a `using shared` statement
        is_shared: bool = false,
        /// Whether the resource is movable out of frame
        is_movable: bool = false,
        /// Whether cleanup is infallible (cannot fail)
        is_infallible: bool = false,
    };

    const Binding = struct {
        /// Name of the bound variable
        name: []const u8,
        /// Source span of the binding
        span: Span,
        /// Whether the binding is mutable
        is_mutable: bool = false,
    };

    const TypeAnnotation = struct {
        /// CID of the type expression
        type_expr: CID,
        /// Source span of the type annotation
        span: Span,
    };

    const SemanticInfo = struct {
        /// CID of the resource type after resolution
        resource_type_cid: CID,
        /// CID of the close method for this resource
        close_method_cid: CID,
        /// Effects required for opening the resource
        open_effects: []const Effect,
        /// Effects required for closing the resource
        close_effects: []const Effect,
        /// Capabilities required for resource operations
        required_capabilities: []const Capability,
        /// Unique resource ID for tracking
        resource_id: ResourceId,
        /// Dependency information for cleanup ordering
        dependencies: []const ResourceDependency,
    };

    const Effect = struct {
        /// Name of the effect (e.g., "io.fs.read", "memory.alloc")
        name: []const u8,
        /// CID of the effect definition
        definition_cid: CID,
        /// Whether this effect is fallible
        is_fallible: bool,
    };

    const Capability = struct {
        /// Name of the capability (e.g., "CapFileRead", "CapNetworkAccess")
        name: []const u8,
        /// CID of the capability definition
        definition_cid: CID,
        /// Whether this capability can be shared
        is_shareable: bool,
    };

    const ResourceId = struct {
        /// Unique identifier for this resource instance
        id: u64,
        /// Acquisition site information for debugging
        acquisition_site: AcquisitionSite,
    };

    const AcquisitionSite = struct {
        /// Source span where resource was acquired
        span: Span,
        /// Stack trace at acquisition (for debugging)
        stack_trace: ?[]const u8 = null,
        /// Function where acquisition occurred
        function_cid: CID,
    };

    const ResourceDependency = struct {
        /// Type of dependency relationship
        dependency_type: DependencyType,
        /// CID of the resource we depend on
        dependent_resource_cid: CID,
        /// Description of the dependency
        description: []const u8,

        const DependencyType = enum {
            /// This resource must be closed before the dependent
            must_close_before,
            /// This resource must be closed after the dependent
            must_close_after,
            /// This resource shares state with the dependent
            shares_state,
            /// This resource is derived from the dependent
            derived_from,
        };
    };

    pub fn init(
        allocator: Allocator,
        span: Span,
        flags: UsingFlags,
        binding: Binding,
        type_annotation: ?TypeAnnotation,
        open_expr: CID,
        block: CID,
    ) !*UsingStmt {
        const using_stmt = try allocator.create(UsingStmt);
        using_stmt.* = UsingStmt{
            .node_id = NodeId{ .id = 0 }, // TODO: Get actual node ID from ASTDB
            .flags = flags,
            .binding = binding,
            .type_annotation = type_annotation,
            .open_expr = open_expr,
            .block = block,
        };

        return using_stmt;
    }

    pub fn deinit(self: *UsingStmt, allocator: Allocator) void {
        // ASTDB nodes are managed by the snapshot, no manual cleanup needed
        if (self.semantic_info) |info| {
            allocator.free(info.open_effects);
            allocator.free(info.close_effects);
            allocator.free(info.required_capabilities);
            allocator.free(info.dependencies);
        }
        allocator.destroy(self);
    }

    /// Check if this using statement is valid for the given profile
    pub fn isValidForProfile(self: UsingStmt, profile: Profile) bool {
        return switch (profile) {
            .min => !self.flags.is_shared, // :min doesn't support shared resources
            .go => true, // :go supports all using variants
            .elixir => true, // :elixir supports all using variants
            .full => true, // :full supports all using variants
        };
    }

    /// Get the desugared defer equivalent for this using statement
    pub fn getDesugaredDefer(self: UsingStmt, allocator: Allocator) !DeferEquivalent {
        return DeferEquivalent{
            .resource_binding = self.binding.name,
            .cleanup_call = try std.fmt.allocPrint(allocator, "{s}.close()", .{self.binding.name}),
            .cleanup_effects = if (self.semantic_info) |info| info.close_effects else &[_]Effect{},
            .error_handling = if (self.flags.is_infallible) .none else .propagate,
        };
    }

    /// Validate semantic constraints for this using statement
    pub fn validateSemantics(self: *UsingStmt, sema_ctx: *SemanticContext) !void {
        // Ensure the open expression has a close method
        const open_type = try sema_ctx.getExpressionType(self.open_expr);
        const close_method = sema_ctx.findMethod(open_type, "close") orelse {
            return sema_ctx.reportError(.missing_close_method, self.binding.span, "Resource type must have a 'close() -> void!E?' method for use in 'using' statement");
        };

        // Validate close method signature
        try self.validateCloseMethodSignature(sema_ctx, close_method);

        // Check capability requirements
        try self.validateCapabilityRequirements(sema_ctx);

        // Validate effect constraints
        try self.validateEffectConstraints(sema_ctx);

        // Check for shared resource constraints
        if (self.flags.is_shared) {
            try self.validateSharedResourceConstraints(sema_ctx);
        }
    }

    fn validateCloseMethodSignature(self: *UsingStmt, sema_ctx: *SemanticContext, close_method: CID) !void {
        const method_sig = try sema_ctx.getMethodSignature(close_method);

        // Close method must take only self parameter
        if (method_sig.parameters.len != 1) {
            return sema_ctx.reportError(.invalid_close_signature, self.binding.span, "Close method must have signature 'close(self) -> void!E?' (found {} parameters)", .{method_sig.parameters.len});
        }

        // Close method must return void or void!E
        if (!sema_ctx.isVoidOrVoidError(method_sig.return_type)) {
            return sema_ctx.reportError(.invalid_close_signature, self.binding.span, "Close method must return 'void' or 'void!E' (found {})", .{method_sig.return_type});
        }
    }

    fn validateCapabilityRequirements(self: *UsingStmt, sema_ctx: *SemanticContext) !void {
        // Check that required capabilities are available in current context
        const required_caps = try sema_ctx.getRequiredCapabilities(self.open_expr);
        const available_caps = sema_ctx.getAvailableCapabilities();

        for (required_caps) |required_cap| {
            if (!sema_ctx.hasCapability(available_caps, required_cap)) {
                return sema_ctx.reportError(.missing_capability, self.binding.span, "Using statement requires capability '{}' which is not available in current context", .{required_cap.name});
            }
        }
    }

    fn validateEffectConstraints(self: *UsingStmt, sema_ctx: *SemanticContext) !void {
        // Get effects from open and close operations
        const open_effects = try sema_ctx.getExpressionEffects(self.open_expr);
        const close_effects = try sema_ctx.getCloseEffects(self.open_expr);

        // Check if current function can handle these effects
        const current_function = sema_ctx.getCurrentFunction();
        const function_effects = try sema_ctx.getFunctionEffects(current_function);

        // Validate that all effects are declared or can be inferred
        for (open_effects) |effect| {
            if (!sema_ctx.hasEffect(function_effects, effect)) {
                return sema_ctx.reportError(.undeclared_effect, self.binding.span, "Using statement requires effect '{}' which is not declared in function signature", .{effect.name});
            }
        }

        for (close_effects) |effect| {
            if (!sema_ctx.hasEffect(function_effects, effect)) {
                return sema_ctx.reportError(.undeclared_effect, self.binding.span, "Resource cleanup requires effect '{}' which is not declared in function signature", .{effect.name});
            }
        }

        // Check for pure function violations
        if (sema_ctx.isFunctionPure(current_function) and (open_effects.len > 0 or close_effects.len > 0)) {
            return sema_ctx.reportError(.pure_function_violation, self.binding.span, "Pure functions cannot use 'using' statements with effectful resources. " ++
                "Consider removing 'pure' annotation or using effect-free resources.");
        }
    }

    fn validateSharedResourceConstraints(self: *UsingStmt, sema_ctx: *SemanticContext) !void {
        // Shared resources require additional capabilities
        const share_cap = sema_ctx.findCapability("CapShare") orelse {
            return sema_ctx.reportError(.missing_capability, self.binding.span, "'using shared' requires CapShare capability");
        };

        const close_shared_cap = sema_ctx.findCapability("CapCloseShared") orelse {
            return sema_ctx.reportError(.missing_capability, self.binding.span, "'using shared' requires CapCloseShared capability for cleanup");
        };

        // Validate that the resource type supports sharing
        const resource_type = try sema_ctx.getExpressionType(self.open_expr);
        if (!sema_ctx.isShareableType(resource_type)) {
            return sema_ctx.reportError(.non_shareable_type, self.binding.span, "Type '{}' cannot be used with 'using shared' (not shareable)", .{resource_type});
        }
    }
};

/// Profile types for using statement validation
pub const Profile = enum {
    min,
    go,
    elixir,
    full,
};

/// Desugared defer equivalent representation
pub const DeferEquivalent = struct {
    resource_binding: []const u8,
    cleanup_call: []const u8,
    cleanup_effects: []const UsingStmt.Effect,
    error_handling: ErrorHandling,

    const ErrorHandling = enum {
        none, // Infallible cleanup
        propagate, // Propagate cleanup errors
        aggregate, // Collect multiple cleanup errors
    };
};

/// Semantic analysis context (forward declaration)
pub const SemanticContext = struct {
    // This would be implemented in the semantic analyzer
    // For now, just provide the interface

    pub fn getExpressionType(self: *SemanticContext, expr_cid: CID) !CID {
        _ = self;
        _ = expr_cid;
        return error.NotImplemented;
    }

    pub fn findMethod(self: *SemanticContext, type_cid: CID, method_name: []const u8) ?CID {
        _ = self;
        _ = type_cid;
        _ = method_name;
        return null;
    }

    pub fn getMethodSignature(self: *SemanticContext, method_cid: CID) !MethodSignature {
        _ = self;
        _ = method_cid;
        return error.NotImplemented;
    }

    pub fn isVoidOrVoidError(self: *SemanticContext, type_cid: CID) bool {
        _ = self;
        _ = type_cid;
        return false;
    }

    pub fn getRequiredCapabilities(self: *SemanticContext, expr_cid: CID) ![]const UsingStmt.Capability {
        _ = self;
        _ = expr_cid;
        return &[_]UsingStmt.Capability{};
    }

    pub fn getAvailableCapabilities(self: *SemanticContext) []const UsingStmt.Capability {
        _ = self;
        return &[_]UsingStmt.Capability{};
    }

    pub fn hasCapability(self: *SemanticContext, available: []const UsingStmt.Capability, required: UsingStmt.Capability) bool {
        _ = self;
        for (available) |cap| {
            if (std.mem.eql(u8, cap.name, required.name)) {
                return true;
            }
        }
        return false;
    }

    pub fn getExpressionEffects(self: *SemanticContext, expr_cid: CID) ![]const UsingStmt.Effect {
        _ = self;
        _ = expr_cid;
        return &[_]UsingStmt.Effect{};
    }

    pub fn getCloseEffects(self: *SemanticContext, expr_cid: CID) ![]const UsingStmt.Effect {
        _ = self;
        _ = expr_cid;
        return &[_]UsingStmt.Effect{};
    }

    pub fn getCurrentFunction(self: *SemanticContext) CID {
        _ = self;
        return CID{ .bytes = [_]u8{0} ** 32 };
    }

    pub fn getFunctionEffects(self: *SemanticContext, func_cid: CID) ![]const UsingStmt.Effect {
        _ = self;
        _ = func_cid;
        return &[_]UsingStmt.Effect{};
    }

    pub fn hasEffect(self: *SemanticContext, effects: []const UsingStmt.Effect, required: UsingStmt.Effect) bool {
        _ = self;
        for (effects) |effect| {
            if (std.mem.eql(u8, effect.name, required.name)) {
                return true;
            }
        }
        return false;
    }

    pub fn isFunctionPure(self: *SemanticContext, func_cid: CID) bool {
        _ = self;
        _ = func_cid;
        return false;
    }

    pub fn findCapability(self: *SemanticContext, cap_name: []const u8) ?UsingStmt.Capability {
        _ = self;
        _ = cap_name;
        return null;
    }

    pub fn isShareableType(self: *SemanticContext, type_cid: CID) bool {
        _ = self;
        _ = type_cid;
        return false;
    }

    pub fn reportError(self: *SemanticContext, error_type: ErrorType, span: Span, comptime fmt: []const u8, args: anytype) !void {
        _ = self;
        _ = error_type;
        _ = span;
        std.log.err(fmt, args);
        return error.SemanticError;
    }

    const ErrorType = enum {
        missing_close_method,
        invalid_close_signature,
        missing_capability,
        undeclared_effect,
        pure_function_violation,
        non_shareable_type,
    };

    const MethodSignature = struct {
        parameters: []const Parameter,
        return_type: CID,

        const Parameter = struct {
            name: []const u8,
            param_type: CID,
        };
    };
};

// Tests
test "UsingStmt creation and basic properties" {
    const allocator = std.testing.allocator;

    const span = Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const flags = UsingStmt.UsingFlags{ .is_shared = false };
    const binding = UsingStmt.Binding{
        .name = "file",
        .span = span,
        .is_mutable = false,
    };
    const open_expr = CID{ .bytes = [_]u8{1} ** 32 };
    const block = CID{ .bytes = [_]u8{2} ** 32 };

    const using_stmt = try UsingStmt.init(allocator, span, flags, binding, null, open_expr, block);
    defer using_stmt.deinit(allocator);

    try std.testing.expectEqualStrings("file", using_stmt.binding.name);
    try std.testing.expect(!using_stmt.flags.is_shared);
    // ASTDB nodes don't have direct children arrays - they're managed by the snapshot
}

test "Profile validation" {
    const span = Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const binding = UsingStmt.Binding{
        .name = "resource",
        .span = span,
        .is_mutable = false,
    };

    // Regular using statement should work in all profiles
    const regular_flags = UsingStmt.UsingFlags{ .is_shared = false };
    const regular_using = UsingStmt{
        .node_id = NodeId{ .id = 1 },
        .flags = regular_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = CID{ .bytes = [_]u8{1} ** 32 },
        .block = CID{ .bytes = [_]u8{2} ** 32 },
    };

    try std.testing.expect(regular_using.isValidForProfile(.min));
    try std.testing.expect(regular_using.isValidForProfile(.go));
    try std.testing.expect(regular_using.isValidForProfile(.elixir));
    try std.testing.expect(regular_using.isValidForProfile(.full));

    // Shared using statement should not work in :min profile
    const shared_flags = UsingStmt.UsingFlags{ .is_shared = true };
    const shared_using = UsingStmt{
        .node_id = NodeId{ .id = 2 },
        .flags = shared_flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = CID{ .bytes = [_]u8{1} ** 32 },
        .block = CID{ .bytes = [_]u8{2} ** 32 },
    };

    try std.testing.expect(!shared_using.isValidForProfile(.min));
    try std.testing.expect(shared_using.isValidForProfile(.go));
    try std.testing.expect(shared_using.isValidForProfile(.elixir));
    try std.testing.expect(shared_using.isValidForProfile(.full));
}

test "Desugared defer generation" {
    const allocator = std.testing.allocator;

    const span = Span{ .start_byte = 0, .end_byte = 10, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 11 };
    const flags = UsingStmt.UsingFlags{ .is_shared = false, .is_infallible = false };
    const binding = UsingStmt.Binding{
        .name = "file",
        .span = span,
        .is_mutable = false,
    };

    const using_stmt = UsingStmt{
        .node_id = NodeId{ .id = 3 },
        .flags = flags,
        .binding = binding,
        .type_annotation = null,
        .open_expr = CID{ .bytes = [_]u8{1} ** 32 },
        .block = CID{ .bytes = [_]u8{2} ** 32 },
    };

    const defer_equiv = try using_stmt.getDesugaredDefer(allocator);
    defer allocator.free(defer_equiv.cleanup_call);

    try std.testing.expectEqualStrings("file", defer_equiv.resource_binding);
    try std.testing.expectEqualStrings("file.close()", defer_equiv.cleanup_call);
    try std.testing.expect(defer_equiv.error_handling == .propagate);
}
