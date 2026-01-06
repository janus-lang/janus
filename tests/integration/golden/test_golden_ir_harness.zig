// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Golden IR Test Harness Integration Tests
//!
//! Demonstrates forensic reproducibility of LLVM IR generation
//! across platforms and time. The compiler's voice must speak
//! the same truth in all worlds.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Import the golden harness
const golden = @import("golden");
const IRHarness = golden.IRHarness;
const GoldenSnapshot = golden.GoldenSnapshot;
const PerformanceContract = golden.PerformanceContract;

// Import the compiler's voice
const codegen_module = @import("codegen");
const DispatchCodegen = codegen_module.DispatchCodegen;
const CallSite = codegen_module.CallSite;
const Strategy = codegen_module.Strategy;

// Semantic foundation
const semantic_module = @import("semantic");
const ValidationEngine = semantic_module.ValidationEngine;
const astdb_api = @import("astdb");
const ASTDBSystem = astdb_api.ASTDBSystem;

test "Golden IR Harness - End-to-End Forensic Validation" {
    const allocator = testing.allocator;

    std.debug.print("\n🔬 Golden IR Harness - Forensic Validation Test\n", .{});
    std.debug.print("================================================\n", .{});

    // Initialize the forensic system
    var harness = IRHarness.init(allocator);
    defer harness.deinit();

    // Initialize the compiler's voice
    var astdb = try ASTDBSystem.init(allocator, true); // deterministic mode for golden tests
    defer astdb.deinit();

    var validation_engine = try ValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    codegen.setGoldenMode(true);
    defer codegen.deinit();

    // Test Case 1: Fibonacci Function - High Frequency Direct Call
    std.debug.print("\n📋 Test Case 1: Fibonacci Function (High Frequency)\n", .{});

    const fibonacci_source =
        \\func fibonacci(n: i32) -> i32 {
        \\    if n <= 1 {
        \\        return n
        \\    }
        \\    return fibonacci(n - 1) + fibonacci(n - 2)
        \\}
    ;

    const fibonacci_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 1,
        .arg_types = &[_]u32{1}, // i32
        .hotness = 5000.0, // High frequency -> direct call
    };

    const fibonacci_strategy = try codegen.strategy_selector.selectOptimalStrategy(fibonacci_site);
    const fibonacci_ir = try codegen.emitCall(fibonacci_site, fibonacci_strategy);

    // Capture golden snapshot
    try harness.captureSnapshot("fibonacci_high_freq", fibonacci_source, fibonacci_ir);

    // Test Case 2: Event Handler - Switch Dispatch
    std.debug.print("\n📋 Test Case 2: Event Handler (Switch Dispatch)\n", .{});

    const event_source =
        \\func handleEvent(eventType: i32, data: i32) -> i32 {
        \\    switch eventType {
        \\        case 0: return processClick(data)
        \\        case 1: return processKeypress(data)
        \\        case 2: return processMouseMove(data)
        \\        default: return -1
        \\    }
        \\}
    ;

    const event_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 2, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 5,
        .arg_types = &[_]u32{ 1, 1 }, // i32, i32
        .hotness = 800.0, // Moderate frequency -> switch dispatch
    };

    const event_strategy = try codegen.strategy_selector.selectOptimalStrategy(event_site);
    const event_ir = try codegen.emitCall(event_site, event_strategy);

    try harness.captureSnapshot("event_handler_switch", event_source, event_ir);

    // Test Case 3: Complex Dispatcher - Jump Table
    std.debug.print("\n📋 Test Case 3: Complex Dispatcher (Jump Table)\n", .{});

    const dispatcher_source =
        \\func complexDispatch(a: i32, b: i32, c: i32, d: i32, e: i32) -> i32 {
        \\    return processComplex(a, b, c, d, e)
        \\}
    ;

    const dispatcher_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 3, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 6,
        .arg_types = &[_]u32{ 1, 1, 1, 1, 1 }, // 5 i32 args
        .hotness = 100.0, // Lower frequency -> jump table
    };

    const dispatcher_strategy = try codegen.strategy_selector.selectOptimalStrategy(dispatcher_site);
    const dispatcher_ir = try codegen.emitCall(dispatcher_site, dispatcher_strategy);

    try harness.captureSnapshot("complex_dispatcher_jump", dispatcher_source, dispatcher_ir);

    // Verify we captured all snapshots
    try testing.expect(harness.snapshots.items.len == 3);

    std.debug.print("\n✅ Captured {} golden snapshots\n", .{harness.snapshots.items.len});
}

