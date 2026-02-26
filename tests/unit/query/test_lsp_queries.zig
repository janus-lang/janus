// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Unit Test: LSP-Focused Query Implementation
// Task 2.4: NodeAt, DefOf, RefsOf, TypeOf, Diag queries for VSCode integration

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;

// Source position for LSP queries
const SourcePosition = struct {
    line: u32,
    column: u32,
    byte_offset: u32,
};

// Source span for ranges
const SourceSpan = struct {
    start: SourcePosition,
    end: SourcePosition,
};

// AST node types for query results
const NodeType = enum {
    function_declaration,
    function_call,
    variable_declaration,
    identifier,
    literal,
    block,
    return_statement,
};

// AST node representation
const ASTNode = struct {
    id: u32,
    node_type: NodeType,
    span: SourceSpan,
    name: ?[]const u8, // For named nodes (functions, variables)
    parent_id: ?u32,
    children: []const u32,
};

// Type information for hover
const TypeInfo = struct {
    name: []const u8,
    kind: TypeKind,
    documentation: ?[]const u8,

    const TypeKind = enum {
        primitive,
        function,
        struct_type,
        array,
        unknown,
    };
};

// Symbol definition information
const DefinitionInfo = struct {
    node_id: u32,
    span: SourceSpan,
    file_path: []const u8,
    symbol_name: []const u8,
};

// Reference information
const ReferenceInfo = struct {
    node_id: u32,
    span: SourceSpan,
    file_path: []const u8,
    reference_type: ReferenceType,

    const ReferenceType = enum {
        definition,
        usage,
        call,
    };
};

// Diagnostic information
const DiagnosticInfo = struct {
    span: SourceSpan,
    severity: Severity,
    code: []const u8,
    message: []const u8,
    suggestion: ?[]const u8,

    const Severity = enum {
        err,
        warning,
        info,
        hint,
    };
};

// LSP Query Engine
const LSPQueryEngine = struct {
    allocator: std.mem.Allocator,
    nodes: std.ArrayList(ASTNode),
    source_text: []const u8,

    pub fn init(allocator: std.mem.Allocator, source_text: []const u8) LSPQueryEngine {
        return LSPQueryEngine{
            .allocator = allocator,
            .nodes = std.ArrayList(ASTNode){},
            .source_text = source_text,
        };
    }

    pub fn deinit(self: *LSPQueryEngine) void {
        self.nodes.deinit(self.allocator);
    }

    // Add a node to the AST (for testing)
    pub fn addNode(self: *LSPQueryEngine, node: ASTNode) !void {
        try self.nodes.append(node);
    }

    // NodeAt query: Find AST node at specific position (innermost node)
    pub fn nodeAt(self: *const LSPQueryEngine, position: SourcePosition) ?ASTNode {
        var best_node: ?ASTNode = null;
        var best_span_size: u32 = std.math.maxInt(u32);

        for (self.nodes.items) |node| {
            if (self.positionInSpan(position, node.span)) {
                const span_size = node.span.end.byte_offset - node.span.start.byte_offset;
                if (span_size < best_span_size) {
                    best_node = node;
                    best_span_size = span_size;
                }
            }
        }

        return best_node;
    }

    // TypeOf query: Get type information for a node
    pub fn typeOf(self: *const LSPQueryEngine, node_id: u32) ?TypeInfo {
        const node = self.findNodeById(node_id) orelse return null;

        return switch (node.node_type) {
            .function_declaration => TypeInfo{
                .name = "function",
                .kind = .function,
                .documentation = "User-defined function",
            },
            .variable_declaration => TypeInfo{
                .name = "var",
                .kind = .unknown,
                .documentation = "Variable declaration",
            },
            .identifier => TypeInfo{
                .name = "identifier",
                .kind = .unknown,
                .documentation = "Symbol reference",
            },
            .literal => TypeInfo{
                .name = "literal",
                .kind = .primitive,
                .documentation = "Literal value",
            },
            .function_call => TypeInfo{
                .name = "call",
                .kind = .function,
                .documentation = "Function call expression",
            },
            else => TypeInfo{
                .name = "unknown",
                .kind = .unknown,
                .documentation = null,
            },
        };
    }

    // DefOf query: Find definition of symbol at position
    pub fn defOf(self: *const LSPQueryEngine, position: SourcePosition) ?DefinitionInfo {
        const node = self.nodeAt(position) orelse return null;

        // For identifiers, find the corresponding declaration
        if (node.node_type == .identifier) {
            const symbol_name = node.name orelse return null;

            // Find declaration with matching name
            for (self.nodes.items) |decl_node| {
                if ((decl_node.node_type == .function_declaration or
                    decl_node.node_type == .variable_declaration) and
                    decl_node.name != null and
                    std.mem.eql(u8, decl_node.name.?, symbol_name))
                {
                    return DefinitionInfo{
                        .node_id = decl_node.id,
                        .span = decl_node.span,
                        .file_path = "test.jan", // Mock file path
                        .symbol_name = symbol_name,
                    };
                }
            }
        }

        return null;
    }

    // RefsOf query: Find all references to a symbol
    pub fn refsOf(self: *const LSPQueryEngine, node_id: u32) ![]ReferenceInfo {
        const target_node = self.findNodeById(node_id) orelse return &[_]ReferenceInfo{};
        const symbol_name = target_node.name orelse return &[_]ReferenceInfo{};

        var references = std.ArrayList(ReferenceInfo){};

        for (self.nodes.items) |node| {
            if (node.name != null and std.mem.eql(u8, node.name.?, symbol_name)) {
                const ref_type: ReferenceInfo.ReferenceType = switch (node.node_type) {
                    .function_declaration, .variable_declaration => .definition,
                    .function_call => .call,
                    .identifier => .usage,
                    else => continue,
                };

                try references.append(self.allocator, ReferenceInfo{
                    .node_id = node.id,
                    .span = node.span,
                    .file_path = "test.jan",
                    .reference_type = ref_type,
                });
            }
        }

        return references.toOwnedSlice();
    }

    // Diag query: Get diagnostics for the source
    pub fn diag(self: *const LSPQueryEngine) ![]DiagnosticInfo {
        var diagnostics = std.ArrayList(DiagnosticInfo){};

        // Example diagnostic: unused variables
        for (self.nodes.items) |node| {
            if (node.node_type == .variable_declaration) {
                const var_name = node.name orelse continue;

                // Check if variable is used
                var is_used = false;
                for (self.nodes.items) |other_node| {
                    if (other_node.id != node.id and
                        other_node.node_type == .identifier and
                        other_node.name != null and
                        std.mem.eql(u8, other_node.name.?, var_name))
                    {
                        is_used = true;
                        break;
                    }
                }

                if (!is_used) {
                    try diagnostics.append(self.allocator, DiagnosticInfo{
                        .span = node.span,
                        .severity = .warning,
                        .code = "unused_variable",
                        .message = "Variable is declared but never used",
                        .suggestion = "Remove unused variable or use it in the code",
                    });
                }
            }
        }

        return diagnostics.toOwnedSlice();
    }

    // Helper functions
    fn positionInSpan(self: *const LSPQueryEngine, position: SourcePosition, span: SourceSpan) bool {
        _ = self;
        return position.byte_offset >= span.start.byte_offset and
            position.byte_offset <= span.end.byte_offset;
    }

    fn findNodeById(self: *const LSPQueryEngine, node_id: u32) ?ASTNode {
        for (self.nodes.items) |node| {
            if (node.id == node_id) return node;
        }
        return null;
    }
};

