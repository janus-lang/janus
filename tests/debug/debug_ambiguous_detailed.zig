// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import all components
const TypeRegistry = @import("compiler/libjanus/type_registry.zig").TypeRegistry;
const TypeId = @import("compiler/libjanus/type_registry.zig").TypeId;
const ConversionRegistry = @import("compiler/libjanus/conversion_registry.zig").ConversionRegistry;
const ScopeManager = @import("compiler/libjanus/scope_manager.zig").ScopeManager;
const FunctionDecl = @import("compiler/libjanus/scope_manager.zig").FunctionDecl;
const SemanticResolver = @import("compiler/libjanus/semantic_resolver.zig").SemanticResolver;
const CallSite = @import("compiler/libjanus/semantic_resolver.zig").CallSite;
const ResolveResult = @import("compiler/libjanus/semantic_resolver.zig").ResolveResult;

test "debug ambiguous resolution detailed" {
    const allocator = std.testing.allocator;

    const type_registry = try allocator.create(TypeRegistry);
    type_registry.* = TypeRegistry.init(allocator);
    defer {
        type_registry.deinit();
        allocator.destroy(type_registry);
    }

    const conversion_registry = try allocator.create(ConversionRegistry);
    conversion_registry.* = ConversionRegistry.init(allocator);
    defer {
        conversion_registry.deinit();
        allocator.destroy(conversion_registry);
    }

    const scope_manager = try allocator.create(ScopeManager);
    scope_manager.* = try ScopeManager.init(allocator);
    defer {
        scope_manager.deinit();
        allocator.destroy(scope_manager);
    }

    const semantic_resolver = SemanticResolver.init(
        allocator,
        type_registry,
        conversion_registry,
        scope_manager,
    );

    // Add two ambiguous functions
    const add_func1 = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "math",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 5,
            .column = 1,
        },
    };

    const add_func2 = FunctionDecl{
        .name = "add",
        .parameter_types = "f64,i32",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "math",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 10,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&add_func1);
    try scope_manager.current_scope.addFunction(&add_func2);

    // Call with ambiguous arguments
    const call_site = CallSite{
        .function_name = "add",
        .argument_types = &[_]TypeId{ TypeId.I32, TypeId.I32 },
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 20,
            .column = 8,
            .start_byte = 300,
            .end_byte = 315,
        },
    };

    const result = try semantic_resolver.resolve(call_site);

    std.debug.print("Result type: {}\n", .{result});

    switch (result) {
        .success => |success| {
            std.debug.print("SUCCESS: Function {s} selected\n", .{success.target_function.name});
            try std.testing.expect(false); // Should be ambiguous
        },
        .ambiguous => |ambiguous| {
            std.debug.print("AMBIGUOUS: Found {} candidates\n", .{ambiguous.candidates.len});
            try std.testing.expect(ambiguous.candidates.len == 2);
        },
        .no_matches => |no_matches| {
            std.debug.print("NO MATCHES: Function {s} not found\n", .{no_matches.function_name});
            try std.testing.expect(false); // Should find functions
        },
        else => {
            std.debug.print("OTHER result type\n", .{});
            try std.testing.expect(false);
        },
    }
}
