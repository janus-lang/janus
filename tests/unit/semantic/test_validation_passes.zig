// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Validation Passes Test Suite
//!
//! This test suite validates the multi-pass semantic validation implementation,
//! ensuring proper declaration collection, type resolution, and semantic validation.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const ValidationEngine = @import("../../../compiler/semantic/validation_engine.zig").ValidationEngine;
const ValidationContext = @import("../../../compiler/semantic/validation_engine.zig").ValidationContext;
const LanguageProfile = @import("../../../compiler/semantic/validation_engine.zig").LanguageProfile;
const TypeAnnotationMap = @import("../../../compiler/semantic/validation_engine.zig").TypeAnnotationMap;

const DeclarationCollector = @import("../../../compiler/semantic/validation_passes.zig").DeclarationCollector;
const TypeResolver = @import("../../../compiler/semantic/validation_passes.zig").TypeResolver;
const SemanticValidator = @import("../../../compiler/semantic/validation_passes.zig").SemanticValidator;

const SymbolTable = @import("../../../compiler/semantic/symbol_table.zig").SymbolTable;
const SymbolResolver = @import("../../../compiler/semantic/symbol_resolver.zig").SymbolResolver;
const TypeSystem = @import("../../../compiler/semantic/type_system.zig").TypeSystem;
const TypeInferenceEngine = @import("../../../compiler/semantic/type_inference.zig").TypeInferenceEngine;
const source_span_utils = @import("../../../compiler/semantic/source_span_utils.zig");
const module_visibility = @import("../../../compiler/semantic/module_visibility.zig");

/// Test context for validation passes
const TestValidationContext = struct {
    allocator: Allocator,
    symbol_table: SymbolTable,
    symbol_resolver: SymbolResolver,
    type_system: TypeSystem,
    type_inference: TypeInferenceEngine,
    module_registry: module_visibility.ModuleRegistry,
    validation_engine: ValidationEngine,
    type_annotations: TypeAnnotationMap,

    pub fn init(allocator: Allocator) !TestValidationContext {
        var symbol_table = try SymbolTable.init(allocator);
        var symbol_resolver = try SymbolResolver.init(allocator, &symbol_table);
        var type_system = try TypeSystem.init(allocator);
        var type_inference = try TypeInferenceEngine.init(allocator, &type_system);
        var mod_registry = module_visibility.ModuleRegistry.init(allocator);

        const validation_engine = ValidationEngine.init(
            allocator,
            &symbol_table,
            &symbol_resolver,
            &type_system,
            &type_inference,
            &module_registry,
        );

        return TestValidationContext{
            .allocator = allocator,
            .symbol_table = symbol_table,
            .symbol_resolver = symbol_resolver,
            .type_system = type_system,
            .type_inference = type_inference,
            .module_registry = module_registry,
            .validation_engine = validation_engine,
            .type_annotations = TypeAnnotationMap.init(allocator),
        };
    }

    pub fn deinit(self: *TestValidationContext) void {
        self.symbol_table.deinit();
        self.symbol_resolver.deinit();
        self.type_system.deinit();
        self.type_inference.deinit();
        self.module_registry.deinit();
        self.type_annotations.deinit();
    }
};

test "declaration collector initialization and basic operations" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var collector = DeclarationCollector.init(&test_context.validation_engine);

    // Verify collector is properly initialized
    try testing.expect(collector.validation_engine == &test_context.validation_engine);
}

test "function declaration collection" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var collector = DeclarationCollector.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    // Create a test function declaration node
    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Collect the function declaration
    try collector.collectDeclarations(&func_node, &validation_context);

    // Verify function was added to symbol table
    const symbol = test_context.symbol_table.lookupSymbol("placeholder_name");
    try testing.expect(symbol != null);

    const symbol_info = test_context.symbol_table.getSymbolInfo(symbol.?);
    try testing.expect(symbol_info.kind == .function);
}

test "variable declaration collection" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var collector = DeclarationCollector.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    // Create a test variable declaration node
    const var_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 2, .column = 1, .offset = 20 },
        .end = source_span_utils.SourcePosition{ .line = 2, .column = 15, .offset = 34 },
        .file_path = "test.jan",
    };

    var var_node = source_span_utils.AstNode{
        .kind = .variable_declaration,
        .span = var_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Collect the variable declaration
    try collector.collectDeclarations(&var_node, &validation_context);

    // Verify variable was added to symbol table
    const symbol = test_context.symbol_table.lookupSymbol("placeholder_name");
    try testing.expect(symbol != null);

    const symbol_info = test_context.symbol_table.getSymbolInfo(symbol.?);
    try testing.expect(symbol_info.kind == .variable);
}

test "type resolver initialization and basic operations" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var resolver = TypeResolver.init(&test_context.validation_engine);

    // Verify resolver is properly initialized
    try testing.expect(resolver.validation_engine == &test_context.validation_engine);
}

