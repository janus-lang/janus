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

test "Debug: Check if functions are found" {
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

    // Add two functions with same name but different signatures
    const add_func1 = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 1,
            .column = 1,
        },
    };

    const add_func2 = FunctionDecl{
        .name = "add",
        .parameter_types = "f64,i32",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 5,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&add_func1);
    try scope_manager.current_scope.addFunction(&add_func2);


    // Try to call with exact match first
    const call_site_exact = CallSite{
        .function_name = "add",
        .argument_types = &[_]TypeId{ TypeId.I32, TypeId.F64 }, // Exact match for first function
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 10,
            .column = 5,
            .start_byte = 200,
            .end_byte = 215,
        },
    };

    var result_exact = try resolver.resolve(call_site_exact);
    defer result_exact.deinit(std.testing.allocator);

    switch (result_exact) {
        .success => |success| {
        },
        .no_matches => {
        },
        .ambiguous => {
        },
        else => {
        },
    }
}

test "Debug: Check conversion path finding" {
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

    // Test conversion path finding
    const from_types = [_]TypeId{TypeId.I32};
    const to_types = [_]TypeId{TypeId.F64};

    var path = try conversion_registry.findConversionPath(from_types[0..], to_types[0..], std.testing.allocator);
    if (path) |*p| {
        defer p.deinit();
    } else {
    }
}