test "Golden IR Harness - Cross-Platform Equivalence Validation" {
    const allocator = testing.allocator;

    std.debug.print("\n🌍 Cross-Platform Equivalence Validation\n", .{});
    std.debug.print("=========================================\n", .{});

    var harness = IRHarness.init(allocator);
    defer harness.deinit();

    // Simulate the same code generation on different platforms
    var astdb = try ASTDBSystem.init(allocator, true); // deterministic mode for golden tests
    defer astdb.deinit();

    var validation_engine = try ValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen_linux = try DispatchCodegen.init(allocator, validation_engine);
    codegen_linux.setGoldenMode(true);
    defer codegen_linux.deinit();

    var codegen_macos = try DispatchCodegen.init(allocator, validation_engine);
    codegen_macos.setGoldenMode(true);
    defer codegen_macos.deinit();

    const test_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 2,
        .arg_types = &[_]u32{1},
        .hotness = 1000.0,
    };

    const strategy = Strategy.Static;

    // Generate IR on both "platforms"
    const linux_ir = try codegen_linux.emitCall(test_site, strategy);
    const macos_ir = try codegen_macos.emitCall(test_site, strategy);

    // Capture golden snapshot from "Linux"
    try harness.captureSnapshot("cross_platform_test", "func test() -> i32 { return 42 }", linux_ir);

    // Compare "macOS" generation against golden
    const diffs = try harness.compareWithGolden("cross_platform_test", macos_ir);
    defer {
        for (diffs) |d| {
            allocator.free(d.expected);
            allocator.free(d.actual);
            allocator.free(d.explanation);
        }
        allocator.free(diffs);
    }

    // Should have no differences (deterministic generation)
    if (diffs.len == 0) {
        std.debug.print("✅ Cross-platform equivalence VERIFIED\n", .{});
    } else {
        std.debug.print("❌ Cross-platform differences detected: {} diffs\n", .{diffs.len});
        for (diffs) |diff| {
            const formatted = try diff.format(allocator);
            defer allocator.free(formatted);
            std.debug.print("{s}\n", .{formatted});
        }
    }

    // Enforce equivalence
    try testing.expect(diffs.len == 0);
}

test "Golden IR Harness - Performance Contract Enforcement" {
    const allocator = testing.allocator;

    std.debug.print("\n📊 Performance Contract Enforcement\n", .{});
    std.debug.print("===================================\n", .{});

    var harness = IRHarness.init(allocator);
    defer harness.deinit();

    // Add performance contracts for M6
    try harness.addPerformanceContract("ir_generation_ms", 5.0, 20.0, 0.95);
    try harness.addPerformanceContract("strategy_selection_ms", 1.0, 15.0, 0.99);
    try harness.addPerformanceContract("hash_computation_ms", 0.5, 10.0, 0.95);

    // Simulate performance measurements
    const measurements = [_]struct { name: []const u8, value: f64 }{
        .{ .name = "ir_generation_ms", .value = 4.2 }, // Within tolerance
        .{ .name = "strategy_selection_ms", .value = 0.9 }, // Within tolerance (±15%)
        .{ .name = "hash_computation_ms", .value = 0.5 }, // Within tolerance (±10%)
    };

    var all_passed = true;

    for (measurements) |measurement| {
        const result = try harness.validatePerformance(measurement.name, measurement.value);
        if (!result.passed) {
            all_passed = false;
        }
    }

    if (all_passed) {
        std.debug.print("\n🎉 All performance contracts PASSED!\n", .{});
    } else {
        std.debug.print("\n❌ Some performance contracts FAILED!\n", .{});
    }
    // Enforce contracts
    try testing.expect(all_passed);
}