test "NodeAt query finds correct node at position" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "func main() { print(\"hello\"); }";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    // Add test nodes
    try engine.addNode(ASTNode{
        .id = 1,
        .node_type = .function_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
            .end = SourcePosition{ .line = 1, .column = 32, .byte_offset = 31 },
        },
        .name = "main",
        .parent_id = null,
        .children = &[_]u32{2},
    });

    try engine.addNode(ASTNode{
        .id = 2,
        .node_type = .function_call,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 15, .byte_offset = 14 },
            .end = SourcePosition{ .line = 1, .column = 29, .byte_offset = 28 },
        },
        .name = "print",
        .parent_id = 1,
        .children = &[_]u32{},
    });

    // Test NodeAt query
    const position = SourcePosition{ .line = 1, .column = 20, .byte_offset = 19 };
    const node = engine.nodeAt(position);

    try testing.expect(node != null);
    try testing.expectEqual(@as(u32, 2), node.?.id);
    try testing.expectEqual(NodeType.function_call, node.?.node_type);
    try testing.expect(std.mem.eql(u8, "print", node.?.name.?));
}

test "TypeOf query returns correct type information" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "func add(x, y) { return x + y; }";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    try engine.addNode(ASTNode{
        .id = 1,
        .node_type = .function_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
            .end = SourcePosition{ .line = 1, .column = 33, .byte_offset = 32 },
        },
        .name = "add",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Test TypeOf query
    const type_info = engine.typeOf(1);

    try testing.expect(type_info != null);
    try testing.expect(std.mem.eql(u8, "function", type_info.?.name));
    try testing.expectEqual(TypeInfo.TypeKind.function, type_info.?.kind);
    try testing.expect(type_info.?.documentation != null);
}

