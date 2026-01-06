// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Integration Tests for LLVM Dispatch Codegen
//!
//! Verifies that the compiler's soul can speak through LLVM IR
//! and act upon the world with deterministic, auditable code generation.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import the forged components - using module imports
const codegen = @import("../../../compiler/libjanus/passes/codegen/llvm/dispatch.zig");
const DispatchCodegen = codegen.DispatchCodegen;
const CallSite = codegen.CallSite;
const Strategy = codegen.Strategy;
const OutputFmt = codegen.OutputFmt;

// For now, create a minimal mock MockValidationEngine since we can't import across modules
const MockMockValidationEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, astdb: anytype) !*MockMockValidationEngine {
        _ = astdb;
        const engine = try allocator.create(MockMockValidationEngine);
        engine.* = MockMockValidationEngine{ .allocator = allocator };
        return engine;
    }

    pub fn deinit(self: *MockMockValidationEngine) void {
        self.allocator.destroy(self);
    }
};
const AstDB = @import("astdb");
const ASTDBSystem = AstDB.ASTDBSystem;

// Inline hex formatting helper
inline fn hexFmt(hash: []const u8, buf: []u8) void {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
}


test "LLVM Dispatch Codegen - Direct Call Generation" {
    const allocator = testing.allocator;

    // Initialize the semantic foundation
    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    // Forge the codegen engine
    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Create a high-frequency call site for direct optimization
    const call_site = CallSite{
        .node_id = 42,
        .function_name = "fibonacci",
        .arg_types = &[_]u32{1}, // i32 type
        .return_type = 1, // i32 return
        .source_location = .{ .file_id = 1, .line = 15, .column = 8 },
        .call_frequency = 5000.0, // High frequency -> direct call
    };

    const strategy = Strategy{
        .direct_call = .{
            .target_function = "fibonacci_optimized",
            .rationale = "High-frequency recursive function optimized for direct dispatch",
        },
    };

    // Transmute semantic intent into LLVM reality
    const ir_ref = try codegen.emitCall(call_site, strategy);

    // Verify the compiler's voice speaks LLVM
    try testing.expect(std.mem.eql(u8, ir_ref.function_name, "fibonacci"));
    try testing.expect(ir_ref.ir_text.len > 0);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "define i32 @fibonacci") != null);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "call i32 @fibonacci_optimized") != null);

    // Verify deterministic hash for golden snapshots
    try testing.expect(ir_ref.metadata.deterministic_hash.len == 32);
    try testing.expect(ir_ref.metadata.strategy_used == .direct_call);

    std.debug.print("✅ Direct call IR generated successfully\n");
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&ir_ref.metadata.deterministic_hash.len * 2]u8 = undefined;
        for (&ir_ref.metadata.deterministic_hash, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("IR Hash: {s}\n", .{hex_buf});
    }
}

test "LLVM Dispatch Codegen - Switch Dispatch Generation" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Create a moderate-frequency call site for switch dispatch
    const call_site = CallSite{
        .node_id = 84,
        .function_name = "process_event",
        .arg_types = &[_]u32{ 1, 2 }, // event_type: i32, data: i32
        .return_type = 1,
        .source_location = .{ .file_id = 2, .line = 25, .column = 12 },
        .call_frequency = 500.0, // Moderate frequency -> switch dispatch
    };

    const strategy = Strategy{
        .switch_dispatch = .{
            .case_count = 4,
            .default_target = null,
            .rationale = "Event processing with known case count benefits from switch optimization",
        },
    };

    const ir_ref = try codegen.emitCall(call_site, strategy);

    // Verify switch-based IR generation
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "switch i32 %arg0") != null);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "label %case0") != null);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "label %case1") != null);
    try testing.expect(ir_ref.metadata.strategy_used == .switch_dispatch);

    std.debug.print("✅ Switch dispatch IR generated successfully\n");
}

