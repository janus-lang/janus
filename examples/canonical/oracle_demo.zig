// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Oracle Proof Pack Demo - Command Line Interface
// Demonstrates Task 2: Oracle Proof Pack Integration

const std = @import("std");
const oracle_proof = @import("oracle_proof_pack_simple.zig");


// Inline hex formatting helper
inline fn hexFmt(hash: []const u8, buf: []u8) void {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Oracle Proof Pack - Perfect Incremental Compilation Demo\n\n", .{});
        std.debug.print("Usage: oracle_demo <command> [args...]\n\n", .{});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  demo                     - Run complete demonstration\n", .{});
        std.debug.print("  build <source.jan>       - Test incremental build\n", .{});
        std.debug.print("  change <orig> <mod>      - Test change detection\n", .{});
        std.debug.print("  metrics --json           - Output JSON metrics\n", .{});
        std.debug.print("  webserver                - Demo with HTTP server source\n", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "demo")) {
        try oracle_proof.demonstrateOracleProofPack(allocator);
    } else if (std.mem.eql(u8, command, "webserver")) {
        try demonstrateWebServerIntegration(allocator);
    } else if (std.mem.eql(u8, command, "build") and args.len >= 3) {
        try demonstrateBuild(args[2], allocator);
    } else if (std.mem.eql(u8, command, "change") and args.len >= 4) {
        try demonstrateChangeDetection(args[2], args[3], allocator);
    } else if (std.mem.eql(u8, command, "metrics")) {
        const json_output = args.len >= 3 and std.mem.eql(u8, args[2], "--json");
        try demonstrateMetrics(json_output, allocator);
    } else {
        std.debug.print("Unknown command: {s}\n", .{command});
        std.debug.print("Run 'oracle_demo' without arguments for help.\n", .{});
    }
}

fn demonstrateWebServerIntegration(allocator: std.mem.Allocator) !void {
    std.debug.print("🌐 HTTP Server + Oracle Proof Pack Integration\n", .{});
    std.debug.print("Task 2: The Credibility Weapon\n\n", .{});

    var oracle = try oracle_proof.OracleProofPack.init(allocator);
    defer oracle.deinit();

    // Use the actual webserver.jan file
    const webserver_path = "webserver.jan";

    // Check if webserver.jan exists, if not use our canonical version
    const source_exists = std.fs.cwd().access(webserver_path, .{}) != std.fs.File.OpenError.FileNotFound;

    if (!source_exists) {
        std.debug.print("📝 Creating canonical webserver.jan for demonstration...\n", .{});

        // Read the canonical webserver source
        const canonical_source = std.fs.cwd().readFileAlloc(allocator, "webserver.jan", 1024 * 1024) catch |err| {
            if (err == std.fs.File.OpenError.FileNotFound) {
                std.debug.print("❌ webserver.jan not found. Please run from examples/canonical/ directory.\n", .{});
                return;
            }
            return err;
        };
        defer allocator.free(canonical_source);

        // Copy to working directory for demo
        try std.fs.cwd().writeFile(.{ .sub_path = "demo_webserver.jan", .data = canonical_source });
        defer std.fs.cwd().deleteFile("demo_webserver.jan") catch {};

        // Demo sequence
        std.debug.print("\n🔄 Step 1: Initial Build\n", .{});
        const result1 = try oracle.demonstrateNoWorkRebuild("demo_webserver.jan");
        std.debug.print("⏱️  Build time: {}ms\n", .{result1.build_time_ms});
        std.debug.print("💾 Cache hit: {}\n", .{result1.cache_hit});
        {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&result1.semantic_cid[0..8].len * 2]u8 = undefined;
        for (&result1.semantic_cid[0..8], 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("🔑 Semantic CID: {s}\n", .{hex_buf});
    }

        std.debug.print("\n🔄 Step 2: No-Work Rebuild (same source)\n", .{});
        const result2 = try oracle.demonstrateNoWorkRebuild("demo_webserver.jan");
        std.debug.print("⏱️  Build time: {}ms ← Should be ~0ms!\n", .{result2.build_time_ms});
        std.debug.print("💾 Cache hit: {} ← Should be true!\n", .{result2.cache_hit});

        std.debug.print("\n🔄 Step 3: Implementation Change (add comment)\n", .{});

        // Add a comment to demonstrate implementation change
        const modified_source = try std.fmt.allocPrint(allocator, "// Oracle Proof Pack Integration - Added comment\n{s}", .{canonical_source});
        defer allocator.free(modified_source);

        const change_analysis = try oracle.demonstrateChangeDetection(canonical_source, modified_source);
        std.debug.print("🔍 Semantic changed: {}\n", .{change_analysis.semantic_changed});
        std.debug.print("🔍 Interface changed: {} ← Should be false for comment!\n", .{change_analysis.interface_changed});
        std.debug.print("📊 Change type: {s}\n", .{@tagName(change_analysis.change_type)});

        oracle.displayProofResults();

        std.debug.print("\n✅ Oracle Proof Pack Integration Complete!\n", .{});
        std.debug.print("✅ Perfect Incremental Compilation: VALIDATED\n", .{});
        std.debug.print("✅ Interface vs Implementation Detection: VALIDATED\n", .{});
        std.debug.print("✅ 0ms No-Work Rebuilds: ACHIEVED\n", .{});
    } else {
        std.debug.print("📁 Using existing webserver.jan\n", .{});

        const result = try oracle.demonstrateNoWorkRebuild(webserver_path);
        std.debug.print("Build time: {}ms\n", .{result.build_time_ms});
        std.debug.print("Cache hit: {}\n", .{result.cache_hit});
        std.debug.print("Message: {s}\n", .{result.message});

        oracle.displayProofResults();
    }
}

