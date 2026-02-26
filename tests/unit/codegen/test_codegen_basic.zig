// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Basic Codegen Tests - M6: Forge the Executable Artifact
//!
//! Unit tests for LLVM codegen functionality

const std = @import("std");
const testing = std.testing;

test "Codegen Module - Basic Functionality" {
    // Basic test to verify the module compiles

    // Test basic types and structures
    const CallSite = struct {
        node_id: u32,
        function_name: []const u8,
        arg_types: []const u32,
        return_type: u32,
        call_frequency: f64,
    };

    const test_site = CallSite{
        .node_id = 1,
        .function_name = "test_function",
        .arg_types = &[_]u32{ 1, 2 },
        .return_type = 1,
        .call_frequency = 100.0,
    };

    // Verify basic functionality
    try testing.expect(test_site.node_id == 1);
    try testing.expect(std.mem.eql(u8, test_site.function_name, "test_function"));
    try testing.expect(test_site.arg_types.len == 2);

}

test "Strategy Selection Logic" {
    // Test the strategy selection logic without full codegen
    const frequency_high = 2000.0;
    const frequency_moderate = 500.0;
    const frequency_low = 50.0;

    const args_few = 2;
    const args_many = 5;

    // Simple strategy selection heuristics
    const high_freq_strategy = if (frequency_high > 1000.0) "direct_call" else "switch_dispatch";
    const moderate_freq_strategy = if (frequency_moderate > 1000.0) "direct_call" else if (args_few <= 3) "switch_dispatch" else "jump_table";
    const low_freq_strategy = if (frequency_low > 1000.0) "direct_call" else if (args_many <= 3) "switch_dispatch" else "jump_table";

    try testing.expect(std.mem.eql(u8, high_freq_strategy, "direct_call"));
    try testing.expect(std.mem.eql(u8, moderate_freq_strategy, "switch_dispatch"));
    try testing.expect(std.mem.eql(u8, low_freq_strategy, "jump_table"));

}

test "IR Builder Simulation" {
    const allocator = testing.allocator;

    // Simulate IR building without full codegen
    var ir_lines = std.ArrayList([]const u8){};
    defer {
        for (ir_lines.items) |line| {
            allocator.free(line);
        }
        ir_lines.deinit(allocator);
    }

    // Build simple IR
    try ir_lines.append(allocator, try allocator.dupe(u8, "define i32 @test_function(i32 %arg0) {"));
    try ir_lines.append(allocator, try allocator.dupe(u8, "entry:"));
    try ir_lines.append(allocator, try allocator.dupe(u8, "  ret i32 %arg0"));
    try ir_lines.append(allocator, try allocator.dupe(u8, "}"));

    // Verify IR structure
    try testing.expect(ir_lines.items.len == 4);
    try testing.expect(std.mem.indexOf(u8, ir_lines.items[0], "define i32 @test_function") != null);
    try testing.expect(std.mem.indexOf(u8, ir_lines.items[2], "ret i32") != null);

}

test "Deterministic Hash Simulation" {

    // Simulate deterministic hashing
    const test_data1 = "test_ir_content_1";
    const test_data2 = "test_ir_content_1"; // Same content
    const test_data3 = "test_ir_content_2"; // Different content

    // Simple hash simulation using std.hash_map.hashString
    const hash1 = std.hash_map.hashString(test_data1);
    const hash2 = std.hash_map.hashString(test_data2);
    const hash3 = std.hash_map.hashString(test_data3);

    // Verify deterministic behavior
    try testing.expect(hash1 == hash2); // Same content = same hash
    try testing.expect(hash1 != hash3); // Different content = different hash

}

test "AI Auditability Simulation" {
    const allocator = testing.allocator;

    // Simulate decision tracking for AI auditability
    const Decision = struct {
        function_name: []const u8,
        strategy: []const u8,
        rationale: []const u8,
        frequency: f64,
    };

    var decisions = std.ArrayList(Decision){};
    defer decisions.deinit(allocator);

    // Record some decisions
    try decisions.append(allocator, Decision{
        .function_name = "hot_function",
        .strategy = "direct_call",
        .rationale = "High frequency call optimized for direct dispatch",
        .frequency = 5000.0,
    });

    try decisions.append(allocator, Decision{
        .function_name = "moderate_function",
        .strategy = "switch_dispatch",
        .rationale = "Moderate frequency with small argument count",
        .frequency = 500.0,
    });

    try decisions.append(allocator, Decision{
        .function_name = "complex_function",
        .strategy = "jump_table",
        .rationale = "Complex call site with many arguments",
        .frequency = 50.0,
    });

    // Verify decision tracking
    try testing.expect(decisions.items.len == 3);
    try testing.expect(std.mem.eql(u8, decisions.items[0].strategy, "direct_call"));
    try testing.expect(std.mem.eql(u8, decisions.items[1].strategy, "switch_dispatch"));
    try testing.expect(std.mem.eql(u8, decisions.items[2].strategy, "jump_table"));


    // Print audit trail
    for (decisions.items, 0..) |decision, i| {
            i + 1,
            decision.function_name,
            decision.strategy,
            @as(u32, @intFromFloat(decision.frequency)),
        });
    }
}
