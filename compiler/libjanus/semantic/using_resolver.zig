// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Using Statement Semantic Resolution
//! Task 1.1 - Semantic resolution for `open_expr`, ensure `close(self) -> void!E?`
//!
//! This module implements semantic analysis for `using` statements, ensuring
//! that resources have proper close methods and integrating with the effect
//! and capability systems.

const std = @import("std");
const Allocator = std.mem.Allocator;
const UsingStmt = @import("../ast/using_stmt.zig").UsingStmt;
const SemanticContext = @import("../ast/using_stmt.zig").SemanticContext;
const CID = @import("../astdb/ids.zig").CID;
const astdb = @import("../astdb.zig");
const NodeId = astdb.NodeId;
const Span = astdb.Span;

/// Semantic resolver for using statements
pub const UsingResolver = struct {
    allocator: Allocator,
    sema_ctx: *SemanticContext,
    resource_registry: ResourceRegistry,
    dependency_analyzer: DependencyAnalyzer,

    pub fn init(allocator: Allocator, sema_ctx: *SemanticContext) UsingResolver {
        return UsingResolver{
            .allocator = allocator,
            .sema_ctx = sema_ctx,
            .resource_registry = ResourceRegistry.init(allocator),
            .dependency_analyzer = DependencyAnalyzer.init(allocator),
        };
    }

    pub fn deinit(self: *UsingResolver) void {
        self.resource_registry.deinit();
        self.dependency_analyzer.deinit();
    }

    /// Resolve a using statement and populate semantic information
    pub fn resolveUsing(self: *UsingResolver, using_stmt: *UsingStmt) !void {
        // Step 1: Resolve the open expression type
        const resource_type = try self.resolveOpenExpression(using_stmt);

        // Step 2: Find and validate the close method
        const close_method = try self.findAndValidateCloseMethod(using_stmt, resource_type);

        // Step 3: Analyze effects for open and close operations
        const open_effects = try self.analyzeOpenEffects(using_stmt);
        const close_effects = try self.analyzeCloseEffects(using_stmt, close_method);

        // Step 4: Determine capability requirements
        const capabilities = try self.analyzeCapabilityRequirements(using_stmt, resource_type);

        // Step 5: Generate unique resource ID and track dependencies
        const resource_id = try self.generateResourceId(using_stmt);
        const dependencies = try self.analyzeDependencies(using_stmt, resource_type);

        // Step 6: Populate semantic information
        using_stmt.semantic_info = UsingStmt.SemanticInfo{
            .resource_type_cid = resource_type,
            .close_method_cid = close_method,
            .open_effects = open_effects,
            .close_effects = close_effects,
            .required_capabilities = capabilities,
            .resource_id = resource_id,
            .dependencies = dependencies,
        };

        // Step 7: Register resource for tracking
        try self.resource_registry.registerResource(resource_id, using_stmt);

        // Step 8: Validate against current context constraints
        try self.validateContextConstraints(using_stmt);
    }

    /// Resolve the type of the open expression
    fn resolveOpenExpression(self: *UsingResolver, using_stmt: *UsingStmt) !CID {
        const open_expr_type = try self.sema_ctx.getExpressionType(using_stmt.open_expr);

        // If there's an explicit type annotation, validate compatibility
        if (using_stmt.type_annotation) |type_ann| {
            const annotated_type = try self.sema_ctx.getExpressionType(type_ann.type_expr);
            if (!try self.sema_ctx.isTypeCompatible(open_expr_type, annotated_type)) {
                return self.sema_ctx.reportError(.type_mismatch, using_stmt.base.location, "Open expression type '{}' is not compatible with annotated type '{}'", .{ open_expr_type, annotated_type });
            }
            return annotated_type;
        }

        return open_expr_type;
    }

    /// Find and validate the close method for the resource type
    fn findAndValidateCloseMethod(self: *UsingResolver, using_stmt: *UsingStmt, resource_type: CID) !CID {
        // Look for close method on the resource type
        const close_method = self.sema_ctx.findMethod(resource_type, "close") orelse {
            return self.sema_ctx.reportError(.missing_close_method, using_stmt.base.location, "Resource type '{}' must have a 'close()' method for use in 'using' statement. " ++
                "Consider implementing: 'func close(self) -> void!CloseError {{ ... }}'", .{resource_type});
        };

        // Validate close method signature
        try self.validateCloseMethodSignature(using_stmt, close_method);

        return close_method;
    }

    /// Validate that the close method has the correct signature
    fn validateCloseMethodSignature(self: *UsingResolver, using_stmt: *UsingStmt, close_method: CID) !void {
        const method_sig = try self.sema_ctx.getMethodSignature(close_method);

        // Must have exactly one parameter (self)
        if (method_sig.parameters.len != 1) {
            return self.sema_ctx.reportError(.invalid_close_signature, using_stmt.base.location, "Close method must have signature 'close(self) -> void!E?' but found {} parameters. " ++
                "Expected: 'func close(self) -> void {{ ... }}' or 'func close(self) -> void!CloseError {{ ... }}'", .{method_sig.parameters.len});
        }

        // Parameter must be self
        const self_param = method_sig.parameters[0];
        if (!std.mem.eql(u8, self_param.name, "self")) {
            return self.sema_ctx.reportError(.invalid_close_signature, using_stmt.base.location, "Close method first parameter must be 'self', found '{s}'", .{self_param.name});
        }

        // Return type must be void or void!E
        if (!self.sema_ctx.isVoidOrVoidError(method_sig.return_type)) {
            return self.sema_ctx.reportError(.invalid_close_signature, using_stmt.base.location, "Close method must return 'void' or 'void!E' for error handling. " ++
                "Found return type '{}'. Consider: 'func close(self) -> void!CloseError {{ ... }}'", .{method_sig.return_type});
        }

        // If return type is void (not void!E), mark as infallible
        if (self.sema_ctx.isVoidType(method_sig.return_type)) {
            using_stmt.flags.is_infallible = true;
        }
    }

    /// Analyze effects required for opening the resource
    fn analyzeOpenEffects(self: *UsingResolver, using_stmt: *UsingStmt) ![]UsingStmt.Effect {
        const effects = try self.sema_ctx.getExpressionEffects(using_stmt.open_expr);

        // Validate that current function can handle these effects
        const current_function = self.sema_ctx.getCurrentFunction();
        const function_effects = try self.sema_ctx.getFunctionEffects(current_function);

        for (effects) |effect| {
            if (!self.sema_ctx.hasEffect(function_effects, effect)) {
                // Try to infer the effect if possible
                if (try self.canInferEffect(current_function, effect)) {
                    try self.sema_ctx.addInferredEffect(current_function, effect);
                } else {
                    return self.sema_ctx.reportError(.undeclared_effect, using_stmt.base.location, "Using statement requires effect '{}' which is not declared in function signature. " ++
                        "Add '{s}' to function effects or use 'func myFunc() -> T!{s} {{ ... }}'", .{ effect.name, effect.name, effect.name });
                }
            }
        }

        return try self.allocator.dupe(UsingStmt.Effect, effects);
    }

    /// Analyze effects required for closing the resource
    fn analyzeCloseEffects(self: *UsingResolver, using_stmt: *UsingStmt, close_method: CID) ![]UsingStmt.Effect {
        const effects = try self.sema_ctx.getMethodEffects(close_method);

        // Validate that current function can handle cleanup effects
        const current_function = self.sema_ctx.getCurrentFunction();
        const function_effects = try self.sema_ctx.getFunctionEffects(current_function);

        for (effects) |effect| {
            if (!self.sema_ctx.hasEffect(function_effects, effect)) {
                // Cleanup effects are often inferred automatically
                if (try self.canInferCleanupEffect(current_function, effect)) {
                    try self.sema_ctx.addInferredEffect(current_function, effect);
                } else {
                    return self.sema_ctx.reportError(.undeclared_effect, using_stmt.base.location, "Resource cleanup requires effect '{}' which is not declared in function signature. " ++
                        "Cleanup effects are usually inferred, but explicit declaration may be needed: " ++
                        "'func myFunc() -> T!{s} {{ ... }}'", .{ effect.name, effect.name });
                }
            }
        }

        return try self.allocator.dupe(UsingStmt.Effect, effects);
    }

    /// Analyze capability requirements for the resource
    fn analyzeCapabilityRequirements(self: *UsingResolver, using_stmt: *UsingStmt, resource_type: CID) ![]UsingStmt.Capability {
        var capabilities: std.ArrayList(UsingStmt.Capability) = .empty;

        // Get capabilities required for opening the resource
        const open_caps = try self.sema_ctx.getRequiredCapabilities(using_stmt.open_expr);
        for (open_caps) |cap| {
            try capabilities.append(cap);
        }

        // Add capabilities required for closing
        const close_caps = try self.sema_ctx.getTypeCloseCapabilities(resource_type);
        for (close_caps) |cap| {
            try capabilities.append(cap);
        }

        // Add shared resource capabilities if needed
        if (using_stmt.flags.is_shared) {
            const share_cap = self.sema_ctx.findCapability("CapShare") orelse {
                return self.sema_ctx.reportError(.missing_capability, using_stmt.base.location, "'using shared' requires CapShare capability. " ++
                    "Add 'CapShare' to function parameters or containing scope.");
            };
            try capabilities.append(share_cap);

            const close_shared_cap = self.sema_ctx.findCapability("CapCloseShared") orelse {
                return self.sema_ctx.reportError(.missing_capability, using_stmt.base.location, "'using shared' requires CapCloseShared capability for cleanup. " ++
                    "Add 'CapCloseShared' to function parameters or containing scope.");
            };
            try capabilities.append(close_shared_cap);
        }

        // Validate that all required capabilities are available
        const available_caps = self.sema_ctx.getAvailableCapabilities();
        for (capabilities.items) |required_cap| {
            if (!self.sema_ctx.hasCapability(available_caps, required_cap)) {
                return self.sema_ctx.reportError(.missing_capability, using_stmt.base.location, "Using statement requires capability '{}' which is not available. " ++
                    "Add '{}' to function parameters: 'func myFunc(cap: {s}) {{ ... }}'", .{ required_cap.name, required_cap.name, required_cap.name });
            }
        }

        return try capabilities.toOwnedSlice(alloc);
    }

    /// Generate a unique resource ID for tracking
    fn generateResourceId(self: *UsingResolver, using_stmt: *UsingStmt) !UsingStmt.ResourceId {
        const id = self.resource_registry.getNextResourceId();

        return UsingStmt.ResourceId{
            .id = id,
            .acquisition_site = UsingStmt.AcquisitionSite{
                .location = using_stmt.base.location,
                .stack_trace = try self.captureStackTrace(),
                .function_cid = self.sema_ctx.getCurrentFunction(),
            },
        };
    }

    /// Analyze dependencies between resources for cleanup ordering
    fn analyzeDependencies(self: *UsingResolver, using_stmt: *UsingStmt, resource_type: CID) ![]UsingStmt.ResourceDependency {
        return self.dependency_analyzer.analyzeDependencies(using_stmt, resource_type);
    }

    /// Validate constraints in the current context
    fn validateContextConstraints(self: *UsingResolver, using_stmt: *UsingStmt) !void {
        // Check profile constraints
        const current_profile = self.sema_ctx.getCurrentProfile();
        if (!using_stmt.isValidForProfile(current_profile)) {
            return self.sema_ctx.reportError(.profile_constraint_violation, using_stmt.base.location, "'using shared' is not supported in profile '{}'. " ++
                "Use regular 'using' statement or switch to :go, :elixir, or :full profile.", .{current_profile});
        }

        // Check pure function constraints
        const current_function = self.sema_ctx.getCurrentFunction();
        if (self.sema_ctx.isFunctionPure(current_function)) {
            return self.sema_ctx.reportError(.pure_function_violation, using_stmt.base.location, "Pure functions cannot use 'using' statements with effectful resources. " ++
                "Remove 'pure' annotation or use effect-free resources. " ++
                "Pure functions guarantee no side effects, but resource management requires effects.");
        }

        // Check loop context constraints
        if (self.sema_ctx.isInLoop()) {
            try self.validateLoopConstraints(using_stmt);
        }

        // Check actor context constraints
        if (self.sema_ctx.isInActor()) {
            try self.validateActorConstraints(using_stmt);
        }
    }

    /// Validate constraints specific to loop contexts
    fn validateLoopConstraints(self: *UsingResolver, using_stmt: *UsingStmt) !void {
        // Check if resource is movable out of frame
        if (using_stmt.flags.is_movable) {
            return self.sema_ctx.reportError(.movable_in_loop, using_stmt.base.location, "Resources marked as movable cannot be used in loops. " ++
                "Each loop iteration must have independent resource lifetimes. " ++
                "Consider moving 'using' statement outside the loop or removing @movable_out_of_frame.");
        }

        // Warn about potential performance issues
        if (self.sema_ctx.isHighFrequencyLoop()) {
            self.sema_ctx.reportWarning(.performance_warning, using_stmt.base.location, "Using statement in high-frequency loop may impact performance. " ++
                "Consider resource pooling or moving resource acquisition outside the loop.");
        }
    }

    /// Validate constraints specific to actor contexts
    fn validateActorConstraints(self: *UsingResolver, using_stmt: *UsingStmt) !void {
        // Shared resources in actors require special handling
        if (using_stmt.flags.is_shared) {
            const supervisor_cap = self.sema_ctx.findCapability("CapSupervisor");
            if (supervisor_cap == null) {
                return self.sema_ctx.reportError(.missing_capability, using_stmt.base.location, "'using shared' in actor context requires CapSupervisor for orphan cleanup. " ++
                    "Add CapSupervisor capability or use regular 'using' statement.");
            }
        }

        // Check for resource sharing across actor boundaries
        if (try self.crossesActorBoundary(using_stmt)) {
            return self.sema_ctx.reportError(.actor_boundary_violation, using_stmt.base.location, "Resources cannot be shared across actor boundaries without explicit capability transfer. " ++
                "Use message passing or explicit capability delegation.");
        }
    }

    /// Helper functions
    fn canInferEffect(self: *UsingResolver, function_cid: CID, effect: UsingStmt.Effect) !bool {
        _ = self;
        _ = function_cid;
        _ = effect;
        // Implementation would check if effect can be safely inferred
        return true;
    }

    fn canInferCleanupEffect(self: *UsingResolver, function_cid: CID, effect: UsingStmt.Effect) !bool {
        _ = self;
        _ = function_cid;
        _ = effect;
        // Cleanup effects are usually more permissive for inference
        return true;
    }

    fn captureStackTrace(self: *UsingResolver) !?[]const u8 {
        _ = self;
        // Implementation would capture stack trace for debugging
        return null;
    }

    fn crossesActorBoundary(self: *UsingResolver, using_stmt: *UsingStmt) !bool {
        _ = self;
        _ = using_stmt;
        // Implementation would analyze if resource crosses actor boundaries
        return false;
    }
};

