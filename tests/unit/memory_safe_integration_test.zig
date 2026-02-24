// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const TypeRegistry = @import("compiler/libjanus/type_registry.zig").TypeRegistry;
const TypeId = @import("compiler/libjanus/type_registry.zig").TypeId;
const ConversionRegistry = @import("compiler/libjanus/conversion_registry.zig").ConversionRegistry;
const Conversion = @import("compiler/libjanus/conversion_registry.zig").Conversion;
const ScopeManager = @import("compiler/libjanus/scope_manager.zig").ScopeManager;
const FunctionDecl = @import("compiler/libjanus/scope_manager.zig").FunctionDecl;
const SemanticResolver = @import("compiler/libjanus/semantic_resolver.zig").SemanticResolver;
const CallSite = @import("compiler/libjanus/semantic_resolver.zig").CallSite;
const ScopedConversionPath = @import("compiler/libjanus/scoped_conversion_path.zig").ScopedConversionPath;

test "Memory-safe exact match resolution" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );
    defer resolver.deinit();

    // Add a simple function
    const add_func = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&add_func);

    // Test exact match resolution
    const call_site = CallSite{
        .function_name = "add",
        .argument_types = &[_]TypeId{ TypeId.I32, TypeId.I32 },
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 5,
            .column = 10,
            .start_byte = 100,
            .end_byte = 110,
        },
    };

    var result = try resolver.resolve(call_site);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .success => |success| {
            try std.testing.expectEqualStrings(success.target_function.name, "add");
            try std.testing.expect(success.conversion_path.get().total_cost == 0);
        },
        else => {
            try std.testing.expect(false); // Should have succeeded
        },
    }
}

test "Memory-safe conversion resolution" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Add i32 -> f64 conversion
    const i32_to_f64 = Conversion{
        .from = TypeId.I32,
        .to = TypeId.F64,
        .cost = 5,
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{} as f64",
    };
    try conversion_registry.registerConversion(i32_to_f64);

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );
    defer resolver.deinit();

    // Add a function that takes f64
    const sqrt_func = FunctionDecl{
        .name = "sqrt",
        .parameter_types = "f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 1,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&sqrt_func);

    // Call with i32 (requires conversion)
    const call_site = CallSite{
        .function_name = "sqrt",
        .argument_types = &[_]TypeId{TypeId.I32},
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 10,
            .column = 5,
            .start_byte = 200,
            .end_byte = 210,
        },
    };

    var result = try resolver.resolve(call_site);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .success => |success| {
            try std.testing.expectEqualStrings(success.target_function.name, "sqrt");
            try std.testing.expect(success.conversion_path.get().total_cost == 5);
        },
        else => {
            try std.testing.expect(false); // Should have succeeded with conversion
        },
    }
}

test "Memory-safe no match resolution" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );
    defer resolver.deinit();

    // Don't add any functions

    // Try to call non-existent function
    const call_site = CallSite{
        .function_name = "nonexistent",
        .argument_types = &[_]TypeId{TypeId.I32},
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 15,
            .column = 8,
            .start_byte = 300,
            .end_byte = 315,
        },
    };

    var result = try resolver.resolve(call_site);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .no_matches => |no_matches| {
            try std.testing.expectEqualStrings(no_matches.function_name, "nonexistent");
        },
        else => {
            try std.testing.expect(false); // Should not find function
        },
    }
}

test "ScopedConversionPath RAII safety" {
    // Test that scoped paths clean up properly
    var scoped = ScopedConversionPath.owned(std.testing.allocator);
    defer scoped.deinit();

    // Test cloning
    var cloned = try scoped.clone(std.testing.allocator);
    defer cloned.deinit();

    // Test view (non-owning)
    var view = ScopedConversionPath.view(scoped.get());
    defer view.deinit(); // Safe to call, won't double-free

}
