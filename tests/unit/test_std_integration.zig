// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const api = @import("compiler/libjanus/api.zig");
const astdb = @import("compiler/libjanus/astdb.zig");
const Semantic = @import("compiler/libjanus/semantic.zig");

test "Revolutionary Standard Library Integration - ASTDB + Capability Resolution" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Phase 1: Revolutionary ASTDB System Initialization
    var astdb_system = astdb.ASTDBSystem.init(allocator, true) catch |err| {
        return err;
    };
    defer astdb_system.deinit();

    // Phase 2: Revolutionary Semantic Analysis with Standard Library Integration
    var semantic_graph = api.analyzeWithASTDB(&astdb_system, allocator) catch |err| {
        return err;
    };
    defer semantic_graph.deinit();

    // Phase 3: Verify Standard Library Symbol Registration

    const print_symbol = semantic_graph.findSymbol("print");
    try testing.expect(print_symbol != null);
    try testing.expect(print_symbol.?.kind == .StdLibFunction);
    try testing.expect(std.mem.eql(u8, print_symbol.?.module_path.?, "std.io"));

    const eprint_symbol = semantic_graph.findSymbol("eprint");
    try testing.expect(eprint_symbol != null);
    try testing.expect(eprint_symbol.?.kind == .StdLibFunction);
    try testing.expect(std.mem.eql(u8, eprint_symbol.?.module_path.?, "std.io"));

    // Phase 4: Verify Capability Type Registration

    const stdout_cap_symbol = semantic_graph.findSymbol("StdoutWriteCapability");
    try testing.expect(stdout_cap_symbol != null);
    try testing.expect(stdout_cap_symbol.?.kind == .CapabilityType);

    const stderr_cap_symbol = semantic_graph.findSymbol("StderrWriteCapability");
    try testing.expect(stderr_cap_symbol != null);
    try testing.expect(stderr_cap_symbol.?.kind == .CapabilityType);

    // Phase 5: Test ASTDB Integration

    // Test string interning
    const test_str = semantic_graph.internString("test_string") catch |err| {
        return err;
    };

    // Test ASTDB statistics
    const astdb_stats = astdb_system.stats();
        astdb_stats.interned_strings,
        astdb_stats.cached_cids,
    });

    // Final Results

}

test "Capability Requirement Inference - Simulated Function Calls" {

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB system
    var astdb_system = astdb.ASTDBSystem.init(allocator, true) catch |err| {
        return err;
    };
    defer astdb_system.deinit();

    // Initialize semantic graph
    var semantic_graph = api.analyzeWithASTDB(&astdb_system, allocator) catch |err| {
        return err;
    };
    defer semantic_graph.deinit();

    // Simulate requiring capabilities (as would happen during function call analysis)
    semantic_graph.requireCapability(Semantic.Type.StdoutWriteCapability) catch |err| {
        return err;
    };

    semantic_graph.requireCapability(Semantic.Type.StderrWriteCapability) catch |err| {
        return err;
    };

    // Verify capability requirements
    const required_caps = semantic_graph.getRequiredCapabilities();

    var stdout_cap_found = false;
    var stderr_cap_found = false;

    for (required_caps) |cap| {
        const cap_name = cap.toString();

        if (cap == .StdoutWriteCapability) stdout_cap_found = true;
        if (cap == .StderrWriteCapability) stderr_cap_found = true;
    }

    // Verify that both capabilities were detected
    try testing.expect(stdout_cap_found);
    try testing.expect(stderr_cap_found);
    try testing.expect(required_caps.len == 2);


}
