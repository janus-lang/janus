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
    std.debug.print("\n=== Starting Focused Ambiguity Test ===\n", .{});

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
    std.debug.print("✅ Registered conversions\n", .{});

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
    std.debug.print("✅ Added 2 functions to scope\n", .{});

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

    std.debug.print("🔍 Resolving call: add(i32, i32)\n", .{});
    std.debug.print("   Available functions:\n", .{});
    std.debug.print("   - add(i32, f64) -> f64\n", .{});
    std.debug.print("   - add(f64, i32) -> f64\n", .{});
    std.debug.print("   Both require 1 conversion with cost 5\n", .{});

    var result = try resolver.resolve(call_site);
    defer result.deinit(std.testing.allocator);

    switch (result) {
        .success => |success| {
            std.debug.print("❌ Expected ambiguity but got success: {s}\n", .{success.target_function.parameter_types});
            std.debug.print("   Conversion cost: {d}\n", .{success.conversion_path.get().total_cost});
            try std.testing.expect(false);
        },
        .ambiguous => |ambiguous| {
            std.debug.print("✅ Ambiguity correctly detected!\n", .{});
            std.debug.print("   Candidates: {d}\n", .{ambiguous.candidates.len});
            for (ambiguous.candidates, 0..) |candidate, i| {
                std.debug.print("   [{d}] {s} (cost: {d})\n", .{ i, candidate.candidate.function.parameter_types, candidate.conversion_path.get().total_cost });
            }
        },
        .no_matches => |no_matches| {
            std.debug.print("❌ No matches found for: {s}\n", .{no_matches.function_name});
            try std.testing.expect(false);
        },
        .error_occurred => |err| {
            std.debug.print("❌ Error occurred: {s}\n", .{err.message});
            try std.testing.expect(false);
        },
    }

    std.debug.print("=== Test Complete ===\n", .{});
}
