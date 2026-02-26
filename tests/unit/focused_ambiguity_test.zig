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

test "Focused ambiguity test with conversions" {

    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Add conversions with equal costs
    const i32_to_f64 = Conversion{
        .from = TypeId.I32,
        .to = TypeId.F64,
        .cost = 5,
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{} as f64",
    };
    const f64_to_i32 = Conversion{
        .from = TypeId.F64,
        .to = TypeId.I32,
        .cost = 5, // Same cost
        .is_lossy = true,
        .method = .builtin_cast,
        .syntax_template = "{} as i32",
    };
    try conversion_registry.registerConversion(i32_to_f64);
    try conversion_registry.registerConversion(f64_to_i32);

    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var resolver = SemanticResolver.init(
        std.testing.allocator,
        &type_registry,
        &conversion_registry,
        &scope_manager,
    );
    defer resolver.deinit();

    // Add two functions that will be ambiguous when called with (i32, i32)
    const add_func1 = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,f64", // Needs conversion: (i32,i32) -> (i32,f64) cost=5
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
        .parameter_types = "f64,i32", // Needs conversion: (i32,i32) -> (f64,i32) cost=5
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

    // Call with (i32, i32) - should be ambiguous
    const call_site = CallSite{
        .function_name = "add",
        .argument_types = &[_]TypeId{ TypeId.I32, TypeId.I32 },
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 10,
            .column = 5,
            .start_byte = 200,
            .end_byte = 215,
        },
    };


    var result = try resolver.resolve(call_site);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .success => |success| {
            try std.testing.expect(false);
        },
        .ambiguous => |ambiguous| {
            for (ambiguous.candidates, 0..) |candidate, i| {
            }
        },
        .no_matches => |no_matches| {
            try std.testing.expect(false);
        },
        .error_occurred => |err| {
            try std.testing.expect(false);
        },
    }

}
