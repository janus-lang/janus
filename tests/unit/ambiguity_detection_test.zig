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
const DiagnosticEngine = @import("compiler/libjanus/diagnostic_engine.zig").DiagnosticEngine;

test "Ambiguity detection with equal conversion costs" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Add conversions: i32 -> f64 (cost 5) and f64 -> i32 (cost 5)
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
        .cost = 5, // Same cost - creates ambiguity
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

    // Add two ambiguous functions
    const add_func1 = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,f64", // i32 + f64
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
        .parameter_types = "f64,i32", // f64 + i32
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

    // Call with (i32, i32) - both functions require one conversion with equal cost
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
        .ambiguous => {
            std.debug.print("✅ Ambiguity correctly detected!\n", .{});
        },
        .success => |success| {
            std.debug.print("❌ Expected ambiguity but got success: {s}\n", .{success.target_function.name});
            try std.testing.expect(false);
        },
        else => {
            std.debug.print("❌ Expected ambiguity but got other result\n", .{});
            try std.testing.expect(false);
        },
    }
}

test "No ambiguity with different conversion costs" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Add conversions with different costs
    const i32_to_f64 = Conversion{
        .from = TypeId.I32,
        .to = TypeId.F64,
        .cost = 3, // Lower cost - should be preferred
        .is_lossy = false,
        .method = .builtin_cast,
        .syntax_template = "{} as f64",
    };
    const f64_to_i32 = Conversion{
        .from = TypeId.F64,
        .to = TypeId.I32,
        .cost = 8, // Higher cost
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

    // Add two functions with different conversion requirements
    const add_func1 = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,f64", // Requires i32->f64 conversion (cost 3)
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
        .parameter_types = "f64,i32", // Requires f64->i32 conversion (cost 8)
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

    // Call with (i32, i32) - first function should win due to lower conversion cost
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
            try std.testing.expectEqualStrings(success.target_function.parameter_types, "i32,f64");
            try std.testing.expect(success.conversion_path.get().total_cost == 3);
            std.debug.print("✅ Correctly resolved to lower-cost function!\n", .{});
        },
        .ambiguous => {
            std.debug.print("❌ Unexpected ambiguity - should have resolved to lower cost function\n", .{});
            try std.testing.expect(false);
        },
        else => {
            std.debug.print("❌ Expected success but got other result\n", .{});
            try std.testing.expect(false);
        },
    }
}

test "Ambiguity diagnostic generation" {
    var type_registry = TypeRegistry.init(std.testing.allocator);
    defer type_registry.deinit();

    var conversion_registry = ConversionRegistry.init(std.testing.allocator);
    defer conversion_registry.deinit();

    // Add equal-cost conversions
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
        .cost = 5,
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

    var diagnostic_engine = DiagnosticEngine.init(std.testing.allocator);

    // Add ambiguous functions
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
        .ambiguous => {
            // Generate diagnostic
            var diagnostic = try diagnostic_engine.generateFromResolveResult(result);
            defer diagnostic.deinit(std.testing.allocator);

            // Verify diagnostic properties
            try std.testing.expectEqualStrings(diagnostic.code, "S1101");
            try std.testing.expect(diagnostic.severity == .@"error");
            try std.testing.expect(std.mem.indexOf(u8, diagnostic.human_message.summary, "Ambiguous call") != null);

            // Verify AI-readable data
            try std.testing.expect(diagnostic.structured_data.candidates.len == 2);
            try std.testing.expect(diagnostic.structured_data.edit_locations.len > 0);

            std.debug.print("✅ Ambiguity diagnostic generated successfully!\n", .{});
            std.debug.print("   Summary: {s}\n", .{diagnostic.human_message.summary});
        },
        else => {
            try std.testing.expect(false); // Should be ambiguous
        },
    }
}
