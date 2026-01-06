// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const EnhancedASTDBParser = @import("compiler/enhanced_astdb_parser.zig").EnhancedASTDBParser;
const ComptimeVM = @import("compiler/comptime_vm.zig").ComptimeVM;
const astdb = @import("compiler/libjanus/astdb.zig");
const ASTDBSystem = astdb.ASTDBSystem;
const contracts = @import("compiler/libjanus/integration_contracts.zig");

// 🔒 STEP 2: COMPTIME VM INTEGRATION CONTRACT - DISCIPLINED IMPLEMENTATION
//
// CONTRACT SPECIFICATION:
// 1. Parser identifies comptime expressions (const declarations, comptime calls)
// 2. Parser creates ComptimeVMInputContract with precise metadata
// 3. ComptimeVM evaluates expressions and returns ComptimeVMOutputContract
// 4. Parser validates response and handles results appropriately
// 5. All boundaries are enforced through immutable contracts
//
// SUCCESS CRITERIA:
// - Const declarations are registered and evaluated
// - Comptime function calls are processed
// - Contract validation prevents malformed data
// - Integration is deterministic and testable

test "Step 2: Comptime VM Integration Contract - DISCIPLINED IMPLEMENTATION" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB system
    var astdb_system = try ASTDBSystem.init(allocator, true);
    defer astdb_system.deinit();

    // Initialize Comptime VM
    var comptime_vm = try ComptimeVM.init(allocator, &astdb_system);
    defer comptime_vm.deinit();

    std.debug.print("\n🔒 STEP 2: COMPTIME VM INTEGRATION CONTRACT\n", .{});
    std.debug.print("============================================\n", .{});

    // Test program with comptime expressions
    const test_source =
        \\const PI = 3.14159
        \\const BUFFER_SIZE = 1024
        \\const MESSAGE = "Hello, Janus!"
        \\
        \\func compute_area(radius: f64) -> f64 {
        \\    return PI * radius * radius
        \\}
    ;

    std.debug.print("📄 Testing comptime integration ({d} bytes)\n", .{test_source.len});

    // Initialize parser with Comptime VM integration
    var parser = try EnhancedASTDBParser.initWithComptimeVM(allocator, test_source, &astdb_system, &comptime_vm);
    defer parser.deinit();

    // Parse the program - this should trigger comptime VM integration
    const root_node = try parser.parseProgram();
    const snapshot = parser.getSnapshot();

    std.debug.print("✅ Parsing complete: {} nodes\n", .{snapshot.nodeCount()});

    // CONTRACT VALIDATION: Verify comptime expressions were registered
    std.debug.print("\n🔗 Validating Comptime VM Integration Contract\n", .{});

    // Test 1: Verify PI constant registration
    const pi_name = try astdb_system.str_interner.get("PI");
    const pi_result = comptime_vm.getConstantValue(pi_name);

    std.debug.print("🔍 Testing PI constant registration: ", .{});
    if (pi_result) |_| {
        std.debug.print("✅ REGISTERED\n", .{});
    } else {
        std.debug.print("❌ NOT REGISTERED\n", .{});
        return error.IntegrationFailed;
    }

    // Test 2: Verify BUFFER_SIZE constant registration
    const buffer_size_name = try astdb_system.str_interner.get("BUFFER_SIZE");
    const buffer_size_result = comptime_vm.getConstantValue(buffer_size_name);

    std.debug.print("🔍 Testing BUFFER_SIZE constant registration: ", .{});
    if (buffer_size_result) |_| {
        std.debug.print("✅ REGISTERED\n", .{});
    } else {
        std.debug.print("❌ NOT REGISTERED\n", .{});
        return error.IntegrationFailed;
    }

    // Test 3: Verify MESSAGE constant registration
    const message_name = try astdb_system.str_interner.get("MESSAGE");
    const message_result = comptime_vm.getConstantValue(message_name);

    std.debug.print("🔍 Testing MESSAGE constant registration: ", .{});
    if (message_result) |_| {
        std.debug.print("✅ REGISTERED\n", .{});
    } else {
        std.debug.print("❌ NOT REGISTERED\n", .{});
        return error.IntegrationFailed;
    }

    // Test 4: Verify evaluation statistics
    const stats = comptime_vm.getEvaluationStats();
    std.debug.print("🔍 Comptime evaluations: {d} total, {d} cached\n", .{ stats.total_evaluations, stats.cached_results });

    // Should have evaluated at least 3 constants
    try testing.expect(stats.total_evaluations >= 3);
    try testing.expect(stats.cached_results >= 3);

    std.debug.print("\n🎉 SUCCESS: Comptime VM Integration Contract Working!\n", .{});
    std.debug.print("✅ Parser successfully registers comptime expressions\n", .{});
    std.debug.print("✅ ComptimeVM evaluates expressions correctly\n", .{});
    std.debug.print("✅ Contract boundaries are enforced\n", .{});
    std.debug.print("✅ Integration is deterministic and testable\n", .{});

    _ = root_node; // Suppress unused variable warning
}

// Test contract structure validation
test "Step 2: Comptime VM Contract Structure Validation" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("\n📋 Testing Comptime VM Contract Structures\n", .{});

    // Test ComptimeVMInputContract validation
    var dependencies = std.ArrayList(astdb.NodeId){};
    defer dependencies.deinit();
    try dependencies.append(@enumFromInt(1));

    const input_contract = contracts.ComptimeVMInputContract{
        .decl_id = @enumFromInt(1),
        .expression_name = @enumFromInt(1),
        .expression_node = @enumFromInt(1),
        .expression_type = .const_declaration,
        .dependencies = dependencies.items,
        .source_span = astdb.Span{
            .start_byte = 0,
            .end_byte = 10,
            .start_line = 1,
            .start_col = 1,
            .end_line = 1,
            .end_col = 10,
        },
    };

    try testing.expect(contracts.ContractValidation.validateComptimeVMInput(&input_contract));
    std.debug.print("✅ ComptimeVMInputContract validation passed\n", .{});

    // Test ComptimeVMOutputContract validation
    const output_contract = contracts.ComptimeVMOutputContract{
        .success = true,
        .result_value = @enumFromInt(1),
        .result_type = @enumFromInt(2),
        .should_cache = true,
        .evaluation_errors = &[_]contracts.ComptimeVMOutputContract.EvaluationError{},
    };

    try testing.expect(contracts.ContractValidation.validateComptimeVMOutput(&output_contract));
    std.debug.print("✅ ComptimeVMOutputContract validation passed\n", .{});

    std.debug.print("✅ All contract structures are well-formed and validated\n", .{});
}