test "LLVM Dispatch Codegen - Jump Table Stub Generation" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    const family_id: u32 = 100;
    const strategy = Strategy{
        .jump_table = .{
            .table_size = 16,
            .density = 0.8,
            .rationale = "Dense dispatch family benefits from jump table optimization",
        },
    };

    // Generate dispatch stub for family
    const ir_ref = try codegen.emitStub(family_id, strategy);

    // Verify jump table stub generation
    try testing.expect(std.mem.startsWith(u8, ir_ref.function_name, "dispatch_stub_family_"));
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "getelementptr") != null);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "@jump_table") != null);
    try testing.expect(ir_ref.metadata.strategy_used == .jump_table);

    std.debug.print("✅ Jump table stub generated successfully\n");
}

test "LLVM Dispatch Codegen - Perfect Hash Stub Generation" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    const family_id: u32 = 200;
    const strategy = Strategy{
        .perfect_hash = .{
            .hash_function = "perfect_hash_fn",
            .collision_rate = 0.0,
            .rationale = "Sparse dispatch family with perfect hash function available",
        },
    };

    const ir_ref = try codegen.emitStub(family_id, strategy);

    // Verify perfect hash stub generation
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "call i32 @perfect_hash_fn") != null);
    try testing.expect(std.mem.indexOf(u8, ir_ref.ir_text, "@hash_table") != null);
    try testing.expect(ir_ref.metadata.strategy_used == .perfect_hash);

    std.debug.print("✅ Perfect hash stub generated successfully\n");
}

test "LLVM Dispatch Codegen - IR Dump Functionality" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Generate some IR first
    const call_site = CallSite{
        .node_id = 1,
        .function_name = "test_function",
        .arg_types = &[_]u32{1},
        .return_type = 1,
        .source_location = .{ .file_id = 1, .line = 1, .column = 1 },
        .call_frequency = 100.0,
    };

    const strategy = Strategy{
        .direct_call = .{
            .target_function = "test_target",
            .rationale = "Test IR generation",
        },
    };

    _ = try codegen.emitCall(call_site, strategy);

    // Test IR dump (output goes to debug print)
    std.debug.print("\n=== Testing IR Dump ===\n");
    try codegen.dumpIR(1, .llvm_ir);
    try codegen.dumpIR(1, .debug_info);

    std.debug.print("✅ IR dump functionality verified\n");
}

test "LLVM Dispatch Codegen - Deterministic Hash Consistency" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen1 = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen1.deinit();

    var codegen2 = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen2.deinit();

    const call_site = CallSite{
        .node_id = 1,
        .function_name = "deterministic_test",
        .arg_types = &[_]u32{1},
        .return_type = 1,
        .source_location = .{ .file_id = 1, .line = 1, .column = 1 },
        .call_frequency = 100.0,
    };

    const strategy = Strategy{
        .direct_call = .{
            .target_function = "deterministic_target",
            .rationale = "Deterministic hash test",
        },
    };

    // Generate identical IR with two different codegen instances
    const ir_ref1 = try codegen1.emitCall(call_site, strategy);
    const ir_ref2 = try codegen2.emitCall(call_site, strategy);

    // Verify deterministic hashes are identical
    try testing.expect(std.mem.eql(u8, &ir_ref1.metadata.deterministic_hash, &ir_ref2.metadata.deterministic_hash));

    std.debug.print("✅ Deterministic hash consistency verified\n");
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&ir_ref1.metadata.deterministic_hash.len * 2]u8 = undefined;
        for (&ir_ref1.metadata.deterministic_hash, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("Hash: {s}\n", .{hex_buf});
    }
}

