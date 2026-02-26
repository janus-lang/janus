// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// Parser components
const Parser = @import("parser.zig");
const ParserDispatchIntegration = @import("parser_dispatch_integration.zig").ParserDispatchIntegration;

// Semantic resolution components
const TypeRegistry = @import("type_registry.zig").TypeRegistry;
const TypeId = @import("type_registry.zig").TypeId;
const ConversionRegistry = @import("conversion_registry.zig").ConversionRegistry;
const Conversion = @import("conversion_registry.zig").Conversion;
const ScopeManager = @import("scope_manager.zig").ScopeManager;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;
const SemanticResolver = @import("semantic_resolver.zig").SemanticResolver;
const CallSite = @import("semantic_resolver.zig").CallSite;
const ResolveResult = @import("semantic_resolver.zig").ResolveResult;
const DiagnosticEngine = @import("diagnostic_engine.zig").DiagnosticEngine;
const Severity = @import("diagnostic_engine.zig").Severity;

/// Bridge between parser AST and semantic resolution
pub const SemanticParserBridge = struct {
    // Core components
    type_registry: TypeRegistry,
    conversion_registry: ConversionRegistry,
    scope_manager: ScopeManager,
    semantic_resolver: SemanticResolver,
    diagnostic_engine: DiagnosticEngine,

    // Parser integration
    parser_integration: ParserDispatchIntegration,

    // State
    allocator: Allocator,
    current_module: []const u8,

    pub fn init(allocator: Allocator, module_path: []const u8) !SemanticParserBridge {
        var type_registry = TypeRegistry.init(allocator);
        var conversion_registry = ConversionRegistry.init(allocator);
        var scope_manager = try ScopeManager.init(allocator);

        // Add basic type conversions
        try addBasicConversions(&conversion_registry);

        const semantic_resolver = SemanticResolver.init(
            allocator,
            &type_registry,
            &conversion_registry,
            &scope_manager,
        );

        const diagnostic_engine = DiagnosticEngine.init(allocator);
        const parser_integration = ParserDispatchIntegration.init(allocator, module_path);

        return SemanticParserBridge{
            .type_registry = type_registry,
            .conversion_registry = conversion_registry,
            .scope_manager = scope_manager,
            .semantic_resolver = semantic_resolver,
            .diagnostic_engine = diagnostic_engine,
            .parser_integration = parser_integration,
            .allocator = allocator,
            .current_module = try allocator.dupe(u8, module_path),
        };
    }

    pub fn deinit(self: *SemanticParserBridge) void {
        self.allocator.free(self.current_module);
        self.parser_integration.deinit();
        self.semantic_resolver.deinit();
        self.scope_manager.deinit();
        self.conversion_registry.deinit();
        self.type_registry.deinit();
    }

    /// Process a complete AST from the parser
    pub fn processAST(self: *SemanticParserBridge, root: *Parser.Node) !ProcessingResult {
        var result = ProcessingResult{
            .success = true,
            .functions_processed = 0,
            .families_created = 0,
            .calls_resolved = 0,
            .diagnostics = .empty,
            .resolution_results = .empty,
        };

        // Phase 1: Extract function declarations and build dispatch families
        try self.extractFunctions(root, &result);

        // Phase 2: Resolve function calls
        try self.resolveCalls(root, &result);

        return result;
    }

    /// Extract function declarations from AST and register them
    fn extractFunctions(self: *SemanticParserBridge, node: *Parser.Node, result: *ProcessingResult) !void {
        switch (node.kind) {
            .Root => {
                // Process all dispatch families
                var current = node.right;
                while (current) |family_node| {
                    if (family_node.kind == .DispatchFamily) {
                        try self.processDispatchFamily(family_node, result);
                    }
                    current = family_node.right;
                }
            },
            .DispatchFamily => {
                try self.processDispatchFamily(node, result);
            },
            else => {
                // Recursively process children
                if (node.left) |left| try self.extractFunctions(left, result);
                if (node.right) |right| try self.extractFunctions(right, result);
            },
        }
    }

    /// Process a dispatch family node from the parser
    fn processDispatchFamily(self: *SemanticParserBridge, family_node: *Parser.Node, result: *ProcessingResult) !void {
        if (family_node.implementations == null) return;

        const implementations = family_node.implementations.?.items;
        result.families_created += 1;

        for (implementations) |impl| {
            if (impl.kind == .FunctionDecl) {
                try self.processFunctionDecl(impl, result);
            }
        }
    }

    /// Convert parser function declaration to semantic function declaration
    fn processFunctionDecl(self: *SemanticParserBridge, func_node: *Parser.Node, result: *ProcessingResult) !void {
        // Extract function information from AST node
        const func_name = func_node.text;

        // For now, use simplified type extraction
        // In a real implementation, this would parse the full function signature
        const param_types = try self.extractParameterTypes(func_node);
        defer self.allocator.free(param_types);

        const return_type = try self.extractReturnType(func_node);
        defer self.allocator.free(return_type);

        // Create semantic function declaration
        const func_decl = FunctionDecl{
            .name = func_name,
            .parameter_types = try self.allocator.dupe(u8, param_types),
            .return_type = try self.allocator.dupe(u8, return_type),
            .visibility = .public, // Default for now
            .module_path = self.current_module,
            .source_location = FunctionDecl.SourceLocation{
                .file = "parsed.jan", // Would come from parser
                .line = 1, // Would come from parser
                .column = 1, // Would come from parser
            },
        };

        // Register with scope manager
        try self.scope_manager.current_scope.addFunction(&func_decl);
        result.functions_processed += 1;

        std.debug.print("✅ Registered function: {s}({s}) -> {s}\n", .{ func_name, param_types, return_type });
    }

    /// Resolve all function calls in the AST
    fn resolveCalls(self: *SemanticParserBridge, node: *Parser.Node, result: *ProcessingResult) !void {
        switch (node.kind) {
            .CallExpr => {
                try self.resolveCallExpr(node, result);
            },
            else => {
                // Recursively process children
                if (node.left) |left| try self.resolveCalls(left, result);
                if (node.right) |right| try self.resolveCalls(right, result);

                // Process implementations in dispatch families
                if (node.implementations) |impls| {
                    for (impls.items) |impl| {
                        try self.resolveCalls(impl, result);
                    }
                }
            },
        }
    }

    /// Resolve a specific function call
    fn resolveCallExpr(self: *SemanticParserBridge, call_node: *Parser.Node, result: *ProcessingResult) !void {
        const function_name = call_node.text;

        // Extract argument types (simplified)
        const arg_types = try self.extractArgumentTypes(call_node);
        defer self.allocator.free(arg_types);

        // Create call site
        const call_site = CallSite{
            .function_name = function_name,
            .argument_types = arg_types,
            .source_location = CallSite.SourceLocation{
                .file = "parsed.jan",
                .line = 1,
                .column = 1,
                .start_byte = 0,
                .end_byte = 10,
            },
        };

        std.debug.print("🔍 Resolving call: {s}(", .{function_name});
        for (arg_types, 0..) |arg_type, i| {
            if (i > 0) std.debug.print(", ", .{});
            std.debug.print("{s}", .{self.typeIdToString(arg_type)});
        }
        std.debug.print(")\n", .{});

        // Use our 4-phase semantic resolution pipeline!
        var resolve_result = try self.semantic_resolver.resolve(call_site);
        defer resolve_result.deinit(self.allocator);

        // Process the result
        const call_result = try self.processResolveResult(resolve_result, call_site);
        try result.resolution_results.append(call_result);
        result.calls_resolved += 1;

        // Generate diagnostics if needed
        if (call_result.status != .success) {
            try self.generateCallDiagnostic(resolve_result, result);
        }
    }

    /// Process the result from semantic resolution
    fn processResolveResult(self: *SemanticParserBridge, resolve_result: ResolveResult, call_site: CallSite) !CallResolutionResult {
        _ = self;

        switch (resolve_result) {
            .success => |success| {
                std.debug.print("✅ Resolved to: {s}\n", .{success.target_function.name});
                return CallResolutionResult{
                    .status = .success,
                    .function_name = call_site.function_name,
                    .resolved_function = success.target_function.name,
                    .conversion_cost = success.conversion_path.get().total_cost,
                    .resolution_method = if (success.conversion_path.get().total_cost == 0) .exact_match else .with_conversion,
                };
            },
            .ambiguous => |ambiguous| {
                std.debug.print("⚠️  Ambiguous call - {d} candidates\n", .{ambiguous.candidates.len});
                return CallResolutionResult{
                    .status = .ambiguous,
                    .function_name = call_site.function_name,
                    .resolved_function = "",
                    .conversion_cost = 0,
                    .resolution_method = .unresolved,
                };
            },
            .no_matches => {
                std.debug.print("❌ No matches found\n", .{});
                return CallResolutionResult{
                    .status = .no_matches,
                    .function_name = call_site.function_name,
                    .resolved_function = "",
                    .conversion_cost = 0,
                    .resolution_method = .unresolved,
                };
            },
            .error_occurred => |err| {
                std.debug.print("💥 Resolution error: {s}\n", .{err.message});
                return CallResolutionResult{
                    .status = .@"error",
                    .function_name = call_site.function_name,
                    .resolved_function = "",
                    .conversion_cost = 0,
                    .resolution_method = .unresolved,
                };
            },
        }
    }

    /// Generate diagnostic information for failed resolutions
    fn generateCallDiagnostic(self: *SemanticParserBridge, resolve_result: ResolveResult, result: *ProcessingResult) !void {
        var diagnostic = try self.diagnostic_engine.generateFromResolveResult(resolve_result);
        defer diagnostic.deinit(self.allocator);

        try result.diagnostics.append(DiagnosticInfo{
            .code = try self.allocator.dupe(u8, diagnostic.code),
            .severity = diagnostic.severity,
            .message = try self.allocator.dupe(u8, diagnostic.human_message.summary),
            .file = try self.allocator.dupe(u8, diagnostic.span.file),
            .line = diagnostic.span.start_line,
            .column = diagnostic.span.start_col,
        });
    }

    // Helper methods for type extraction (simplified for now)

    fn typeIdToString(self: *SemanticParserBridge, type_id: TypeId) []const u8 {
        _ = self;
        if (type_id.equals(TypeId.I32)) return "i32";
        if (type_id.equals(TypeId.F64)) return "f64";
        if (type_id.equals(TypeId.BOOL)) return "bool";
        if (type_id.equals(TypeId.STRING)) return "string";
        return "unknown";
    }

    fn extractParameterTypes(self: *SemanticParserBridge, func_node: *Parser.Node) ![]const u8 {
        _ = func_node;
        // For Hello World example, assume no parameters
        return self.allocator.dupe(u8, "");
    }

    fn extractReturnType(self: *SemanticParserBridge, func_node: *Parser.Node) ![]const u8 {
        _ = func_node;
        // For Hello World example, assume void return
        return self.allocator.dupe(u8, "void");
    }

    fn extractArgumentTypes(self: *SemanticParserBridge, call_node: *Parser.Node) ![]TypeId {
        _ = call_node;
        // For Hello World example with print("Hello, World!"), assume string argument
        const types = try self.allocator.alloc(TypeId, 1);
        types[0] = TypeId.STRING;
        return types;
    }

    /// Add basic type conversions to the registry
    fn addBasicConversions(conversion_registry: *ConversionRegistry) !void {
        const conversions = [_]Conversion{
            Conversion{
                .from = TypeId.I32,
                .to = TypeId.F64,
                .cost = 5,
                .is_lossy = false,
                .method = .builtin_cast,
                .syntax_template = "{} as f64",
            },
            Conversion{
                .from = TypeId.F64,
                .to = TypeId.I32,
                .cost = 10,
                .is_lossy = true,
                .method = .builtin_cast,
                .syntax_template = "{} as i32",
            },
            Conversion{
                .from = TypeId.I32,
                .to = TypeId.STRING,
                .cost = 15,
                .is_lossy = false,
                .method = .builtin_cast,
                .syntax_template = "toString({})",
            },
        };

        for (conversions) |conversion| {
            try conversion_registry.registerConversion(conversion);
        }
    }

    // Result types

    pub const ProcessingResult = struct {
        success: bool,
        functions_processed: u32,
        families_created: u32,
        calls_resolved: u32,
        diagnostics: std.ArrayList(DiagnosticInfo),
        resolution_results: std.ArrayList(CallResolutionResult),

        pub fn deinit(self: *ProcessingResult, allocator: Allocator) void {
            for (self.diagnostics.items) |*diagnostic| {
                allocator.free(diagnostic.code);
                allocator.free(diagnostic.message);
                allocator.free(diagnostic.file);
            }
            self.diagnostics.deinit();
            self.resolution_results.deinit();
        }

        pub fn hasErrors(self: *const ProcessingResult) bool {
            for (self.diagnostics.items) |diagnostic| {
                if (diagnostic.severity == .@"error") return true;
            }
            return false;
        }

        pub fn getSuccessRate(self: *const ProcessingResult) f32 {
            if (self.calls_resolved == 0) return 1.0;

            var successful_calls: u32 = 0;
            for (self.resolution_results.items) |result| {
                if (result.status == .success) successful_calls += 1;
            }

            return @as(f32, @floatFromInt(successful_calls)) / @as(f32, @floatFromInt(self.calls_resolved));
        }
    };

    pub const DiagnosticInfo = struct {
        code: []const u8,
        severity: Severity,
        message: []const u8,
        file: []const u8,
        line: u32,
        column: u32,
    };

    pub const CallResolutionResult = struct {
        status: ResolutionStatus,
        function_name: []const u8,
        resolved_function: []const u8,
        conversion_cost: u32,
        resolution_method: ResolutionMethod,

        pub const ResolutionStatus = enum {
            success,
            ambiguous,
            no_matches,
            @"error",
        };

        pub const ResolutionMethod = enum {
            exact_match,
            with_conversion,
            unresolved,
        };
    };
};

// Tests
test "SemanticParserBridge basic functionality" {
    var bridge = try SemanticParserBridge.init(std.testing.allocator, "test_module");
    defer bridge.deinit();

    // Test that the bridge initializes correctly
    try std.testing.expect(bridge.scope_manager.current_scope.name.len > 0);
    try std.testing.expect(std.mem.eql(u8, bridge.current_module, "test_module"));

    std.debug.print("✅ SemanticParserBridge initialized successfully\n", .{});
}
