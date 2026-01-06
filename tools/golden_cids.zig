// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Golden CIDs Tool - Task 4.1
//!
//! Generates golden CID references for ASTDB invariance testing
//! Inputs: list of source files; flags: --deterministic, --profile=<p>
//! Outputs: cids.json with { unit, items: [{name, cid}] }
//! Requirements: E-1, E-2, E-4
//!
//! REAL INTEGRATION WITH LIBJANUS ASTDB - NO SECOND SEMANTICS

const std = @import("std");
const print = std.debug.print;
const json = std.json;
const libjanus = @import("libjanus");
const region = @import("mem/region.zig");
const List = @import("mem/ctx/List.zig").List;


// Inline hex formatting helper
inline fn hexFmt(hash: []const u8, buf: []u8) void {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
}

const GoldenCIDsConfig = struct {
    deterministic: bool = true,
    profile: []const u8 = "min",
    output_file: []const u8 = "cids.json",
    source_files: [][]const u8,
};

const CIDOutput = struct {
    unit: []const u8,
    unit_cid: []const u8,
    items: []ItemCID,

    const ItemCID = struct {
        name: []const u8,
        cid: []const u8,
        node_type: []const u8,
    };
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try parseArgs(allocator, args);
    defer {
        for (config.source_files) |file| {
            allocator.free(file);
        }
        allocator.free(config.source_files);
    }

    print("🔍 Golden CIDs Tool - ASTDB Invariance Testing\n", .{});
    print("==============================================\n", .{});
    print("Profile: {s}\n", .{config.profile});
    print("Deterministic: {}\n", .{config.deterministic});
    print("Source files: {d}\n", .{config.source_files.len});
    print("Output: {s}\n\n", .{config.output_file});

    // Process each source file and compute CIDs
    var cid_outputs = std.ArrayList(CIDOutput).init(allocator);
    defer {
        for (cid_outputs.items) |*output| {
            allocator.free(output.unit);
            allocator.free(output.unit_cid);
            for (output.items) |*item| {
                allocator.free(item.name);
                allocator.free(item.cid);
                allocator.free(item.node_type);
            }
            allocator.free(output.items);
        }
        cid_outputs.deinit();
    }

    for (config.source_files) |source_file| {
        print("📄 Processing: {s}\n", .{source_file});

        const cid_output = try processSourceFile(allocator, source_file, config);
        try cid_outputs.append(cid_output);

        print("  ✅ Unit CID: {s}\n", .{cid_output.unit_cid});
        print("  📊 Items: {d}\n", .{cid_output.items.len});

        for (cid_output.items) |item| {
            print("    • {s} ({s}): {s}\n", .{ item.name, item.node_type, item.cid });
        }
        print("\n", .{});
    }

    // Write output JSON
    try writeOutputJSON(allocator, cid_outputs.items, config.output_file);

    print("✅ Golden CIDs generated successfully!\n", .{});
    print("📁 Output written to: {s}\n", .{config.output_file});
}

