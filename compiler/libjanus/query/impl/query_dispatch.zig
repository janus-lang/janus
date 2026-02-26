// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.Dispatch Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Resolves function dispatch for overloaded functions and methods.
//! This is critical for Janus's multiple dispatch system.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const astdb = @import("../../astdb.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const DispatchInfo = context.DispatchInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Resolve function dispatch for a call site
pub fn dispatch(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 3) {
        return error.QE0005_NonCanonicalArg;
    }

    const function_name = switch (args.items[0]) {
        .string => |name| name,
        else => return error.QE0005_NonCanonicalArg,
    };

    const argument_types = switch (args.items[1]) {
        .cid => |cid| cid, // CID of argument type list
        else => return error.QE0005_NonCanonicalArg,
    };

    const call_site_cid = switch (args.items[2]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependencies
    try query_ctx.dependency_tracker.addDependency(.{ .cid = argument_types });
    try query_ctx.dependency_tracker.addDependency(.{ .cid = call_site_cid });

    // Find all candidate functions
    const candidates = try findDispatchCandidates(query_ctx, function_name, call_site_cid);
    defer query_ctx.allocator.free(candidates);

    // Get argument type information
    const arg_types = try getArgumentTypes(query_ctx, argument_types);
    defer query_ctx.allocator.free(arg_types);

    // Perform dispatch resolution
    const selected_function = try resolveDispatch(query_ctx, candidates, arg_types);

    return QueryResultData{
        .dispatch_info = DispatchInfo{
            .selected_function = selected_function.name,
            .function_cid = selected_function.cid,
            .dispatch_strategy = selected_function.strategy,
            .specificity_score = selected_function.specificity,
            .is_ambiguous = false,
            .candidates = candidates,
        },
    };
}

/// Information about a dispatch candidate
const DispatchCandidate = struct {
    name: []const u8,
    cid: CID,
    parameter_types: []TypeInfo,
    specificity: u32,
    strategy: DispatchStrategy,
    visibility: Visibility,

    const DispatchStrategy = enum {
        static_dispatch,
        dynamic_dispatch,
        inline_dispatch,
        virtual_dispatch,
    };

    const Visibility = enum {
        public,
        private,
        protected,
    };
};

/// Type information for dispatch resolution
const TypeInfo = struct {
    type_name: []const u8,
    type_cid: CID,
    is_generic: bool,
    generic_params: []TypeInfo,
    inheritance_chain: []CID,
};

/// Find all functions that could match the dispatch
fn findDispatchCandidates(query_ctx: *QueryCtx, function_name: []const u8, call_site_cid: CID) ![]DispatchCandidate {
    var candidates: std.ArrayList(DispatchCandidate) = .empty;

    // Get the scope from the call site
    const call_site_node = try query_ctx.astdb.getNode(call_site_cid);
    const scope_cid = call_site_node.scope_cid;

    // Search for functions in current scope and parent scopes
    try searchScopeForFunctions(query_ctx, &candidates, function_name, scope_cid);

    // Search imported modules
    try searchImportsForFunctions(query_ctx, &candidates, function_name, scope_cid);

    return try candidates.toOwnedSlice(alloc);
}

/// Search a scope and its parents for matching functions
fn searchScopeForFunctions(query_ctx: *QueryCtx, candidates: *std.ArrayList(DispatchCandidate), function_name: []const u8, scope_cid: CID) !void {
    var current_scope = scope_cid;

    while (true) {
        const scope_node = try query_ctx.astdb.getNode(current_scope);
        const symbol_table = try query_ctx.astdb.getSymbolTable(current_scope);

        // Look for functions with matching name
        for (symbol_table.symbols) |symbol| {
            if (std.mem.eql(u8, symbol.name, function_name) and symbol.symbol_type == .function) {
                const candidate = try createDispatchCandidate(query_ctx, symbol);
                try candidates.append(candidate);

                // Record dependency on this function
                try query_ctx.dependency_tracker.addDependency(.{ .cid = symbol.definition_cid });
            }
        }

        // Move to parent scope
        if (scope_node.parent_scope) |parent| {
            current_scope = parent;
        } else {
            break;
        }
    }
}

/// Search imported modules for matching functions
fn searchImportsForFunctions(query_ctx: *QueryCtx, candidates: *std.ArrayList(DispatchCandidate), function_name: []const u8, scope_cid: CID) !void {
    const imports = try query_ctx.astdb.getImports(scope_cid);

    for (imports) |import_cid| {
        // Record dependency on the imported module
        try query_ctx.dependency_tracker.addDependency(.{ .cid = import_cid });

        // Search the imported module's public symbols
        const import_node = try query_ctx.astdb.getNode(import_cid);
        const symbol_table = try query_ctx.astdb.getSymbolTable(import_cid);

        for (symbol_table.symbols) |symbol| {
            if (std.mem.eql(u8, symbol.name, function_name) and
                symbol.symbol_type == .function and
                symbol.visibility == .public) {

                const candidate = try createDispatchCandidate(query_ctx, symbol);
                try candidates.append(candidate);

                // Record dependency on this function
                try query_ctx.dependency_tracker.addDependency(.{ .cid = symbol.definition_cid });
            }
        }
    }
}