test "LLVM Dispatch Codegen - AI Auditability" {
    const allocator = testing.allocator;

    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Generate multiple calls with different strategies
    const sites = [_]CallSite{
        .{
            .node_id = 1,
            .function_name = "hot_path",
            .arg_types = &[_]u32{1},
            .return_type = 1,
            .source_location = .{ .file_id = 1, .line = 10, .column = 5 },
            .call_frequency = 10000.0, // Should get direct call
        },
        .{
            .node_id = 2,
            .function_name = "moderate_path",
            .arg_types = &[_]u32{ 1, 2 },
            .return_type = 1,
            .source_location = .{ .file_id = 1, .line = 20, .column = 8 },
            .call_frequency = 500.0, // Should get switch dispatch
        },
        .{
            .node_id = 3,
            .function_name = "complex_path",
            .arg_types = &[_]u32{ 1, 2, 3, 4, 5 },
            .return_type = 1,
            .source_location = .{ .file_id = 1, .line = 30, .column = 12 },
            .call_frequency = 50.0, // Should get jump table
        },
    };

    // Let the strategy selector choose optimal strategies
    for (sites) |site| {
        const strategy = try codegen.strategy_selector.selectStrategy(site);
        _ = try codegen.emitCall(site, strategy);
    }

    // Verify AI auditability - all decisions should be recorded
    const decisions = codegen.optimization_tracker.getDecisionHistory();
    try testing.expect(decisions.len == 3);

    // Verify strategy selection rationale
    try testing.expect(decisions[0].strategy == .direct_call); // Hot path
    try testing.expect(decisions[1].strategy == .switch_dispatch); // Moderate path
    try testing.expect(decisions[2].strategy == .jump_table); // Complex path

    std.debug.print("✅ AI auditability verified - {} decisions recorded\n", .{decisions.len});

    // Print decision audit trail
    for (decisions, 0..) |decision, i| {
        std.debug.print("Decision {}: {} -> {} (freq: {d:.1f})\n", .{ i + 1, decision.site.function_name, @tagName(decision.strategy), decision.site.call_frequency });
    }
}

test "LLVM Dispatch Codegen - End-to-End Integration" {
    const allocator = testing.allocator;

    // This test verifies the complete pipeline from semantic analysis to LLVM IR
    var astdb = try ASTDBSystem.init(allocator, true);
    defer astdb.deinit();

    // Add a simple Janus program to ASTDB
    const source =
        \\func fibonacci(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return n
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2)
        \\}
        \\
        \\func main() -> i32 {
        \\    return fibonacci(10)
        \\}
    ;

    const unit_id = try astdb.addUnit("fibonacci.jan", source);

    // Perform semantic validation
    var validation_engine = try MockValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var validation_result = try validation_engine.validateUnit(unit_id);
    defer validation_result.deinit(allocator);

    try testing.expect(validation_result.success);

    // Generate LLVM IR from validated semantic information
    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Simulate call site analysis from semantic validation
    const fibonacci_site = CallSite{
        .node_id = 1,
        .function_name = "fibonacci",
        .arg_types = &[_]u32{1}, // i32
        .return_type = 1, // i32
        .source_location = .{ .file_id = unit_id, .line = 1, .column = 1 },
        .call_frequency = 1000.0, // Recursive calls are frequent
    };

    const main_site = CallSite{
        .node_id = 2,
        .function_name = "main",
        .arg_types = &[_]u32{},
        .return_type = 1, // i32
        .source_location = .{ .file_id = unit_id, .line = 7, .column = 1 },
        .call_frequency = 1.0, // Called once
    };

    // Generate optimized IR for both functions
    const fib_strategy = try codegen.strategy_selector.selectStrategy(fibonacci_site);
    const main_strategy = try codegen.strategy_selector.selectStrategy(main_site);

    const fib_ir = try codegen.emitCall(fibonacci_site, fib_strategy);
    const main_ir = try codegen.emitCall(main_site, main_strategy);

    // Verify end-to-end pipeline
    try testing.expect(std.mem.eql(u8, fib_ir.function_name, "fibonacci"));
    try testing.expect(std.mem.eql(u8, main_ir.function_name, "main"));
    try testing.expect(fib_ir.metadata.strategy_used == .direct_call); // High frequency

    std.debug.print("✅ End-to-end integration successful\n");
    std.debug.print("Generated IR for {} functions\n", .{codegen.generated_functions.items.len});

    // Dump the complete IR for inspection
    std.debug.print("\n=== Complete Generated IR ===\n");
    try codegen.dumpIR(1, .llvm_ir);
}