fn parseArgs(allocator: std.mem.Allocator, args: [][:0]u8) !GoldenCIDsConfig {
    // PHASE 3: RAII/USING SUGAR - eliminates ALL region boilerplate
    return try region.withScratch(GoldenCIDsConfig, allocator, struct {
        fn parse(scratch_alloc: std.mem.Allocator) !GoldenCIDsConfig {
            // Long-lived configuration - uses function allocator (persists beyond function)
            var config = GoldenCIDsConfig{
                .source_files = &[_][]const u8{},
            };

            // Temporary list for parsing - uses scratch allocator (auto-cleanup)
            var source_files = List([]const u8).with(scratch_alloc);
            // No manual deinit needed - withScratch handles cleanup

            var i: usize = 1; // Skip program name
            while (i < args.len) {
                if (std.mem.eql(u8, args[i], "--deterministic")) {
                    config.deterministic = true;
                    i += 1;
                } else if (std.mem.eql(u8, args[i], "--no-deterministic")) {
                    config.deterministic = false;
                    i += 1;
                } else if (std.mem.startsWith(u8, args[i], "--profile=")) {
                    // Direct string slice - no allocation needed
                    config.profile = args[i][10..];
                    i += 1;
                } else if (std.mem.startsWith(u8, args[i], "--output=")) {
                    // Direct string slice - no allocation needed
                    config.output_file = args[i][9..];
                    i += 1;
                } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
                    showUsage();
                    std.process.exit(0);
                } else {
                    // Source file - needs to persist, so use function allocator
                    const file_copy = try allocator.dupe(u8, args[i]);
                    try source_files.append(file_copy); // ← no allocator arg needed!
                    i += 1;
                }
            }

            if (source_files.toSlice().len == 0) {
                print("❌ Error: No source files specified\n", .{});
                showUsage();
                std.process.exit(1);
            }

            // Convert to owned slice using function allocator (long-lived)
            config.source_files = try source_files.toOwnedSlice();
            return config;
        }
    }.parse);
}

fn processSourceFile(allocator: std.mem.Allocator, source_file: []const u8, config: GoldenCIDsConfig) !CIDOutput {
    // Read source file
    const source_content = std.fs.cwd().readFileAlloc(allocator, source_file, 1024 * 1024) catch |err| {
        print("❌ Error reading file {s}: {}\n", .{ source_file, err });
        return err;
    };
    defer allocator.free(source_content);

    // REAL INTEGRATION: Parse source file using libjanus
    print("  🔧 Parsing with libjanus ASTDB...\n", .{});
    const parsed_snapshot = libjanus.parse_root(source_content, allocator) catch |err| {
        print("❌ Error parsing file {s}: {}\n", .{ source_file, err });
        return err;
    };
    defer parsed_snapshot.deinit();

    print("  ✅ Parsed successfully\n", .{});

    // REAL INTEGRATION: Initialize ASTDB system for CID computation
    var astdb_system = try libjanus.ASTDBSystem.init(allocator, config.deterministic);
    defer astdb_system.deinit();

    // REAL INTEGRATION: Compute unit CID using canonical ASTDB CID computation
    const cid_opts = libjanus.CIDOpts{};

    // Find the root node (program/source_file) - use the actual root from snapshot
    const root_node_id: libjanus.NodeId = @enumFromInt(0); // Root is typically first node
    const unit_cid_raw = try astdb_system.getCID(parsed_snapshot, root_node_id, cid_opts);
    const unit_cid = try (blk: {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&unit_cid_raw.len * 2]u8 = undefined;
        for (&unit_cid_raw, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        break :blk try std.fmt.allocPrint(allocator, "blake3:{s}", .{hex_buf});
    });

    print("  🔍 Unit CID computed: {s}\n", .{unit_cid});

    // REAL INTEGRATION: Extract top-level items using ASTDB queries
    var query_engine = libjanus.QueryEngine.init(allocator, parsed_snapshot);
    defer query_engine.deinit();

    var items = std.ArrayList(CIDOutput.ItemCID).init(allocator);
    defer items.deinit();

    // Find all function declarations using real ASTDB query
    const func_predicate = libjanus.Predicate{ .node_kind = .func_decl };
    const func_nodes_result = query_engine.filterNodes(func_predicate);
    defer allocator.free(func_nodes_result.result);

    print("  📊 Found {} function declarations\n", .{func_nodes_result.result.len});

    // REAL INTEGRATION: Compute CID for each function using canonical ASTDB
    for (func_nodes_result.result) |func_node| {
        // Get function name from the real snapshot
        const token_span_result = query_engine.tokenSpan(func_node);
        const first_token = parsed_snapshot.getToken(token_span_result.result.start);
        const func_name = if (first_token) |token|
            parsed_snapshot.*.str_interner.str(token.str_id)
        else
            "unknown";

        // REAL INTEGRATION: Compute CID using canonical ASTDB CID computation
        const item_cid_raw = try astdb_system.getCID(parsed_snapshot, func_node, cid_opts);
        const item_cid = try (blk: {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&item_cid_raw.len * 2]u8 = undefined;
        for (&item_cid_raw, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        break :blk try std.fmt.allocPrint(allocator, "blake3:{s}", .{hex_buf});
    });

        try items.append(CIDOutput.ItemCID{
            .name = try allocator.dupe(u8, func_name),
            .cid = item_cid,
            .node_type = try allocator.dupe(u8, "function"),
        });

        print("    • {s}: {s}\n", .{ func_name, item_cid });
    }

    // Find variable declarations using real ASTDB query
    const var_predicate = libjanus.Predicate{ .node_kind = .var_decl };
    const var_nodes_result = query_engine.filterNodes(var_predicate);
    defer allocator.free(var_nodes_result.result);

    print("  📊 Found {} variable declarations\n", .{var_nodes_result.result.len});

    for (var_nodes_result.result) |var_node| {
        // Get variable name from the real snapshot
        const token_span_result = query_engine.tokenSpan(var_node);
        const first_token = parsed_snapshot.getToken(token_span_result.result.start);
        const var_name = if (first_token) |token|
            parsed_snapshot.str_interner.str(token.str_id)
        else
            "unknown";

        // REAL INTEGRATION: Compute CID using canonical ASTDB CID computation
        const item_cid_raw = try astdb_system.getCID(parsed_snapshot, var_node, cid_opts);
        const item_cid = try (blk: {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&item_cid_raw.len * 2]u8 = undefined;
        for (&item_cid_raw, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        break :blk try std.fmt.allocPrint(allocator, "blake3:{s}", .{hex_buf});
    });

        try items.append(CIDOutput.ItemCID{
            .name = try allocator.dupe(u8, var_name),
            .cid = item_cid,
            .node_type = try allocator.dupe(u8, "variable"),
        });

        print("    • {s}: {s}\n", .{ var_name, item_cid });
    }

    return CIDOutput{
        .unit = try allocator.dupe(u8, source_file),
        .unit_cid = unit_cid,
        .items = try items.toOwnedSlice(),
    };
}

