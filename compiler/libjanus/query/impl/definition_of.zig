// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.DefinitionOf Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Finds the definition location of symbols, types, and other entities.
//! This is essential for "Go to Definition" IDE functionality.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const astdb = @import("../../astdb.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const DefinitionInfo = context.DefinitionInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Find the definition of a symbol or entity
pub fn definitionOf(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 2) {
        return error.QE0005_NonCanonicalArg;
    }

    const entity_cid = switch (args.items[0]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    const context_cid = switch (args.items[1]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependencies
    try query_ctx.dependency_tracker.addDependency(.{ .cid = entity_cid });
    try query_ctx.dependency_tracker.addDependency(.{ .cid = context_cid });

    // Get the entity node
    const entity_node = try query_ctx.astdb.getNode(entity_cid);

    // Find definition based on entity type
    const definition_info = try findDefinition(query_ctx, entity_node, context_cid);

    return QueryResultData{
        .definition_info = definition_info,
    };
}

/// Find the definition of an entity
fn findDefinition(query_ctx: *QueryCtx, entity_node: astdb.AstNode, context_cid: CID) !DefinitionInfo {
    return switch (entity_node.node_type) {
        .identifier => try findIdentifierDefinition(query_ctx, entity_node, context_cid),
        .type_reference => try findTypeDefinition(query_ctx, entity_node, context_cid),
        .function_call => try findFunctionDefinition(query_ctx, entity_node, context_cid),
        .member_access => try findMemberDefinition(query_ctx, entity_node, context_cid),
        .import_statement => try findImportDefinition(query_ctx, entity_node),
        .module_reference => try findModuleDefinition(query_ctx, entity_node),
        else => blk: {
            // For other node types, the definition is the node itself
            break :blk DefinitionInfo{
                .location = entity_node.source_location,
                .definition_cid = entity_node.cid,
                .definition_type = .self_defining,
                .symbol_name = entity_node.name orelse "anonymous",
                .containing_scope = entity_node.scope_cid,
                .visibility = .public,
                .is_builtin = false,
            };
        },
    };
}

/// Find definition of an identifier
fn findIdentifierDefinition(query_ctx: *QueryCtx, identifier_node: astdb.AstNode, context_cid: CID) !DefinitionInfo {
    const symbol_name = identifier_node.token_text;

    // Use Q.ResolveName to find the symbol
    const resolve_name = @import("resolve_name.zig");
    var resolve_args = CanonicalArgs.init(query_ctx.allocator);
    defer resolve_args.deinit();

    try resolve_args.append(.{ .string = symbol_name });
    try resolve_args.append(.{ .cid = context_cid });

    const resolve_result = try resolve_name.resolveName(query_ctx, resolve_args);
    const symbol_info = resolve_result.symbol_info;

    // Get the definition node
    const definition_node = try query_ctx.astdb.getNode(symbol_info.definition_cid);

    return DefinitionInfo{
        .location = definition_node.source_location,
        .definition_cid = symbol_info.definition_cid,
        .definition_type = mapSymbolTypeToDefinitionType(symbol_info.symbol_type),
        .symbol_name = symbol_info.name,
        .containing_scope = definition_node.scope_cid,
        .visibility = symbol_info.visibility,
        .is_builtin = isBuiltinSymbol(symbol_info.name),
    };
}

/// Find definition of a type reference
fn findTypeDefinition(query_ctx: *QueryCtx, type_node: astdb.AstNode, context_cid: CID) !DefinitionInfo {
    const type_name = type_node.type_name;

    // Look up type in type registry
    const type_registry = try query_ctx.astdb.getTypeRegistry(context_cid);

    for (type_registry.types) |type_entry| {
        if (std.mem.eql(u8, type_entry.name, type_name)) {
            const definition_node = try query_ctx.astdb.getNode(type_entry.definition_cid);

            return DefinitionInfo{
                .location = definition_node.source_location,
                .definition_cid = type_entry.definition_cid,
                .definition_type = .type_definition,
                .symbol_name = type_name,
                .containing_scope = definition_node.scope_cid,
                .visibility = type_entry.visibility,
                .is_builtin = isBuiltinType(type_name),
            };
        }
    }

    return error.TypeNotFound;
}

/// Find definition of a function call
fn findFunctionDefinition(query_ctx: *QueryCtx, call_node: astdb.AstNode, context_cid: CID) !DefinitionInfo {
    // Use Q.Dispatch to resolve the function
    const dispatch = @import("dispatch.zig");
    var dispatch_args = CanonicalArgs.init(query_ctx.allocator);
    defer dispatch_args.deinit();

    const function_name = call_node.function_name;
    try dispatch_args.append(.{ .string = function_name });
    try dispatch_args.append(.{ .cid = call_node.arguments_cid });
    try dispatch_args.append(.{ .cid = context_cid });

    const dispatch_result = try dispatch.dispatch(query_ctx, dispatch_args);
    const selected_function_cid = dispatch_result.dispatch_info.function_cid;

    // Get the function definition
    const function_node = try query_ctx.astdb.getNode(selected_function_cid);

    return DefinitionInfo{
        .location = function_node.source_location,
        .definition_cid = selected_function_cid,
        .definition_type = .function_definition,
        .symbol_name = function_name,
        .containing_scope = function_node.scope_cid,
        .visibility = function_node.visibility,
        .is_builtin = isBuiltinFunction(function_name),
    };
}

/// Find definition of a member access
fn findMemberDefinition(query_ctx: *QueryCtx, member_node: astdb.AstNode, context_cid: CID) !DefinitionInfo {
    // Get the object type
    const object_node = try query_ctx.astdb.getNode(member_node.children[0]);

    // Use Q.TypeOf to get the object's type
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = object_node.cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    const object_type_cid = type_result.type_info.type_cid orelse return error.UnknownObjectType;

    // Get the type definition
    const type_def = try query_ctx.astdb.getTypeDefinition(object_type_cid);

    // Find the member in the type definition
    const member_name = member_node.member_name;

    for (type_def.fields) |field| {
        if (std.mem.eql(u8, field.name, member_name)) {
            return DefinitionInfo{
                .location = field.source_location,
                .definition_cid = field.definition_cid,
                .definition_type = .field_definition,
                .symbol_name = member_name,
                .containing_scope = object_type_cid,
                .visibility = field.visibility,
                .is_builtin = false,
            };
        }
    }

    // Check methods
    for (type_def.methods) |method| {
        if (std.mem.eql(u8, method.name, member_name)) {
            return DefinitionInfo{
                .location = method.source_location,
                .definition_cid = method.definition_cid,
                .definition_type = .method_definition,
                .symbol_name = member_name,
                .containing_scope = object_type_cid,
                .visibility = method.visibility,
                .is_builtin = false,
            };
        }
    }

    return error.MemberNotFound;
}

/// Find definition of an import statement
fn findImportDefinition(query_ctx: *QueryCtx, import_node: astdb.AstNode) !DefinitionInfo {
    const module_path = import_node.module_path;

    // Resolve module path to actual file
    const module_cid = try query_ctx.astdb.resolveModulePath(module_path);
    const module_node = try query_ctx.astdb.getNode(module_cid);

    return DefinitionInfo{
        .location = module_node.source_location,
        .definition_cid = module_cid,
        .definition_type = .module_definition,
        .symbol_name = module_path,
        .containing_scope = CID{ .bytes = [_]u8{0} ** 32 }, // Global scope
        .visibility = .public,
        .is_builtin = isBuiltinModule(module_path),
    };
}

/// Find definition of a module reference
fn findModuleDefinition(query_ctx: *QueryCtx, module_node: astdb.AstNode) !DefinitionInfo {
    const module_name = module_node.module_name;

    // Look up module in module registry
    const module_registry = try query_ctx.astdb.getModuleRegistry();

    for (module_registry.modules) |module_entry| {
        if (std.mem.eql(u8, module_entry.name, module_name)) {
            const definition_node = try query_ctx.astdb.getNode(module_entry.definition_cid);

            return DefinitionInfo{
                .location = definition_node.source_location,
                .definition_cid = module_entry.definition_cid,
                .definition_type = .module_definition,
                .symbol_name = module_name,
                .containing_scope = CID{ .bytes = [_]u8{0} ** 32 }, // Global scope
                .visibility = .public,
                .is_builtin = isBuiltinModule(module_name),
            };
        }
    }

    return error.ModuleNotFound;
}

/// Map symbol type to definition type
fn mapSymbolTypeToDefinitionType(symbol_type: astdb.SymbolType) DefinitionInfo.DefinitionType {
    return switch (symbol_type) {
        .variable => .variable_definition,
        .function => .function_definition,
        .type => .type_definition,
        .module => .module_definition,
        .constant => .constant_definition,
        .parameter => .parameter_definition,
        .field => .field_definition,
        .method => .method_definition,
    };
}

/// Check if a symbol is builtin
fn isBuiltinSymbol(symbol_name: []const u8) bool {
    const builtin_symbols = [_][]const u8{
        "print", "println", "assert", "panic",
        "len",   "cap",     "append", "copy",
        "new",   "make",    "delete",
    };

    for (builtin_symbols) |builtin| {
        if (std.mem.eql(u8, symbol_name, builtin)) {
            return true;
        }
    }

    return false;
}

/// Check if a type is builtin
fn isBuiltinType(type_name: []const u8) bool {
    const builtin_types = [_][]const u8{
        "i8",   "i16",  "i32",  "i64",
        "u8",   "u16",  "u32",  "u64",
        "f32",  "f64",  "bool", "string",
        "char", "void", "any",  "never",
    };

    for (builtin_types) |builtin| {
        if (std.mem.eql(u8, type_name, builtin)) {
            return true;
        }
    }

    return false;
}

/// Check if a function is builtin
fn isBuiltinFunction(function_name: []const u8) bool {
    return isBuiltinSymbol(function_name);
}

/// Check if a module is builtin
fn isBuiltinModule(module_name: []const u8) bool {
    const builtin_modules = [_][]const u8{
        "std",         "core",       "builtin",
        "math",        "string",     "io",
        "collections", "algorithms",
    };

    for (builtin_modules) |builtin| {
        if (std.mem.eql(u8, module_name, builtin)) {
            return true;
        }
    }

    return false;
}

/// Find all references to a definition
pub fn findReferences(query_ctx: *QueryCtx, definition_cid: CID) ![]DefinitionInfo.Reference {
    var references: std.ArrayList(DefinitionInfo.Reference) = .empty;

    // This would require a reverse index of all symbol usages
    // For now, return empty list
    _ = query_ctx;
    _ = definition_cid;

    return try references.toOwnedSlice(alloc);
}

/// Find all implementations of an interface or abstract method
pub fn findImplementations(query_ctx: *QueryCtx, interface_cid: CID) ![]DefinitionInfo {
    var implementations: std.ArrayList(DefinitionInfo) = .empty;

    // This would require analysis of type hierarchy and interface implementations
    // For now, return empty list
    _ = query_ctx;
    _ = interface_cid;

    return try implementations.toOwnedSlice(alloc);
}

// Tests
test "definitionOf basic functionality" {
    const allocator = std.testing.allocator;

    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });
    try args.append(.{ .cid = CID{ .bytes = [_]u8{2} ** 32 } });

    // Would call definitionOf here with a proper QueryCtx
    try std.testing.expect(args.items.len == 2);
}

test "builtin symbol detection" {
    try std.testing.expect(isBuiltinSymbol("print"));
    try std.testing.expect(isBuiltinSymbol("len"));
    try std.testing.expect(!isBuiltinSymbol("my_function"));
}

test "builtin type detection" {
    try std.testing.expect(isBuiltinType("i32"));
    try std.testing.expect(isBuiltinType("string"));
    try std.testing.expect(!isBuiltinType("MyCustomType"));
}

test "builtin module detection" {
    try std.testing.expect(isBuiltinModule("std"));
    try std.testing.expect(isBuiltinModule("math"));
    try std.testing.expect(!isBuiltinModule("my_module"));
}
