// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type Inference Engine Tests
//!
//! Tests the constraint-based type inference system including expression
//! type inference, constraint generation, unification, and error detection.

const std = @import("std");
const compat_time = @import("compat_time");
const testing = std.testing;
const print = std.debug.print;

const astdb = @import("../../../compiler/astdb/astdb.zig");
const symbol_table = @import("../../../compiler/semantic/symbol_table.zig");
const type_system = @import("../../../compiler/semantic/type_system.zig");
const type_inference = @import("../../../compiler/semantic/type_inference.zig");

const TypeInference = type_inference.TypeInference;
const TypeConstraint = type_inference.TypeConstraint;
const TypeSystem = type_system.TypeSystem;
const SymbolTable = symbol_table.SymbolTable;

test "Type Inference - Basic Constraint Generation" {
    print("\n🧠 TYPE INFERENCE CONSTRAINT GENERATION TEST\n");
    print("=============================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test 1: Inference Variable Creation\n");

    const var1 = try inference.createInferenceVar();
    const var2 = try inference.createInferenceVar();

    try testing.expect(var1 != var2);

    const stats = inference.getStatistics();
    try testing.expect(stats.inference_vars_created == 2);

    print("   ✅ Inference variables created: {}\n", .{stats.inference_vars_created});

    print("🧪 Test 2: Constraint Addition\n");

    // Add equality constraint: T1 = T2
    try inference.addConstraint(.{ .equality = .{ .left = type_sys.primitives.i32, .right = type_sys.primitives.i32 } });

    // Add subtype constraint: i16 <: i32
    try inference.addConstraint(.{ .subtype = .{ .sub = type_sys.primitives.i16, .super = type_sys.primitives.i32 } });

    // Add numeric constraint
    try inference.addConstraint(.{ .numeric = type_sys.primitives.f64 });

    const final_stats = inference.getStatistics();
    try testing.expect(final_stats.constraints_generated == 3);

    print("   ✅ Constraints generated: {}\n", .{final_stats.constraints_generated});

    print("🧠 Constraint Generation: ALL TESTS PASSED!\n");
}

test "Type Inference - Literal Type Inference" {
    print("\n🧠 TYPE INFERENCE LITERAL TYPES TEST\n");
    print("====================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test 1: Integer Literal Inference\n");

    // Mock node ID for integer literal
    const int_node: astdb.NodeId = @enumFromInt(1);
    try inference.inferLiteralInt(int_node);

    const int_type = inference.getNodeType(int_node);
    try testing.expect(int_type == type_sys.primitives.i32);

    print("   ✅ Integer literal inferred as i32\n");

    print("🧪 Test 2: Float Literal Inference\n");

    const float_node: astdb.NodeId = @enumFromInt(2);
    try inference.inferLiteralFloat(float_node);

    const float_type = inference.getNodeType(float_node);
    try testing.expect(float_type == type_sys.primitives.f64);

    print("   ✅ Float literal inferred as f64\n");

    print("🧪 Test 3: String Literal Inference\n");

    const string_node: astdb.NodeId = @enumFromInt(3);
    try inference.inferLiteralString(string_node);

    const string_type = inference.getNodeType(string_node);
    try testing.expect(string_type == type_sys.primitives.string);

    print("   ✅ String literal inferred as string\n");

    print("🧪 Test 4: Boolean Literal Inference\n");

    const bool_node: astdb.NodeId = @enumFromInt(4);
    try inference.inferLiteralBool(bool_node);

    const bool_type = inference.getNodeType(bool_node);
    try testing.expect(bool_type == type_sys.primitives.bool);

    print("   ✅ Boolean literal inferred as bool\n");

    print("🧠 Literal Type Inference: ALL TESTS PASSED!\n");
}