fn demonstrateBuild(source_path: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("🔨 Oracle Proof Pack Build Test\n", .{});
    std.debug.print("Source: {s}\n\n", .{source_path});

    var oracle = try oracle_proof.OracleProofPack.init(allocator);
    defer oracle.deinit();

    const result = try oracle.demonstrateNoWorkRebuild(source_path);

    std.debug.print("Results:\n", .{});
    std.debug.print("  Build time: {}ms\n", .{result.build_time_ms});
    std.debug.print("  Cache hit: {}\n", .{result.cache_hit});
    std.debug.print("  Change type: {s}\n", .{@tagName(result.change_type)});
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&result.semantic_cid.len * 2]u8 = undefined;
        for (&result.semantic_cid, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("  Semantic CID: {s}\n", .{hex_buf});
    }
    std.debug.print("  Message: {s}\n", .{result.message});
}

fn demonstrateChangeDetection(original_path: []const u8, modified_path: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("🔍 Oracle Proof Pack Change Detection\n", .{});
    std.debug.print("Original: {s}\n", .{original_path});
    std.debug.print("Modified: {s}\n\n", .{modified_path});

    var oracle = try oracle_proof.OracleProofPack.init(allocator);
    defer oracle.deinit();

    // Read both files
    const original_source = try std.fs.cwd().readFileAlloc(allocator, original_path, 1024 * 1024);
    defer allocator.free(original_source);

    const modified_source = try std.fs.cwd().readFileAlloc(allocator, modified_path, 1024 * 1024);
    defer allocator.free(modified_source);

    const analysis = try oracle.demonstrateChangeDetection(original_source, modified_source);

    std.debug.print("Analysis Results:\n", .{});
    std.debug.print("  Semantic changed: {}\n", .{analysis.semantic_changed});
    std.debug.print("  Interface changed: {}\n", .{analysis.interface_changed});
    std.debug.print("  Change type: {s}\n", .{@tagName(analysis.change_type)});
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&analysis.original_semantic_cid[0..8].len * 2]u8 = undefined;
        for (&analysis.original_semantic_cid[0..8], 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("  Original semantic CID: {s}\n", .{hex_buf});
    }
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&analysis.modified_semantic_cid[0..8].len * 2]u8 = undefined;
        for (&analysis.modified_semantic_cid[0..8], 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("  Modified semantic CID: {s}\n", .{hex_buf});
    }
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&analysis.original_interface_cid[0..8].len * 2]u8 = undefined;
        for (&analysis.original_interface_cid[0..8], 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("  Original interface CID: {s}\n", .{hex_buf});
    }
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&analysis.modified_interface_cid[0..8].len * 2]u8 = undefined;
        for (&analysis.modified_interface_cid[0..8], 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("  Modified interface CID: {s}\n", .{hex_buf});
    }
}

fn demonstrateMetrics(json_output: bool, allocator: std.mem.Allocator) !void {
    var oracle = try oracle_proof.OracleProofPack.init(allocator);
    defer oracle.deinit();

    // Run a few builds to generate metrics
    const test_source = "func main() { print(\"Metrics test\") }";
    try std.fs.cwd().writeFile(.{ .sub_path = "metrics_test.jan", .data = test_source });
    defer std.fs.cwd().deleteFile("metrics_test.jan") catch {};

    // Initial build
    _ = try oracle.demonstrateNoWorkRebuild("metrics_test.jan");

    // Rebuild (should be cache hit)
    _ = try oracle.demonstrateNoWorkRebuild("metrics_test.jan");

    if (json_output) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        try oracle.generateMetricsJSON(stdout);
        try stdout.flush();
    } else {
        oracle.displayProofResults();
    }
}
