// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const HashMap = std.HashMap;
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = TypeRegistry.TypeId;
const SignatureAnalyzer = @import("signature_analyzer.zig").SignatureAnalyzer;
const SpecificityAnalyzer = @import("specificity_analyzer.zig").SpecificityAnalyzer;

/// Ownership state of a value
pub const OwnershipState = enum {
    owned, // Value is owned and can be moved
    borrowed, // Value is borrowed (immutable reference)
    mut_borrowed, // Value is mutably borrowed
    moved, // Value has been moved and is no longer accessible

    pub fn canMove(self: OwnershipState) bool {
        return self == .owned;
    }

    pub fn canBorrow(self: OwnershipState) bool {
        return switch (self) {
            .owned, .borrowed => true,
            .mut_borrowed, .moved => false,
        };
    }

    pub fn canMutBorrow(self: OwnershipState) bool {
        return self == .owned;
    }
};

/// Move semantics information for a type
pub const MoveSemantics = struct {
    type_id: TypeId,
    is_unique: bool,
    is_copyable: bool,
    is_movable: bool,
    destructor_required: bool,

    pub fn format(self: MoveSemantics, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("MoveSemantics({})", .{self.type_id});
        if (self.is_unique) try writer.print(" unique", .{});
        if (self.is_copyable) try writer.print(" copyable", .{});
        if (self.is_movable) try writer.print(" movable", .{});
        if (self.destructor_required) try writer.print(" +dtor", .{});
    }
};

/// Ownership tracking for function parameters
pub const ParameterOwnership = struct {
    parameter_index: u32,
    ownership_mode: OwnershipMode,
    lifetime_constraint: ?[]const u8,

    pub const OwnershipMode = enum {
        take_ownership, // fn(x: unique T) - takes ownership
        borrow_immutable, // fn(x: &T) - borrows immutably
        borrow_mutable, // fn(x: &mut T) - borrows mutably
        copy_value, // fn(x: T) - copies the value
    };

    pub fn format(self: ParameterOwnership, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("param[{}]: {}", .{ self.parameter_index, self.ownership_mode });
        if (self.lifetime_constraint) |lifetime| {
            try writer.print(" '{s}", .{lifetime});
        }
    }
};

/// Capability requirement for dispatch
pub const CapabilityRequirement = struct {
    capability_name: []const u8,
    is_required: bool,
    parameter_index: ?u32, // Which parameter provides this capability

    pub fn format(self: CapabilityRequirement, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        if (!self.is_required) try writer.print("?", .{});
        try writer.print("{s}", .{self.capability_name});
        if (self.parameter_index) |idx| {
            try writer.print("@{}", .{idx});
        }
    }
};

/// Ownership-aware implementation metadata
pub const UniqueImplementation = struct {
    base_implementation: *const SignatureAnalyzer.Implementation,
    parameter_ownership: []const ParameterOwnership,
    capability_requirements: []const CapabilityRequirement,
    move_semantics: []const MoveSemantics,
    ownership_transfer_map: []const OwnershipTransfer,

    pub const OwnershipTransfer = struct {
        from_parameter: u32,
        to_parameter: ?u32, // null means return value
        transfer_type: TransferType,

        pub const TransferType = enum {
            move_ownership,
            transfer_borrow,
            extend_lifetime,
        };
    };

    pub fn format(self: UniqueImplementation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("UniqueImpl({})", .{self.base_implementation.function_id.name});
        if (self.parameter_ownership.len > 0) {
            try writer.print(" [", .{});
            for (self.parameter_ownership, 0..) |param, i| {
                if (i > 0) try writer.print(", ", .{});
                try writer.print("{}", .{param});
            }
            try writer.print("]", .{});
        }
    }
};

/// Ownership violation detected during dispatch
pub const OwnershipViolation = struct {
    violation_type: ViolationType,
    parameter_index: u32,
    expected_ownership: ParameterOwnership.OwnershipMode,
    actual_ownership: OwnershipState,
    description: []const u8,

    pub const ViolationType = enum {
        use_after_move,
        double_move,
        borrow_after_move,
        mut_borrow_conflict,
        capability_missing,
        lifetime_violation,
    };

    pub fn format(self: OwnershipViolation, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("{} at param[{}]: {s}", .{ self.violation_type, self.parameter_index, self.description });
    }
};