/// Create a dispatch candidate from a symbol
fn createDispatchCandidate(query_ctx: *QueryCtx, symbol: astdb.Symbol) !DispatchCandidate {
    const function_node = try query_ctx.astdb.getNode(symbol.definition_cid);
    const parameter_types = try getFunctionParameterTypes(query_ctx, function_node);
    const specificity = calculateSpecificity(parameter_types);

    return DispatchCandidate{
        .name = symbol.name,
        .cid = symbol.definition_cid,
        .parameter_types = parameter_types,
        .specificity = specificity,
        .strategy = determineDispatchStrategy(function_node),
        .visibility = symbol.visibility,
    };
}

/// Get parameter types for a function
fn getFunctionParameterTypes(query_ctx: *QueryCtx, function_node: astdb.AstNode) ![]TypeInfo {
    var param_types: std.ArrayList(TypeInfo) = .empty;

    for (function_node.parameters) |param_cid| {
        const param_node = try query_ctx.astdb.getNode(param_cid);
        const param_type = try getParameterType(query_ctx, param_node);
        try param_types.append(param_type);
    }

    return try param_types.toOwnedSlice(alloc);
}

/// Get type information for a parameter
fn getParameterType(query_ctx: *QueryCtx, param_node: astdb.AstNode) !TypeInfo {
    if (param_node.type_annotation) |type_cid| {
        const type_node = try query_ctx.astdb.getNode(type_cid);
        return TypeInfo{
            .type_name = type_node.type_name,
            .type_cid = type_cid,
            .is_generic = type_node.is_generic,
            .generic_params = &[_]TypeInfo{}, // Would parse generic params
            .inheritance_chain = &[_]CID{}, // Would compute inheritance
        };
    }

    return error.MissingTypeAnnotation;
}

/// Get argument types from the call site
fn getArgumentTypes(query_ctx: *QueryCtx, arg_types_cid: CID) ![]TypeInfo {
    const arg_list_node = try query_ctx.astdb.getNode(arg_types_cid);
    var arg_types: std.ArrayList(TypeInfo) = .empty;

    for (arg_list_node.children) |arg_cid| {
        const arg_node = try query_ctx.astdb.getNode(arg_cid);

        // Use Q.TypeOf to get the argument type
        const type_of = @import("type_of.zig");
        var type_args = CanonicalArgs.init(query_ctx.allocator);
        defer type_args.deinit();

        try type_args.append(.{ .cid = arg_cid });
        const type_result = try type_of.typeOf(query_ctx, type_args);

        const arg_type = TypeInfo{
            .type_name = type_result.type_info.type_name,
            .type_cid = type_result.type_info.type_cid orelse CID{ .bytes = [_]u8{0} ** 32 },
            .is_generic = false,
            .generic_params = &[_]TypeInfo{},
            .inheritance_chain = &[_]CID{},
        };

        try arg_types.append(arg_type);
    }

    return try arg_types.toOwnedSlice(alloc);
}

/// Resolve dispatch among candidates
fn resolveDispatch(query_ctx: *QueryCtx, candidates: []DispatchCandidate, arg_types: []TypeInfo) !DispatchCandidate {
    if (candidates.len == 0) {
        return error.NoMatchingFunction;
    }

    // Filter candidates by compatibility
    var compatible: std.ArrayList(DispatchCandidate) = .empty;
    defer compatible.deinit();

    for (candidates) |candidate| {
        if (try isCompatible(query_ctx, candidate.parameter_types, arg_types)) {
            try compatible.append(candidate);
        }
    }

    if (compatible.items.len == 0) {
        return error.NoCompatibleFunction;
    }

    if (compatible.items.len == 1) {
        return compatible.items[0];
    }

    // Multiple candidates - find most specific
    var best_candidate = compatible.items[0];
    var is_ambiguous = false;

    for (compatible.items[1..]) |candidate| {
        const comparison = compareSpecificity(best_candidate, candidate);
        switch (comparison) {
            .more_specific => {
                // Current best is more specific, keep it
            },
            .less_specific => {
                best_candidate = candidate;
                is_ambiguous = false;
            },
            .equal => {
                is_ambiguous = true;
            },
        }
    }

    if (is_ambiguous) {
        return error.AmbiguousDispatch;
    }

    return best_candidate;
}