test "function type resolution" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    // First collect a function declaration
    var collector = DeclarationCollector.init(&test_context.validation_engine);
    var resolver = TypeResolver.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Collect then resolve
    try collector.collectDeclarations(&func_node, &validation_context);
    try resolver.resolveTypes(&func_node, &validation_context);

    // Verify function has a type
    const symbol = test_context.symbol_table.lookupSymbol("placeholder_name");
    try testing.expect(symbol != null);

    const symbol_info = test_context.symbol_table.getSymbolInfo(symbol.?);
    try testing.expect(!symbol_info.type_id.eql(@import("../../../compiler/semantic/type_system.zig").TypeId{ .id = 0 }));

    // Verify AST node is annotated with type
    const node_type = validation_context.getAnnotatedType(&func_node);
    try testing.expect(node_type != null);
}

test "semantic validator initialization and basic operations" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var validator = SemanticValidator.init(&test_context.validation_engine);

    // Verify validator is properly initialized
    try testing.expect(validator.validation_engine == &test_context.validation_engine);
}

test "function semantic validation" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var validator = SemanticValidator.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    // Create a function node with body
    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    const body_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 2, .column = 1, .offset = 20 },
        .end = source_span_utils.SourcePosition{ .line = 4, .column = 1, .offset = 80 },
        .file_path = "test.jan",
    };

    var body_node = source_span_utils.AstNode{
        .kind = .statement,
        .span = body_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    const children = [_]*const source_span_utils.AstNode{&body_node};

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &children,
    };

    // Validate the function
    try validator.validateSemantics(&func_node, &validation_context);

    // Should not have errors for a valid function with body
    try testing.expect(validation_context.errors.items.len == 0);
}

test "empty function validation error" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var validator = SemanticValidator.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    // Create an empty function node
    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 1, .column = 20, .offset = 19 },
        .file_path = "test.jan",
    };

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Validate the empty function
    try validator.validateSemantics(&func_node, &validation_context);

    // Should have an error for empty function body
    try testing.expect(validation_context.errors.items.len == 1);
    try testing.expect(validation_context.errors.items[0].kind == .missing_return);
}

test "profile violation detection in declaration collection" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var collector = DeclarationCollector.init(&test_context.validation_engine);

    // Use minimal profile that restricts advanced features
    var validation_context = ValidationContext.init(allocator, .core, &test_context.type_annotations);
    defer validation_context.deinit();

    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    // Functions should be allowed in min profile
    try collector.collectDeclarations(&func_node, &validation_context);

    // Should not have profile violation errors for basic functions
    try testing.expect(validation_context.errors.items.len == 0);
}

test "multi-pass validation integration" {
    const allocator = testing.allocator;

    var test_context = try TestValidationContext.init(allocator);
    defer test_context.deinit();

    var collector = DeclarationCollector.init(&test_context.validation_engine);
    var resolver = TypeResolver.init(&test_context.validation_engine);
    var validator = SemanticValidator.init(&test_context.validation_engine);

    var validation_context = ValidationContext.init(allocator, .sovereign, &test_context.type_annotations);
    defer validation_context.deinit();

    // Create a complete function with body
    const func_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 1, .column = 1, .offset = 0 },
        .end = source_span_utils.SourcePosition{ .line = 5, .column = 1, .offset = 100 },
        .file_path = "test.jan",
    };

    const return_span = source_span_utils.SourceSpan{
        .start = source_span_utils.SourcePosition{ .line = 3, .column = 5, .offset = 50 },
        .end = source_span_utils.SourcePosition{ .line = 3, .column = 15, .offset = 60 },
        .file_path = "test.jan",
    };

    var return_node = source_span_utils.AstNode{
        .kind = .return_statement,
        .span = return_span,
        .children = &[_]*const source_span_utils.AstNode{},
    };

    const children = [_]*const source_span_utils.AstNode{&return_node};

    var func_node = source_span_utils.AstNode{
        .kind = .function_declaration,
        .span = func_span,
        .children = &children,
    };

    // Run all three passes
    try collector.collectDeclarations(&func_node, &validation_context);
    try resolver.resolveTypes(&func_node, &validation_context);
    try validator.validateSemantics(&func_node, &validation_context);

    // Verify symbol was created and typed
    const symbol = test_context.symbol_table.lookupSymbol("placeholder_name");
    try testing.expect(symbol != null);

    const symbol_info = test_context.symbol_table.getSymbolInfo(symbol.?);
    try testing.expect(symbol_info.kind == .function);
    try testing.expect(!symbol_info.type_id.eql(@import("../../../compiler/semantic/type_system.zig").TypeId{ .id = 0 }));

    // Verify AST annotations
    const func_type = validation_context.getAnnotatedType(&func_node);
    try testing.expect(func_type != null);

    // Should have no validation errors for complete function
    try testing.expect(validation_context.errors.items.len == 0);
}