/// Result of ownership-aware dispatch resolution
pub const UniqueDispatchResult = struct {
    result_type: ResultType,
    selected_implementation: ?UniqueImplementation,
    ownership_violations: []const OwnershipViolation,
    required_moves: []const u32, // Parameter indices that must be moved
    capability_grants: []const CapabilityGrant,

    pub const ResultType = enum {
        success,
        ownership_violation,
        capability_missing,
        no_match,
        ambiguous,
    };

    pub const CapabilityGrant = struct {
        capability_name: []const u8,
        granted_by_parameter: u32,
        required_by_implementation: bool,
    };

    pub fn format(self: UniqueDispatchResult, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("UniqueDispatch: {}", .{self.result_type});
        if (self.selected_implementation) |impl| {
            try writer.print(" -> {}", .{impl});
        }
        if (self.ownership_violations.len > 0) {
            try writer.print(" ({} violations)", .{self.ownership_violations.len});
        }
    }
};
/// Unique type and move semantics dispatch system
pub const UniqueDispatcher = struct {
    allocator: Allocator,
    type_registry: *const TypeRegistry,
    signature_analyzer: *const SignatureAnalyzer,
    specificity_analyzer: *SpecificityAnalyzer,

    // Unique type tracking
    unique_implementations: std.AutoHashMap(u32, UniqueImplementation),
    move_semantics_cache: std.AutoHashMap(TypeId, MoveSemantics),
    ownership_states: std.AutoHashMap(u64, OwnershipState), // Variable ID -> State

    // Capability tracking
    available_capabilities: std.StringHashMap(bool),
    capability_providers: std.StringHashMap(ArrayList(u32)), // Capability -> Parameter indices

    const Self = @This();

    pub fn init(
        allocator: Allocator,
        type_registry: *const TypeRegistry,
        signature_analyzer: *const SignatureAnalyzer,
        specificity_analyzer: *SpecificityAnalyzer,
    ) Self {
        return Self{
            .allocator = allocator,
            .type_registry = type_registry,
            .signature_analyzer = signature_analyzer,
            .specificity_analyzer = specificity_analyzer,
            .unique_implementations = std.AutoHashMap(u32, UniqueImplementation).init(allocator),
            .move_semantics_cache = std.AutoHashMap(TypeId, MoveSemantics).init(allocator),
            .ownership_states = std.AutoHashMap(u64, OwnershipState).init(allocator),
            .available_capabilities = std.StringHashMap(bool).init(allocator),
            .capability_providers = std.StringHashMap(ArrayList(u32)).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        // Clean up unique implementations
        var impl_iter = self.unique_implementations.iterator();
        while (impl_iter.next()) |entry| {
            self.freeUniqueImplementation(entry.value_ptr);
        }
        self.unique_implementations.deinit();

        self.move_semantics_cache.deinit();
        self.ownership_states.deinit();
        self.available_capabilities.deinit();

        // Clean up capability providers
        var cap_iter = self.capability_providers.iterator();
        while (cap_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.capability_providers.deinit();
    }

    /// Register a unique implementation with ownership semantics
    pub fn registerUniqueImplementation(
        self: *Self,
        base_implementation: *const SignatureAnalyzer.Implementation,
        parameter_ownership: []const ParameterOwnership,
        capability_requirements: []const CapabilityRequirement,
    ) !void {
        // Generate move semantics for parameter types
        var move_semantics: ArrayList(MoveSemantics) = .empty;
        defer move_semantics.deinit();

        for (base_implementation.param_type_ids) |type_id| {
            const semantics = try self.getMoveSemantics(type_id);
            try move_semantics.append(semantics);
        }

        const unique_impl = UniqueImplementation{
            .base_implementation = base_implementation,
            .parameter_ownership = try self.allocator.dupe(ParameterOwnership, parameter_ownership),
            .capability_requirements = try self.allocator.dupe(CapabilityRequirement, capability_requirements),
            .move_semantics = try self.allocator.dupe(MoveSemantics, move_semantics.items),
            .ownership_transfer_map = &.{}, // Simplified for now
        };

        // Use function ID as key (simplified)
        const key: u32 = @intCast(base_implementation.function_id.name.len);
        try self.unique_implementations.put(key, unique_impl);
    }

    /// Resolve dispatch with ownership and move semantics checking
    pub fn resolveUniqueDispatch(
        self: *Self,
        argument_types: []const TypeId,
        argument_ownership_states: []const OwnershipState,
        available_capabilities: []const []const u8,
    ) !UniqueDispatchResult {
        // Update available capabilities
        try self.updateAvailableCapabilities(available_capabilities);

        // Find candidate implementations
        var candidates: ArrayList(UniqueImplementation) = .empty;
        defer candidates.deinit();

        var impl_iter = self.unique_implementations.iterator();
        while (impl_iter.next()) |entry| {
            const impl = entry.value_ptr.*;
            if (self.implementationMatches(&impl, argument_types)) {
                try candidates.append(impl);
            }
        }

        if (candidates.items.len == 0) {
            return UniqueDispatchResult{
                .result_type = .no_match,
                .selected_implementation = null,
                .ownership_violations = try self.allocator.alloc(OwnershipViolation, 0),
                .required_moves = try self.allocator.alloc(u32, 0),
                .capability_grants = try self.allocator.alloc(UniqueDispatchResult.CapabilityGrant, 0),
            };
        }

        // Check ownership constraints for each candidate
        var valid_candidates: ArrayList(UniqueImplementation) = .empty;
        defer valid_candidates.deinit();

        var all_violations: ArrayList(OwnershipViolation) = .empty;
        defer all_violations.deinit();

        for (candidates.items) |candidate| {
            const violations = try self.checkOwnershipConstraints(&candidate, argument_ownership_states);
            if (violations.len == 0) {
                try valid_candidates.append(candidate);
            } else {
                try all_violations.appendSlice(violations);
                self.allocator.free(violations);
            }
        }

        if (valid_candidates.items.len == 0) {
            return UniqueDispatchResult{
                .result_type = .ownership_violation,
                .selected_implementation = null,
                .ownership_violations = try self.allocator.dupe(OwnershipViolation, all_violations.items),
                .required_moves = try self.allocator.alloc(u32, 0),
                .capability_grants = try self.allocator.alloc(UniqueDispatchResult.CapabilityGrant, 0),
            };
        }

        // Select best candidate using specificity analysis
        const best_candidate = try self.selectBestUniqueCandidate(valid_candidates.items, argument_types);

        if (best_candidate == null) {
            return UniqueDispatchResult{
                .result_type = .ambiguous,
                .selected_implementation = null,
                .ownership_violations = try self.allocator.alloc(OwnershipViolation, 0),
                .required_moves = try self.allocator.alloc(u32, 0),
                .capability_grants = try self.allocator.alloc(UniqueDispatchResult.CapabilityGrant, 0),
            };
        }

        // Calculate required moves and capability grants
        const required_moves = try self.calculateRequiredMoves(&best_candidate.?, argument_ownership_states);
        const capability_grants = try self.calculateCapabilityGrants(&best_candidate.?, available_capabilities);

        return UniqueDispatchResult{
            .result_type = .success,
            .selected_implementation = best_candidate,
            .ownership_violations = try self.allocator.alloc(OwnershipViolation, 0),
            .required_moves = required_moves,
            .capability_grants = capability_grants,
        };
    }

    /// Get or compute move semantics for a type
    pub fn getMoveSemantics(self: *Self, type_id: TypeId) !MoveSemantics {
        if (self.move_semantics_cache.get(type_id)) |cached| {
            return cached;
        }

        const type_info = self.type_registry.getTypeInfo(type_id) orelse {
            return MoveSemantics{
                .type_id = type_id,
                .is_unique = false,
                .is_copyable = true,
                .is_movable = true,
                .destructor_required = false,
            };
        };

        const semantics = MoveSemantics{
            .type_id = type_id,
            .is_unique = type_info.kind == .unique,
            .is_copyable = type_info.kind != .unique,
            .is_movable = true,
            .destructor_required = type_info.kind == .unique or type_info.kind == .table_sealed,
        };

        try self.move_semantics_cache.put(type_id, semantics);
        return semantics;
    }

    /// Update ownership state for a variable
    pub fn updateOwnershipState(self: *Self, variable_id: u64, new_state: OwnershipState) !void {
        try self.ownership_states.put(variable_id, new_state);
    }

    /// Get ownership state for a variable
    pub fn getOwnershipState(self: *Self, variable_id: u64) OwnershipState {
        return self.ownership_states.get(variable_id) orelse .owned;
    }

    /// Check if a move is valid
    pub fn canMove(self: *Self, variable_id: u64, type_id: TypeId) !bool {
        const ownership_state = self.getOwnershipState(variable_id);
        const move_semantics = try self.getMoveSemantics(type_id);

        return ownership_state.canMove() and move_semantics.is_movable;
    }

    /// Perform a move operation
    pub fn performMove(self: *Self, variable_id: u64) !void {
        const current_state = self.getOwnershipState(variable_id);
        if (!current_state.canMove()) {
            return error.InvalidMove;
        }

        try self.updateOwnershipState(variable_id, .moved);
    }

    /// Grant a capability
    pub fn grantCapability(self: *Self, capability_name: []const u8) !void {
        try self.available_capabilities.put(capability_name, true);
    }

    /// Revoke a capability
    pub fn revokeCapability(self: *Self, capability_name: []const u8) void {
        _ = self.available_capabilities.remove(capability_name);
    }

    /// Check if a capability is available
    pub fn hasCapability(self: *Self, capability_name: []const u8) bool {
        return self.available_capabilities.get(capability_name) orelse false;
    }

    /// Update available capabilities from argument list
    fn updateAvailableCapabilities(self: *Self, capabilities: []const []const u8) !void {
        self.available_capabilities.clearRetainingCapacity();
        for (capabilities) |cap| {
            try self.available_capabilities.put(cap, true);
        }
    }

    /// Check if implementation matches argument types
    fn implementationMatches(self: *Self, impl: *const UniqueImplementation, argument_types: []const TypeId) bool {
        if (impl.base_implementation.param_type_ids.len != argument_types.len) {
            return false;
        }

        for (impl.base_implementation.param_type_ids, argument_types) |param_type, arg_type| {
            if (!self.type_registry.isSubtype(arg_type, param_type)) {
                return false;
            }
        }

        return true;
    }

    /// Check ownership constraints for an implementation
    fn checkOwnershipConstraints(
        self: *Self,
        impl: *const UniqueImplementation,
        argument_ownership_states: []const OwnershipState,
    ) ![]OwnershipViolation {
        var violations: ArrayList(OwnershipViolation) = .empty;

        for (impl.parameter_ownership, 0..) |param_ownership, i| {
            if (i >= argument_ownership_states.len) continue;

            const arg_state = argument_ownership_states[i];
            const violation = self.checkSingleOwnershipConstraint(param_ownership, arg_state, @as(u32, @intCast(i)));

            if (violation) |v| {
                try violations.append(v);
            }
        }

        // Check capability requirements
        for (impl.capability_requirements) |cap_req| {
            if (cap_req.is_required and !self.hasCapability(cap_req.capability_name)) {
                try violations.append(OwnershipViolation{
                    .violation_type = .capability_missing,
                    .parameter_index = cap_req.parameter_index orelse 0,
                    .expected_ownership = .take_ownership,
                    .actual_ownership = .owned,
                    .description = try std.fmt.allocPrint(self.allocator, "Required capability '{s}' not available", .{cap_req.capability_name}),
                });
            }
        }

        return try violations.toOwnedSlice(alloc);
    }

    /// Check a single ownership constraint
    fn checkSingleOwnershipConstraint(
        self: *Self,
        param_ownership: ParameterOwnership,
        arg_state: OwnershipState,
        param_index: u32,
    ) ?OwnershipViolation {
        _ = self;

        switch (param_ownership.ownership_mode) {
            .take_ownership => {
                if (!arg_state.canMove()) {
                    return OwnershipViolation{
                        .violation_type = if (arg_state == .moved) .use_after_move else .double_move,
                        .parameter_index = param_index,
                        .expected_ownership = .take_ownership,
                        .actual_ownership = arg_state,
                        .description = "Cannot take ownership of non-owned value",
                    };
                }
            },
            .borrow_immutable => {
                if (!arg_state.canBorrow()) {
                    return OwnershipViolation{
                        .violation_type = .borrow_after_move,
                        .parameter_index = param_index,
                        .expected_ownership = .borrow_immutable,
                        .actual_ownership = arg_state,
                        .description = "Cannot borrow moved value",
                    };
                }
            },
            .borrow_mutable => {
                if (!arg_state.canMutBorrow()) {
                    return OwnershipViolation{
                        .violation_type = .mut_borrow_conflict,
                        .parameter_index = param_index,
                        .expected_ownership = .borrow_mutable,
                        .actual_ownership = arg_state,
                        .description = "Cannot mutably borrow non-owned or already borrowed value",
                    };
                }
            },
            .copy_value => {
                // Copy is always allowed if the type is copyable
                // This would need to check the type's copy semantics
            },
        }

        return null;
    }

    /// Select the best unique candidate using specificity analysis
    fn selectBestUniqueCandidate(
        self: *Self,
        candidates: []const UniqueImplementation,
        argument_types: []const TypeId,
    ) !?UniqueImplementation {
        if (candidates.len == 0) return null;
        if (candidates.len == 1) return candidates[0];

        // Convert to base implementations for specificity analysis
        var base_impls: ArrayList(SignatureAnalyzer.Implementation) = .empty;
        defer base_impls.deinit();

        for (candidates) |candidate| {
            try base_impls.append(candidate.base_implementation.*);
        }

        var result = try self.specificity_analyzer.findMostSpecific(base_impls.items, argument_types);
        defer result.deinit(self.allocator);

        switch (result) {
            .unique => |impl| {
                // Find the corresponding unique implementation
                for (candidates) |candidate| {
                    if (std.mem.eql(u8, candidate.base_implementation.function_id.name, impl.function_id.name)) {
                        return candidate;
                    }
                }
            },
            .ambiguous => return null,
            .no_match => return null,
        }

        return null;
    }

    /// Calculate required moves for an implementation
    fn calculateRequiredMoves(
        self: *Self,
        impl: *const UniqueImplementation,
        argument_ownership_states: []const OwnershipState,
    ) ![]u32 {
        var required_moves: ArrayList(u32) = .empty;

        for (impl.parameter_ownership, 0..) |param_ownership, i| {
            if (param_ownership.ownership_mode == .take_ownership and
                i < argument_ownership_states.len and
                argument_ownership_states[i].canMove())
            {
                try required_moves.append(@as(u32, @intCast(i)));
            }
        }

        return try required_moves.toOwnedSlice(alloc);
    }

    /// Calculate capability grants for an implementation
    fn calculateCapabilityGrants(
        self: *Self,
        impl: *const UniqueImplementation,
        available_capabilities: []const []const u8,
    ) ![]UniqueDispatchResult.CapabilityGrant {
        _ = impl;
        var grants: ArrayList(UniqueDispatchResult.CapabilityGrant) = .empty;

        for (available_capabilities, 0..) |cap, i| {
            try grants.append(UniqueDispatchResult.CapabilityGrant{
                .capability_name = cap,
                .granted_by_parameter = @as(u32, @intCast(i)),
                .required_by_implementation = self.hasCapability(cap),
            });
        }

        return try grants.toOwnedSlice(alloc);
    }

    /// Free unique implementation memory
    fn freeUniqueImplementation(self: *Self, impl: *UniqueImplementation) void {
        self.allocator.free(impl.parameter_ownership);
        self.allocator.free(impl.capability_requirements);
        self.allocator.free(impl.move_semantics);
        self.allocator.free(impl.ownership_transfer_map);
    }
};
// Tests
test "UniqueDispatcher basic ownership tracking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = UniqueDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const unique_type = try type_registry.registerType("UniqueResource", .unique, &.{});

    // Test move semantics
    const semantics = try dispatcher.getMoveSemantics(unique_type);
    try testing.expect(semantics.is_unique);
    try testing.expect(!semantics.is_copyable);
    try testing.expect(semantics.is_movable);
    try testing.expect(semantics.destructor_required);

    // Test ownership state tracking
    const var_id: u64 = 123;
    try testing.expectEqual(OwnershipState.owned, dispatcher.getOwnershipState(var_id));

    try dispatcher.updateOwnershipState(var_id, .moved);
    try testing.expectEqual(OwnershipState.moved, dispatcher.getOwnershipState(var_id));

    // Test move validation
    try testing.expect(!try dispatcher.canMove(var_id, unique_type));
}

test "UniqueDispatcher capability management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = UniqueDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    // Test capability granting and checking
    try testing.expect(!dispatcher.hasCapability("file_read"));

    try dispatcher.grantCapability("file_read");
    try testing.expect(dispatcher.hasCapability("file_read"));

    dispatcher.revokeCapability("file_read");
    try testing.expect(!dispatcher.hasCapability("file_read"));
}

