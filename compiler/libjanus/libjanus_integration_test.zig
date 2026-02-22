// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;

// Import all components
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
const FixSuggestionEngine = @import("fix_suggestion_engine.zig").FixSuggestionEngine;

/// Integration test suite for the complete semantic resolution system
pub const IntegrationTestSuite = struct {
    allocator: Allocator,
    type_registry: *TypeRegistry,
    conversion_registry: *ConversionRegistry,
    scope_manager: *ScopeManager,
    semantic_resolver: SemanticResolver,
    diagnostic_engine: DiagnosticEngine,
    fix_suggestion_engine: FixSuggestionEngine,

    pub fn init(allocator: Allocator) !IntegrationTestSuite {
        const type_registry = try allocator.create(TypeRegistry);
        type_registry.* = TypeRegistry.init(allocator);

        const conversion_registry = try allocator.create(ConversionRegistry);
        conversion_registry.* = ConversionRegistry.init(allocator);

        const scope_manager = try allocator.create(ScopeManager);
        scope_manager.* = try ScopeManager.init(allocator);

        const semantic_resolver = SemanticResolver.init(
            allocator,
            type_registry,
            conversion_registry,
            scope_manager,
        );

        // Add basic type conversions for testing
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
            .cost = 10,
            .is_lossy = true,
            .method = .builtin_cast,
            .syntax_template = "{} as i32",
        };
        try conversion_registry.registerConversion(i32_to_f64);
        try conversion_registry.registerConversion(f64_to_i32);

        const diagnostic_engine = DiagnosticEngine.init(allocator);
        const fix_suggestion_engine = FixSuggestionEngine.init(allocator);

        return IntegrationTestSuite{
            .allocator = allocator,
            .type_registry = type_registry,
            .conversion_registry = conversion_registry,
            .scope_manager = scope_manager,
            .semantic_resolver = semantic_resolver,
            .diagnostic_engine = diagnostic_engine,
            .fix_suggestion_engine = fix_suggestion_engine,
        };
    }

    pub fn deinit(self: *IntegrationTestSuite) void {
        self.type_registry.deinit();
        self.allocator.destroy(self.type_registry);

        self.conversion_registry.deinit();
        self.allocator.destroy(self.conversion_registry);

        self.scope_manager.deinit();
        self.allocator.destroy(self.scope_manager);
    }

    /// Test successful resolution with exact type match
    pub fn testExactMatch(self: *IntegrationTestSuite) !void {
        // Add a function to the scope
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

        try self.scope_manager.current_scope.addFunction(&add_func);

        // Create call site
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

        // Resolve the call
        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);

        // Verify successful resolution
        switch (result) {
            .success => |success| {
                try std.testing.expectEqualStrings(success.target_function.name, "add");
                try std.testing.expect(success.conversion_path.total_cost == 0);
            },
            else => {
                try std.testing.expect(false); // Should have succeeded
            },
        }
    }

    /// Test resolution with type conversion
    pub fn testWithConversion(self: *IntegrationTestSuite) !void {
        // Add a function that takes f64
        const sqrt_func = FunctionDecl{
            .name = "sqrt",
            .parameter_types = "f64",
            .return_type = "f64",
            .visibility = .public,
            .module_path = "",
            .source_location = FunctionDecl.SourceLocation{
                .file = "test.jan",
                .line = 10,
                .column = 1,
            },
        };

        try self.scope_manager.current_scope.addFunction(&sqrt_func);

        // Call with i32 (requires conversion)
        const call_site = CallSite{
            .function_name = "sqrt",
            .argument_types = &[_]TypeId{TypeId.I32},
            .source_location = CallSite.SourceLocation{
                .file = "test.jan",
                .line = 15,
                .column = 5,
                .start_byte = 200,
                .end_byte = 210,
            },
        };

        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);

        switch (result) {
            .success => |success| {
                try std.testing.expectEqualStrings(success.target_function.name, "sqrt");
                try std.testing.expect(success.conversion_path.total_cost == 5); // i32 -> f64 cost
            },
            else => {
                try std.testing.expect(false); // Should have succeeded with conversion
            },
        }
    }

    /// Test ambiguous function resolution with diagnostic generation
    pub fn testAmbiguousResolution(self: *IntegrationTestSuite) !void {
        // Create a fresh scope for this test
        const test_scope = try self.scope_manager.createChildScope("ambiguous_test");
        const original_scope = self.scope_manager.current_scope;
        self.scope_manager.enterScope(test_scope);
        defer self.scope_manager.enterScope(original_scope);

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

        try self.scope_manager.current_scope.addFunction(&add_func1);
        try self.scope_manager.current_scope.addFunction(&add_func2);

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

        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);

        switch (result) {
            .ambiguous => |ambiguous| {
                try std.testing.expect(ambiguous.candidates.len == 2);

                // Generate diagnostic
                var diagnostic = try self.diagnostic_engine.generateFromResolveResult(result);
                defer diagnostic.deinit(self.allocator);

                // Verify diagnostic properties
                try std.testing.expectEqualStrings(diagnostic.code, "S1101");
                try std.testing.expect(diagnostic.severity == .@"error");
                try std.testing.expect(std.mem.indexOf(u8, diagnostic.human_message.summary, "Ambiguous call") != null);

                // Generate fix suggestions
                const fixes = try self.fix_suggestion_engine.generateAmbiguityFixes(
                    ambiguous.candidates,
                    call_site,
                );
                defer {
                    for (fixes) |*fix| {
                        fix.deinit(self.allocator);
                    }
                    self.allocator.free(fixes);
                }

                // Should have cast suggestions
                try std.testing.expect(fixes.len > 0);

                var found_cast_fix = false;
                for (fixes) |fix| {
                    if (std.mem.indexOf(u8, fix.description, "Cast argument") != null) {
                        found_cast_fix = true;
                        try std.testing.expect(fix.confidence > 0.5);
                    }
                }
                try std.testing.expect(found_cast_fix);
            },
            else => {
                try std.testing.expect(false); // Should be ambiguous
            },
        }
    }

    /// Test function not found with typo correction
    pub fn testFunctionNotFound(self: *IntegrationTestSuite) !void {
        // Create a fresh scope for this test
        const test_scope = try self.scope_manager.createChildScope("not_found_test");
        const original_scope = self.scope_manager.current_scope;
        self.scope_manager.enterScope(test_scope);
        defer self.scope_manager.enterScope(original_scope);

        // Add some functions for typo correction
        const length_func = FunctionDecl{
            .name = "length",
            .parameter_types = "string",
            .return_type = "i32",
            .visibility = .public,
            .module_path = "",
            .source_location = FunctionDecl.SourceLocation{
                .file = "string.jan",
                .line = 1,
                .column = 1,
            },
        };

        try self.scope_manager.current_scope.addFunction(&length_func);

        // Call with typo
        const call_site = CallSite{
            .function_name = "lenght", // Typo
            .argument_types = &[_]TypeId{TypeId.STRING},
            .source_location = CallSite.SourceLocation{
                .file = "test.jan",
                .line = 25,
                .column = 12,
                .start_byte = 400,
                .end_byte = 407,
            },
        };

        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);

        switch (result) {
            .no_matches => |no_matches| {
                try std.testing.expectEqualStrings(no_matches.function_name, "lenght");

                // Generate diagnostic
                var diagnostic = try self.diagnostic_engine.generateFromResolveResult(result);
                defer diagnostic.deinit(self.allocator);

                try std.testing.expectEqualStrings(diagnostic.code, "S1102");

                // Generate fix suggestions
                const fixes = try self.fix_suggestion_engine.generateNoMatchFixes(
                    call_site,
                    no_matches.available_functions,
                );
                defer {
                    for (fixes) |*fix| {
                        fix.deinit(self.allocator);
                    }
                    self.allocator.free(fixes);
                }

                // Should suggest "length" as typo correction
                var found_typo_fix = false;
                for (fixes) |fix| {
                    if (std.mem.indexOf(u8, fix.description, "length") != null) {
                        found_typo_fix = true;
                        try std.testing.expect(fix.confidence > 0.2);
                    }
                }
                try std.testing.expect(found_typo_fix);
            },
            else => {
                try std.testing.expect(false); // Should not find function
            },
        }
    }

    /// Test performance characteristics
    pub fn testPerformance(self: *IntegrationTestSuite) !void {
        // Create a fresh scope for this test
        const test_scope = try self.scope_manager.createChildScope("performance_test");
        const original_scope = self.scope_manager.current_scope;
        self.scope_manager.enterScope(test_scope);
        defer self.scope_manager.enterScope(original_scope);

        // Store function names to avoid freeing them prematurely
        var function_names: std.ArrayList([]u8) = .empty;
        defer {
            for (function_names.items) |name| {
                self.allocator.free(name);
            }
            function_names.deinit();
        }

        // Add multiple functions to test performance
        var i: u32 = 0;
        while (i < 100) : (i += 1) {
            const func_name = try std.fmt.allocPrint(self.allocator, "func_{d}", .{i});
            try function_names.append(func_name);

            const func = FunctionDecl{
                .name = func_name,
                .parameter_types = "i32",
                .return_type = "i32",
                .visibility = .public,
                .module_path = "",
                .source_location = FunctionDecl.SourceLocation{
                    .file = "perf.jan",
                    .line = i + 1,
                    .column = 1,
                },
            };

            try self.scope_manager.current_scope.addFunction(&func);
        }

        // Test resolution performance
        const call_site = CallSite{
            .function_name = "func_50",
            .argument_types = &[_]TypeId{TypeId.I32},
            .source_location = CallSite.SourceLocation{
                .file = "test.jan",
                .line = 30,
                .column = 5,
                .start_byte = 500,
                .end_byte = 507,
            },
        };

        const start_time = std.time.nanoTimestamp();
        var result = try self.semantic_resolver.resolve(call_site);
        defer result.deinit(self.allocator);
        const end_time = std.time.nanoTimestamp();

        const resolution_time_ns = @as(u64, @intCast(end_time - start_time));

        // Should resolve successfully
        switch (result) {
            .success => |success| {
                try std.testing.expectEqualStrings(success.target_function.name, "func_50");

                // Performance check: should be under 1ms (1,000,000 ns)
                try std.testing.expect(resolution_time_ns < 1_000_000);
            },
            else => {
                try std.testing.expect(false); // Should have succeeded
            },
        }
    }
};

