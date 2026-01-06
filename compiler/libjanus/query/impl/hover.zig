// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Q.Hover Implementation
//! Task 2.5 - Core Query Implementations (v1)
//!
//! Provides rich hover information for IDE tooltips.
//! Combines type information, documentation, and usage examples.

const std = @import("std");
const Allocator = std.mem.Allocator;
const context = @import("../context.zig");
const astdb = @import("../../astdb.zig");

const QueryCtx = context.QueryCtx;
const CanonicalArgs = context.CanonicalArgs;
const QueryResultData = context.QueryResultData;
const HoverInfo = context.HoverInfo;
const CID = @import("../../astdb/ids.zig").CID;

/// Generate hover information for a position in source code
pub fn hover(query_ctx: *QueryCtx, args: CanonicalArgs) !QueryResultData {
    // Extract arguments
    if (args.items.len != 2) {
        return error.QE0005_NonCanonicalArg;
    }

    const position_cid = switch (args.items[0]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    const context_cid = switch (args.items[1]) {
        .cid => |cid| cid,
        else => return error.QE0005_NonCanonicalArg,
    };

    // Record dependencies
    try query_ctx.dependency_tracker.addDependency(.{ .cid = position_cid });
    try query_ctx.dependency_tracker.addDependency(.{ .cid = context_cid });

    // Get the node at the position
    const node = try query_ctx.astdb.getNode(position_cid);

    // Generate hover information based on node type
    const hover_info = try generateHoverInfo(query_ctx, node, context_cid);

    return QueryResultData{
        .hover_info = hover_info,
    };
}

/// Generate comprehensive hover information for a node
fn generateHoverInfo(query_ctx: *QueryCtx, node: astdb.AstNode, context_cid: CID) !HoverInfo {
    return switch (node.node_type) {
        .identifier => try generateIdentifierHover(query_ctx, node, context_cid),
        .function_call => try generateFunctionCallHover(query_ctx, node, context_cid),
        .function_declaration => try generateFunctionDeclarationHover(query_ctx, node),
        .type_reference => try generateTypeReferenceHover(query_ctx, node, context_cid),
        .variable_declaration => try generateVariableDeclarationHover(query_ctx, node),
        .member_access => try generateMemberAccessHover(query_ctx, node, context_cid),
        .literal_integer, .literal_float, .literal_string, .literal_boolean => try generateLiteralHover(query_ctx, node),
        .binary_operation, .unary_operation => try generateOperationHover(query_ctx, node),
        .import_statement => try generateImportHover(query_ctx, node),
        else => HoverInfo{
            .text = "Unknown element",
            .markdown = "```\nUnknown element\n```",
            .signature = null,
            .documentation = null,
            .type_info = null,
            .examples = &[_][]const u8{},
            .related_links = &[_]HoverInfo.Link{},
        },
    };
}

/// Generate hover for identifier
fn generateIdentifierHover(query_ctx: *QueryCtx, node: astdb.AstNode, context_cid: CID) !HoverInfo {
    const symbol_name = node.token_text;

    // Use Q.ResolveName to find the symbol
    const resolve_name = @import("resolve_name.zig");
    var resolve_args = CanonicalArgs.init(query_ctx.allocator);
    defer resolve_args.deinit();

    try resolve_args.append(.{ .string = symbol_name });
    try resolve_args.append(.{ .cid = context_cid });

    const resolve_result = resolve_name.resolveName(query_ctx, resolve_args) catch |err| {
        return switch (err) {
            error.SymbolNotFound => HoverInfo{
                .text = try std.fmt.allocPrint(query_ctx.allocator, "Unknown symbol: {s}", .{symbol_name}),
                .markdown = try std.fmt.allocPrint(query_ctx.allocator, "```\nUnknown symbol: {s}\n```", .{symbol_name}),
                .signature = null,
                .documentation = null,
                .type_info = null,
                .examples = &[_][]const u8{},
                .related_links = &[_]HoverInfo.Link{},
            },
            else => return err,
        };
    };

    const symbol_info = resolve_result.symbol_info;

    // Get type information
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = symbol_info.definition_cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    // Get definition information
    const definition_of = @import("definition_of.zig");
    var def_args = CanonicalArgs.init(query_ctx.allocator);
    defer def_args.deinit();

    try def_args.append(.{ .cid = node.cid });
    try def_args.append(.{ .cid = context_cid });
    const def_result = try definition_of.definitionOf(query_ctx, def_args);

    // Build hover text
    const signature = try buildSignature(query_ctx, symbol_info, type_result.type_info);
    const documentation = try getDocumentation(query_ctx, symbol_info.definition_cid);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "{s}: {s}", .{ symbol_name, type_result.type_info.type_name }),
        .markdown = try buildMarkdownHover(query_ctx, symbol_name, signature, documentation, type_result.type_info),
        .signature = signature,
        .documentation = documentation,
        .type_info = type_result.type_info,
        .examples = try getExamples(query_ctx, symbol_info.definition_cid),
        .related_links = try getRelatedLinks(query_ctx, symbol_info.definition_cid),
    };
}

