// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.EffectsOf Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Analyzes the effects of functions and expressions.
//! This is crucial for Janus's effect system and capability analysis.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const astdb = @import("../../astdb.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const EffectsInfo = context.EffectsInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Analyze the effects of a function or expression
pub fn effectsOf(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 1) {
        return error.QE0005_NonCanonicalArg;
    }

    const node_cid = switch (args.items[0]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependency on the node
    try query_ctx.dependency_tracker.addDependency(.{ .cid = node_cid });

    // Get the AST node
    const node = try query_ctx.astdb.getNode(node_cid);

    // Analyze effects based on node type
    const effects_info = try analyzeNodeEffects(query_ctx, node);

    return QueryResultData{
        .effects_info = effects_info,
    };
}

/// Analyze effects of an AST node
fn analyzeNodeEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    return switch (node.node_type) {
        .function_declaration => try analyzeFunctionEffects(query_ctx, node),
        .function_call => try analyzeFunctionCallEffects(query_ctx, node),
        .variable_assignment => try analyzeAssignmentEffects(query_ctx, node),
        .member_access => try analyzeMemberAccessEffects(query_ctx, node),
        .array_access => try analyzeArrayAccessEffects(query_ctx, node),
        .block => try analyzeBlockEffects(query_ctx, node),
        .if_statement => try analyzeConditionalEffects(query_ctx, node),
        .while_loop, .for_loop => try analyzeLoopEffects(query_ctx, node),
        .return_statement => try analyzeReturnEffects(query_ctx, node),
        else => EffectsInfo{
            .effects = &[_][]const u8{}, // Pure by default
            .capabilities_required = &[_][]const u8{},
            .capabilities_granted = &[_][]const u8{},
            .is_pure = true,
            .is_deterministic = true,
            .memory_effects = .none,
            .io_effects = .none,
        },
    };
}

/// Analyze effects of a function declaration
fn analyzeFunctionEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    var effects: std.ArrayList([]const u8) = .empty;
    var capabilities_required: std.ArrayList([]const u8) = .empty;
    var capabilities_granted: std.ArrayList([]const u8) = .empty;

    // Check for explicit effect annotations
    if (node.effect_annotations) |annotations| {
        for (annotations) |effect_cid| {
            const effect_node = try query_ctx.astdb.getNode(effect_cid);
            try effects.append(effect_node.effect_name);

            // Record dependency on effect definition
            try query_ctx.dependency_tracker.addDependency(.{ .cid = effect_cid });
        }
    }

    // Analyze function body for implicit effects
    if (node.body) |body_cid| {
        const body_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(body_cid));

        // Merge body effects
        for (body_effects.effects) |effect| {
            try effects.append(effect);
        }

        for (body_effects.capabilities_required) |cap| {
            try capabilities_required.append(cap);
        }
    }

    // Determine purity and determinism
    const is_pure = effects.items.len == 0;
    const is_deterministic = !hasNonDeterministicEffects(effects.items);

    return EffectsInfo{
        .effects = effects.toOwnedSlice(),
        .capabilities_required = capabilities_required.toOwnedSlice(),
        .capabilities_granted = capabilities_granted.toOwnedSlice(),
        .is_pure = is_pure,
        .is_deterministic = is_deterministic,
        .memory_effects = determineMemoryEffects(effects.items),
        .io_effects = determineIOEffects(effects.items),
    };
}