// Integration tests
test "Integration: Complete semantic resolution pipeline" {
    var test_suite = try IntegrationTestSuite.init(std.testing.allocator);
    defer test_suite.deinit();

    // Run all integration tests
    try test_suite.testExactMatch();
    try test_suite.testWithConversion();
    try test_suite.testAmbiguousResolution();
    try test_suite.testFunctionNotFound();
    try test_suite.testPerformance();
}

test "Integration: End-to-end diagnostic generation" {
    var test_suite = try IntegrationTestSuite.init(std.testing.allocator);
    defer test_suite.deinit();

    // Test the complete diagnostic pipeline
    try test_suite.testAmbiguousResolution();
    try test_suite.testFunctionNotFound();
}

test "Integration: Performance under load" {
    var test_suite = try IntegrationTestSuite.init(std.testing.allocator);
    defer test_suite.deinit();

    try test_suite.testPerformance();
}
// Dispatch codegen integration tests
const DispatchIR = @import("ir_dispatch.zig").DispatchIR;
const DispatchIRBuilder = @import("ir_dispatch.zig").DispatchIRBuilder;
const LLVMDispatchCodegen = @import("passes/codegen/llvm/dispatch.zig").LLVMDispatchCodegen;
const DispatchTableManager = @import("dispatch_table_manager.zig").DispatchTableManager;