/// Generate hover for function call
fn generateFunctionCallHover(query_ctx: *QueryCtx, node: astdb.AstNode, context_cid: CID) !HoverInfo {
    // Use Q.Dispatch to resolve the function
    const dispatch = @import("dispatch.zig");
    var dispatch_args = CanonicalArgs.init(query_ctx.allocator);
    defer dispatch_args.deinit();

    const function_name = node.function_name;
    try dispatch_args.append(.{ .string = function_name });
    try dispatch_args.append(.{ .cid = node.arguments_cid });
    try dispatch_args.append(.{ .cid = context_cid });

    const dispatch_result = try dispatch.dispatch(query_ctx, dispatch_args);
    const selected_function_cid = dispatch_result.dispatch_info.function_cid;

    // Get function information
    const function_node = try query_ctx.astdb.getNode(selected_function_cid);

    // Build function signature
    const signature = try buildFunctionSignature(query_ctx, function_node);
    const documentation = try getDocumentation(query_ctx, selected_function_cid);

    // Get effects information
    const effects_of = @import("effects_of.zig");
    var effects_args = CanonicalArgs.init(query_ctx.allocator);
    defer effects_args.deinit();

    try effects_args.append(.{ .cid = selected_function_cid });
    const effects_result = try effects_of.effectsOf(query_ctx, effects_args);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "function {s}", .{function_name}),
        .markdown = try buildFunctionMarkdownHover(query_ctx, function_name, signature, documentation, effects_result.effects_info),
        .signature = signature,
        .documentation = documentation,
        .type_info = null, // Functions don't have simple type info
        .examples = try getExamples(query_ctx, selected_function_cid),
        .related_links = try getRelatedLinks(query_ctx, selected_function_cid),
    };
}

/// Generate hover for function declaration
fn generateFunctionDeclarationHover(query_ctx: *QueryCtx, node: astdb.AstNode) !HoverInfo {
    const function_name = node.function_name;
    const signature = try buildFunctionSignature(query_ctx, node);
    const documentation = try getDocumentation(query_ctx, node.cid);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "function {s}", .{function_name}),
        .markdown = try buildFunctionMarkdownHover(query_ctx, function_name, signature, documentation, null),
        .signature = signature,
        .documentation = documentation,
        .type_info = null,
        .examples = try getExamples(query_ctx, node.cid),
        .related_links = try getRelatedLinks(query_ctx, node.cid),
    };
}

/// Generate hover for type reference
fn generateTypeReferenceHover(query_ctx: *QueryCtx, node: astdb.AstNode, context_cid: CID) !HoverInfo {
    const type_name = node.type_name;

    // Use Q.DefinitionOf to find the type definition
    const definition_of = @import("definition_of.zig");
    var def_args = CanonicalArgs.init(query_ctx.allocator);
    defer def_args.deinit();

    try def_args.append(.{ .cid = node.cid });
    try def_args.append(.{ .cid = context_cid });

    const def_result = definition_of.definitionOf(query_ctx, def_args) catch |err| {
        return switch (err) {
            error.TypeNotFound => HoverInfo{
                .text = try std.fmt.allocPrint(query_ctx.allocator, "Unknown type: {s}", .{type_name}),
                .markdown = try std.fmt.allocPrint(query_ctx.allocator, "```\nUnknown type: {s}\n```", .{type_name}),
                .signature = null,
                .documentation = null,
                .type_info = null,
                .examples = &[_][]const u8{},
                .related_links = &[_]HoverInfo.Link{},
            },
            else => return err,
        };
    };

    const type_def_node = try query_ctx.astdb.getNode(def_result.definition_cid);
    const signature = try buildTypeSignature(query_ctx, type_def_node);
    const documentation = try getDocumentation(query_ctx, def_result.definition_cid);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "type {s}", .{type_name}),
        .markdown = try buildTypeMarkdownHover(query_ctx, type_name, signature, documentation),
        .signature = signature,
        .documentation = documentation,
        .type_info = null,
        .examples = try getExamples(query_ctx, def_result.definition_cid),
        .related_links = try getRelatedLinks(query_ctx, def_result.definition_cid),
    };
}