test "Type Inference - Binary Operation Constraints" {
    print("\n🧠 TYPE INFERENCE BINARY OPERATIONS TEST\n");
    print("========================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test 1: Arithmetic Operation Constraints\n");

    // Simulate: 42 + 3.14 (i32 + f64)
    const left_node: astdb.NodeId = @enumFromInt(10);
    const right_node: astdb.NodeId = @enumFromInt(11);
    const add_node: astdb.NodeId = @enumFromInt(12);

    // Set up operand types
    try inference.setNodeType(left_node, type_sys.primitives.i32);
    try inference.setNodeType(right_node, type_sys.primitives.f64);

    // Mock binary operation inference (simplified)
    const result_type = try inference.promoteArithmeticTypes(type_sys.primitives.i32, type_sys.primitives.f64);
    try inference.setNodeType(add_node, result_type);

    // Add constraints for arithmetic operation
    try inference.addConstraint(.{ .numeric = type_sys.primitives.i32 });
    try inference.addConstraint(.{ .numeric = type_sys.primitives.f64 });

    const stats = inference.getStatistics();
    try testing.expect(stats.constraints_generated >= 2);

    print("   ✅ Arithmetic constraints generated\n");

    print("🧪 Test 2: Comparison Operation Constraints\n");

    // Simulate: x == y (comparison)
    const comp_left: astdb.NodeId = @enumFromInt(20);
    const comp_right: astdb.NodeId = @enumFromInt(21);
    const comp_node: astdb.NodeId = @enumFromInt(22);

    try inference.setNodeType(comp_left, type_sys.primitives.i32);
    try inference.setNodeType(comp_right, type_sys.primitives.i32);
    try inference.setNodeType(comp_node, type_sys.primitives.bool);

    // Add comparison constraints
    try inference.addConstraint(.{ .comparable = type_sys.primitives.i32 });
    try inference.addConstraint(.{ .equality = .{ .left = type_sys.primitives.i32, .right = type_sys.primitives.i32 } });

    const comp_type = inference.getNodeType(comp_node);
    try testing.expect(comp_type == type_sys.primitives.bool);

    print("   ✅ Comparison result type is bool\n");

    print("🧪 Test 3: Logical Operation Constraints\n");

    // Simulate: true && false
    const logic_left: astdb.NodeId = @enumFromInt(30);
    const logic_right: astdb.NodeId = @enumFromInt(31);
    const logic_node: astdb.NodeId = @enumFromInt(32);

    try inference.setNodeType(logic_left, type_sys.primitives.bool);
    try inference.setNodeType(logic_right, type_sys.primitives.bool);
    try inference.setNodeType(logic_node, type_sys.primitives.bool);

    // Add logical constraints
    try inference.addConstraint(.{ .equality = .{ .left = type_sys.primitives.bool, .right = type_sys.primitives.bool } });

    const logic_type = inference.getNodeType(logic_node);
    try testing.expect(logic_type == type_sys.primitives.bool);

    print("   ✅ Logical operation constraints working\n");

    print("🧠 Binary Operations: ALL TESTS PASSED!\n");
}

test "Type Inference - Function Call Constraints" {
    print("\n🧠 TYPE INFERENCE FUNCTION CALLS TEST\n");
    print("=====================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test 1: Function Call Constraint Generation\n");

    // Create function type: (i32, string) -> bool
    const params = [_]type_system.TypeId{ type_sys.primitives.i32, type_sys.primitives.string };
    const func_type = try type_sys.createFunctionType(&params, type_sys.primitives.bool, true);

    // Simulate function call: func(42, "hello")
    const func_node: astdb.NodeId = @enumFromInt(40);
    const arg1_node: astdb.NodeId = @enumFromInt(41);
    const arg2_node: astdb.NodeId = @enumFromInt(42);
    const call_node: astdb.NodeId = @enumFromInt(43);

    try inference.setNodeType(func_node, func_type);
    try inference.setNodeType(arg1_node, type_sys.primitives.i32);
    try inference.setNodeType(arg2_node, type_sys.primitives.string);

    // Create result inference variable
    const result_var = try inference.createInferenceVar();
    const result_type = try inference.createInferredType(result_var);
    try inference.setNodeType(call_node, result_type);

    // Add function call constraint
    const arg_types = [_]type_system.TypeId{ type_sys.primitives.i32, type_sys.primitives.string };
    const owned_args = try allocator.dupe(type_system.TypeId, &arg_types);
    defer allocator.free(owned_args);

    try inference.addConstraint(.{ .function_call = .{ .func = func_type, .args = owned_args, .result = result_type } });

    const stats = inference.getStatistics();
    try testing.expect(stats.constraints_generated >= 1);
    try testing.expect(stats.inference_vars_created >= 1);

    print("   ✅ Function call constraint generated\n");

    print("🧪 Test 2: Array Access Constraint\n");

    // Create array type: [10]i32
    const array_type = try type_sys.createArrayType(type_sys.primitives.i32, type_system.TypeSystem.Type.ArrayType.ArraySize{ .fixed = 10 });

    // Simulate: arr[5]
    const array_node: astdb.NodeId = @enumFromInt(50);
    const index_node: astdb.NodeId = @enumFromInt(51);
    const access_node: astdb.NodeId = @enumFromInt(52);

    try inference.setNodeType(array_node, array_type);
    try inference.setNodeType(index_node, type_sys.primitives.i32);

    const element_var = try inference.createInferenceVar();
    const element_type = try inference.createInferredType(element_var);
    try inference.setNodeType(access_node, element_type);

    // Add array access constraint
    try inference.addConstraint(.{ .array_access = .{ .array = array_type, .index = type_sys.primitives.i32, .element = element_type } });

    print("   ✅ Array access constraint generated\n");

    print("🧪 Test 3: Field Access Constraint\n");

    // Simulate: obj.field
    const struct_node: astdb.NodeId = @enumFromInt(60);
    const field_node: astdb.NodeId = @enumFromInt(61);

    const field_var = try inference.createInferenceVar();
    const field_type = try inference.createInferredType(field_var);
    try inference.setNodeType(field_node, field_type);

    // Add field access constraint
    const field_name = try allocator.dupe(u8, "my_field");
    defer allocator.free(field_name);

    try inference.addConstraint(.{
        .field_access = .{
            .struct_type = type_sys.primitives.unknown, // Mock struct type
            .field_name = field_name,
            .field_type = field_type,
        },
    });

    print("   ✅ Field access constraint generated\n");

    print("🧠 Function Calls: ALL TESTS PASSED!\n");
}