test "Integration: Dispatch codegen pipeline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🚀 Starting dispatch codegen integration test\n", .{});

    // Phase 1: Create IR
    std.debug.print("📝 Phase 1: Creating dispatch IR\n", .{});

    var ir_builder = DispatchIRBuilder.init(allocator);

    const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
    const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;
    const SourceSpan = @import("ir_dispatch.zig").SourceSpan;
    const CallingConvention = @import("ir_dispatch.zig").CallingConvention;

    const target_func = FunctionRef{
        .name = "add",
        .mangled_name = "_Z3addii",
        .signature = FunctionSignature{
            .parameters = @constCast(&[_]TypeId{ TypeId.I32, TypeId.I32 }),
            .return_type = TypeId.I32,
            .is_variadic = false,
        },
    };

    const source_loc = SourceSpan{
        .file = "integration_test.jan",
        .start_line = 10,
        .start_col = 5,
        .end_line = 10,
        .end_col = 15,
    };

    var static_call = try ir_builder.createStaticCall(
        target_func,
        &[_]@import("ir_dispatch.zig").ConversionStep{},
        CallingConvention.system_v,
        source_loc,
    );
    defer static_call.deinit(allocator);

    const dispatch_ir = DispatchIR{ .static_call = static_call };

    std.debug.print("✅ Static call IR created: {s}\n", .{target_func.name});

    // Phase 2: Initialize codegen
    std.debug.print("🔧 Phase 2: Initializing LLVM codegen\n", .{});

    var codegen = try LLVMDispatchCodegen.init(allocator, "x86_64-linux-gnu");
    defer codegen.deinit();

    std.debug.print("✅ LLVM codegen initialized for x86_64-linux-gnu\n", .{});

    // Phase 3: Generate code
    std.debug.print("⚡ Phase 3: Generating LLVM IR\n", .{});

    // Mock LLVM values for arguments
    const LLVM = @import("passes/codegen/llvm/dispatch.zig").LLVM;
    var args = [_]LLVM.ValueRef{ @ptrFromInt(0x7000), @ptrFromInt(0x7001) };

    const result = try codegen.generateFromIR(&dispatch_ir, &args);
    try std.testing.expect(@intFromPtr(result) != 0);

    std.debug.print("✅ LLVM IR generated successfully\n", .{});

    // Phase 4: Verify statistics
    std.debug.print("📊 Phase 4: Verifying codegen statistics\n", .{});

    const stats = codegen.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.static_calls_generated);
    try std.testing.expectEqual(@as(u32, 0), stats.dynamic_stubs_generated);

    std.debug.print("✅ Statistics verified: {} static calls, {} dynamic stubs\n", .{
        stats.static_calls_generated,
        stats.dynamic_stubs_generated,
    });

    // Phase 5: Test memory management
    std.debug.print("🏛️ Phase 5: Testing dispatch table management\n", .{});

    var table_manager = DispatchTableManager.init(allocator, null);
    defer table_manager.deinit();

    const manager_stats = table_manager.getStats();
    try std.testing.expectEqual(@as(u32, 0), manager_stats.tables_created);

    std.debug.print("✅ Dispatch table manager initialized\n", .{});

    // Phase 6: Test IR serialization
    std.debug.print("💾 Phase 6: Testing IR serialization\n", .{});

    var serializer = @import("ir_dispatch.zig").DispatchIRSerializer.init(allocator);
    const json_output = try serializer.toJson(&dispatch_ir);
    defer allocator.free(json_output);

    try std.testing.expect(json_output.len > 0);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "static_call") != null);
    try std.testing.expect(std.mem.indexOf(u8, json_output, "static") != null);

    std.debug.print("✅ IR serialization successful: {} bytes\n", .{json_output.len});
    std.debug.print("📄 JSON output: {s}\n", .{json_output});

    std.debug.print("\n🎉 Integration test completed successfully!\n", .{});
    std.debug.print("🏆 All phases passed: IR creation → codegen → memory management → serialization\n", .{});
}

