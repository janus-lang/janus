// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Validator Tests
//!
//! Tests the Semantic Validation Engine including profile-aware checking,
//! definite assignment analysis, control flow validation, and language
//! rule enforcement.

const std = @import("std");
const testing = std.testing;
const print = std.debug.print;

const astdb = @import("../../../compiler/astdb/astdb.zig");
const symbol_table = @import("../../../compiler/semantic/symbol_table.zig");
const type_system = @import("../../../compiler/semantic/type_system.zig");
const type_inference = @import("../../../compiler/semantic/type_inference.zig");
const semantic_validator = @import("../../../compiler/semantic/semantic_validator.zig");

const SemanticValidator = semantic_validator.SemanticValidator;
const Profile = semantic_validator.Profile;
const Feature = semantic_validator.Feature;
const ValidationError = semantic_validator.ValidationError;

test "Semantic Validator - Profile Feature Gates" {
    print("\n🛡️  SEMANTIC VALIDATOR PROFILE GATES TEST\n", .{});
    print("========================================\n", .{});

    const allocator = std.testing.allocator;

    print("🧪 Test 1: Profile Feature Availability\n", .{});

    // Test :min profile (most restrictive)
    const min_profile = Profile.core;
    try testing.expect(min_profile.hasFeature(.basic_types));
    try testing.expect(min_profile.hasFeature(.functions));
    try testing.expect(min_profile.hasFeature(.variables));
    try testing.expect(min_profile.hasFeature(.control_flow));

    // Should NOT have advanced features
    try testing.expect(!min_profile.hasFeature(.error_handling));
    try testing.expect(!min_profile.hasFeature(.pattern_matching));
    try testing.expect(!min_profile.hasFeature(.effects));

    print("   ✅ :min profile correctly restricts advanced features\n", .{});

    // Test :go profile
    const go_profile = Profile.service;
    try testing.expect(go_profile.hasFeature(.basic_types));
    try testing.expect(go_profile.hasFeature(.error_handling));
    try testing.expect(go_profile.hasFeature(.interfaces));
    try testing.expect(go_profile.hasFeature(.channels));

    // Should NOT have :elixir+ features
    try testing.expect(!go_profile.hasFeature(.pattern_matching));
    try testing.expect(!go_profile.hasFeature(.actors));
    try testing.expect(!go_profile.hasFeature(.effects));

    print("   ✅ :go profile correctly enables error handling and channels\n", .{});

    // Test :elixir profile
    const elixir_profile = Profile.cluster;
    try testing.expect(elixir_profile.hasFeature(.error_handling));
    try testing.expect(elixir_profile.hasFeature(.pattern_matching));
    try testing.expect(elixir_profile.hasFeature(.actors));
    try testing.expect(elixir_profile.hasFeature(.supervision));

    // Should NOT have :full features
    try testing.expect(!elixir_profile.hasFeature(.effects));
    try testing.expect(!elixir_profile.hasFeature(.comptime_eval));
    try testing.expect(!elixir_profile.hasFeature(.unsafe_ops));

    print("   ✅ :elixir profile correctly enables pattern matching and actors\n", .{});

    // Test :full profile (least restrictive)
    const full_profile = Profile.sovereign;
    try testing.expect(full_profile.hasFeature(.basic_types));
    try testing.expect(full_profile.hasFeature(.error_handling));
    try testing.expect(full_profile.hasFeature(.pattern_matching));
    try testing.expect(full_profile.hasFeature(.effects));
    try testing.expect(full_profile.hasFeature(.comptime_eval));
    try testing.expect(full_profile.hasFeature(.metaprogramming));
    try testing.expect(full_profile.hasFeature(.unsafe_ops));

    print("   ✅ :full profile correctly enables all features\n", .{});

    _ = allocator; // Suppress unused warning

    print("🛡️  Profile Gates: ALL TESTS PASSED!\n", .{});
}