test "Golden IR Harness - Regression Detection" {
    const allocator = testing.allocator;

    std.debug.print("\n🔍 Regression Detection Test\n", .{});
    std.debug.print("============================\n", .{});

    var harness = IRHarness.init(allocator);
    defer harness.deinit();

    var astdb = try ASTDBSystem.init(allocator, true); // deterministic mode for golden tests
    defer astdb.deinit();

    var validation_engine = try ValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    // Original "good" version
    const original_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 3,
        .arg_types = &[_]u32{1},
        .hotness = 2000.0, // Should get direct call
    };

    const original_strategy = try codegen.strategy_selector.selectOptimalStrategy(original_site);
    const original_ir = try codegen.emitCall(original_site, original_strategy);

    // Capture as golden
    try harness.captureSnapshot("regression_test", "func test() -> i32 { return 42 }", original_ir);

    // Simulate a "regression" - different frequency leads to different strategy
    const regressed_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 3,
        .arg_types = &[_]u32{1},
        .hotness = 500.0, // Lower frequency -> different strategy
    };

    const regressed_strategy = try codegen.strategy_selector.selectOptimalStrategy(regressed_site);
    const regressed_ir = try codegen.emitCall(regressed_site, regressed_strategy);

    // Compare against golden
    const diffs = try harness.compareWithGolden("regression_test", regressed_ir);
    defer {
        for (diffs) |d| {
            allocator.free(d.expected);
            allocator.free(d.actual);
            allocator.free(d.explanation);
        }
        allocator.free(diffs);
    }

    if (diffs.len > 0) {
        std.debug.print("🚨 REGRESSION DETECTED: {} differences found\n", .{diffs.len});

        for (diffs) |diff| {
            std.debug.print("   - {s}: {s} -> {s}\n", .{ @tagName(diff.diff_type), diff.expected[0..@min(20, diff.expected.len)], diff.actual[0..@min(20, diff.actual.len)] });
        }

        // Check if this is an approved difference
        const platform = "test-platform";
        var approved_count: u32 = 0;

        for (diffs) |diff| {
            if (harness.isDifferenceApproved(diff, platform)) {
                approved_count += 1;
            }
        }

        if (approved_count == diffs.len) {
            std.debug.print("✅ All differences are approved for platform: {s}\n", .{platform});
        } else {
            std.debug.print("❌ {} unapproved differences detected\n", .{diffs.len - approved_count});
        }
    } else {
        std.debug.print("✅ No regression detected - IR generation is stable\n", .{});
    }

    // For this test, we expect differences (strategy change)
    try testing.expect(diffs.len > 0);
}

test "Golden IR Harness - Snapshot Persistence" {
    const allocator = testing.allocator;

    std.debug.print("\n💾 Snapshot Persistence Test\n", .{});
    std.debug.print("============================\n", .{});

    var harness = IRHarness.init(allocator);
    defer harness.deinit();

    // Create a test snapshot
    var astdb = try ASTDBSystem.init(allocator, true); // deterministic mode for golden tests
    defer astdb.deinit();

    var validation_engine = try ValidationEngine.init(allocator, &astdb);
    defer validation_engine.deinit();

    var codegen = try DispatchCodegen.init(allocator, validation_engine);
    defer codegen.deinit();

    const test_site = CallSite{
        .unit_id = 1,
        .loc = .{ .file_id = 1, .start_line = 1, .start_col = 1, .end_line = 1, .end_col = 1 },
        .family = 4,
        .arg_types = &[_]u32{1},
        .hotness = 1000.0,
    };

    const strategy = Strategy.Static;

    const ir_ref = try codegen.emitCall(test_site, strategy);
    try harness.captureSnapshot("persistence_test", "func test() -> i32 { return 42 }", ir_ref);

    // Save snapshots to disk
    const test_dir = "test_golden_snapshots";
    try harness.saveSnapshots(test_dir);

    // Verify file was created
    const filename = try std.fmt.allocPrint(allocator, "{s}/persistence_test.json", .{test_dir});
    defer allocator.free(filename);

    var file_exists = true;
    std.fs.cwd().access(filename, .{}) catch {
        file_exists = false;
    };
    if (file_exists) {
        std.debug.print("✅ Snapshot saved successfully: {s}\n", .{filename});

        // Clean up test file
        std.fs.cwd().deleteFile(filename) catch {};
        std.fs.cwd().deleteDir(test_dir) catch {};
    } else {
        std.debug.print("❌ Snapshot file not found: {s}\n", .{filename});
    }

    try testing.expect(file_exists);
}
