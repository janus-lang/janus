// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! TODO Liability Elimination Test Suite
//!
//! This test suite validates the complete implementation of functions
//! that were previously marked as TODO liabilities.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

const source_span_utils = @import("../../../compiler/semantic/source_span_utils.zig");
const module_visibility = @import("../../../compiler/semantic/module_visibility.zig");

const SourceSpan = source_span_utils.SourceSpan;
const SourcePosition = sourils.SourcePosition;
const AstNode = source_span_utils.AstNode;
const getNodeSpan = source_span_utils.getNodeSpan;
const SourceSpanTracker = source_span_utils.SourceSpanTracker;

const ModuleRegistry = module_visibility.ModuleRegistry;
const ModuleId = module_visibility.ModuleId;
const Visibility = module_visibility.Visibility;
const isInSameModule = module_visibility.isInSameModule;
const isSymbolAccessible = module_visibility.isSymbolAccessible;

test "getNodeSpan implementation completeness" {
    // Test that getNodeSpan function is fully implemented and functional

    const test_span = SourceSpan{
        .start = SourcePosition{ .line = 5, .column = 10, .offset = 100 },
        .end = SourcePosition{ .line = 5, .column = 25, .offset = 115 },
        .file_path = "src/main.jan",
    };

    const test_node = AstNode{
        .kind = .function_declaration,
        .span = test_span,
        .children = &[_]*const AstNode{},
    };

    // Call getNodeSpan - should return complete span information
    const retrieved_span = getNodeSpan(&test_node);

    // Verify all span components are correctly returned
    try testing.expect(retrieved_span.start.line == 5);
    try testing.expect(retrieved_span.start.column == 10);
    try testing.expect(retrieved_span.start.offset == 100);
    try testing.expect(retrieved_span.end.line == 5);
    try testing.expect(retrieved_span.end.column == 25);
    try testing.expect(retrieved_span.end.offset == 115);
    try testing.expectEqualStrings(retrieved_span.file_path, "src/main.jan");

    // Verify span operations work correctly
    try testing.expect(retrieved_span.length() == 15);
}

test "isInSameModule implementation completeness" {
    const allocator = testing.allocator;

    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    // Register test modules
    const module1 = try registry.registerModule("core", "src/core.jan", "janus.core");
    const module2 = try registry.registerModule("utils", "src/utils.jan", "janus.core");
    const module3 = try registry.registerModule("main", "src/main.jan", "janus.app");

    // Test same module detection
    try testing.expect(isInSameModule(&registry, module1, module1));

    // Test different module detection
    try testing.expect(!isInSameModule(&registry, module1, module2));
    try testing.expect(!isInSameModule(&registry, module1, module3));
    try testing.expect(!isInSameModule(&registry, module2, module3));

    // Test with invalid module IDs (should handle gracefully)
    const invalid_module = ModuleId{ .id = 999 };
    try testing.expect(!isInSameModule(&registry, module1, invalid_module));
}

test "source span tracking accuracy" {
    const allocator = testing.allocator;

    // Test with realistic source code
    const source_code =
        \\function fibonacci(n: i32) -> i32 {
        \\    if (n <= 1) {
        \\        return n;
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2);
        \\}
    ;

    var tracker = try SourceSpanTracker.init(allocator, "fibonacci.jan", source_code);
    defer tracker.deinit();

    // Test function keyword span
    const func_span = tracker.createSpan(0, 8); // "function"
    try testing.expect(func_span.start.line == 1);
    try testing.expect(func_span.start.column == 1);
    try testing.expect(func_span.end.column == 9);

    // Test identifier span
    const name_start = std.mem.indexOf(u8, source_code, "fibonacci").?;
    const name_span = tracker.createSpan(@intCast(name_start), @intCast(name_start + 9));
    try testing.expect(name_span.start.line == 1);
    try testing.expect(name_span.start.column == 10);

    // Test multi-line span
    const return_pos = std.mem.indexOf(u8, source_code, "return fibonacci").?;
    const end_pos = std.mem.indexOf(u8, source_code, "- 2);").? + 5;
    const return_span = tracker.createSpan(@intCast(return_pos), @intCast(end_pos));
    try testing.expect(return_span.start.line == 5);
    try testing.expect(return_span.end.line == 5);

    // Test span text extraction
    const func_text = source_span_utils.getSpanText(func_span, source_code);
    try testing.expectEqualStrings("function", func_text);
}