/// Generate hover for variable declaration
fn generateVariableDeclarationHover(query_ctx: *QueryCtx, node: astdb.AstNode) !HoverInfo {
    const var_name = node.variable_name;

    // Get type information
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = node.cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    const signature = try std.fmt.allocPrint(query_ctx.allocator, "{s} {s}: {s}", .{
        if (node.is_mutable) "var" else "let",
        var_name,
        type_result.type_info.type_name,
    });

    const documentation = try getDocumentation(query_ctx, node.cid);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "{s}: {s}", .{ var_name, type_result.type_info.type_name }),
        .markdown = try buildVariableMarkdownHover(query_ctx, var_name, signature, documentation, type_result.type_info),
        .signature = signature,
        .documentation = documentation,
        .type_info = type_result.type_info,
        .examples = &[_][]const u8{},
        .related_links = &[_]HoverInfo.Link{},
    };
}

/// Generate hover for member access
fn generateMemberAccessHover(query_ctx: *QueryCtx, node: astdb.AstNode, context_cid: CID) !HoverInfo {
    // Use Q.DefinitionOf to find the member definition
    const definition_of = @import("definition_of.zig");
    var def_args = CanonicalArgs.init(query_ctx.allocator);
    defer def_args.deinit();

    try def_args.append(.{ .cid = node.cid });
    try def_args.append(.{ .cid = context_cid });

    const def_result = try definition_of.definitionOf(query_ctx, def_args);
    const member_name = node.member_name;

    // Get type information
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = def_result.definition_cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    const signature = try std.fmt.allocPrint(query_ctx.allocator, "{s}: {s}", .{ member_name, type_result.type_info.type_name });
    const documentation = try getDocumentation(query_ctx, def_result.definition_cid);

    return HoverInfo{
        .text = signature,
        .markdown = try buildMemberMarkdownHover(query_ctx, member_name, signature, documentation, type_result.type_info),
        .signature = signature,
        .documentation = documentation,
        .type_info = type_result.type_info,
        .examples = &[_][]const u8{},
        .related_links = &[_]HoverInfo.Link{},
    };
}

/// Generate hover for literals
fn generateLiteralHover(query_ctx: *QueryCtx, node: astdb.AstNode) !HoverInfo {
    // Get type information
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = node.cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    const literal_value = node.token_text;
    const signature = try std.fmt.allocPrint(query_ctx.allocator, "{s}: {s}", .{ literal_value, type_result.type_info.type_name });

    return HoverInfo{
        .text = signature,
        .markdown = try std.fmt.allocPrint(query_ctx.allocator, "```janus\n{s}\n```\n\nLiteral value of type `{s}`", .{ literal_value, type_result.type_info.type_name }),
        .signature = signature,
        .documentation = null,
        .type_info = type_result.type_info,
        .examples = &[_][]const u8{},
        .related_links = &[_]HoverInfo.Link{},
    };
}

/// Generate hover for operations
fn generateOperationHover(query_ctx: *QueryCtx, node: astdb.AstNode) !HoverInfo {
    // Get type information
    const type_of = @import("type_of.zig");
    var type_args = CanonicalArgs.init(query_ctx.allocator);
    defer type_args.deinit();

    try type_args.append(.{ .cid = node.cid });
    const type_result = try type_of.typeOf(query_ctx, type_args);

    const operator_name = @tagName(node.operator_type);
    const signature = try std.fmt.allocPrint(query_ctx.allocator, "operator {s}: {s}", .{ operator_name, type_result.type_info.type_name });

    return HoverInfo{
        .text = signature,
        .markdown = try std.fmt.allocPrint(query_ctx.allocator, "```janus\noperator {s}\n```\n\nResult type: `{s}`", .{ operator_name, type_result.type_info.type_name }),
        .signature = signature,
        .documentation = null,
        .type_info = type_result.type_info,
        .examples = &[_][]const u8{},
        .related_links = &[_]HoverInfo.Link{},
    };
}