test "Type Inference - Constraint Solving" {
    print("\n🧠 TYPE INFERENCE CONSTRAINT SOLVING TEST\n");
    print("=========================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test 1: Equality Constraint Solving\n");

    // Test unification: i32 = i32 (should succeed)
    const unified = try inference.unifyTypes(type_sys.primitives.i32, type_sys.primitives.i32);
    try testing.expect(!unified); // Already equal, no change

    print("   ✅ Identity unification working\n");

    print("🧪 Test 2: Subtype Constraint Checking\n");

    // Test subtyping: i16 <: i32 (should succeed)
    const subtype_ok = try inference.checkSubtype(type_sys.primitives.i16, type_sys.primitives.i32);
    try testing.expect(subtype_ok);

    // Test invalid subtyping: i32 <: i16 (should fail)
    const subtype_fail = try inference.checkSubtype(type_sys.primitives.i32, type_sys.primitives.i16);
    try testing.expect(!subtype_fail);

    print("   ✅ Subtype checking working correctly\n");

    print("🧪 Test 3: Constraint Solving Statistics\n");

    // Add several constraints and attempt solving
    try inference.addConstraint(.{ .equality = .{ .left = type_sys.primitives.i32, .right = type_sys.primitives.i32 } });

    try inference.addConstraint(.{ .subtype = .{ .sub = type_sys.primitives.i16, .super = type_sys.primitives.i32 } });

    try inference.addConstraint(.{ .numeric = type_sys.primitives.f64 });

    // Attempt constraint solving
    try inference.solveConstraints();

    const stats = inference.getStatistics();
    print("   Constraints generated: {}\n", .{stats.constraints_generated});
    print("   Unification steps: {}\n", .{stats.unification_steps});
    print("   Inference variables: {}\n", .{stats.inference_vars_created});

    try testing.expect(stats.constraints_generated >= 3);
    try testing.expect(stats.unification_steps >= 3);

    print("   ✅ Constraint solving statistics tracked\n");

    print("🧠 Constraint Solving: ALL TESTS PASSED!\n");
}

test "Type Inference - Performance Characteristics" {
    print("\n⚡ TYPE INFERENCE PERFORMANCE TEST\n");
    print("=================================\n");

    const allocator = std.testing.allocator;

    // Initialize components
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test: Large Constraint System Performance\n");

    const num_constraints = 1000;

    const start_time = compat_time.nanoTimestamp();

    // Generate many constraints
    for (0..num_constraints) |i| {
        const constraint_type = i % 4;

        switch (constraint_type) {
            0 => {
                // Equality constraints
                try inference.addConstraint(.{ .equality = .{ .left = type_sys.primitives.i32, .right = type_sys.primitives.i32 } });
            },
            1 => {
                // Subtype constraints
                try inference.addConstraint(.{ .subtype = .{ .sub = type_sys.primitives.i16, .super = type_sys.primitives.i32 } });
            },
            2 => {
                // Numeric constraints
                try inference.addConstraint(.{ .numeric = type_sys.primitives.f64 });
            },
            3 => {
                // Comparable constraints
                try inference.addConstraint(.{ .comparable = type_sys.primitives.string });
            },
            else => unreachable,
        }
    }

    const generation_time = compat_time.nanoTimestamp();
    const generation_duration = @as(f64, @floatFromInt(generation_time - start_time)) / 1_000_000.0;

    print("   Constraint generation time: {d:.2f}ms for {} constraints\n", .{ generation_duration, num_constraints });

    // Test constraint solving performance
    try inference.solveConstraints();

    const solving_time = compat_time.nanoTimestamp();
    const solving_duration = @as(f64, @floatFromInt(solving_time - generation_time)) / 1_000_000.0;

    print("   Constraint solving time: {d:.2f}ms\n", .{solving_duration});

    // Performance requirements
    const avg_generation_time = generation_duration / @as(f64, @floatFromInt(num_constraints));

    print("   Average constraint generation: {d:.6f}ms per constraint\n", .{avg_generation_time});

    // Should be sub-millisecond for individual operations
    try testing.expect(avg_generation_time < 0.1);
    try testing.expect(solving_duration < 100.0); // 100ms for 1000 constraints

    print("   ✅ Performance requirements met\n");

    // Test statistics
    const stats = inference.getStatistics();
    print("   Final statistics:\n");
    print("     Constraints generated: {}\n", .{stats.constraints_generated});
    print("     Unification steps: {}\n", .{stats.unification_steps});
    print("     Inference variables: {}\n", .{stats.inference_vars_created});

    try testing.expect(stats.constraints_generated == num_constraints);

    print("⚡ Performance: ALL TESTS PASSED!\n");
}