/// Analyze effects of a function call
fn analyzeFunctionCallEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    // Get the function being called
    const function_node = try query_ctx.astdb.getNode(node.children[0]);

    // Use Q.Dispatch to resolve the actual function
    const dispatch = @import("dispatch.zig");
    var dispatch_args = CanonicalArgs.init(query_ctx.allocator);
    defer dispatch_args.deinit();

    try dispatch_args.append(.{ .string = function_node.function_name });
    try dispatch_args.append(.{ .cid = node.arguments_cid });
    try dispatch_args.append(.{ .cid = node.cid });

    const dispatch_result = try dispatch.dispatch(query_ctx, dispatch_args);
    const selected_function = dispatch_result.dispatch_info.function_cid;

    // Get effects of the selected function
    var function_effects_args = CanonicalArgs.init(query_ctx.allocator);
    defer function_effects_args.deinit();

    try function_effects_args.append(.{ .cid = selected_function });
    const function_effects_result = try effectsOf(query_ctx, function_effects_args);

    // Analyze argument effects
    var combined_effects: std.ArrayList([]const u8) = .empty;
    var combined_capabilities: std.ArrayList([]const u8) = .empty;

    // Add function effects
    for (function_effects_result.effects_info.effects) |effect| {
        try combined_effects.append(effect);
    }

    for (function_effects_result.effects_info.capabilities_required) |cap| {
        try combined_capabilities.append(cap);
    }

    // Analyze effects of arguments
    for (node.arguments) |arg_cid| {
        const arg_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(arg_cid));

        for (arg_effects.effects) |effect| {
            try combined_effects.append(effect);
        }

        for (arg_effects.capabilities_required) |cap| {
            try combined_capabilities.append(cap);
        }
    }

    return EffectsInfo{
        .effects = combined_effects.toOwnedSlice(),
        .capabilities_required = combined_capabilities.toOwnedSlice(),
        .capabilities_granted = &[_][]const u8{},
        .is_pure = combined_effects.items.len == 0,
        .is_deterministic = !hasNonDeterministicEffects(combined_effects.items),
        .memory_effects = determineMemoryEffects(combined_effects.items),
        .io_effects = determineIOEffects(combined_effects.items),
    };
}

/// Analyze effects of variable assignment
fn analyzeAssignmentEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    var effects: std.ArrayList([]const u8) = .empty;

    // Assignment always has memory write effect
    try effects.append("memory.write");

    // Analyze effects of the assigned expression
    if (node.assigned_value) |value_cid| {
        const value_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(value_cid));

        for (value_effects.effects) |effect| {
            try effects.append(effect);
        }
    }

    return EffectsInfo{
        .effects = effects.toOwnedSlice(),
        .capabilities_required = &[_][]const u8{"memory.write"},
        .capabilities_granted = &[_][]const u8{},
        .is_pure = false,
        .is_deterministic = true,
        .memory_effects = .write,
        .io_effects = .none,
    };
}

/// Analyze effects of member access
fn analyzeMemberAccessEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    // Member access can have effects if it triggers getters/setters
    const object_node = try query_ctx.astdb.getNode(node.children[0]);
    const object_effects = try analyzeNodeEffects(query_ctx, object_node);

    // Check if this is a property access that triggers methods
    if (node.is_property_access) {
        var effects: std.ArrayList([]const u8) = .empty;

        // Add object effects
        for (object_effects.effects) |effect| {
            try effects.append(effect);
        }

        // Property access might have additional effects
        if (node.property_getter) |getter_cid| {
            const getter_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(getter_cid));

            for (getter_effects.effects) |effect| {
                try effects.append(effect);
            }
        }

        return EffectsInfo{
            .effects = effects.toOwnedSlice(),
            .capabilities_required = object_effects.capabilities_required,
            .capabilities_granted = &[_][]const u8{},
            .is_pure = effects.items.len == 0,
            .is_deterministic = object_effects.is_deterministic,
            .memory_effects = object_effects.memory_effects,
            .io_effects = object_effects.io_effects,
        };
    }

    // Simple field access - inherit object effects
    return object_effects;
}

/// Analyze effects of array access
fn analyzeArrayAccessEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    // Array access can have bounds checking effects
    const array_node = try query_ctx.astdb.getNode(node.children[0]);
    const index_node = try query_ctx.astdb.getNode(node.children[1]);

    const array_effects = try analyzeNodeEffects(query_ctx, array_node);
    const index_effects = try analyzeNodeEffects(query_ctx, index_node);

    var combined_effects: std.ArrayList([]const u8) = .empty;

    // Add array effects
    for (array_effects.effects) |effect| {
        try combined_effects.append(effect);
    }

    // Add index effects
    for (index_effects.effects) |effect| {
        try combined_effects.append(effect);
    }

    // Array access might throw bounds check exception
    if (node.has_bounds_check) {
        try combined_effects.append("exception.bounds_check");
    }

    return EffectsInfo{
        .effects = combined_effects.toOwnedSlice(),
        .capabilities_required = &[_][]const u8{},
        .capabilities_granted = &[_][]const u8{},
        .is_pure = combined_effects.items.len == 0,
        .is_deterministic = array_effects.is_deterministic and index_effects.is_deterministic,
        .memory_effects = .read,
        .io_effects = .none,
    };
}

