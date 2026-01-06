// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Semantic Engine Interactive Demo
// Demonstrates the complete semantic analysis pipeline

const std = @import("std");
const print = std.debug.print;
const Allocator = std.mem.Allocator;

// Import semantic engine components
const SymbolTable = @import("../../compiler/semantic/symbol_table.zig").SymbolTable;
const SymbolResolver = @import("../../compiler/semantic/symbol_resolver.zig").SymbolResolver;
const TypeSystem = @import("../../compiler/semantic/type_system.zig").TypeSystem;
const TypeInference = @import("../../compiler/semantic/type_inference.zig").TypeInference;
const ValidationEngine = @import("../../compiler/semantic/validation_engine.zig").ValidationEngine;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🚀 Janus Semantic Engine Demo\n");
    print("=====================================\n\n");

    // Demo 1: Symbol Table and Resolution
    try demoSymbolResolution(allocator);

    // Demo 2: Type System and Inference
    try demoTypeInference(allocator);

    // Demo 3: Semantic Validation
    try demoSemanticValidation(allocator);

    // Demo 4: Profile Enforcement
    try demoProfileEnforcement(allocator);

    print("\n✅ Semantic Engine Demo Complete!\n");
}

fn demoSymbolResolution(allocator: Allocator) !void {
    print("📋 Demo 1: Symbol Resolution\n");
    print("----------------------------\n");

    var symbol_table = SymbolTable.init(allocator);
    defer symbol_table.deinit();

    // Create a global scope
    const global_scope = try symbol_table.enterScope(.global);
    print("✓ Created global scope (ID: {})\n", .{global_scope});

    // Declare some symbols
    const func_symbol = try symbol_table.declareSymbol("calculateArea", .{
        .kind = .function,
        .visibility = .public,
        .type_id = null,
        .declaration_node = 1,
        .module_id = 0,
        .flags = .{},
    });
    print("✓ Declared function 'calculateArea' (Symbol ID: {})\n", .{func_symbol});

    // Enter function scope
    const func_scope = try symbol_table.enterScope(.function);
    print("✓ Entered function scope (ID: {})\n", .{func_scope});

    // Declare parameters
    const width_symbol = try symbol_table.declareSymbol("width", .{
        .kind = .variable,
        .visibility = .private,
        .type_id = null,
        .declaration_node = 2,
        .module_id = 0,
        .flags = .{},
    });
    print("✓ Declared parameter 'width' (Symbol ID: {})\n", .{width_symbol});

    // Lookup symbols
    if (symbol_table.lookupSymbol("calculateArea")) |symbol_id| {
        print("✓ Successfully resolved 'calculateArea' to Symbol ID: {}\n", .{symbol_id});
    }

    if (symbol_table.lookupSymbol("width")) |symbol_id| {
        print("✓ Successfully resolved 'width' to Symbol ID: {}\n", .{symbol_id});
    }

    symbol_table.exitScope();
    print("✓ Exited function scope\n");

    print("✅ Symbol resolution demo complete!\n\n");
}

fn demoTypeInference(allocator: Allocator) !void {
    print("🔍 Demo 2: Type System and Inference\n");
    print("------------------------------------\n");

    var type_system = TypeSystem.init(allocator);
    defer type_system.deinit();

    // Create basic types
    const i32_type = type_system.getCanonicalType(.{ .primitive = .i32 });
    const f64_type = type_system.getCanonicalType(.{ .primitive = .f64 });
    const string_type = type_system.getCanonicalType(.{ .primitive = .string });

    print("✓ Created primitive types: i32={}, f64={}, string={}\n", .{ i32_type, f64_type, string_type });

    // Create function type
    const params = [_]u32{ i32_type, i32_type };
    const func_type = type_system.createFunctionType(&params, i32_type);
    print("✓ Created function type (i32, i32) -> i32: {}\n", .{func_type});

    // Test type compatibility
    const compatible = type_system.areTypesCompatible(i32_type, i32_type);
    const incompatible = type_system.areTypesCompatible(i32_type, string_type);
    print("✓ Type compatibility: i32 ≡ i32 = {}, i32 ≡ string = {}\n", .{ compatible, incompatible });

    print("✅ Type system demo complete!\n\n");
}

fn demoSemanticValidation(allocator: Allocator) !void {
    print("🔬 Demo 3: Semantic Validation\n");
    print("------------------------------\n");

    // Create validation context
    const context = ValidationContext{
        .allocator = allocator,
        .profile = .min,
        .strict_mode = true,
    };

    var validation_engine = ValidationEngine.init(allocator, context);
    defer validation_engine.deinit();

    print("✓ Initialized validation engine with :min profile\n");

    // Simulate validation of different constructs
    print("✓ Validating variable declarations...\n");
    print("✓ Validating function calls...\n");
    print("✓ Validating control flow...\n");
    print("✓ Checking definite assignment...\n");

    // Get diagnostics (simulated)
    const diagnostics = validation_engine.getDiagnostics();
    print("✓ Generated {} diagnostic messages\n", .{diagnostics.len});

    print("✅ Semantic validation demo complete!\n\n");
}

fn demoProfileEnforcement(allocator: Allocator) !void {
    print("⚙️  Demo 4: Profile Enforcement\n");
    print("------------------------------\n");

    const profiles = [_]LanguageProfile{ .min, .go, .elixir, .full };
    const profile_names = [_][]const u8{ ":min", ":go", ":elixir", ":full" };

    for (profiles, profile_names) |profile, name| {
        print("✓ Testing profile {s}:\n", .{name});

        switch (profile) {
            .min => {
                print("  - Basic arithmetic: ✅ allowed\n");
                print("  - Simple control flow: ✅ allowed\n");
                print("  - Pattern matching: ❌ forbidden\n");
                print("  - Actors: ❌ forbidden\n");
            },
            .go => {
                print("  - Error handling: ✅ allowed\n");
                print("  - Concurrency: ✅ allowed\n");
                print("  - Pattern matching: ❌ forbidden\n");
                print("  - Compile-time execution: ❌ forbidden\n");
            },
            .elixir => {
                print("  - Actor model: ✅ allowed\n");
                print("  - Pattern matching: ✅ allowed\n");
                print("  - Supervision trees: ✅ allowed\n");
                print("  - Compile-time execution: ❌ forbidden\n");
            },
            .full => {
                print("  - All language features: ✅ allowed\n");
                print("  - Compile-time execution: ✅ allowed\n");
                print("  - Effect system: ✅ allowed\n");
                print("  - Metaprogramming: ✅ allowed\n");
            },
        }
        print("\n");
    }

    print("✅ Profile enforcement demo complete!\n\n");
}

// Mock types for demo purposes
const ValidationContext = struct {
    allocator: Allocator,
    profile: LanguageProfile,
    strict_mode: bool,
};

const LanguageProfile = enum {
    min,
    go,
    elixir,
    full,
};

const Diagnostic = struct {
    message: []const u8,
    location: u32,
};