test "UniqueDispatcher ownership constraint checking" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = UniqueDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const unique_type = try type_registry.registerType("UniqueResource", .unique, &.{});

    // Create a mock implementation
    const base_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "consume", .module = "test", .id = 1 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{unique_type}),
        .return_type_id = unique_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(base_impl.param_type_ids);

    const param_ownership = [_]ParameterOwnership{
        ParameterOwnership{
            .parameter_index = 0,
            .ownership_mode = .take_ownership,
            .lifetime_constraint = null,
        },
    };

    try dispatcher.registerUniqueImplementation(&base_impl, &param_ownership, &.{});

    // Test dispatch with valid ownership
    const arg_types = [_]TypeId{unique_type};
    const arg_states = [_]OwnershipState{.owned};
    const capabilities: []const []const u8 = &.{};

    const result = try dispatcher.resolveUniqueDispatch(&arg_types, &arg_states, capabilities);
    defer {
        allocator.free(result.ownership_violations);
        allocator.free(result.required_moves);
        allocator.free(result.capability_grants);
    }

    try testing.expectEqual(UniqueDispatchResult.ResultType.success, result.result_type);
    try testing.expect(result.selected_implementation != null);
    try testing.expectEqual(@as(usize, 1), result.required_moves.len);
    try testing.expectEqual(@as(u32, 0), result.required_moves[0]);
}