// NO LOCAL CID COMPUTATION - DOCTRINE OF NO SECOND SEMANTICS
// All CID computation is handled exclusively by the canonical libjanus ASTDB system

fn writeOutputJSON(allocator: std.mem.Allocator, outputs: []const CIDOutput, output_file: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_file, .{});
    defer file.close();

    // Create JSON structure
    var json_output = std.ArrayList(u8).init(allocator);
    defer json_output.deinit();

    try json.stringify(outputs, .{ .whitespace = .indent_2 }, json_output.writer());

    try file.writeAll(json_output.items);
}

fn showUsage() void {
    print("Golden CIDs Tool - ASTDB Invariance Testing\n\n", .{});
    print("Usage: golden_cids [options] <source_files...>\n\n", .{});
    print("Options:\n", .{});
    print("  --deterministic      Enable deterministic mode (default)\n", .{});
    print("  --no-deterministic   Disable deterministic mode\n", .{});
    print("  --profile=<profile>  Set profile (min, go, full) (default: min)\n", .{});
    print("  --output=<file>      Output file (default: cids.json)\n", .{});
    print("  --help, -h           Show this help\n\n", .{});
    print("Examples:\n", .{});
    print("  golden_cids main.jan\n", .{});
    print("  golden_cids --profile=full --output=full_cids.json *.jan\n", .{});
    print("  golden_cids --deterministic main.jan lib.jan\n\n", .{});
    print("The tool generates CID references for ASTDB invariance testing.\n", .{});
    print("CIDs should be identical across formatting changes but differ for semantic changes.\n", .{});
}
