// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const testing = std.testing;
const api = @import("compiler/libjanus/api.zig");
const astdb = @import("compiler/libjanus/astdb.zig");
const Semantic = @import("compiler/libjanus/semantic.zig");

test "Revolutionary Standard Library Integration - ASTDB + Capability Resolution" {
    std.debug.print("\n🚀 REVOLUTIONARY STANDARD LIBRARY INTEGRATION TEST\n", .{});
    std.debug.print("==================================================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Phase 1: Revolutionary ASTDB System Initialization
    std.debug.print("📊 Phase 1: ASTDB System Initialization\n", .{});
    var astdb_system = astdb.ASTDBSystem.init(allocator, true) catch |err| {
        std.debug.print("❌ ASTDB initialization failed: {}\n", .{err});
        return err;
    };
    defer astdb_system.deinit();
    std.debug.print("✅ ASTDB system initialized\n", .{});

    // Phase 2: Revolutionary Semantic Analysis with Standard Library Integration
    std.debug.print("\n🔒 Phase 2: Revolutionary Semantic Analysis with Standard Library Integration\n", .{});
    var semantic_graph = api.analyzeWithASTDB(&astdb_system, allocator) catch |err| {
        std.debug.print("❌ Semantic analysis failed: {}\n", .{err});
        return err;
    };
    defer semantic_graph.deinit();
    std.debug.print("✅ Semantic analysis successful\n", .{});

    // Phase 3: Verify Standard Library Symbol Registration
    std.debug.print("\n🔍 Phase 3: Standard Library Symbol Verification\n", .{});

    const print_symbol = semantic_graph.findSymbol("print");
    try testing.expect(print_symbol != null);
    try testing.expect(print_symbol.?.kind == .StdLibFunction);
    try testing.expect(std.mem.eql(u8, print_symbol.?.module_path.?, "std.io"));
    std.debug.print("✅ print() resolved to std.io.print\n", .{});

    const eprint_symbol = semantic_graph.findSymbol("eprint");
    try testing.expect(eprint_symbol != null);
    try testing.expect(eprint_symbol.?.kind == .StdLibFunction);
    try testing.expect(std.mem.eql(u8, eprint_symbol.?.module_path.?, "std.io"));
    std.debug.print("✅ eprint() resolved to std.io.eprint\n", .{});

    // Phase 4: Verify Capability Type Registration
    std.debug.print("\n🔐 Phase 4: Capability Type Verification\n", .{});

    const stdout_cap_symbol = semantic_graph.findSymbol("StdoutWriteCapability");
    try testing.expect(stdout_cap_symbol != null);
    try testing.expect(stdout_cap_symbol.?.kind == .CapabilityType);
    std.debug.print("✅ StdoutWriteCapability type registered\n", .{});

    const stderr_cap_symbol = semantic_graph.findSymbol("StderrWriteCapability");
    try testing.expect(stderr_cap_symbol != null);
    try testing.expect(stderr_cap_symbol.?.kind == .CapabilityType);
    std.debug.print("✅ StderrWriteCapability type registered\n", .{});

    // Phase 5: Test ASTDB Integration
    std.debug.print("\n🗄️ Phase 5: ASTDB Integration Verification\n", .{});

    // Test string interning
    const test_str = semantic_graph.internString("test_string") catch |err| {
        std.debug.print("❌ String interning failed: {}\n", .{err});
        return err;
    };
    std.debug.print("✅ String interning operational: {}\n", .{test_str});

    // Test ASTDB statistics
    const astdb_stats = astdb_system.stats();
    std.debug.print("📊 ASTDB Stats: {} interned strings, {} cached CIDs\n", .{
        astdb_stats.interned_strings,
        astdb_stats.cached_cids,
    });

    // Final Results
    std.debug.print("\n🎉 REVOLUTIONARY INTEGRATION TEST RESULTS:\n", .{});
    std.debug.print("✅ ASTDB system operational and integrated\n", .{});
    std.debug.print("✅ Standard library symbols correctly registered\n", .{});
    std.debug.print("✅ Capability types properly defined\n", .{});
    std.debug.print("✅ String interning functional\n", .{});
    std.debug.print("✅ Revolutionary semantic analysis architecture operational\n", .{});

    std.debug.print("\n🚀 THE COMPILER NOW SPEAKS THE REVOLUTIONARY LANGUAGE OF CAPABILITIES! 🚀\n", .{});
}

test "Capability Requirement Inference - Simulated Function Calls" {
    std.debug.print("\n🔧 CAPABILITY REQUIREMENT INFERENCE TEST\n", .{});
    std.debug.print("=======================================\n", .{});

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB system
    var astdb_system = astdb.ASTDBSystem.init(allocator, true) catch |err| {
        std.debug.print("❌ ASTDB initialization failed: {}\n", .{err});
        return err;
    };
    defer astdb_system.deinit();

    // Initialize semantic graph
    var semantic_graph = api.analyzeWithASTDB(&astdb_system, allocator) catch |err| {
        std.debug.print("❌ Semantic analysis failed: {}\n", .{err});
        return err;
    };
    defer semantic_graph.deinit();

    // Simulate requiring capabilities (as would happen during function call analysis)
    std.debug.print("🔍 Simulating print() call - requiring StdoutWriteCapability\n", .{});
    semantic_graph.requireCapability(Semantic.Type.StdoutWriteCapability) catch |err| {
        std.debug.print("❌ Capability requirement failed: {}\n", .{err});
        return err;
    };

    std.debug.print("🔍 Simulating eprint() call - requiring StderrWriteCapability\n", .{});
    semantic_graph.requireCapability(Semantic.Type.StderrWriteCapability) catch |err| {
        std.debug.print("❌ Capability requirement failed: {}\n", .{err});
        return err;
    };

    // Verify capability requirements
    const required_caps = semantic_graph.getRequiredCapabilities();
    std.debug.print("📋 Required capabilities: {d}\n", .{required_caps.len});

    var stdout_cap_found = false;
    var stderr_cap_found = false;

    for (required_caps) |cap| {
        const cap_name = cap.toString();
        std.debug.print("  - {s}\n", .{cap_name});

        if (cap == .StdoutWriteCapability) stdout_cap_found = true;
        if (cap == .StderrWriteCapability) stderr_cap_found = true;
    }

    // Verify that both capabilities were detected
    try testing.expect(stdout_cap_found);
    try testing.expect(stderr_cap_found);
    try testing.expect(required_caps.len == 2);

    std.debug.print("\n🎉 CAPABILITY INFERENCE TEST RESULTS:\n", .{});
    std.debug.print("✅ StdoutWriteCapability correctly inferred\n", .{});
    std.debug.print("✅ StderrWriteCapability correctly inferred\n", .{});
    std.debug.print("✅ No duplicate capability requirements\n", .{});
    std.debug.print("✅ Capability tracking operational\n", .{});

    std.debug.print("\n🔐 THE CAPABILITY SYSTEM IS OPERATIONAL! 🔐\n", .{});
}