/// Registry for tracking active resources
const ResourceRegistry = struct {
    allocator: Allocator,
    active_resources: std.HashMap(u64, *UsingStmt, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage),
    next_resource_id: u64,

    pub fn init(allocator: Allocator) ResourceRegistry {
        return ResourceRegistry{
            .allocator = allocator,
            .active_resources = std.HashMap(u64, *UsingStmt, std.hash_map.DefaultContext(u64), std.hash_map.default_max_load_percentage).init(allocator),
            .next_resource_id = 1,
        };
    }

    pub fn deinit(self: *ResourceRegistry) void {
        self.active_resources.deinit();
    }

    pub fn getNextResourceId(self: *ResourceRegistry) u64 {
        const id = self.next_resource_id;
        self.next_resource_id += 1;
        return id;
    }

    pub fn registerResource(self: *ResourceRegistry, resource_id: UsingStmt.ResourceId, using_stmt: *UsingStmt) !void {
        try self.active_resources.put(resource_id.id, using_stmt);
    }

    pub fn unregisterResource(self: *ResourceRegistry, resource_id: u64) void {
        _ = self.active_resources.remove(resource_id);
    }

    pub fn getActiveResources(self: *ResourceRegistry) []const *UsingStmt {
        var resources: std.ArrayList(*UsingStmt) = .empty;
        defer resources.deinit();

        var iterator = self.active_resources.valueIterator();
        while (iterator.next()) |using_stmt| {
            resources.append(using_stmt.*) catch {};
        }

        return try resources.toOwnedSlice(alloc) catch &[_]*UsingStmt{};
    }
};