test "DefOf query finds symbol definition" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "var x = 42; print(x);";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    // Variable declaration
    try engine.addNode(ASTNode{
        .id = 1,
        .node_type = .variable_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
            .end = SourcePosition{ .line = 1, .column = 11, .byte_offset = 10 },
        },
        .name = "x",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Variable usage
    try engine.addNode(ASTNode{
        .id = 2,
        .node_type = .identifier,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 19, .byte_offset = 18 },
            .end = SourcePosition{ .line = 1, .column = 20, .byte_offset = 19 },
        },
        .name = "x",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Test DefOf query on the identifier
    const position = SourcePosition{ .line = 1, .column = 19, .byte_offset = 18 };
    const def_info = engine.defOf(position);

    try testing.expect(def_info != null);
    try testing.expectEqual(@as(u32, 1), def_info.?.node_id);
    try testing.expect(std.mem.eql(u8, "x", def_info.?.symbol_name));
    try testing.expect(std.mem.eql(u8, "test.jan", def_info.?.file_path));
}

test "RefsOf query finds all symbol references" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "func foo() {} foo(); foo();";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    // Function declaration
    try engine.addNode(ASTNode{
        .id = 1,
        .node_type = .function_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
            .end = SourcePosition{ .line = 1, .column = 13, .byte_offset = 12 },
        },
        .name = "foo",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // First function call
    try engine.addNode(ASTNode{
        .id = 2,
        .node_type = .function_call,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 15, .byte_offset = 14 },
            .end = SourcePosition{ .line = 1, .column = 20, .byte_offset = 19 },
        },
        .name = "foo",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Second function call
    try engine.addNode(ASTNode{
        .id = 3,
        .node_type = .function_call,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 22, .byte_offset = 21 },
            .end = SourcePosition{ .line = 1, .column = 27, .byte_offset = 26 },
        },
        .name = "foo",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Test RefsOf query
    const refs = try engine.refsOf(1);
    defer allocator.free(refs);

    try testing.expectEqual(@as(usize, 3), refs.len);

    // Check reference types
    try testing.expectEqual(ReferenceInfo.ReferenceType.definition, refs[0].reference_type);
    try testing.expectEqual(ReferenceInfo.ReferenceType.call, refs[1].reference_type);
    try testing.expectEqual(ReferenceInfo.ReferenceType.call, refs[2].reference_type);
}

test "Diag query detects unused variables" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "var unused = 42; var used = 10; print(used);";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    // Unused variable
    try engine.addNode(ASTNode{
        .id = 1,
        .node_type = .variable_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
            .end = SourcePosition{ .line = 1, .column = 16, .byte_offset = 15 },
        },
        .name = "unused",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Used variable declaration
    try engine.addNode(ASTNode{
        .id = 2,
        .node_type = .variable_declaration,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 18, .byte_offset = 17 },
            .end = SourcePosition{ .line = 1, .column = 31, .byte_offset = 30 },
        },
        .name = "used",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Variable usage
    try engine.addNode(ASTNode{
        .id = 3,
        .node_type = .identifier,
        .span = SourceSpan{
            .start = SourcePosition{ .line = 1, .column = 39, .byte_offset = 38 },
            .end = SourcePosition{ .line = 1, .column = 43, .byte_offset = 42 },
        },
        .name = "used",
        .parent_id = null,
        .children = &[_]u32{},
    });

    // Test Diag query
    const diagnostics = try engine.diag();
    defer allocator.free(diagnostics);

    try testing.expectEqual(@as(usize, 1), diagnostics.len);
    try testing.expectEqual(DiagnosticInfo.Severity.warning, diagnostics[0].severity);
    try testing.expect(std.mem.eql(u8, "unused_variable", diagnostics[0].code));
    try testing.expect(std.mem.indexOf(u8, diagnostics[0].message, "never used") != null);
}

test "LSP queries performance within latency targets" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const source = "func main() { var x = 42; print(x); }";
    var engine = LSPQueryEngine.init(allocator, source);
    defer engine.deinit();

    // Add multiple nodes to simulate a larger AST
    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        try engine.addNode(ASTNode{
            .id = i,
            .node_type = .identifier,
            .span = SourceSpan{
                .start = SourcePosition{ .line = 1, .column = 1, .byte_offset = 0 },
                .end = SourcePosition{ .line = 1, .column = 10, .byte_offset = 9 },
            },
            .name = "test_symbol",
            .parent_id = null,
            .children = &[_]u32{},
        });
    }

    const start_time = compat_time.nanoTimestamp();

    // Perform multiple queries
    const position = SourcePosition{ .line = 1, .column = 5, .byte_offset = 4 };
    _ = engine.nodeAt(position);
    _ = engine.typeOf(100);
    _ = engine.defOf(position);

    const refs = try engine.refsOf(100);
    defer allocator.free(refs);

    const diagnostics = try engine.diag();
    defer allocator.free(diagnostics);

    const end_time = compat_time.nanoTimestamp();
    const duration_ms = @as(f64, @floatFromInt(end_time - start_time)) / 1_000_000.0;

    // Should complete within 10ms for 1000 nodes
    try testing.expect(duration_ms < 10.0);
}