test "Integration: Dynamic dispatch codegen" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔀 Starting dynamic dispatch integration test\n", .{});

    // Create dynamic stub IR
    var ir_builder = DispatchIRBuilder.init(allocator);

    const CandidateIR = @import("ir_dispatch.zig").CandidateIR;
    const TypeCheckIR = @import("ir_dispatch.zig").TypeCheckIR;
    const StubStrategy = @import("ir_dispatch.zig").StubStrategy;
    const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
    const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;
    const SourceSpan = @import("ir_dispatch.zig").SourceSpan;

    const candidates = [_]CandidateIR{
        CandidateIR{
            .function_ref = FunctionRef{
                .name = "process_int",
                .mangled_name = "_Z11process_inti",
                .signature = FunctionSignature{
                    .parameters = @constCast(&[_]TypeId{TypeId.I32}),
                    .return_type = TypeId.STRING,
                    .is_variadic = false,
                },
            },
            .conversion_path = &[_]@import("ir_dispatch.zig").ConversionStep{},
            .match_score = 10,
            .type_check_ir = TypeCheckIR{
                .check_kind = .exact_match,
                .target_type = TypeId.I32,
                .parameter_index = 0,
            },
        },
        CandidateIR{
            .function_ref = FunctionRef{
                .name = "process_float",
                .mangled_name = "_Z13process_floatd",
                .signature = FunctionSignature{
                    .parameters = @constCast(&[_]TypeId{TypeId.F64}),
                    .return_type = TypeId.STRING,
                    .is_variadic = false,
                },
            },
            .conversion_path = &[_]@import("ir_dispatch.zig").ConversionStep{},
            .match_score = 10,
            .type_check_ir = TypeCheckIR{
                .check_kind = .exact_match,
                .target_type = TypeId.F64,
                .parameter_index = 0,
            },
        },
    };

    const source_loc = SourceSpan{
        .file = "dynamic_test.jan",
        .start_line = 5,
        .start_col = 1,
        .end_line = 5,
        .end_col = 20,
    };

    var dynamic_stub = try ir_builder.createDynamicStub(
        "process",
        &candidates,
        StubStrategy.switch_table,
        source_loc,
    );
    defer dynamic_stub.deinit(allocator);

    const dispatch_ir = DispatchIR{ .dynamic_stub = dynamic_stub };

    std.debug.print("✅ Dynamic stub IR created: {s} ({} candidates)\n", .{
        dynamic_stub.family_name,
        dynamic_stub.candidates.len,
    });

    // Test codegen
    var codegen = try LLVMDispatchCodegen.init(allocator, "x86_64-linux-gnu");
    defer codegen.deinit();

    const LLVM = @import("passes/codegen/llvm/dispatch.zig").LLVM;
    var args = [_]LLVM.ValueRef{@ptrFromInt(0x8000)};

    const result = try codegen.generateFromIR(&dispatch_ir, &args);
    try std.testing.expect(@intFromPtr(result) != 0);

    const stats = codegen.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.dynamic_stubs_generated);

    std.debug.print("✅ Dynamic stub generated: estimated {} bytes\n", .{
        dynamic_stub.getStubSizeEstimate(),
    });

    // Test table management
    var table_manager = DispatchTableManager.init(allocator, null);
    defer table_manager.deinit();

    const table = try table_manager.getOrCreateTable("process", dynamic_stub);
    try std.testing.expect(table.entries.len == 2);

    // Test lookup
    const int_entry = table.findEntry(TypeId.I32);
    try std.testing.expect(int_entry != null);
    try std.testing.expectEqualStrings("process_int", int_entry.?.function_name);

    const float_entry = table.findEntry(TypeId.F64);
    try std.testing.expect(float_entry != null);
    try std.testing.expectEqualStrings("process_float", float_entry.?.function_name);

    std.debug.print("✅ Dispatch table lookup successful\n", .{});

    std.debug.print("\n🎉 Dynamic dispatch integration test completed!\n", .{});
}