test "Semantic Validator - Profile Violation Detection" {
    print("\n🛡️  SEMANTIC VALIDATOR PROFILE VIOLATIONS TEST\n", .{});
    print("=============================================\n", .{});

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try type_system.TypeSystem.init(allocator);
    defer type_sys.deinit();

    const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer type_inf.deinit();

    print("🧪 Test 1: :min Profile Violation Detection\n", .{});

    // Create validator with :min profile (most restrictive)
    const validator = try SemanticValidator.init(allocator, &db, symbol_tbl, type_sys, type_inf, .core);
    defer validator.deinit();

    // Simulate advanced feature usage that should be rejected
    const advanced_node: astdb.NodeId = @enumFromInt(100);

    // Mock node that requires error handling (not available in :min)
    try validator.reportProfileViolation(advanced_node, .error_handling);

    const errors = validator.getErrors();
    try testing.expect(errors.len == 1);

    const error_item = errors[0];
    try testing.expect(error_item.kind == .profile_violation);
    try testing.expect(std.mem.indexOf(u8, error_item.message, "error_handling") != null);
    try testing.expect(std.mem.indexOf(u8, error_item.message, ":min") != null);

    print("   ✅ Profile violation correctly detected and reported\n", .{});

    print("🧪 Test 2: Profile Violation Suggestions\n", .{});

    try testing.expect(error_item.suggestions.len >= 1);
    const suggestion = error_item.suggestions[0];
    try testing.expect(std.mem.indexOf(u8, suggestion, ":full") != null);

    print("   ✅ Profile violation includes helpful suggestions\n", .{});

    print("🧪 Test 3: Multiple Profile Violations\n", .{});

    // Add more violations
    try validator.reportProfileViolation(@enumFromInt(101), .pattern_matching);
    try validator.reportProfileViolation(@enumFromInt(102), .effects);

    const all_errors = validator.getErrors();
    try testing.expect(all_errors.len == 3);

    const stats = validator.getStatistics();
    try testing.expect(stats.errors_found == 3);

    print("   ✅ Multiple profile violations tracked correctly\n", .{});

    print("🛡️  Profile Violations: ALL TESTS PASSED!\n", .{});
}

test "Semantic Validator - Definite Assignment Analysis" {
    print("\n🛡️  SEMANTIC VALIDATOR DEFINITE ASSIGNMENT TEST\n", .{});
    print("==============================================\n", .{});

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try type_system.TypeSystem.init(allocator);
    defer type_sys.deinit();

    const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer type_inf.deinit();

    const validator = try SemanticValidator.init(allocator, &db, symbol_tbl, type_sys, type_inf, .sovereign);
    defer validator.deinit();

    print("🧪 Test 1: Variable Declaration Tracking\n", .{});

    // Create a symbol for testing
    const var_name = try symbol_tbl.symbol_interner.intern("test_var");
    const test_span = symbol_table.SourceSpan{
        .start_line = 1,
        .start_column = 5,
        .end_line = 1,
        .end_column = 13,
    };

    const symbol_id = try symbol_tbl.declareSymbol(
        var_name,
        .variable,
        @enumFromInt(200),
        test_span,
        .private,
    );

    // Simulate variable declaration without initializer
    const var_node: astdb.NodeId = @enumFromInt(200);
    try validator.analyzeVariableDeclaration(var_node);

    // Check assignment state
    const assignment_state = validator.assignments.get(symbol_id);
    try testing.expect(assignment_state != null);
    try testing.expect(!assignment_state.?.is_initialized);

    print("   ✅ Uninitialized variable correctly tracked\n", .{});

    print("🧪 Test 2: Use-Before-Definition Detection\n", .{});

    // Simulate identifier usage before initialization
    const usage_node: astdb.NodeId = @enumFromInt(201);

    // Mock the ASTDB to return our symbol for this node
    try db.setNodeSymbol(usage_node, symbol_id);

    try validator.analyzeIdentifierUsage(usage_node);

    const errors = validator.getErrors();
    try testing.expect(errors.len >= 1);

    // Find the use-before-definition error
    var found_error = false;
    for (errors) |error_item| {
        if (error_item.kind == .use_before_definition) {
            found_error = true;
            try testing.expect(std.mem.indexOf(u8, error_item.message, "test_var") != null);
            try testing.expect(error_item.suggestions.len >= 1);
            break;
        }
    }
    try testing.expect(found_error);

    print("   ✅ Use-before-definition correctly detected\n", .{});

    print("🧪 Test 3: Assignment Tracking\n", .{});

    // Simulate assignment to initialize the variable
    const assign_node: astdb.NodeId = @enumFromInt(202);
    const value_node: astdb.NodeId = @enumFromInt(203);

    // Mock assignment target and value
    try db.setAssignmentTarget(assign_node, usage_node);
    try db.setAssignmentValue(assign_node, value_node);

    try validator.analyzeAssignment(assign_node);

    // Check that variable is now initialized
    const updated_state = validator.assignments.get(symbol_id);
    try testing.expect(updated_state != null);
    try testing.expect(updated_state.?.is_initialized);

    print("   ✅ Variable assignment correctly tracked\n", .{});

    print("🛡️  Definite Assignment: ALL TESTS PASSED!\n", .{});
}