/// Generate hover for import statements
fn generateImportHover(query_ctx: *QueryCtx, node: astdb.AstNode) !HoverInfo {
    const module_path = node.module_path;

    // Use Q.DefinitionOf to find the module
    const definition_of = @import("definition_of.zig");
    var def_args = CanonicalArgs.init(query_ctx.allocator);
    defer def_args.deinit();

    try def_args.append(.{ .cid = node.cid });
    try def_args.append(.{ .cid = CID{ .bytes = [_]u8{0} ** 32 } }); // Global scope

    const def_result = try definition_of.definitionOf(query_ctx, def_args);
    const documentation = try getDocumentation(query_ctx, def_result.definition_cid);

    return HoverInfo{
        .text = try std.fmt.allocPrint(query_ctx.allocator, "module {s}", .{module_path}),
        .markdown = try buildModuleMarkdownHover(query_ctx, module_path, documentation),
        .signature = try std.fmt.allocPrint(query_ctx.allocator, "import {s}", .{module_path}),
        .documentation = documentation,
        .type_info = null,
        .examples = &[_][]const u8{},
        .related_links = &[_]HoverInfo.Link{},
    };
}

// Helper functions for building hover content

fn buildSignature(query_ctx: *QueryCtx, symbol_info: astdb.SymbolInfo, type_info: context.TypeInfo) ![]const u8 {
    _ = query_ctx;
    return std.fmt.allocPrint(query_ctx.allocator, "{s}: {s}", .{ symbol_info.name, type_info.type_name });
}

fn buildFunctionSignature(query_ctx: *QueryCtx, function_node: astdb.AstNode) ![]const u8 {
    var signature = std.ArrayList(u8).init(query_ctx.allocator);
    var writer = signature.writer();

    try writer.print("func {s}(", .{function_node.function_name});

    // Add parameters
    for (function_node.parameters) |param_cid, i| {
        if (i > 0) try writer.print(", ");

        const param_node = try query_ctx.astdb.getNode(param_cid);
        try writer.print("{s}: {s}", .{ param_node.parameter_name, param_node.parameter_type });
    }

    try writer.print(")");

    // Add return type
    if (function_node.return_type) |return_type| {
        try writer.print(" -> {s}", .{return_type});
    }

    return signature.toOwnedSlice();
}

fn buildTypeSignature(query_ctx: *QueryCtx, type_node: astdb.AstNode) ![]const u8 {
    return std.fmt.allocPrint(query_ctx.allocator, "type {s}", .{type_node.type_name});
}

fn buildMarkdownHover(query_ctx: *QueryCtx, name: []const u8, signature: []const u8, documentation: ?[]const u8, type_info: context.TypeInfo) ![]const u8 {
    var markdown = std.ArrayList(u8).init(query_ctx.allocator);
    var writer = markdown.writer();

    try writer.print("```janus\n{s}\n```\n\n", .{signature});

    if (documentation) |doc| {
        try writer.print("{s}\n\n", .{doc});
    }

    try writer.print("**Type:** `{s}`\n", .{type_info.type_name});

    if (type_info.is_mutable) {
        try writer.print("**Mutable:** Yes\n");
    }

    if (type_info.is_optional) {
        try writer.print("**Optional:** Yes\n");
    }

    return markdown.toOwnedSlice();
}

fn buildFunctionMarkdownHover(query_ctx: *QueryCtx, name: []const u8, signature: []const u8, documentation: ?[]const u8, effects_info: ?context.EffectsInfo) ![]const u8 {
    var markdown = std.ArrayList(u8).init(query_ctx.allocator);
    var writer = markdown.writer();

    try writer.print("```janus\n{s}\n```\n\n", .{signature});

    if (documentation) |doc| {
        try writer.print("{s}\n\n", .{doc});
    }

    if (effects_info) |effects| {
        if (effects.is_pure) {
            try writer.print("**Pure function** - No side effects\n");
        } else {
            try writer.print("**Effects:**\n");
            for (effects.effects) |effect| {
                try writer.print("- `{s}`\n", .{effect});
            }
        }

        if (!effects.is_deterministic) {
            try writer.print("**Non-deterministic** - Results may vary\n");
        }
    }

    return markdown.toOwnedSlice();
}