test "module visibility cross-package access" {
    const allocator = testing.allocator;

    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    // Create modules in different packages
    const core_module = try registry.registerModule("core", "janus/core/core.jan", "janus.core");
    const std_module = try registry.registerModule("std", "janus/std/std.jan", "janus.std");
    const app_module = try registry.registerModule("app", "myapp/main.jan", "myapp");

    // Test private symbol access (only same module)
    try testing.expect(isSymbolAccessible(&registry, core_module, .private, core_module));
    try testing.expect(!isSymbolAccessible(&registry, core_module, .private, std_module));
    try testing.expect(!isSymbolAccessible(&registry, core_module, .private, app_module));

    // Test internal symbol access (same package)
    const internal_core = try registry.registerModule("internal", "janus/core/internal.jan", "janus.core");
    try testing.expect(isSymbolAccessible(&registry, core_module, .internal, internal_core));
    try testing.expect(!isSymbolAccessible(&registry, core_module, .internal, std_module));
    try testing.expect(!isSymbolAccessible(&registry, core_module, .internal, app_module));

    // Test public symbol access (everywhere)
    try testing.expect(isSymbolAccessible(&registry, core_module, .public, std_module));
    try testing.expect(isSymbolAccessible(&registry, core_module, .public, app_module));
    try testing.expect(isSymbolAccessible(&registry, std_module, .public, app_module));
}

test "comprehensive span operations" {
    const allocator = testing.allocator;

    const source = "let result = calculate(x, y);";

    var tracker = try SourceSpanTracker.init(allocator, "test.jan", source);
    defer tracker.deinit();

    // Create spans for different parts
    const let_span = tracker.createSpan(0, 3);
    const identifier_span = tracker.createSpan(4, 10);
    const call_span = tracker.createSpan(13, 28);

    // Test span containment
    const full_span = tracker.createSpan(0, 29);
    try testing.expect(full_span.contains(let_span));
    try testing.expect(full_span.contains(identifier_span));
    try testing.expect(full_span.contains(call_span));

    // Test span lengths
    try testing.expect(let_span.length() == 3);
    try testing.expect(identifier_span.length() == 6);
    try testing.expect(call_span.length() == 15);

    // Test diagnostic message creation
    const diagnostic = try source_span_utils.createDiagnosticWithContext(allocator, identifier_span, source, "undefined variable");
    defer allocator.free(diagnostic);

    try testing.expect(std.mem.indexOf(u8, diagnostic, "undefined variable") != null);
    try testing.expect(std.mem.indexOf(u8, diagnostic, "result") != null);
    try testing.expect(std.mem.indexOf(u8, diagnostic, "test.jan") != null);
}

test "module import and export validation" {
    const allocator = testing.allocator;

    var registry = ModuleRegistry.init(allocator);
    defer registry.deinit();

    const math_module = try registry.registerModule("math", "lib/math.jan", "stdlib");
    const app_module = try registry.registerModule("app", "src/main.jan", "myapp");

    // Add import relationship
    try registry.addImport(app_module, math_module);

    // Verify import relationship
    try testing.expect(module_visibility.doesModuleImport(&registry, app_module, math_module));
    try testing.expect(!module_visibility.doesModuleImport(&registry, math_module, app_module));

    // Add exports to math module
    try registry.addExport(math_module, "sqrt", .public, 1);
    try registry.addExport(math_module, "internal_helper", .internal, 2);
    try registry.addExport(math_module, "private_impl", .private, 3);

    // Verify exports
    const exports = module_visibility.getExportedSymbols(&registry, math_module, .public);
    try testing.expect(exports.len >= 3);

    // Find specific exports
    var found_sqrt = false;
    var found_internal = false;
    var found_private = false;

    for (exports) |export_info| {
        if (std.mem.eql(u8, export_info.name, "sqrt")) {
            found_sqrt = true;
            try testing.expect(export_info.visibility == .public);
        } else if (std.mem.eql(u8, export_info.name, "internal_helper")) {
            found_internal = true;
            try testing.expect(export_info.visibility == .internal);
        } else if (std.mem.eql(u8, export_info.name, "private_impl")) {
            found_private = true;
            try testing.expect(export_info.visibility == .private);
        }
    }

    try testing.expect(found_sqrt);
    try testing.expect(found_internal);
    try testing.expect(found_private);
}

test "edge cases and error handling" {
    const allocator = testing.allocator;

    // Test empty source span tracking
    var empty_tracker = try SourceSpanTracker.init(allocator, "empty.jan", "");
    defer empty_tracker.deinit();

    const empty_span = empty_tracker.createSpan(0, 0);
    try testing.expect(empty_span.length() == 0);

    // Test invalid span text extraction
    const invalid_span = SourceSpan{
        .start = SourcePosition{ .line = 1, .column = 1, .offset = 100 },
        .end = SourcePosition{ .line = 1, .column = 1, .offset = 200 },
        .file_path = "test.jan",
    };

    const empty_text = source_span_utils.getSpanText(invalid_span, "short text");
    try testing.expectEqualStrings("", empty_text);

    // Test module registry with no modules
    var empty_registry = ModuleRegistry.init(allocator);
    defer empty_registry.deinit();

    const invalid_module = ModuleId{ .id = 999 };
    try testing.expect(!isInSameModule(&empty_registry, invalid_module, invalid_module));

    const no_module = empty_registry.getModule(invalid_module);
    try testing.expect(no_module == null);

    const no_path_module = empty_registry.getModuleByPath("nonexistent.jan");
    try testing.expect(no_path_module == null);
}