test "Semantic Validator - Control Flow Analysis" {
    print("\n🛡️  SEMANTIC VALIDATOR CONTROL FLOW TEST\n", .{});
    print("=======================================\n", .{});

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try type_system.TypeSystem.init(allocator);
    defer type_sys.deinit();

    const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer type_inf.deinit();

    const validator = try SemanticValidator.init(allocator, &db, symbol_tbl, type_sys, type_inf, .sovereign);
    defer validator.deinit();

    print("🧪 Test 1: Return Statement Analysis\n", .{});

    // Simulate return statement
    const return_node: astdb.NodeId = @enumFromInt(300);
    try validator.analyzeReturnStatement(return_node);

    // Check that return path is recorded
    try testing.expect(validator.control_flow.return_paths.items.len == 1);
    try testing.expect(validator.control_flow.return_paths.items[0] == return_node);

    print("   ✅ Return statement correctly analyzed\n", .{});

    print("🧪 Test 2: Function Control Flow\n", .{});

    // Simulate function with missing return
    const func_node: astdb.NodeId = @enumFromInt(301);
    const body_node: astdb.NodeId = @enumFromInt(302);
    const ret_type_node: astdb.NodeId = @enumFromInt(303);

    // Mock function structure
    try db.setFunctionBody(func_node, body_node);
    try db.setFunctionReturnType(func_node, ret_type_node);

    try validator.analyzeFunctionControlFlow(func_node);

    // Should detect missing return (since hasReturnPath returns false)
    const errors = validator.getErrors();
    var found_missing_return = false;
    for (errors) |error_item| {
        if (error_item.kind == .missing_return) {
            found_missing_return = true;
            break;
        }
    }
    try testing.expect(found_missing_return);

    print("   ✅ Missing return statement detected\n", .{});

    print("🧪 Test 3: Reachability Analysis\n", .{});

    // Test that nodes are marked as reachable
    const test_node: astdb.NodeId = @enumFromInt(400);
    try validator.analyzeControlFlow(test_node);

    const is_reachable = validator.control_flow.reachable_nodes.get(test_node);
    try testing.expect(is_reachable != null);
    try testing.expect(is_reachable.?);

    print("   ✅ Node reachability correctly tracked\n", .{});

    print("🛡️  Control Flow: ALL TESTS PASSED!\n", .{});
}

test "Semantic Validator - Performance Characteristics" {
    print("\n⚡ SEMANTIC VALIDATOR PERFORMANCE TEST\n", .{});
    print("====================================\n", .{});

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try type_system.TypeSystem.init(allocator);
    defer type_sys.deinit();

    const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer type_inf.deinit();

    const validator = try SemanticValidator.init(allocator, &db, symbol_tbl, type_sys, type_inf, .sovereign);
    defer validator.deinit();

    print("🧪 Test: Large Validation Performance\n", .{});

    const num_validations = 1000;

    const start_time = std.time.nanoTimestamp();

    // Perform many profile checks
    for (0..num_validations) |i| {
        const node_id: astdb.NodeId = @enumFromInt(@as(u32, @intCast(500 + i)));

        // Simulate different node kinds requiring different features
        const feature = switch (i % 4) {
            0 => Feature.basic_types,
            1 => Feature.error_handling,
            2 => Feature.pattern_matching,
            3 => Feature.effects,
            else => unreachable,
        };

        // Check feature availability (should all pass in :full profile)
        const available = validator.profile.hasFeature(feature);
        try testing.expect(available);

        // Simulate control flow analysis
        try validator.control_flow.reachable_nodes.put(node_id, true);
    }

    const validation_time = std.time.nanoTimestamp();
    const validation_duration = @as(f64, @floatFromInt(validation_time - start_time)) / 1_000_000.0;

    print("   Validation time: {d:.2f}ms for {} checks\n", .{ validation_duration, num_validations });

    // Performance requirements
    const avg_validation_time = validation_duration / @as(f64, @floatFromInt(num_validations));

    print("   Average validation time: {d:.6f}ms per check\n", .{avg_validation_time});

    // Should be sub-millisecond for individual operations
    try testing.expect(avg_validation_time < 0.1);

    print("   ✅ Performance requirements met\n", .{});

    // Test statistics
    const stats = validator.getStatistics();
    print("   Validation statistics:\n", .{});
    print("     Nodes validated: {}\n", .{stats.nodes_validated});
    print("     Profile checks: {}\n", .{stats.profile_checks});
    print("     Assignment checks: {}\n", .{stats.assignment_checks});
    print("     Control flow checks: {}\n", .{stats.control_flow_checks});
    print("     Errors found: {}\n", .{stats.errors_found});

    print("⚡ Performance: ALL TESTS PASSED!\n", .{});
}