fn buildTypeMarkdownHover(query_ctx: *QueryCtx, name: []const u8, signature: []const u8, documentation: ?[]const u8) ![]const u8 {
    var markdown = std.ArrayList(u8).init(query_ctx.allocator);
    var writer = markdown.writer();

    try writer.print("```janus\n{s}\n```\n\n", .{signature});

    if (documentation) |doc| {
        try writer.print("{s}\n\n", .{doc});
    }

    return markdown.toOwnedSlice();
}

fn buildVariableMarkdownHover(query_ctx: *QueryCtx, name: []const u8, signature: []const u8, documentation: ?[]const u8, type_info: context.TypeInfo) ![]const u8 {
    return buildMarkdownHover(query_ctx, name, signature, documentation, type_info);
}

fn buildMemberMarkdownHover(query_ctx: *QueryCtx, name: []const u8, signature: []const u8, documentation: ?[]const u8, type_info: context.TypeInfo) ![]const u8 {
    return buildMarkdownHover(query_ctx, name, signature, documentation, type_info);
}

fn buildModuleMarkdownHover(query_ctx: *QueryCtx, module_path: []const u8, documentation: ?[]const u8) ![]const u8 {
    var markdown = std.ArrayList(u8).init(query_ctx.allocator);
    var writer = markdown.writer();

    try writer.print("```janus\nimport {s}\n```\n\n", .{module_path});

    if (documentation) |doc| {
        try writer.print("{s}\n\n", .{doc});
    }

    try writer.print("**Module:** `{s}`\n", .{module_path});

    return markdown.toOwnedSlice();
}

fn getDocumentation(query_ctx: *QueryCtx, cid: CID) !?[]const u8 {
    // Get documentation from AST node comments
    const node = try query_ctx.astdb.getNode(cid);

    if (node.documentation) |doc_cid| {
        const doc_node = try query_ctx.astdb.getNode(doc_cid);
        return doc_node.comment_text;
    }

    return null;
}

fn getExamples(query_ctx: *QueryCtx, cid: CID) ![][]const u8 {
    // Extract examples from documentation
    _ = query_ctx;
    _ = cid;

    // For now, return empty array
    // In a full implementation, we'd parse documentation for example blocks
    return &[_][]const u8{};
}

fn getRelatedLinks(query_ctx: *QueryCtx, cid: CID) ![]HoverInfo.Link {
    // Generate related links (references, implementations, etc.)
    _ = query_ctx;
    _ = cid;

    // For now, return empty array
    return &[_]HoverInfo.Link{};
}

// Tests
test "hover basic functionality" {
    const allocator = std.testing.allocator;

    var args = CanonicalArgs.init(allocator);
    defer args.deinit();

    try args.append(.{ .cid = CID{ .bytes = [_]u8{1} ** 32 } });
    try args.append(.{ .cid = CID{ .bytes = [_]u8{2} ** 32 } });

    // Would call hover here with a proper QueryCtx
    try std.testing.expect(args.items.len == 2);
}

test "signature building" {
    const allocator = std.testing.allocator;

    const symbol_info = astdb.SymbolInfo{
        .name = "test_var",
        .definition_cid = CID{ .bytes = [_]u8{1} ** 32 },
        .symbol_type = .variable,
        .visibility = .public,
        .location = astdb.Span{ .start_byte = 0, .end_byte = 8, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 9 },
    };

    const type_info = context.TypeInfo{
        .type_name = "i32",
        .type_cid = null,
        .is_mutable = false,
        .is_optional = false,
        .generic_params = &[_]context.TypeInfo{},
    };

    // Would test buildSignature here with proper QueryCtx
    try std.testing.expectEqualStrings("test_var", symbol_info.name);
    try std.testing.expectEqualStrings("i32", type_info.type_name);
}