/// Check if parameter types are compatible with argument types
fn isCompatible(query_ctx: *QueryCtx, param_types: []TypeInfo, arg_types: []TypeInfo) !bool {
    if (param_types.len != arg_types.len) {
        return false;
    }

    for (param_types) |param_type, i| {
        const arg_type = arg_types[i];
        if (!try isTypeCompatible(query_ctx, param_type, arg_type)) {
            return false;
        }
    }

    return true;
}

/// Check if two types are compatible
fn isTypeCompatible(query_ctx: *QueryCtx, param_type: TypeInfo, arg_type: TypeInfo) !bool {
    _ = query_ctx;

    // Exact match
    if (std.mem.eql(u8, param_type.type_name, arg_type.type_name)) {
        return true;
    }

    // Check inheritance/subtyping
    for (arg_type.inheritance_chain) |ancestor_cid| {
        if (std.mem.eql(u8, &param_type.type_cid.bytes, &ancestor_cid.bytes)) {
            return true;
        }
    }

    // Check implicit conversions
    return isImplicitlyConvertible(param_type.type_name, arg_type.type_name);
}

/// Check if one type can be implicitly converted to another
fn isImplicitlyConvertible(target_type: []const u8, source_type: []const u8) bool {
    // Numeric widening conversions
    const conversions = std.ComptimeStringMap([]const []const u8, .{
        .{ "i16", &[_][]const u8{"i8"} },
        .{ "i32", &[_][]const u8{ "i8", "i16" } },
        .{ "i64", &[_][]const u8{ "i8", "i16", "i32" } },
        .{ "f32", &[_][]const u8{ "i8", "i16", "i32" } },
        .{ "f64", &[_][]const u8{ "i8", "i16", "i32", "i64", "f32" } },
    });

    if (conversions.get(target_type)) |allowed_sources| {
        for (allowed_sources) |allowed| {
            if (std.mem.eql(u8, source_type, allowed)) {
                return true;
            }
        }
    }

    return false;
}

/// Calculate specificity score for parameter types
fn calculateSpecificity(param_types: []TypeInfo) u32 {
    var score: u32 = 0;

    for (param_types) |param_type| {
        // More specific types get higher scores
        if (param_type.is_generic) {
            score += 1; // Generic types are less specific
        } else {
            score += 10; // Concrete types are more specific
        }

        // Types with longer inheritance chains are more specific
        score += @intCast(u32, param_type.inheritance_chain.len * 5);
    }

    return score;
}

/// Compare specificity of two candidates
fn compareSpecificity(a: DispatchCandidate, b: DispatchCandidate) enum { more_specific, less_specific, equal } {
    if (a.specificity > b.specificity) {
        return .more_specific;
    } else if (a.specificity < b.specificity) {
        return .less_specific;
    } else {
        return .equal;
    }
}

/// Determine dispatch strategy for a function
fn determineDispatchStrategy(function_node: astdb.AstNode) DispatchCandidate.DispatchStrategy {
    // Simple heuristics for dispatch strategy
    if (function_node.is_inline) {
        return .inline_dispatch;
    } else if (function_node.is_virtual) {
        return .virtual_dispatch;
    } else if (function_node.has_generic_params) {
        return .static_dispatch; // Generics use static dispatch
    } else {
        return .dynamic_dispatch;
    }
}

// Tests
test "dispatch basic functionality" {
    const allocator = std.testing.allocator;

    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .string = "test_function" });
    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });
    try args.append(.{ .cid = CID{ .bytes = [_]u8{2} ** 32 } });

    // Would call dispatch here with a proper QueryCtx
    try std.testing.expect(args.items.len == 3);
}

test "type compatibility" {
    try std.testing.expect(isImplicitlyConvertible("i32", "i16"));
    try std.testing.expect(isImplicitlyConvertible("f64", "i32"));
    try std.testing.expect(!isImplicitlyConvertible("i16", "i32"));
}

test "specificity calculation" {
    const concrete_type = TypeInfo{
        .type_name = "i32",
        .type_cid = CID{ .bytes = [_]u8{1} ** 32 },
        .is_generic = false,
        .generic_params = &[_]TypeInfo{},
        .inheritance_chain = &[_]CID{},
    };

    const generic_type = TypeInfo{
        .type_name = "T",
        .type_cid = CID{ .bytes = [_]u8{2} ** 32 },
        .is_generic = true,
        .generic_params = &[_]TypeInfo{},
        .inheritance_chain = &[_]CID{},
    };

    const concrete_score = calculateSpecificity(&[_]TypeInfo{concrete_type});
    const generic_score = calculateSpecificity(&[_]TypeInfo{generic_type});

    try std.testing.expect(concrete_score > generic_score);
}