test "Integration: Semantic resolution to codegen pipeline" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n🔗 Starting semantic-to-codegen integration test\n", .{});

    // Phase 1: Set up semantic resolution
    var test_suite = try IntegrationTestSuite.init(allocator);
    defer test_suite.deinit();

    // Add overloaded functions
    const add_int_func = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 1,
            .column = 1,
        },
    };

    const add_float_func = FunctionDecl{
        .name = "add",
        .parameter_types = "f64,f64",
        .return_type = "f64",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "math.jan",
            .line = 5,
            .column = 1,
        },
    };

    try test_suite.scope_manager.current_scope.addFunction(&add_int_func);
    try test_suite.scope_manager.current_scope.addFunction(&add_float_func);

    // Phase 2: Resolve call (should be static - exact match)
    const call_site = CallSite{
        .function_name = "add",
        .argument_types = &[_]TypeId{ TypeId.I32, TypeId.I32 },
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 10,
            .column = 5,
            .start_byte = 100,
            .end_byte = 110,
        },
    };

    var resolve_result = try test_suite.semantic_resolver.resolve(call_site);
    defer resolve_result.deinit(allocator);

    std.debug.print("✅ Semantic resolution completed\n", .{});

    // Phase 3: Convert to dispatch IR
    var ir_builder = DispatchIRBuilder.init(allocator);

    const dispatch_ir = switch (resolve_result) {
        .success => |success| blk: {
            const FunctionRef = @import("ir_dispatch.zig").FunctionRef;
            const FunctionSignature = @import("ir_dispatch.zig").FunctionSignature;
            const SourceSpan = @import("ir_dispatch.zig").SourceSpan;
            const CallingConvention = @import("ir_dispatch.zig").CallingConvention;

            const target_func = FunctionRef{
                .name = success.target_function.name,
                .mangled_name = try std.fmt.allocPrint(allocator, "_Z{d}{s}ii", .{ success.target_function.name.len, success.target_function.name }),
                .signature = FunctionSignature{
                    .parameters = @constCast(&[_]TypeId{ TypeId.I32, TypeId.I32 }),
                    .return_type = TypeId.I32,
                    .is_variadic = false,
                },
            };
            defer allocator.free(target_func.mangled_name);

            const source_loc = SourceSpan{
                .file = call_site.source_location.file,
                .start_line = call_site.source_location.line,
                .start_col = call_site.source_location.column,
                .end_line = call_site.source_location.line,
                .end_col = call_site.source_location.column + 10,
            };

            const static_call = try ir_builder.createStaticCall(
                target_func,
                &[_]@import("ir_dispatch.zig").ConversionStep{},
                CallingConvention.system_v,
                source_loc,
            );

            break :blk DispatchIR{ .static_call = static_call };
        },
        else => {
            try std.testing.expect(false); // Should have resolved successfully
            unreachable;
        },
    };

    std.debug.print("✅ Dispatch IR created from semantic resolution\n", .{});

    // Phase 4: Generate LLVM code
    var codegen = try LLVMDispatchCodegen.init(allocator, "x86_64-linux-gnu");
    defer codegen.deinit();

    const LLVM = @import("passes/codegen/llvm/dispatch.zig").LLVM;
    var args = [_]LLVM.ValueRef{ @ptrFromInt(0x9000), @ptrFromInt(0x9001) };

    const result = try codegen.generateFromIR(&dispatch_ir, &args);
    try std.testing.expect(@intFromPtr(result) != 0);

    // Clean up dispatch IR
    var mutable_dispatch_ir = dispatch_ir;
    mutable_dispatch_ir.deinit(allocator);

    const stats = codegen.getStats();
    try std.testing.expectEqual(@as(u32, 1), stats.static_calls_generated);

    std.debug.print("✅ LLVM IR generated from dispatch IR\n", .{});
    std.debug.print("🎉 Complete semantic-to-codegen pipeline successful!\n", .{});
}