test "Semantic Validator - Integration Test" {
    print("\n🔗 SEMANTIC VALIDATOR INTEGRATION TEST\n", .{});
    print("=====================================\n", .{});

    const allocator = std.testing.allocator;

    // Initialize full system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try symbol_table.SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try type_system.TypeSystem.init(allocator);
    defer type_sys.deinit();

    const type_inf = try type_inference.TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer type_inf.deinit();

    const validator = try SemanticValidator.init(allocator, &db, symbol_tbl, type_sys, type_inf, .service // Use :go profile for testing
    );
    defer validator.deinit();

    print("🧪 Test: Complete Validation Workflow\n", .{});

    // Simulate a complex validation scenario
    // Function with error handling (allowed in :go) and pattern matching (not allowed)

    // 1. Create function with error handling (should pass)
    const func_node: astdb.NodeId = @enumFromInt(600);
    const error_node: astdb.NodeId = @enumFromInt(601);
    _ = func_node; // Suppress unused warning
    _ = error_node; // Suppress unused warning

    // Mock error handling feature usage
    const error_feature = validator.getRequiredFeature(.try_expression);
    try testing.expect(error_feature == .error_handling);
    try testing.expect(validator.profile.hasFeature(.error_handling));

    // 2. Try to use pattern matching (should fail in :go profile)
    const pattern_node: astdb.NodeId = @enumFromInt(602);
    try validator.reportProfileViolation(pattern_node, .pattern_matching);

    // 3. Create variable and use before initialization
    const var_name = try symbol_tbl.symbol_interner.intern("uninitialized_var");
    const test_span = symbol_table.SourceSpan{
        .start_line = 5,
        .start_column = 10,
        .end_line = 5,
        .end_column = 25,
    };

    const symbol_id = try symbol_tbl.declareSymbol(
        var_name,
        .variable,
        @enumFromInt(603),
        test_span,
        .private,
    );

    const var_decl_node: astdb.NodeId = @enumFromInt(603);
    const var_usage_node: astdb.NodeId = @enumFromInt(604);

    try validator.analyzeVariableDeclaration(var_decl_node);

    try db.setNodeSymbol(var_usage_node, symbol_id);
    try validator.analyzeIdentifierUsage(var_usage_node);

    // 4. Check validation results
    const errors = validator.getErrors();
    try testing.expect(errors.len >= 2); // Profile violation + use-before-definition

    var profile_error_found = false;
    var assignment_error_found = false;

    for (errors) |error_item| {
        switch (error_item.kind) {
            .profile_violation => {
                profile_error_found = true;
                try testing.expect(std.mem.indexOf(u8, error_item.message, "pattern_matching") != null);
            },
            .use_before_definition => {
                assignment_error_found = true;
                try testing.expect(std.mem.indexOf(u8, error_item.message, "uninitialized_var") != null);
            },
            else => {},
        }
    }

    try testing.expect(profile_error_found);
    try testing.expect(assignment_error_found);

    print("   ✅ Complex validation scenario completed successfully\n", .{});

    // Test system integration
    const stats = validator.getStatistics();
    print("   Integration statistics:\n", .{});
    print("     Total errors: {}\n", .{stats.errors_found});
    print("     Profile checks: {}\n", .{stats.profile_checks});
    print("     Assignment checks: {}\n", .{stats.assignment_checks});

    try testing.expect(stats.errors_found >= 2);

    print("🔗 Integration: ALL TESTS PASSED!\n", .{});
}