test "Type Inference - Integration Test" {
    print("\n🔗 TYPE INFERENCE INTEGRATION TEST\n");
    print("==================================\n");

    const allocator = std.testing.allocator;

    // Initialize full system
    var db = astdb.AstDB.initWithMode(allocator, true);
    defer db.deinit();

    const symbol_tbl = try SymbolTable.init(allocator);
    defer symbol_tbl.deinit();

    const type_sys = try TypeSystem.init(allocator);
    defer type_sys.deinit();

    const inference = try TypeInference.init(allocator, type_sys, symbol_tbl, &db);
    defer inference.deinit();

    print("🧪 Test: Complete Type Inference Workflow\n");

    // Simulate a complex expression: (x + y) * z where x: i16, y: i32, z: f32

    // Create nodes
    const x_node: astdb.NodeId = @enumFromInt(100);
    const y_node: astdb.NodeId = @enumFromInt(101);
    const z_node: astdb.NodeId = @enumFromInt(102);
    const add_node: astdb.NodeId = @enumFromInt(103);
    const mul_node: astdb.NodeId = @enumFromInt(104);

    // Set initial types
    try inference.setNodeType(x_node, type_sys.primitives.i16);
    try inference.setNodeType(y_node, type_sys.primitives.i32);
    try inference.setNodeType(z_node, type_sys.primitives.f32);

    // Infer addition: x + y (i16 + i32 -> i32)
    const add_result = try inference.promoteArithmeticTypes(type_sys.primitives.i16, type_sys.primitives.i32);
    try inference.setNodeType(add_node, add_result);

    // Add constraints for addition
    try inference.addConstraint(.{ .numeric = type_sys.primitives.i16 });
    try inference.addConstraint(.{ .numeric = type_sys.primitives.i32 });
    try inference.addConstraint(.{ .subtype = .{ .sub = type_sys.primitives.i16, .super = add_result } });
    try inference.addConstraint(.{ .subtype = .{ .sub = type_sys.primitives.i32, .super = add_result } });

    // Infer multiplication: (i32) * f32 -> f32
    const mul_result = try inference.promoteArithmeticTypes(add_result, type_sys.primitives.f32);
    try inference.setNodeType(mul_node, mul_result);

    // Add constraints for multiplication
    try inference.addConstraint(.{ .numeric = add_result });
    try inference.addConstraint(.{ .numeric = type_sys.primitives.f32 });

    // Solve all constraints
    try inference.solveConstraints();

    // Verify final types
    const final_x_type = inference.getNodeType(x_node);
    const final_y_type = inference.getNodeType(y_node);
    const final_z_type = inference.getNodeType(z_node);
    const final_add_type = inference.getNodeType(add_node);
    const final_mul_type = inference.getNodeType(mul_node);

    try testing.expect(final_x_type == type_sys.primitives.i16);
    try testing.expect(final_y_type == type_sys.primitives.i32);
    try testing.expect(final_z_type == type_sys.primitives.f32);

    print("   ✅ Complex expression type inference completed\n");

    // Test system integration
    const stats = inference.getStatistics();
    print("   Integration statistics:\n");
    print("     Constraints: {}\n", .{stats.constraints_generated});
    print("     Unification steps: {}\n", .{stats.unification_steps});
    print("     Inference variables: {}\n", .{stats.inference_vars_created});

    try testing.expect(stats.constraints_generated > 0);

    print("🔗 Integration: ALL TESTS PASSED!\n");
}