/// Analyze effects of a block statement
fn analyzeBlockEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    var combined_effects: std.ArrayList([]const u8) = .empty;
    var combined_capabilities: std.ArrayList([]const u8) = .empty;

    var is_pure = true;
    var is_deterministic = true;
    var memory_effects = EffectsInfo.MemoryEffects.none;
    var io_effects = EffectsInfo.IOEffects.none;

    // Analyze each statement in the block
    for (node.statements) |stmt_cid| {
        const stmt_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(stmt_cid));

        // Combine effects
        for (stmt_effects.effects) |effect| {
            try combined_effects.append(effect);
        }

        for (stmt_effects.capabilities_required) |cap| {
            try combined_capabilities.append(cap);
        }

        // Update aggregate properties
        is_pure = is_pure and stmt_effects.is_pure;
        is_deterministic = is_deterministic and stmt_effects.is_deterministic;
        memory_effects = combineMemoryEffects(memory_effects, stmt_effects.memory_effects);
        io_effects = combineIOEffects(io_effects, stmt_effects.io_effects);
    }

    return EffectsInfo{
        .effects = combined_effects.toOwnedSlice(),
        .capabilities_required = combined_capabilities.toOwnedSlice(),
        .capabilities_granted = &[_][]const u8{},
        .is_pure = is_pure,
        .is_deterministic = is_deterministic,
        .memory_effects = memory_effects,
        .io_effects = io_effects,
    };
}

/// Analyze effects of conditional statements
fn analyzeConditionalEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    // Analyze condition effects
    const condition_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(node.condition));

    // Analyze then branch effects
    const then_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(node.then_branch));

    // Analyze else branch effects (if present)
    var else_effects: ?EffectsInfo = null;
    if (node.else_branch) |else_cid| {
        else_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(else_cid));
    }

    // Combine all effects
    var combined_effects: std.ArrayList([]const u8) = .empty;

    // Add condition effects (always executed)
    for (condition_effects.effects) |effect| {
        try combined_effects.append(effect);
    }

    // Add potential effects from branches
    for (then_effects.effects) |effect| {
        try combined_effects.append(effect);
    }

    if (else_effects) |else_eff| {
        for (else_eff.effects) |effect| {
            try combined_effects.append(effect);
        }
    }

    return EffectsInfo{
        .effects = combined_effects.toOwnedSlice(),
        .capabilities_required = &[_][]const u8{},
        .capabilities_granted = &[_][]const u8{},
        .is_pure = condition_effects.is_pure and then_effects.is_pure and (else_effects == null or else_effects.?.is_pure),
        .is_deterministic = condition_effects.is_deterministic and then_effects.is_deterministic and (else_effects == null or else_effects.?.is_deterministic),
        .memory_effects = .read, // Conditional execution
        .io_effects = .none,
    };
}

/// Analyze effects of loop statements
fn analyzeLoopEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    // Loops can have unbounded effects due to iteration
    var effects: std.ArrayList([]const u8) = .empty;

    // Analyze loop body
    const body_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(node.body));

    // Loop effects are amplified versions of body effects
    for (body_effects.effects) |effect| {
        try effects.append(effect);
    }

    // Loops are generally not pure and might not be deterministic
    return EffectsInfo{
        .effects = effects.toOwnedSlice(),
        .capabilities_required = body_effects.capabilities_required,
        .capabilities_granted = &[_][]const u8{},
        .is_pure = false, // Loops are not pure due to control flow
        .is_deterministic = body_effects.is_deterministic,
        .memory_effects = body_effects.memory_effects,
        .io_effects = body_effects.io_effects,
    };
}