/// Analyzer for resource dependencies
const DependencyAnalyzer = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DependencyAnalyzer) void {
        _ = self;
    }

    pub fn analyzeDependencies(self: *DependencyAnalyzer, using_stmt: *UsingStmt, resource_type: CID) ![]UsingStmt.ResourceDependency {
        _ = self;
        _ = using_stmt;
        _ = resource_type;

        // Implementation would analyze:
        // 1. Data dependencies (resource A uses data from resource B)
        // 2. Ordering dependencies (resource A must close before B)
        // 3. Shared state dependencies (resources share mutable state)
        // 4. Capability dependencies (resource A requires caps from B)

        return &[_]UsingStmt.ResourceDependency{};
    }
};

// Tests
test "UsingResolver basic functionality" {
    const allocator = std.testing.allocator;

    // This would require a full semantic context setup
    // For now, just test the structure
    var sema_ctx = SemanticContext{};
    var resolver = UsingResolver.init(allocator, &sema_ctx);
    defer resolver.deinit();

    try std.testing.expect(resolver.resource_registry.next_resource_id == 1);
}

test "ResourceRegistry operations" {
    const allocator = std.testing.allocator;

    var registry = ResourceRegistry.init(allocator);
    defer registry.deinit();

    const id1 = registry.getNextResourceId();
    const id2 = registry.getNextResourceId();

    try std.testing.expect(id1 == 1);
    try std.testing.expect(id2 == 2);
    try std.testing.expect(registry.next_resource_id == 3);
}