test "UniqueDispatcher ownership violations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = UniqueDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const unique_type = try type_registry.registerType("UniqueResource", .unique, &.{});

    // Create a mock implementation that takes ownership
    const base_impl = SignatureAnalyzer.Implementation{
        .function_id = SignatureAnalyzer.FunctionId{ .name = "consume", .module = "test", .id = 1 },
        .param_type_ids = try allocator.dupe(TypeId, &[_]TypeId{unique_type}),
        .return_type_id = unique_type,
        .effects = SignatureAnalyzer.EffectSet.init(SignatureAnalyzer.EffectSet.PURE),
        .source_location = SignatureAnalyzer.SourceSpan.dummy(),
        .specificity_rank = 100,
    };
    defer allocator.free(base_impl.param_type_ids);

    const param_ownership = [_]ParameterOwnership{
        ParameterOwnership{
            .parameter_index = 0,
            .ownership_mode = .take_ownership,
            .lifetime_constraint = null,
        },
    };

    try dispatcher.registerUniqueImplementation(&base_impl, &param_ownership, &.{});

    // Test dispatch with moved value (should fail)
    const arg_types = [_]TypeId{unique_type};
    const arg_states = [_]OwnershipState{.moved}; // Already moved!
    const capabilities: []const []const u8 = &.{};

    const result = try dispatcher.resolveUniqueDispatch(&arg_types, &arg_states, capabilities);
    defer {
        allocator.free(result.ownership_violations);
        allocator.free(result.required_moves);
        allocator.free(result.capability_grants);
    }

    try testing.expectEqual(UniqueDispatchResult.ResultType.ownership_violation, result.result_type);
    try testing.expect(result.ownership_violations.len > 0);
    try testing.expectEqual(OwnershipViolation.ViolationType.use_after_move, result.ownership_violations[0].violation_type);
}