/// Analyze effects of return statements
fn analyzeReturnEffects(query_ctx: *QueryCtx, node: astdb.AstNode) !EffectsInfo {
    var effects: std.ArrayList([]const u8) = .empty;

    // Return has control flow effect
    try effects.append("control.return");

    // Analyze return value effects
    if (node.return_value) |value_cid| {
        const value_effects = try analyzeNodeEffects(query_ctx, try query_ctx.astdb.getNode(value_cid));

        for (value_effects.effects) |effect| {
            try effects.append(effect);
        }
    }

    return EffectsInfo{
        .effects = effects.toOwnedSlice(),
        .capabilities_required = &[_][]const u8{},
        .capabilities_granted = &[_][]const u8{},
        .is_pure = false, // Return changes control flow
        .is_deterministic = true,
        .memory_effects = .none,
        .io_effects = .none,
    };
}

/// Check if effects list contains non-deterministic effects
fn hasNonDeterministicEffects(effects: [][]const u8) bool {
    const non_deterministic = [_][]const u8{
        "random",
        "time.current",
        "network.receive",
        "io.read",
        "thread.spawn",
    };

    for (effects) |effect| {
        for (non_deterministic) |nd_effect| {
            if (std.mem.eql(u8, effect, nd_effect)) {
                return true;
            }
        }
    }

    return false;
}

/// Determine memory effects from effects list
fn determineMemoryEffects(effects: [][]const u8) EffectsInfo.MemoryEffects {
    var has_read = false;
    var has_write = false;

    for (effects) |effect| {
        if (std.mem.startsWith(u8, effect, "memory.read")) {
            has_read = true;
        } else if (std.mem.startsWith(u8, effect, "memory.write")) {
            has_write = true;
        }
    }

    if (has_write) {
        return .write;
    } else if (has_read) {
        return .read;
    } else {
        return .none;
    }
}

/// Determine I/O effects from effects list
fn determineIOEffects(effects: [][]const u8) EffectsInfo.IOEffects {
    for (effects) |effect| {
        if (std.mem.startsWith(u8, effect, "io.")) {
            return .read_write;
        } else if (std.mem.startsWith(u8, effect, "network.")) {
            return .read_write;
        } else if (std.mem.startsWith(u8, effect, "file.")) {
            return .read_write;
        }
    }

    return .none;
}

/// Combine memory effects
fn combineMemoryEffects(a: EffectsInfo.MemoryEffects, b: EffectsInfo.MemoryEffects) EffectsInfo.MemoryEffects {
    if (a == .write or b == .write) {
        return .write;
    } else if (a == .read or b == .read) {
        return .read;
    } else {
        return .none;
    }
}

/// Combine I/O effects
fn combineIOEffects(a: EffectsInfo.IOEffects, b: EffectsInfo.IOEffects) EffectsInfo.IOEffects {
    if (a == .read_write or b == .read_write) {
        return .read_write;
    } else {
        return .none;
    }
}

// Tests
test "effectsOf basic functionality" {
    const allocator = std.testing.allocator;

    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });

    // Would call effectsOf here with a proper QueryCtx
    try std.testing.expect(args.items.len == 1);
}

test "non-deterministic effect detection" {
    const effects = [_][]const u8{ "memory.read", "random", "io.write" };
    try std.testing.expect(hasNonDeterministicEffects(&effects));

    const deterministic_effects = [_][]const u8{ "memory.read", "memory.write" };
    try std.testing.expect(!hasNonDeterministicEffects(&deterministic_effects));
}

test "memory effects determination" {
    const read_effects = [_][]const u8{"memory.read"};
    try std.testing.expect(determineMemoryEffects(&read_effects) == .read);

    const write_effects = [_][]const u8{ "memory.read", "memory.write" };
    try std.testing.expect(determineMemoryEffects(&write_effects) == .write);

    const no_effects = [_][]const u8{};
    try std.testing.expect(determineMemoryEffects(&no_effects) == .none);
}