test "UniqueDispatcher move operation" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var type_registry = try TypeRegistry.init(allocator);
    defer type_registry.deinit();

    var signature_analyzer = SignatureAnalyzer.init(allocator, &type_registry);
    defer signature_analyzer.deinit();

    var specificity_analyzer = SpecificityAnalyzer.init(allocator, &type_registry);

    var dispatcher = UniqueDispatcher.init(allocator, &type_registry, &signature_analyzer, &specificity_analyzer);
    defer dispatcher.deinit();

    const unique_type = try type_registry.registerType("UniqueResource", .unique, &.{});
    const var_id: u64 = 456;

    // Initially owned, can move
    try testing.expect(try dispatcher.canMove(var_id, unique_type));

    // Perform move
    try dispatcher.performMove(var_id);

    // After move, cannot move again
    try testing.expect(!try dispatcher.canMove(var_id, unique_type));

    // Trying to move again should fail
    try testing.expectError(error.InvalidMove, dispatcher.performMove(var_id));
}

test "UniqueDispatcher formatting" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test MoveSemantics formatting
    const semantics = MoveSemantics{
        .type_id = 1,
        .is_unique = true,
        .is_copyable = false,
        .is_movable = true,
        .destructor_required = true,
    };

    var buffer: std.ArrayList(u8) = .empty;
    defer buffer.deinit();

    try std.fmt.format(buffer.writer(), "{}", .{semantics});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "unique") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "movable") != null);

    // Test ParameterOwnership formatting
    buffer.clearRetainingCapacity();
    const param_ownership = ParameterOwnership{
        .parameter_index = 0,
        .ownership_mode = .take_ownership,
        .lifetime_constraint = "static",
    };

    try std.fmt.format(buffer.writer(), "{}", .{param_ownership});
    try testing.expect(buffer.items.len > 0);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "param[0]") != null);
    try testing.expect(std.mem.indexOf(u8, buffer.items, "static") != null);
}
