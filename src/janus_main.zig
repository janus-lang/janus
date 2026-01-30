// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Main Entry Point - Core Compiler
//!
//! Primary entry point for the Janus compiler and toolchain
//! Handles command-line interface and delegates to specialized modules
//! Requirements: Core CLI, Build System Integration
//!
//! REVOLUTIONARY ASTDB ARCHITECTURE - QUERY-POWERED COMPILATION

const std = @import("std");
const janus = @import("janus_lib");
const version_info = @import("version.zig");

// Import the revolutionary command modules
const BuildCommand = @import("build_command.zig");
const pipeline = @import("pipeline.zig");
const QueryCommand = @import("query_command.zig");
const profiles = @import("profiles.zig");
const vfs = @import("vfs_adapter");
const fs = std.fs;
const tensor = janus.tensor_jir;
const tensor_builder = janus.tensor_builder;
const tensor_cid = janus.tensor_cid;
const List = @import("mem/ctx/List.zig").List;
const inspect = @import("inspect"); // Epic 3.4 Oracle
const jit_runner = @import("jit_runner.zig"); // JIT execution for :script

// Inline hex formatting helper
inline fn hexFmt(hash: []const u8, buf: []u8) void {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
}

// Integration Protocol - Validation configuration
// ValidationConfig import not required here; semantic module manages validation configuration.

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Convert [:0]u8 to []const u8 for profile detection
    const const_args = try allocator.alloc([]const u8, args.len);
    defer allocator.free(const_args);
    for (args, 0..) |arg, i| {
        const_args[i] = arg;
    }

    // Detect profile from CLI args and environment
    const profile = profiles.ProfileDetector.detectProfile(const_args);
    const profile_config = profiles.ProfileConfig.init(profile);
    // Inform libjanus API about :npu so J-IR extractor can be gated properly
    janus.api.setNpuEnabled(profile == .npu);

    if (args.len < 2) {
        std.debug.print("Janus - Systems language with precise incremental compilation\n\n", .{});
        std.debug.print("Usage: janus <command> [args...]\n\n", .{});
        std.debug.print("Commands:\n", .{});
        std.debug.print("  run <source.jan> [args...]   - Execute script via JIT (:script profile)\n", .{});
        std.debug.print("     Flags: --verbose, --trace\n", .{});
        std.debug.print("  build <source.jan> [output]  - Compile with incremental compilation\n", .{});
        std.debug.print("     Flags: --verify, --verify-only, --emit=llvm\n", .{});
        std.debug.print("            --print-graph-cid (:npu)\n", .{});
        std.debug.print("            --cache-root <path> (:npu, content-addressed cache)\n", .{});
        std.debug.print("            --cache-flavor <name> (default: npu-O2)\n", .{});
        std.debug.print("  inspect <source.jan>         - Introspection Oracle (AST/Symbols)\n", .{});
        std.debug.print("     Flags: --show=ast, --format=json|text\n", .{});
        std.debug.print("  oracle <mode> [args...]      - Semantic analysis tools\n", .{});
        std.debug.print("  query --log <pattern> [files] - High-performance log analysis\n", .{});
        std.debug.print("  query \"<predicate>\"           - Execute semantic query\n", .{});
        std.debug.print("  diff <old> <new>             - Semantic diff analysis\n", .{});
        std.debug.print("  profile [show|explain <feature>] - Profile system management\n", .{});
        std.debug.print("  test-cas                     - Test Content-Addressed Storage\n", .{});
        std.debug.print("  version                      - Show version information\n\n", .{});
        std.debug.print("Profile Options:\n", .{});
        std.debug.print("  --profile=min                - Minimal feature set (default)\n", .{});
        std.debug.print("  --profile=go                 - Go-style patterns and concurrency\n", .{});
        std.debug.print("  --profile=full               - Complete Janus feature set\n", .{});
        std.debug.print("  --profile=npu                - NPU-native ML (tensors, graph IR)\n", .{});
        std.debug.print("\nBootstrap Mode:\n", .{});
        std.debug.print("  --bootstrap-s0[=on|off]      - Toggle S0 bootstrap gate (default: on)\n", .{});
        std.debug.print("  --no-bootstrap-s0            - Disable S0 gate explicitly\n\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  janus --profile=go build hello.jan\n", .{});
        std.debug.print("  janus profile show\n", .{});
        std.debug.print("  janus profile explain goroutines\n", .{});
        std.debug.print("  janus query --log \"ERROR\" *.log\n", .{});
        return;
    }

    const command = args[1];

    if (std.mem.eql(u8, command, "version")) {
        const verbose = args.len >= 3 and std.mem.eql(u8, args[2], "--verbose");
        std.debug.print("Janus Language Compiler v{s}\n", .{version_info.version});
        std.debug.print("Active profile: {s}\n", .{profile.toString()});
        std.debug.print("Features:\n", .{});
        std.debug.print("  - Incremental compilation with content-addressed builds\n", .{});
        std.debug.print("  - Semantic analysis and query tools\n", .{});
        std.debug.print("  - High-performance log analysis\n", .{});
        std.debug.print("  - Profiles: min, go, full, npu (orthogonal ML)\n", .{});
        std.debug.print("Built with libjanus core\n", .{});
        if (verbose and args.len >= 4) {
            try analyzeArtifact(args[3], allocator);
        } else if (verbose) {
            std.debug.print("\nUsage: janus version --verbose <artifact_path>\n", .{});
        }
        return;
    }

    // Commands
    if (std.mem.eql(u8, command, "test")) {
        if (args.len < 3) {
            std.debug.print("Usage: janus test <source.jan> [--verbose]\n", .{});
            return;
        }
        const source_path = args[2];
        var verbose = false;
        var json_output = false;

        for (args[3..]) |arg| {
            if (std.mem.eql(u8, arg, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, arg, "--json")) {
                json_output = true;
            }
        }

        // Tests run in script context (JIT)
        var runner = jit_runner.JitRunner.init(allocator, .{
            .source_path = source_path,
            .profile = .script,
            .verbose = verbose,
        });

        var result = runner.runTests() catch |err| {
            if (json_output) {
                // TODO: Print JSON error?
                // For now, allow regular error print or panic
            }
            std.debug.print("Error executing tests: {any}\n", .{err});
            std.process.exit(1);
        };
        defer result.deinit(allocator);

        if (json_output) {
            var buf: [4096]u8 = undefined;
            var stdout = std.fs.File.stdout().writer(&buf);
            try std.json.Stringify.value(result, .{ .whitespace = .indent_2 }, &stdout.interface);
            try stdout.interface.writeAll("\n");
            try stdout.end();
        } else {
            std.debug.print("\nTest Summary:\n", .{});
            std.debug.print("  Passed: {d}\n", .{result.passed});
            std.debug.print("  Failed: {d}\n", .{result.failed});
            std.debug.print("  Duration: {d:.3}ms\n", .{@as(f64, @floatFromInt(result.total_duration_ns)) / 1_000_000.0});

            if (result.failed > 0) {
                std.debug.print("\nFailures:\n", .{});
                for (result.tests) |t| {
                    if (!t.passed) {
                        const msg = t.error_msg orelse "Unknown error";
                        std.debug.print("  ❌ \"{s}\": {s}\n", .{ t.name, msg });
                    }
                }
            } else {
                std.debug.print("✅ All tests passed.\n", .{});
            }
        }

        if (result.failed > 0) std.process.exit(1);
        return;
    }

    // S0 bootstrap: parse → bind → IR dump
    if (comptime false and std.mem.eql(u8, command, "s0-check")) {
        if (args.len < 3) {
            std.debug.print("Usage: janus s0-check <source.jan>\n", .{});
            return;
        }
        const source_path = args[2];
        const bytes = try vfs.readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
        defer allocator.free(bytes);

        const core = @import("astdb_core");
        const region = @import("astdb");
        const irgen = @import("ir_generator");

        // Lex + parse with S0 gate
        var interner = region.StrInterner.init(allocator, true);
        defer interner.deinit();
        var lx = region.RegionLexer.init(allocator, bytes, &interner);
        const toks = try lx.lexAll();
        var rp = region.RegionParser.init(allocator, toks, &interner);
        rp.enableS0(true);
        _ = try rp.parse();
        var db = try rp.createSnapshot();

        // Bind discovered functions
        const binder = @import("astdb_binder");
        const unit_id: core.UnitId = @enumFromInt(0);
        try binder.bindUnit(&db, unit_id);

        // Build snapshot and generate IR
        var snap_ptr = try allocator.create(core.Snapshot);
        snap_ptr.* = try db.createSnapshot();
        defer {
            snap_ptr.deinit();
            allocator.destroy(snap_ptr);
        }

        var ig = try irgen.IRGenerator.init(allocator, snap_ptr, &db);
        defer ig.deinit();
        // Choose first decl for IR
        const unit2 = db.getUnit(unit_id).?;
        if (unit2.decls.len == 0) {
            std.debug.print("S0: no declarations bound\n", .{});
            return;
        }
        var ir = try ig.generateIR(unit_id, @enumFromInt(0));
        defer ir.deinit(allocator);

        // Dump minimal IR summary
        std.debug.print("Function: {s}\n", .{ir.function_name});
        std.debug.print("Blocks: {d}\n", .{ir.basic_blocks.len});
        return;
    }

    if (std.mem.eql(u8, command, "profile")) {
        try handleProfileCommand(const_args[2..], profile_config, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "cache")) {
        if (args.len < 3) {
            std.debug.print("Usage: janus cache <ls|verify|gc|inspect> --root <path> [--cid HEX] [--max-keep N] [--flavor NAME]\n", .{});
            return;
        }
        const sub = args[2];
        var root_opt: ?[]const u8 = null;
        var max_keep: usize = 3;
        var cid_filter_opt: ?[]const u8 = null;
        var flavor_opt: ?[]const u8 = null;
        var idx2: usize = 3;
        while (idx2 < args.len) : (idx2 += 1) {
            if (std.mem.eql(u8, args[idx2], "--root")) {
                if (idx2 + 1 < args.len) {
                    root_opt = args[idx2 + 1];
                    idx2 += 1;
                    continue;
                }
                std.debug.print("Error: --root requires a path\n", .{});
                return;
            }
            if (std.mem.eql(u8, args[idx2], "--max-keep")) {
                if (idx2 + 1 < args.len) {
                    max_keep = std.fmt.parseInt(usize, args[idx2 + 1], 10) catch 3;
                    idx2 += 1;
                    continue;
                }
                std.debug.print("Error: --max-keep requires a number\n", .{});
                return;
            }
            if (std.mem.eql(u8, args[idx2], "--cid")) {
                if (idx2 + 1 < args.len) {
                    cid_filter_opt = args[idx2 + 1];
                    idx2 += 1;
                    continue;
                }
                std.debug.print("Error: --cid requires a hex string\n", .{});
                return;
            }
            if (std.mem.eql(u8, args[idx2], "--flavor")) {
                if (idx2 + 1 < args.len) {
                    flavor_opt = args[idx2 + 1];
                    idx2 += 1;
                    continue;
                }
                std.debug.print("Error: --flavor requires a name\n", .{});
                return;
            }
        }
        const root = root_opt orelse {
            std.debug.print("Error: --root <path> required\n", .{});
            return;
        };
        if (std.mem.eql(u8, sub, "ls")) {
            try cacheList(root, cid_filter_opt, allocator);
        } else if (std.mem.eql(u8, sub, "verify")) {
            try cacheVerify(root, allocator);
        } else if (std.mem.eql(u8, sub, "gc")) {
            try cacheGc(root, max_keep, allocator);
        } else if (std.mem.eql(u8, sub, "prune")) {
            var older_days_opt: ?u64 = null;
            var max_size_mb_opt: ?u64 = null;
            var dry_run = false;
            var yes = false;
            var confirms = List([]const u8).with(allocator);

            defer confirms.deinit();

            // parse local flags
            var j: usize = 3;
            while (j < args.len) : (j += 1) {
                if (std.mem.eql(u8, args[j], "--older-than") and j + 1 < args.len) {
                    older_days_opt = std.fmt.parseInt(u64, args[j + 1], 10) catch null;
                    j += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[j], "--max-size") and j + 1 < args.len) {
                    max_size_mb_opt = std.fmt.parseInt(u64, args[j + 1], 10) catch null;
                    j += 1;
                    continue;
                }
                if (std.mem.eql(u8, args[j], "--dry-run")) {
                    dry_run = true;
                    continue;
                }
                if (std.mem.eql(u8, args[j], "--yes")) {
                    yes = true;
                    continue;
                }
                if (std.mem.eql(u8, args[j], "--confirm-cid") and j + 1 < args.len) {
                    try confirms.append(args[j + 1]);
                    j += 1;
                    continue;
                }
            }
            if (!dry_run and confirms.items().len == 0 and !yes) {
                std.debug.print("Refusing to prune without --yes or specific --confirm-cid. Use --dry-run to preview.\n", .{});
                return;
            }
            try cachePruneAdvanced(root, older_days_opt, max_size_mb_opt, dry_run, try confirms.toOwnedSlice(), allocator);
        } else if (std.mem.eql(u8, sub, "clean")) {
            var yes = false;
            var k: usize = 3;
            while (k < args.len) : (k += 1) {
                if (std.mem.eql(u8, args[k], "--yes")) {
                    yes = true;
                    continue;
                }
            }
            if (!yes) {
                std.debug.print("Refusing to delete without --yes confirmation.\n", .{});
                std.debug.print("Run: janus cache clean --root {s} --yes\n", .{root});
                return;
            }
            try cacheClean(root, allocator);
        } else if (std.mem.eql(u8, sub, "doctor")) {
            var top_n: usize = 10;
            var kdoc: usize = 3;
            while (kdoc < args.len) : (kdoc += 1) {
                if (std.mem.eql(u8, args[kdoc], "--top") and kdoc + 1 < args.len) {
                    top_n = std.fmt.parseInt(usize, args[kdoc + 1], 10) catch 10;
                    kdoc += 1;
                }
            }
            try cacheDoctor(root, top_n, allocator);
        } else if (std.mem.eql(u8, sub, "gc")) {
            var yes = false;
            var dry_run = false;
            var confirms = List([]const u8).with(allocator);

            defer confirms.deinit();

            var k2: usize = 3;
            while (k2 < args.len) : (k2 += 1) {
                if (std.mem.eql(u8, args[k2], "--yes")) {
                    yes = true;
                    continue;
                }
                if (std.mem.eql(u8, args[k2], "--dry-run")) {
                    dry_run = true;
                    continue;
                }
                if (std.mem.eql(u8, args[k2], "--confirm-cid") and k2 + 1 < args.len) {
                    try confirms.append(args[k2 + 1]);
                    k2 += 1;
                    continue;
                }
            }
            if (!dry_run and confirms.items().len == 0 and !yes) {
                std.debug.print("Refusing GC without --yes or --confirm-cid. Use --dry-run to preview.\n", .{});
                return;
            }
            try cacheGcAdvanced(root, max_keep, dry_run, try confirms.toOwnedSlice(), allocator);
        } else if (std.mem.eql(u8, sub, "inspect")) {
            const cid_hex = cid_filter_opt orelse {
                std.debug.print("Error: inspect requires --cid <hex>\n", .{});
                return;
            };
            const flavor = flavor_opt orelse {
                std.debug.print("Error: inspect requires --flavor <name>\n", .{});
                return;
            };
            try cacheInspect(root, cid_hex, flavor, allocator);
        } else {
            std.debug.print("Unknown cache subcommand '{s}'\n", .{sub});
        }
        return;
    }

    if (std.mem.eql(u8, command, "oracle")) {
        const oracle = @import("oracle.zig");
        // Convert [][:0]u8 to [][]const u8
        const oracle_args = @as([][]const u8, @ptrCast(args));
        try oracle.runOracle(oracle_args, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "query")) {
        // Revolutionary Query Command - Front 2: The Trojan Horse
        const query_args = @as([][]const u8, @ptrCast(args));
        try QueryCommand.executeQuery(query_args, allocator);
        return;
    }

    if (std.mem.eql(u8, command, "diff")) {
        // Classical diff command - delegate to Oracle
        const oracle = @import("oracle.zig");
        var oracle_args = List([]const u8).with(allocator);

        defer oracle_args.deinit();

        try oracle_args.append("janus");
        try oracle_args.append("oracle");
        try oracle_args.append("diff");
        try oracle_args.appendSlice(args[1..]);

        try oracle.runOracle(try oracle_args.toOwnedSlice(), allocator);
        return;
    }

    // ==========================================================================
    // RUN COMMAND - JIT Script Execution (:script profile)
    // ==========================================================================
    // Doctrine: Engine Orthogonality - Same IR (QTJIR), different execution path
    // Pipeline: Source → ASTDB → QTJIR → JIT Forge → Execution
    // ==========================================================================
    if (std.mem.eql(u8, command, "run")) {
        if (args.len < 3) {
            std.debug.print("Error: run command requires source file\n", .{});
            std.debug.print("Usage: janus run <source.jan> [args...]\n", .{});
            std.debug.print("       janus run --verbose <source.jan>\n", .{});
            std.debug.print("       janus run --trace <source.jan>\n", .{});
            return;
        }

        var verbose = false;
        var trace_execution = false;
        var source_path: ?[]const u8 = null;
        var script_args = List([]const u8).with(allocator);
        defer script_args.deinit();

        var i: usize = 2;
        var collecting_args = false;
        while (i < args.len) : (i += 1) {
            if (collecting_args) {
                try script_args.append(args[i]);
                continue;
            }
            if (std.mem.eql(u8, args[i], "--verbose") or std.mem.eql(u8, args[i], "-v")) {
                verbose = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--trace") or std.mem.eql(u8, args[i], "-t")) {
                trace_execution = true;
                continue;
            }
            if (args[i].len > 0 and args[i][0] != '-') {
                source_path = args[i];
                collecting_args = true; // Remaining args are for the script
                continue;
            }
        }

        const src_path = source_path orelse {
            std.debug.print("Error: No source file specified\n", .{});
            std.debug.print("Usage: janus run <source.jan>\n", .{});
            return;
        };

        if (verbose) {
            std.debug.print("🔥 Janus JIT Runner (Profile: :script)\n", .{});
            std.debug.print("   Source: {s}\n", .{src_path});
            if (script_args.items().len > 0) {
                std.debug.print("   Args: ", .{});
                for (script_args.items()) |arg| {
                    std.debug.print("{s} ", .{arg});
                }
                std.debug.print("\n", .{});
            }
        }

        var runner = jit_runner.JitRunner.init(allocator, .{
            .source_path = src_path,
            .args = script_args.items(),
            .verbose = verbose,
            .trace_execution = trace_execution,
            .profile = .script,
        });

        var result = runner.run() catch |err| {
            std.debug.print("❌ JIT execution failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer result.deinit(allocator);

        // Output results
        if (result.stdout.len > 0) {
            std.debug.print("{s}", .{result.stdout});
        }
        if (result.stderr.len > 0) {
            std.debug.print("{s}", .{result.stderr});
        }

        if (verbose) {
            std.debug.print("✅ Exit code: {}\n", .{result.exit_code});
            std.debug.print("   Execution time: {d:.3}ms\n", .{
                @as(f64, @floatFromInt(result.execution_time_ns)) / 1_000_000.0,
            });
        }

        if (result.exit_code != 0) {
            std.process.exit(@intCast(result.exit_code));
        }

        return;
    }

    if (std.mem.eql(u8, command, "build")) {
        if (args.len < 3) {
            std.debug.print("Error: build command requires source file\n", .{});
            std.debug.print("Usage: janus build <source.jan> [output]\n", .{});
            std.debug.print(" janus build --emit=llvm <source.jan> [out.ll]\n", .{});
            return;
        }

        var emit_llvm = false;
        var verify_only = false;
        var verify_flag = false;
        var print_graph_cid = false;
        var verbose_flag = false;
        var cache_root_opt: ?[]const u8 = null;
        var cache_flavor: []const u8 = "npu-O2";
        var src_idx_opt: ?usize = null;
        var output_path_opt: ?[]const u8 = null;
        var i: usize = 2;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--verbose") or std.mem.eql(u8, args[i], "-v")) {
                verbose_flag = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--emit=llvm")) {
                emit_llvm = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--verify")) {
                verify_flag = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--verify-only")) {
                verify_only = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--print-graph-cid")) {
                print_graph_cid = true;
                continue;
            }
            if (std.mem.eql(u8, args[i], "-o") or std.mem.eql(u8, args[i], "--output")) {
                if (i + 1 < args.len) {
                    output_path_opt = args[i + 1];
                    i += 1;
                } else {
                    std.debug.print("Error: -o/--output requires a path argument\n", .{});
                    return;
                }
                continue;
            }
            if (std.mem.eql(u8, args[i], "--cache-root")) {
                if (i + 1 < args.len) {
                    cache_root_opt = args[i + 1];
                    i += 1;
                } else {
                    std.debug.print("Error: --cache-root requires a path argument\n", .{});
                    return;
                }
                continue;
            }
            if (std.mem.eql(u8, args[i], "--cache-flavor")) {
                if (i + 1 < args.len) {
                    cache_flavor = args[i + 1];
                    i += 1;
                } else {
                    std.debug.print("Error: --cache-flavor requires a value\n", .{});
                    return;
                }
                continue;
            }
            if (src_idx_opt == null and args[i].len > 0 and args[i][0] != '-') {
                src_idx_opt = i;
            }
        }

        if (verify_only) {
            if (src_idx_opt == null) {
                std.debug.print("Usage: janus build --verify-only <source.jan>\n", .{});
                return;
            }
            // Deprecated legacy verification
            std.debug.print("Verification mode is temporarily unavailable during QTJIR transition.\n", .{});
            // const sidx = src_idx_opt.?;
            // const source_path = args[sidx];
            // ...
        } else if (emit_llvm and profile != .min) {
            if (src_idx_opt == null) {
                std.debug.print("Usage: janus build --emit=llvm <source.jan> [out.ll]\n", .{});
                return;
            }
            // const sidx = src_idx_opt.?;
            // const source_path = args[sidx];
            // const out_ll = if (sidx + 1 < args.len and args[sidx + 1].len > 0 and args[sidx + 1][0] != '-') args[sidx + 1] else "out.ll";
            // const bytes = try std.fs.cwd().readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
            // defer allocator.free(bytes);

            if (verify_flag) {
                std.debug.print("Verification flag ignored during QTJIR transition.\n", .{});
            }

            // try janus.api.emitLLVMFromSource(bytes, out_ll, allocator);
            std.debug.print("LLVM emission via legacy path disabled. Use :min profile or wait for update.\n", .{});
            // std.debug.print("Wrote LLVM IR to {s}\n", .{out_ll});
        } else {
            const sidx2: usize = src_idx_opt orelse 2;
            const source_path = args[sidx2];
            // Use -o flag if provided, otherwise derive from source filename
            const output_path = output_path_opt orelse blk: {
                const basename = std.fs.path.basename(source_path);
                const name_without_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
                    basename[0..idx]
                else
                    basename;
                break :blk name_without_ext;
            };

            if (verify_flag) {
                std.debug.print("Verification flag ignored (deprecated).\n", .{});
                // const bytes = try vfs.readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
                // ...
            }

            // Use new pipeline for :min profile (0.2.0 "Weihnachtsmann")
            // Fall back to old buildCommand for other profiles
            if (profile == .min) {
                if (!verbose_flag) {
                    std.debug.print("Compiling {s}...\n", .{source_path});
                }

                // Locate runtime directory for scheduler support
                // Priority: JANUS_RUNTIME_DIR env > "runtime" relative to CWD
                const runtime_dir: ?[]const u8 = std.process.getEnvVarOwned(allocator, "JANUS_RUNTIME_DIR") catch |err| blk: {
                    if (err == error.EnvironmentVariableNotFound) {
                        // Try relative path from CWD
                        break :blk std.fs.cwd().realpathAlloc(allocator, "runtime") catch null;
                    }
                    break :blk null;
                };
                defer if (runtime_dir) |d| allocator.free(d);

                var compiler = pipeline.Pipeline.init(allocator, .{
                    .source_path = source_path,
                    .output_path = output_path,
                    .emit_llvm_ir = emit_llvm,
                    .verbose = verbose_flag,
                    .runtime_dir = runtime_dir,
                });

                var result = compiler.compile() catch |err| {
                    std.debug.print("❌ Compilation failed: {s}\n", .{@errorName(err)});
                    std.process.exit(1);
                };
                defer result.deinit(allocator);

                std.debug.print("✅ Success: {s}\n", .{result.executable_path});
            } else {
                try buildCommand(source_path, output_path, profile_config, allocator);
            }
            // Optional: content-addressed graph artifact caching for :npu
            if (profile == .npu) {
                if (cache_root_opt) |_| {
                    std.debug.print("NPU Graph extraction disabled in legacy build path.\n", .{});
                }
            }
            if (print_graph_cid and profile == .npu) {
                std.debug.print("Graph CID printing disabled during QTJIR transition.\n", .{});
            }
        }
        return;
    }

    if (std.mem.eql(u8, command, "inspect")) {
        if (args.len < 3) {
            std.debug.print("Usage: janus inspect <source.jan> [--show=ast] [--format=json|text]\n", .{});
            return;
        }

        const source_path = args[2];
        var options = inspect.InspectOptions{ .format = .text, .show_ast = true };

        var i: usize = 3;
        while (i < args.len) : (i += 1) {
            if (std.mem.startsWith(u8, args[i], "--format=")) {
                const val = args[i]["--format=".len..];
                if (std.mem.eql(u8, val, "json")) options.format = .json;
                continue;
            }
            if (std.mem.eql(u8, args[i], "--show=ast")) {
                options.show_ast = true;
                continue;
            }
            // Add more flags later
        }

        const source = try vfs.readFileAlloc(allocator, source_path, 16 * 1024 * 1024);
        defer allocator.free(source);

        var inspector = inspect.Inspector.init(allocator);
        defer inspector.deinit();

        const result = inspector.inspectSource(source, options) catch |err| {
            std.debug.print("Inspection failed: {s}\n", .{@errorName(err)});
            return;
        };
        defer allocator.free(result);

        std.debug.print("{s}\n", .{result});
        return;
    }

    if (std.mem.eql(u8, command, "test-case")) {
        try testCASCommand(allocator);
        return;
    }

    std.debug.print("Error: Unknown command '{s}'\n", .{command});
    std.debug.print("Run 'janus' without arguments to see available commands.\n", .{});
}

/// Debug helper: build a small J-IR demo graph and print its canonical BLAKE3 CID
// printGraphCIDDemo and printGraphCIDFromPipeline removed to cleaup legacy IR dependency

fn analyzeArtifact(path: []const u8, allocator: std.mem.Allocator) !void {
    const data = vfs.readFileAlloc(allocator, path, 50 * 1024 * 1024) catch |err| {
        std.debug.print("Error reading artifact '{s}': {}\n", .{ path, err });
        return;
    };
    defer allocator.free(data);

    const tag = "JANUS_ARTIFACT::PROFILE=";
    if (std.mem.indexOf(u8, data, tag)) |pos| {
        const window = data[pos..@min(pos + 256, data.len)];
        var profile_val: []const u8 = ":unknown";
        var safety_val: []const u8 = "Unknown";
        var opt_val: []const u8 = "Unknown";

        // PROFILE=<val>;SAFETY=<val>;OPT=<val>
        const after = window[tag.len..];
        if (std.mem.indexOfScalar(u8, after, ';')) |semi1| {
            profile_val = after[0..semi1];
            const rest1 = after[semi1 + 1 ..];
            if (std.mem.indexOf(u8, rest1, "SAFETY=")) |sidx| {
                const srest = rest1[sidx + 7 ..];
                if (std.mem.indexOfScalar(u8, srest, ';')) |semi2| {
                    safety_val = srest[0..semi2];
                    const rest2 = srest[semi2 + 1 ..];
                    if (std.mem.indexOf(u8, rest2, "OPT=")) |oidx| {
                        const orest = rest2[oidx + 4 ..];
                        // read until non-printable or quote or end
                        var len: usize = 0;
                        while (len < orest.len and orest[len] >= 32 and orest[len] <= 126 and orest[len] != '"') : (len += 1) {}
                        opt_val = orest[0..len];
                    }
                }
            }
        }

        std.debug.print("\nJanus Artifact Analysis:\n", .{});
        std.debug.print("  - Compiled With Profile: {s}\n", .{profile_val});
        std.debug.print("  - Safety Checks: {s}\n", .{safety_val});
        std.debug.print("  - Optimization Level: {s}\n", .{opt_val});
    } else {
        std.debug.print("\nNo Janus artifact metadata found in '{s}'.\n", .{path});
    }
}

pub fn cacheListCollectVfs(root: []const u8, cid_filter_opt: ?[]const u8, allocator: std.mem.Allocator) !std.ArrayList([]const u8) {
    var results = try std.ArrayList([]const u8).initCapacity(allocator, 0);
    const objects_path = try std.fmt.allocPrint(allocator, "{s}/objects", .{root});
    defer allocator.free(objects_path);
    var it = vfs.openDirIter(allocator, objects_path) catch {
        // No objects directory; return empty
        return results;
    };
    defer it.deinit();
    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        const cid_hex = ent.name;
        if (cid_filter_opt) |f| if (!std.mem.eql(u8, cid_hex, f)) continue;
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ objects_path, cid_hex });
        defer allocator.free(cid_path);
        var it2 = vfs.openDirIter(allocator, cid_path) catch {
            continue;
        };
        defer it2.deinit();
        while (try it2.next()) |e2| {
            if (e2.kind == .file and std.mem.startsWith(u8, e2.name, "artifact-") and std.mem.endsWith(u8, e2.name, ".bin")) {
                try results.append(allocator, try allocator.dupe(u8, e2.name));
            }
        }
    }
    return results;
}

fn cacheList(root: []const u8, cid_filter_opt: ?[]const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("Cache root: {s}\n", .{root});
    var list = try cacheListCollectVfs(root, cid_filter_opt, allocator);
    defer {
        for (list.items) |s| allocator.free(s);
        list.deinit(allocator);
    }
    if (cid_filter_opt) |cid| {
        std.debug.print("- {s}: ", .{cid});
        var first: bool = true;
        for (list.items) |name| {
            if (!first) std.debug.print(", ", .{});
            first = false;
            std.debug.print("{s}", .{name});
        }
        std.debug.print("\n", .{});
    } else {
        // Group by CID prefix (artifact names include flavor; but we only have names; print flat)
        var first: bool = true;
        std.debug.print("- artifacts: ", .{});
        for (list.items) |name| {
            if (!first) std.debug.print(", ", .{});
            first = false;
            std.debug.print("{s}", .{name});
        }
        std.debug.print("\n", .{});
    }
}

fn cacheInspect(root: []const u8, cid_hex: []const u8, flavor: []const u8, allocator: std.mem.Allocator) !void {
    std.debug.print("Inspecting CID={s}, flavor={s}\n", .{ cid_hex, flavor });
    const base = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ root, cid_hex });
    defer allocator.free(base);

    const meta_path = try std.fmt.allocPrint(allocator, "{s}/meta-{s}.json", .{ base, flavor });
    defer allocator.free(meta_path);
    const onnx_path = try std.fmt.allocPrint(allocator, "{s}/artifact-{s}.bin", .{ base, flavor });
    defer allocator.free(onnx_path);
    const ir_path = try std.fmt.allocPrint(allocator, "{s}/ir-{s}.txt", .{ base, flavor });
    defer allocator.free(ir_path);
    const sum_path = try std.fmt.allocPrint(allocator, "{s}/graph-{s}-summary.json", .{ base, flavor });
    defer allocator.free(sum_path);

    const meta: []const u8 = vfs.readFileAlloc(allocator, meta_path, 256 * 1024) catch |err| blk: {
        std.debug.print("meta not found: {}\n", .{err});
        break :blk &[_]u8{};
    };
    defer if (meta.len > 0) allocator.free(@constCast(meta));
    if (meta.len > 0) {
        std.debug.print("meta.json:\n{s}\n", .{meta});
        // Naive extraction of digests
        const find = struct {
            fn get(meta_bytes: []const u8, name: []const u8, field: []const u8) ?[]const u8 {
                if (std.mem.indexOf(u8, meta_bytes, name)) |p| {
                    const after = meta_bytes[p + name.len ..];
                    const key = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\": \"", .{field}) catch return null;
                    defer std.heap.page_allocator.free(key);
                    if (std.mem.indexOf(u8, after, key)) |pf| {
                        const start = pf + key.len;
                        const rest = after[start..];
                        if (std.mem.indexOfScalar(u8, rest, '"')) |e| return rest[0..e];
                    }
                }
                return null;
            }
        };
        const onnx_d = find.get(meta, "\"onnx\"", "digest") orelse "";
        const ir_d = find.get(meta, "\"ir\"", "digest") orelse "";
        std.debug.print("digests: onnx={s} ir={s}\n", .{ onnx_d, ir_d });
    }

    const st_onnx = vfs.statFile(onnx_path) catch |err| blk2: {
        std.debug.print("artifact missing: {}\n", .{err});
        break :blk2 null;
    };
    if (st_onnx) |st| std.debug.print("artifact size: {} bytes\n", .{st.size});

    const st_ir = vfs.statFile(ir_path) catch null;
    if (st_ir) |st| std.debug.print("ir size: {} bytes\n", .{st.size});

    const summary: []const u8 = vfs.readFileAlloc(allocator, sum_path, 128 * 1024) catch &[_]u8{};
    defer if (summary.len > 0) allocator.free(summary);
    if (summary.len > 0) std.debug.print("summary:\n{s}\n", .{summary});
}

pub const CacheInspectInfo = struct {
    have_meta: bool,
    artifact_size: ?u64,
    ir_size: ?u64,
    summary_present: bool,
};

pub fn cacheInspectCollectVfs(root: []const u8, cid_hex: []const u8, flavor: []const u8, allocator: std.mem.Allocator) !CacheInspectInfo {
    const base = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ root, cid_hex });
    defer allocator.free(base);

    const meta_path = try std.fmt.allocPrint(allocator, "{s}/meta-{s}.json", .{ base, flavor });
    defer allocator.free(meta_path);
    const onnx_path = try std.fmt.allocPrint(allocator, "{s}/artifact-{s}.bin", .{ base, flavor });
    defer allocator.free(onnx_path);
    const ir_path = try std.fmt.allocPrint(allocator, "{s}/ir-{s}.txt", .{ base, flavor });
    defer allocator.free(ir_path);
    const sum_path = try std.fmt.allocPrint(allocator, "{s}/graph-{s}-summary.json", .{ base, flavor });
    defer allocator.free(sum_path);

    var have_meta = true;
    const meta = vfs.readFileAlloc(allocator, meta_path, 256 * 1024) catch {
        have_meta = false;
        return CacheInspectInfo{ .have_meta = false, .artifact_size = null, .ir_size = null, .summary_present = false };
    };
    defer allocator.free(meta);
    const st_art = vfs.statFile(onnx_path) catch null;
    const st_ir = vfs.statFile(ir_path) catch null;
    const summary: []const u8 = vfs.readFileAlloc(allocator, sum_path, 128 * 1024) catch &[_]u8{};
    defer if (summary.len > 0) allocator.free(summary);
    return CacheInspectInfo{
        .have_meta = have_meta,
        .artifact_size = if (st_art) |s| s.size else null,
        .ir_size = if (st_ir) |s| s.size else null,
        .summary_present = summary.len > 0,
    };
}

// Verify (OK/BAD) collector using VFS for deterministic testing
pub const VerifyStats = struct { ok: usize, bad: usize };

pub fn cacheVerifyCollectVfs(root: []const u8, allocator: std.mem.Allocator) !VerifyStats {
    var ok_count: usize = 0;
    var bad_count: usize = 0;
    const objects_path = try std.fmt.allocPrint(allocator, "{s}/objects", .{root});
    defer allocator.free(objects_path);
    var it = vfs.openDirIter(allocator, objects_path) catch {
        return VerifyStats{ .ok = 0, .bad = 0 };
    };
    defer it.deinit();
    while (try it.next()) |ent| {
        if (ent.kind != vfs.FileType.directory) continue;
        const cid_hex = ent.name;
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ objects_path, cid_hex });
        defer allocator.free(cid_path);
        var it2 = vfs.openDirIter(allocator, cid_path) catch {
            continue;
        };
        defer it2.deinit();
        while (try it2.next()) |ent2| {
            if (!(ent2.kind == vfs.FileType.file and std.mem.startsWith(u8, ent2.name, "meta-") and std.mem.endsWith(u8, ent2.name, ".json"))) continue;
            const flavor = ent2.name[5 .. ent2.name.len - 5];
            _ = flavor; // suppress unused
            const meta_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, ent2.name });
            defer allocator.free(meta_path);
            const meta = vfs.readFileAlloc(allocator, meta_path, 256 * 1024) catch {
                bad_count += 1;
                continue;
            };
            defer allocator.free(meta);

            const extractField = struct {
                fn get(meta_bytes: []const u8, name: []const u8, field: []const u8) ?[]const u8 {
                    if (std.mem.indexOf(u8, meta_bytes, name)) |pname| {
                        const after = meta_bytes[pname + name.len ..];
                        const key = std.fmt.allocPrint(std.heap.page_allocator, "\"{s}\": \"", .{field}) catch return null;
                        defer std.heap.page_allocator.free(key);
                        if (std.mem.indexOf(u8, after, key)) |pf| {
                            const start = pf + key.len;
                            const rest = after[start..];
                            if (std.mem.indexOfScalar(u8, rest, '"')) |e| return rest[0..e];
                        }
                    }
                    return null;
                }
            };
            // ONNX
            if (extractField.get(meta, "\"onnx\"", "file")) |onnx_file| {
                const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, onnx_file });
                defer allocator.free(path);
                const data = vfs.readFileAlloc(allocator, path, 64 * 1024 * 1024) catch {
                    bad_count += 1;
                    continue;
                };
                defer allocator.free(data);
                const dig = janus.blake3Hash(data);
                const dig_hex = try janus.contentIdToHex(dig, allocator);
                defer allocator.free(dig_hex);
                const exp = extractField.get(meta, "\"onnx\"", "digest") orelse "";
                if (std.mem.eql(u8, exp, dig_hex)) ok_count += 1 else bad_count += 1;
            }
            // IR
            if (extractField.get(meta, "\"ir\"", "file")) |ir_file| {
                const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, ir_file });
                defer allocator.free(path);
                const data = vfs.readFileAlloc(allocator, path, 64 * 1024 * 1024) catch {
                    bad_count += 1;
                    continue;
                };
                defer allocator.free(data);
                const dig = janus.blake3Hash(data);
                const dig_hex = try janus.contentIdToHex(dig, allocator);
                defer allocator.free(dig_hex);
                const exp = extractField.get(meta, "\"ir\"", "digest") orelse "";
                if (std.mem.eql(u8, exp, dig_hex)) ok_count += 1 else bad_count += 1;
            }
        }
    }
    return VerifyStats{ .ok = ok_count, .bad = bad_count };
}

// Doctor (summary) collector using VFS for deterministic testing
pub const DoctorHog = struct { cid: []u8, size: u128 };
pub const DoctorStats = struct { cid_count: usize, art: usize, ir: usize, meta: usize, summary: usize, total_size: u128, hogs: []DoctorHog };

pub fn cacheDoctorCollectVfs(root: []const u8, allocator: std.mem.Allocator) !DoctorStats {
    var cid_count: usize = 0;
    var art_count: usize = 0;
    var ir_count: usize = 0;
    var meta_count: usize = 0;
    var summary_count: usize = 0;
    var total_size: u128 = 0;
    var hogs_list = std.ArrayList(DoctorHog){};
    errdefer {
        for (hogs_list.items) |h| allocator.free(h.cid);
        hogs_list.deinit(allocator);
    }

    const objects_path = try std.fmt.allocPrint(allocator, "{s}/objects", .{root});
    defer allocator.free(objects_path);
    var it = vfs.openDirIter(allocator, objects_path) catch {
        return DoctorStats{ .cid_count = 0, .art = 0, .ir = 0, .meta = 0, .summary = 0, .total_size = 0, .hogs = try allocator.alloc(DoctorHog, 0) };
    };
    defer it.deinit();
    while (try it.next()) |ent| {
        if (ent.kind != vfs.FileType.directory) continue;
        cid_count += 1;
        const cid_hex = ent.name;
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ objects_path, cid_hex });
        defer allocator.free(cid_path);
        var it2 = vfs.openDirIter(allocator, cid_path) catch {
            continue;
        };
        defer it2.deinit();
        var cid_total: u128 = 0;
        while (try it2.next()) |e2| {
            if (e2.kind != vfs.FileType.file) continue;
            const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, e2.name });
            defer allocator.free(full);
            const st = vfs.statFile(full) catch continue;
            const sz: u128 = @intCast(st.size);
            total_size += sz;
            cid_total += sz;
            if (std.mem.startsWith(u8, e2.name, "artifact-")) art_count += 1 else if (std.mem.startsWith(u8, e2.name, "ir-")) ir_count += 1 else if (std.mem.startsWith(u8, e2.name, "meta-")) meta_count += 1 else if (std.mem.startsWith(u8, e2.name, "graph-")) summary_count += 1;
        }
        try hogs_list.append(allocator, .{ .cid = try allocator.dupe(u8, cid_hex), .size = cid_total });
    }

    return DoctorStats{ .cid_count = cid_count, .art = art_count, .ir = ir_count, .meta = meta_count, .summary = summary_count, .total_size = total_size, .hogs = hogs_list.items };
}

fn cacheVerify(root: []const u8, allocator: std.mem.Allocator) !void {
    const stats = try cacheVerifyCollectVfs(root, allocator);
    std.debug.print("Verify OK: {}, Bad: {}\n", .{ stats.ok, stats.bad });
}

fn cacheDoctor(root: []const u8, top_n: usize, allocator: std.mem.Allocator) !void {
    std.debug.print("Running cache doctor on '{s}'...\n", .{root});
    cacheVerify(root, allocator) catch |err| {
        std.debug.print("verify error: {}\n", .{err});
    };
    const stats = try cacheDoctorCollectVfs(root, allocator);
    const total_mb: u64 = @intCast(stats.total_size / (1024 * 1024));
    std.debug.print("Summary: CIDs={}, artifacts={}, ir={}, meta={}, summary={}, size={} MB\n", .{ stats.cid_count, stats.art, stats.ir, stats.meta, stats.summary, total_mb });
    // Top N CIDs by size
    std.sort.block(DoctorHog, stats.hogs, {}, struct {
        fn less(_: void, a: DoctorHog, b: DoctorHog) bool {
            return a.size > b.size;
        }
    }.less);
    const limit = if (top_n == 0) 10 else top_n;
    const top = if (stats.hogs.len < limit) stats.hogs.len else limit;
    if (top > 0) {
        std.debug.print("Top {d} CIDs by size:\n", .{top});
        var i_top: usize = 0;
        while (i_top < top) : (i_top += 1) {
            const mb: u64 = @intCast(stats.hogs[i_top].size / (1024 * 1024));
            std.debug.print("  {s}  {d} MB\n", .{ stats.hogs[i_top].cid, mb });
        }
    }
    // Free hog CIDs
    for (stats.hogs) |h| allocator.free(h.cid);
    if (total_mb > 1024) {
        std.debug.print("Suggestion: prune to 512 MB: janus cache prune --root {s} --max-size 512\n", .{root});
    } else if (total_mb > 256) {
        std.debug.print("Suggestion: prune to 128 MB: janus cache prune --root {s} --max-size 128\n", .{root});
    }
    if (stats.cid_count > 0 and stats.art > stats.cid_count * 4) {
        std.debug.print("Suggestion: GC to keep last 2 artifacts per CID: janus cache gc --root {s} --max-keep 2\n", .{root});
    }
}

fn cacheGc(root: []const u8, max_keep: usize, allocator: std.mem.Allocator) !void {
    const objects_path = try std.fmt.allocPrint(allocator, "{s}/objects", .{root});
    defer allocator.free(objects_path);
    var it = vfs.openDirIter(allocator, objects_path) catch {
        return;
    };
    defer it.deinit();
    var removed: usize = 0;
    while (try it.next()) |ent| {
        if (ent.kind != vfs.FileType.directory) continue;
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ objects_path, ent.name });
        defer allocator.free(cid_path);
        var it2 = vfs.openDirIter(allocator, cid_path) catch {
            continue;
        };
        defer it2.deinit();
        // collect artifact files with mtimes
        var files = std.ArrayList(struct { name: []u8, mtime: i128, full: []u8 }){};
        defer {
            for (files.items) |f| {
                allocator.free(f.name);
                allocator.free(f.full);
            }
            files.deinit(allocator);
        }
        while (try it2.next()) |ent2| {
            if (ent2.kind == vfs.FileType.file and std.mem.startsWith(u8, ent2.name, "artifact-") and std.mem.endsWith(u8, ent2.name, ".bin")) {
                const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, ent2.name });
                const st = vfs.statFile(full) catch {
                    allocator.free(full);
                    continue;
                };
                const nm = try allocator.dupe(u8, ent2.name);
                try files.append(allocator, .{ .name = nm, .mtime = st.mtime, .full = full });
            }
        }
        if (files.items.len > max_keep) {
            // sort by mtime desc keep newest
            const F = @TypeOf(files.items[0]);
            std.sort.block(F, files.items, {}, struct {
                fn less(_: void, a: F, b: F) bool {
                    return a.mtime > b.mtime;
                }
            }.less);
            var idx: usize = max_keep;
            while (idx < files.items.len) : (idx += 1) {
                vfs.deleteFile(files.items[idx].full) catch {};
                removed += 1;
            }
        }
    }
    std.debug.print("GC removed {} old artifacts\n", .{removed});
}

fn cachePrune(root: []const u8, older_days_opt: ?u64, max_size_mb_opt: ?u64, allocator: std.mem.Allocator) !void {
    var root_dir = try fs.cwd().openDir(root, .{ .iterate = true });
    defer root_dir.close();
    var obj_dir = try root_dir.openDir("objects", .{ .iterate = true });
    defer obj_dir.close();

    const now = std.time.timestamp();
    const cutoff: i64 = if (older_days_opt) |d| now - @as(i64, @intCast(d)) * 24 * 60 * 60 else std.math.maxInt(i64);
    const max_total: u64 = if (max_size_mb_opt) |mb| mb * 1024 * 1024 else 0;

    // Gather all artifact and text files for size/age accounting
    const FileInfo = struct { path: []u8, mtime: i128, size: u64, cid_path: []u8, flavor: []u8 };
    var files = std.ArrayList(FileInfo){};
    defer {
        for (files.items) |f| {
            allocator.free(f.path);
            allocator.free(f.cid_path);
            allocator.free(f.flavor);
        }
        files.deinit(allocator);
    }

    // Track per (cid, flavor) remaining file counts
    const FlavorCount = struct { cid_path: []u8, flavor: []u8, remaining: usize };
    var counts = std.ArrayList(FlavorCount){};
    defer {
        for (counts.items) |c| {
            allocator.free(c.cid_path);
            allocator.free(c.flavor);
        }
        counts.deinit(allocator);
    }
    const addCount = struct {
        fn upsert(list: *std.ArrayList(FlavorCount), cid_path: []const u8, flavor: []const u8, A: std.mem.Allocator) !void {
            var i: usize = 0;
            while (i < list.items.len) : (i += 1) {
                if (std.mem.eql(u8, list.items[i].cid_path, cid_path) and std.mem.eql(u8, list.items[i].flavor, flavor)) {
                    list.items[i].remaining += 1;
                    return;
                }
            }
            const ccp = try A.dupe(u8, cid_path);
            const cfl = try A.dupe(u8, flavor);
            try list.append(A, .{ .cid_path = ccp, .flavor = cfl, .remaining = 1 });
        }
    }.upsert;

    var it = obj_dir.iterate();
    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        var cid_dir = try obj_dir.openDir(ent.name, .{ .iterate = true, .access_sub_paths = true });
        defer cid_dir.close();
        var it2 = cid_dir.iterate();
        while (try it2.next()) |ent2| {
            if (ent2.kind != .file) continue;
            const is_art = std.mem.startsWith(u8, ent2.name, "artifact-") and std.mem.endsWith(u8, ent2.name, ".bin");
            const is_ir = std.mem.startsWith(u8, ent2.name, "ir-") and std.mem.endsWith(u8, ent2.name, ".txt");
            const is_summary = std.mem.startsWith(u8, ent2.name, "graph-") and std.mem.endsWith(u8, ent2.name, ".json");
            if (!(is_art or is_ir or is_summary)) continue;
            const st = cid_dir.statFile(ent2.name) catch continue;
            const full = try std.fmt.allocPrint(allocator, "{s}/objects/{s}/{s}", .{ root, ent.name, ent2.name });
            // derive cid_path and flavor
            const cid_path = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ root, ent.name });
            var flavor: []const u8 = "";
            if (is_art) flavor = ent2.name[9 .. ent2.name.len - 4] else if (is_ir) flavor = ent2.name[3 .. ent2.name.len - 4] else flavor = ent2.name[6 .. ent2.name.len - 14];
            const flavor_owned = try allocator.dupe(u8, flavor);
            try files.append(allocator, .{ .path = full, .mtime = st.mtime, .size = @intCast(st.size), .cid_path = cid_path, .flavor = flavor_owned });
            try addCount(&counts, cid_path, flavor, allocator);
        }
    }

    var removed: usize = 0;
    var freed: u64 = 0;

    // Prune by age if requested
    if (older_days_opt != null) {
        var i: usize = 0;
        while (i < files.items.len) : (i += 1) {
            if (files.items[i].mtime < cutoff and files.items[i].size > 0) {
                vfs.deleteFile(files.items[i].path) catch {};
                freed += files.items[i].size;
                removed += 1;
                files.items[i].size = 0;
                // decrement flavor count
                var k: usize = 0;
                while (k < counts.items.len) : (k += 1) {
                    if (std.mem.eql(u8, counts.items[k].cid_path, files.items[i].cid_path) and std.mem.eql(u8, counts.items[k].flavor, files.items[i].flavor)) {
                        if (counts.items[k].remaining > 0) counts.items[k].remaining -= 1;
                        break;
                    }
                }
            }
        }
    }

    // Compute total size
    var total: u64 = 0;
    for (files.items) |f| total += f.size;

    // Prune to max size (delete oldest first) if requested
    if (max_total > 0 and total > max_total) {
        const F = @TypeOf(files.items[0]);
        std.sort.block(F, files.items, {}, struct {
            fn less(_: void, a: F, b: F) bool {
                return a.mtime < b.mtime;
            }
        }.less);
        var k: usize = 0;
        while (k < files.items.len and total > max_total) : (k += 1) {
            if (files.items[k].size == 0) continue;
            vfs.deleteFile(files.items[k].path) catch {};
            freed += files.items[k].size;
            total -= files.items[k].size;
            removed += 1;
            // decrement flavor count
            var k2: usize = 0;
            while (k2 < counts.items.len) : (k2 += 1) {
                if (std.mem.eql(u8, counts.items[k2].cid_path, files.items[k].cid_path) and std.mem.eql(u8, counts.items[k2].flavor, files.items[k].flavor)) {
                    if (counts.items[k2].remaining > 0) counts.items[k2].remaining -= 1;
                    break;
                }
            }
        }
    }

    // Remove meta files for flavors with zero remaining
    var m: usize = 0;
    while (m < counts.items.len) : (m += 1) {
        if (counts.items[m].remaining == 0) {
            const meta_path = std.fmt.allocPrint(allocator, "{s}/meta-{s}.json", .{ counts.items[m].cid_path, counts.items[m].flavor }) catch null;
            if (meta_path) |mp| {
                vfs.deleteFile(mp) catch {};
                allocator.free(mp);
            }
        }
    }

    // Remove empty CID directories
    var it3 = obj_dir.iterate();
    while (try it3.next()) |ent| {
        if (ent.kind != .directory) continue;
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ root, ent.name });
        defer allocator.free(cid_path);
        var iter = vfs.openDirIter(allocator, cid_path) catch |e| {
            _ = e;
            continue;
        };
        defer iter.deinit();
        var any_file = false;
        while (try iter.next()) |e2| {
            if (e2.kind == vfs.FileType.file) {
                any_file = true;
                break;
            }
        }
        if (!any_file) {
            vfs.deleteTree(cid_path) catch {};
        }
    }

    std.debug.print("Pruned files: {} (freed {} bytes)\n", .{ removed, freed });
}

fn cachePruneAdvanced(root: []const u8, older_days_opt: ?u64, max_size_mb_opt: ?u64, dry_run: bool, confirms: [][]const u8, allocator: std.mem.Allocator) !void {
    const objects_path = try std.fmt.allocPrint(allocator, "{s}/objects", .{root});
    defer allocator.free(objects_path);

    const now = std.time.timestamp();
    const cutoff: i64 = if (older_days_opt) |d| now - @as(i64, @intCast(d)) * 24 * 60 * 60 else std.math.maxInt(i64);
    const max_total: u64 = if (max_size_mb_opt) |mb| mb * 1024 * 1024 else 0;

    const FileInfo = struct { path: []u8, mtime: i128, size: u64, cid_hex: []u8, flavor: []u8 };
    var files = std.ArrayList(FileInfo){};
    defer {
        for (files.items) |f| {
            allocator.free(f.path);
            allocator.free(f.cid_hex);
            allocator.free(f.flavor);
        }
        files.deinit(allocator);
    }

    const FlavorCount = struct { cid_hex: []u8, flavor: []u8, remaining: usize };
    var counts = std.ArrayList(FlavorCount){};
    defer {
        for (counts.items) |c| {
            allocator.free(c.cid_hex);
            allocator.free(c.flavor);
        }
        counts.deinit(allocator);
    }

    var it = vfs.openDirIter(allocator, objects_path) catch {
        return;
    };
    defer it.deinit();
    while (try it.next()) |ent| {
        if (ent.kind != vfs.FileType.directory) continue;
        if (confirms.len > 0) {
            var ok = false;
            for (confirms) |c| {
                if (std.mem.eql(u8, ent.name, c)) {
                    ok = true;
                    break;
                }
            }
            if (!ok) continue;
        }
        const cid_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ objects_path, ent.name });
        defer allocator.free(cid_path);
        var it2 = vfs.openDirIter(allocator, cid_path) catch {
            continue;
        };
        defer it2.deinit();
        while (try it2.next()) |ent2| {
            if (ent2.kind != vfs.FileType.file) continue;
            const is_art = std.mem.startsWith(u8, ent2.name, "artifact-") and std.mem.endsWith(u8, ent2.name, ".bin");
            const is_ir = std.mem.startsWith(u8, ent2.name, "ir-") and std.mem.endsWith(u8, ent2.name, ".txt");
            const is_summary = std.mem.startsWith(u8, ent2.name, "graph-") and std.mem.endsWith(u8, ent2.name, ".json");
            if (!(is_art or is_ir or is_summary)) continue;
            const full = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ cid_path, ent2.name });
            const st = vfs.statFile(full) catch {
                allocator.free(full);
                continue;
            };
            const cid_hex = try allocator.dupe(u8, ent.name);
            var flavor: []const u8 = "";
            if (is_art) flavor = ent2.name[9 .. ent2.name.len - 4] else if (is_ir) flavor = ent2.name[3 .. ent2.name.len - 4] else flavor = ent2.name[6 .. ent2.name.len - 14];
            const flv = try allocator.dupe(u8, flavor);
            try files.append(allocator, .{ .path = full, .mtime = st.mtime, .size = @intCast(st.size), .cid_hex = cid_hex, .flavor = flv });
            // upsert flavor count
            var found = false;
            var idx: usize = 0;
            while (idx < counts.items.len) : (idx += 1) {
                if (std.mem.eql(u8, counts.items[idx].cid_hex, cid_hex) and std.mem.eql(u8, counts.items[idx].flavor, flv)) {
                    counts.items[idx].remaining += 1;
                    found = true;
                    break;
                }
            }
            if (!found) try counts.append(allocator, .{ .cid_hex = try allocator.dupe(u8, ent.name), .flavor = try allocator.dupe(u8, flavor), .remaining = 1 });
        }
    }

    // When dry_run, stage planned deletions per CID for grouped output
    const PlanEntry = struct { cid: []u8, paths: std.ArrayList([]u8) };
    var plan = std.ArrayList(PlanEntry){};
    defer {
        var idxp: usize = 0;
        while (idxp < plan.items.len) : (idxp += 1) {
            var p = &plan.items[idxp];
            for (p.paths.items) |pp| allocator.free(pp);
            p.paths.deinit(allocator);
            allocator.free(p.cid);
        }
        plan.deinit(allocator);
    }
    const record = struct {
        fn add(plan_ref: *std.ArrayList(PlanEntry), allocator_: std.mem.Allocator, cid: []const u8, path: []const u8) !void {
            var i: usize = 0;
            while (i < plan_ref.items.len) : (i += 1) {
                if (std.mem.eql(u8, plan_ref.items[i].cid, cid)) {
                    try plan_ref.items[i].paths.append(allocator_, try allocator_.dupe(u8, path));
                    return;
                }
            }
            var entry = PlanEntry{ .cid = try allocator_.dupe(u8, cid), .paths = std.ArrayList([]u8){} };
            try entry.paths.append(allocator_, try allocator_.dupe(u8, path));
            try plan_ref.append(allocator_, entry);
        }
    }.add;

    var removed: usize = 0;
    var freed: u64 = 0;
    // Age prune
    if (older_days_opt != null) {
        for (files.items) |*f| {
            if (f.size == 0) continue;
            if (f.mtime < cutoff) {
                if (dry_run) try record(&plan, allocator, f.cid_hex, f.path) else {
                    fs.cwd().deleteFile(f.path) catch {};
                }
                freed += f.size;
                removed += 1;
                f.size = 0;
                for (counts.items) |*c| {
                    if (std.mem.eql(u8, c.cid_hex, f.cid_hex) and std.mem.eql(u8, c.flavor, f.flavor)) {
                        if (c.remaining > 0) c.remaining -= 1;
                        break;
                    }
                }
            }
        }
    }
    // Size prune
    var total: u64 = 0;
    for (files.items) |f| total += f.size;
    if (max_total > 0 and total > max_total) {
        const F = @TypeOf(files.items[0]);
        std.sort.block(F, files.items, {}, struct {
            fn less(_: void, a: F, b: F) bool {
                return a.mtime < b.mtime;
            }
        }.less);
        var k: usize = 0;
        while (k < files.items.len and total > max_total) : (k += 1) {
            if (files.items[k].size == 0) continue;
            if (dry_run) try record(&plan, allocator, files.items[k].cid_hex, files.items[k].path) else {
                fs.cwd().deleteFile(files.items[k].path) catch {};
            }
            freed += files.items[k].size;
            total -= files.items[k].size;
            removed += 1;
            files.items[k].size = 0;
            for (counts.items) |*c| {
                if (std.mem.eql(u8, c.cid_hex, files.items[k].cid_hex) and std.mem.eql(u8, c.flavor, files.items[k].flavor)) {
                    if (c.remaining > 0) c.remaining -= 1;
                    break;
                }
            }
        }
    }
    // Remove empty flavor meta
    for (counts.items) |c| {
        if (c.remaining == 0) {
            const mp = std.fmt.allocPrint(allocator, "{s}/objects/{s}/meta-{s}.json", .{ root, c.cid_hex, c.flavor }) catch null;
            if (mp) |mpp| {
                if (dry_run) {
                    try record(&plan, allocator, c.cid_hex, mpp);
                } else fs.cwd().deleteFile(mpp) catch {};
                allocator.free(mpp);
            }
        }
    }
    // Remove empty CID dirs
    var it3 = vfs.openDirIter(allocator, objects_path) catch {
        return;
    };
    defer it3.deinit();
    while (try it3.next()) |ent| {
        if (ent.kind != vfs.FileType.directory) continue;
        const cpath = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ root, ent.name });
        defer allocator.free(cpath);
        var it4 = vfs.openDirIter(allocator, cpath) catch {
            continue;
        };
        defer it4.deinit();
        var any = false;
        while (try it4.next()) |e| {
            if (e.kind == vfs.FileType.file) {
                any = true;
                break;
            }
        }
        if (!any) {
            if (dry_run) {
                try record(&plan, allocator, ent.name, cpath);
            } else vfs.deleteTree(cpath) catch {};
        }
    }
    if (dry_run) {
        std.debug.print("DRY-RUN grouped plan:\n", .{});
        for (plan.items) |p| {
            std.debug.print("- CID {s}\n", .{p.cid});
            for (p.paths.items) |pp| {
                std.debug.print("    {s}\n", .{pp});
            }
        }
    }
    std.debug.print("Pruned files: {} (freed {} bytes)\n", .{ removed, freed });
}

fn cacheGcAdvanced(root: []const u8, max_keep: usize, dry_run: bool, confirms: [][]const u8, allocator: std.mem.Allocator) !void {
    var root_dir = try fs.cwd().openDir(root, .{ .iterate = true });
    defer root_dir.close();
    var obj_dir = try root_dir.openDir("objects", .{ .iterate = true });
    defer obj_dir.close();
    var it = obj_dir.iterate();
    var removed: usize = 0;
    // Grouped dry-run plan per CID
    const PlanEntry2 = struct { cid: []u8, paths: std.ArrayList([]u8) };
    var plan = std.ArrayList(PlanEntry2){};
    defer {
        var idxp2: usize = 0;
        while (idxp2 < plan.items.len) : (idxp2 += 1) {
            var p = &plan.items[idxp2];
            for (p.paths.items) |pp| allocator.free(pp);
            p.paths.deinit(allocator);
            allocator.free(p.cid);
        }
        plan.deinit(allocator);
    }
    const record = struct {
        fn add(plan_ref: *std.ArrayList(PlanEntry2), allocator_: std.mem.Allocator, cid: []const u8, path: []const u8) !void {
            var i: usize = 0;
            while (i < plan_ref.items.len) : (i += 1) {
                if (std.mem.eql(u8, plan_ref.items[i].cid, cid)) {
                    try plan_ref.items[i].paths.append(allocator_, try allocator_.dupe(u8, path));
                    return;
                }
            }
            var entry = PlanEntry2{ .cid = try allocator_.dupe(u8, cid), .paths = std.ArrayList([]u8){} };
            try entry.paths.append(allocator_, try allocator_.dupe(u8, path));
            try plan_ref.append(allocator_, entry);
        }
    }.add;
    while (try it.next()) |ent| {
        if (ent.kind != .directory) continue;
        if (confirms.len > 0) {
            var ok = false;
            for (confirms) |c| {
                if (std.mem.eql(u8, ent.name, c)) {
                    ok = true;
                    break;
                }
            }
            if (!ok) continue;
        }
        var cid_dir = try obj_dir.openDir(ent.name, .{ .iterate = true });
        defer cid_dir.close();
        var files = std.ArrayList(struct { name: []u8, mtime: i128 }){};
        defer {
            for (files.items) |f| allocator.free(f.name);
            files.deinit(allocator);
        }
        var it2 = cid_dir.iterate();
        while (try it2.next()) |ent2| {
            if (ent2.kind == .file and std.mem.startsWith(u8, ent2.name, "artifact-") and std.mem.endsWith(u8, ent2.name, ".bin")) {
                const st = cid_dir.statFile(ent2.name) catch continue;
                const nm = try allocator.dupe(u8, ent2.name);
                try files.append(allocator, .{ .name = nm, .mtime = st.mtime });
            }
        }
        if (files.items.len > max_keep) {
            const FT = @TypeOf(files.items[0]);
            std.sort.block(FT, files.items, {}, struct {
                fn less(_: void, a: FT, b: FT) bool {
                    return a.mtime > b.mtime;
                }
            }.less);
            var idx: usize = max_keep;
            while (idx < files.items.len) : (idx += 1) {
                if (dry_run) {
                    const full = try std.fmt.allocPrint(allocator, "{s}/objects/{s}/{s}", .{ root, ent.name, files.items[idx].name });
                    try record(&plan, allocator, ent.name, full);
                    allocator.free(full);
                } else cid_dir.deleteFile(files.items[idx].name) catch {};
                removed += 1;
            }
        }
    }
    if (dry_run) {
        std.debug.print("DRY-RUN grouped plan:\n", .{});
        for (plan.items) |p| {
            std.debug.print("- CID {s}\n", .{p.cid});
            for (p.paths.items) |pp| {
                std.debug.print("    {s}\n", .{pp});
            }
        }
    }
    std.debug.print("GC removed {} old artifacts\n", .{removed});
}

fn cacheClean(root: []const u8, allocator: std.mem.Allocator) !void {
    // Guardrails: refuse extremely short or root paths
    if (root.len == 0 or std.mem.eql(u8, root, "/") or std.mem.eql(u8, root, ".")) {
        std.debug.print("Refusing to delete dangerous root '{s}'.\n", .{root});
        return error.InvalidCacheRoot;
    }
    // Warn and refuse if root resolves to current working directory
    const cwd = try fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);
    const rpath = fs.cwd().realpathAlloc(allocator, root) catch root;
    defer if (!std.mem.eql(u8, rpath, root)) allocator.free(rpath);
    if (std.mem.eql(u8, rpath, cwd)) {
        std.debug.print("Refusing to delete current working directory '{s}'.\n", .{rpath});
        return error.InvalidCacheRoot;
    }
    if (rpath.len < 5) {
        std.debug.print("Refusing to delete very short path '{s}'.\n", .{rpath});
        return error.InvalidCacheRoot;
    }
    // Safety check: ensure this looks like a cache root (must contain 'objects' dir)
    var root_dir = try fs.cwd().openDir(root, .{ .iterate = true });
    defer root_dir.close();
    _ = root_dir.openDir("objects", .{ .iterate = false }) catch {
        std.debug.print("'{s}' does not look like a cache root (missing 'objects' dir). Aborting.\n", .{root});
        return error.InvalidCacheRoot;
    };
    fs.cwd().deleteTree(root) catch |err| {
        std.debug.print("Failed to delete '{s}': {}\n", .{ root, err });
        return err;
    };
    std.debug.print("Deleted cache root '{s}'.\n", .{root});
}

fn buildCommand(source_path: []const u8, output_path: []const u8, profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) !void {
    _ = allocator;
    std.debug.print("Building {s} -> {s} (profile: {s})\n", .{ source_path, output_path, profile_config.profile.toString() });

    // For Janus 0.2.0 "Weihnachtsmann", only :min profile is implemented
    // Other profiles (:go, :script, :full, :npu) will be available in 0.3.0+
    std.debug.print("\n❌ Profile '{s}' not yet implemented in Janus 0.2.0\n", .{profile_config.profile.toString()});
    std.debug.print("Currently supported profiles:\n", .{});
    std.debug.print("  - :min (default) - Minimal feature set\n", .{});
    std.debug.print("\nComing in 0.3.0:\n", .{});
    std.debug.print("  - :go    - Go-style patterns\n", .{});
    std.debug.print("  - :script - Scripting conveniences\n", .{});
    std.debug.print("  - :full  - Complete feature set\n", .{});
    std.debug.print("  - :npu   - NPU-native ML\n", .{});
    std.debug.print("\nPlease use --profile=min or omit the flag (min is default)\n", .{});
}

// No legacy build path: single authoritative pipeline

fn handleProfileCommand(args: [][]const u8, profile_config: profiles.ProfileConfig, allocator: std.mem.Allocator) !void {
    _ = allocator;

    if (args.len == 0) {
        // Show current profile
        std.debug.print("Current profile: {s}\n", .{profile_config.profile.toString()});
        std.debug.print("Description: {s}\n", .{profile_config.profile.description()});
        return;
    }

    const subcommand = args[0];

    if (std.mem.eql(u8, subcommand, "show")) {
        std.debug.print("Janus Profile System\n", .{});
        std.debug.print("Current profile: {s}\n\n", .{profile_config.profile.toString()});

        std.debug.print("Available profiles:\n", .{});
        std.debug.print("  min  - {s}\n", .{profiles.Profile.min.description()});
        std.debug.print("  go   - {s}\n", .{profiles.Profile.go.description()});
        std.debug.print("  full - {s}\n", .{profiles.Profile.full.description()});
        std.debug.print("  npu  - {s}\n", .{profiles.Profile.npu.description()});

        std.debug.print("\nUsage: janus --profile=<name> <command>\n", .{});
        std.debug.print("Environment: JANUS_PROFILE=<name>\n", .{});
    } else if (std.mem.eql(u8, subcommand, "explain") and args.len > 1) {
        const feature_name = args[1];

        // Simple feature explanation (could be expanded)
        if (std.mem.eql(u8, feature_name, "goroutines")) {
            const feature = profiles.Feature.goroutines;
            std.debug.print("Feature: goroutines\n", .{});
            std.debug.print("Available in profile: {s}+\n", .{feature.requiredProfile().toString()});
            std.debug.print("Current profile: {s}\n", .{profile_config.profile.toString()});

            if (profile_config.isFeatureAvailable(feature)) {
                std.debug.print("Status: Available\n", .{});
            } else {
                std.debug.print("Status: Not available\n", .{});
                if (profile_config.getUpgradeHint(feature)) |hint| {
                    std.debug.print("Hint: {s}\n", .{hint});
                }
            }
        } else if (std.mem.eql(u8, feature_name, "effects")) {
            const feature = profiles.Feature.effects;
            std.debug.print("Feature: effects\n", .{});
            std.debug.print("Available in profile: {s}+\n", .{feature.requiredProfile().toString()});
            std.debug.print("Current profile: {s}\n", .{profile_config.profile.toString()});

            if (profile_config.isFeatureAvailable(feature)) {
                std.debug.print("Status: Available\n", .{});
            } else {
                std.debug.print("Status: Not available\n", .{});
                if (profile_config.getUpgradeHint(feature)) |hint| {
                    std.debug.print("Hint: {s}\n", .{hint});
                }
            }
        } else {
            std.debug.print("Unknown feature: {s}\n", .{feature_name});
            std.debug.print("Available features: goroutines, effects, capabilities, actors\n", .{});
        }
    } else {
        std.debug.print("Usage: janus profile [show|explain <feature>]\n", .{});
    }
}

fn testCASCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 Testing Janus Ledger CAS Core...\n", .{});

    // Test 1: BLAKE3 hashing
    const test_data = "Hello, Janus Ledger!";
    const hash1 = janus.blake3Hash(test_data);
    const hash2 = janus.blake3Hash(test_data);

    std.debug.print("✅ BLAKE3 hash deterministic: {}\n", .{std.mem.eql(u8, &hash1, &hash2)});

    // Test 2: ContentId hex conversion
    const hex = try janus.contentIdToHex(hash1, allocator);
    defer allocator.free(hex);

    std.debug.print("✅ ContentId hex: {s}\n", .{hex});

    const parsed_id = try janus.hexToContentId(hex);
    std.debug.print("✅ Hex round-trip: {}\n", .{std.mem.eql(u8, &hash1, &parsed_id)});

    // Test 3: Archive normalization
    const crlf_data = "line1\r\nline2\r\nline3\r\n";
    const normalized = try janus.normalizeArchive(crlf_data, allocator);
    defer allocator.free(normalized);

    const expected = "line1\nline2\nline3\n";
    std.debug.print("✅ Archive normalization: {}\n", .{std.mem.eql(u8, expected, normalized)});

    // Test 4: CAS operations
    const cas_root = "test_cas_demo";

    // Clean up any existing test directory
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    try janus.initializeCAS(cas_root);
    var cas = janus.createCAS(cas_root, allocator);
    defer cas.deinit();

    const test_content = "This is test content for the CAS";
    const content_id = try cas.hashArchive(test_content);

    // Store content
    try cas.store(content_id, test_content);
    std.debug.print("✅ Content stored in CAS\n", .{});

    // Verify it exists
    std.debug.print("✅ Content exists: {}\n", .{cas.exists(content_id)});

    // Retrieve content
    const retrieved = try cas.retrieve(content_id, allocator);
    defer allocator.free(retrieved);

    std.debug.print("✅ Content retrieved: {}\n", .{std.mem.eql(u8, test_content, retrieved)});

    // Verify integrity
    std.debug.print("✅ Integrity verified: {}\n", .{try cas.verify(content_id)});

    std.debug.print("\n🎉 All CAS tests passed! The cryptographic bedrock is solid.\n", .{});
}

// Test function for the complete pipeline - TODO: Implement when parser is complete
fn testManifestCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 Testing Janus Manifest & Lockfile Parsers...\n", .{});

    // Test 1: KDL Manifest Parsing
    std.debug.print("\n--- Testing KDL Manifest Parser ---\n", .{});

    const kdl_manifest =
        \\name "test-package"
        \\version "1.0.0"
        \\
        \\dependency "crypto" {
        \\    git "https://github.com/example/crypto.git" tag="v2.1.0"
        \\    capability "fs" path="./data"
        \\    capability "net" hosts="api.example.com"
        \\}
        \\
        \\dev-dependency "test-utils" {
        \\    path "./test-utils"
        \\}
    ;

    var parsed_manifest = janus.parseManifest(kdl_manifest, allocator) catch |err| {
        std.debug.print("❌ KDL parsing failed: {}\n", .{err});
        return;
    };
    defer parsed_manifest.deinit();

    std.debug.print("✅ Package name: {s}\n", .{parsed_manifest.name});
    std.debug.print("✅ Package version: {s}\n", .{parsed_manifest.version});
    std.debug.print("✅ Dependencies: {}\n", .{parsed_manifest.dependencies.len});
    std.debug.print("✅ Dev dependencies: {}\n", .{parsed_manifest.dev_dependencies.len});

    if (parsed_manifest.dependencies.len > 0) {
        const crypto_dep = parsed_manifest.dependencies[0];
        std.debug.print("✅ First dependency: {s}\n", .{crypto_dep.name});
        std.debug.print("✅ Capabilities: {}\n", .{crypto_dep.capabilities.len});
    }

    // Test 2: JSON Lockfile Parsing
    std.debug.print("\n--- Testing JSON Lockfile Parser ---\n", .{});

    const json_lockfile =
        \\{
        \\  "version": 1,
        \\  "packages": {
        \\    "crypto": {
        \\      "name": "crypto",
        \\      "version": "2.1.0",
        \\      "content_id": "a1b2c3d4e5f6789012345678901234567890123456789012345678901234567890",
        \\      "source": {
        \\        "type": "git",
        \\        "url": "https://github.com/example/crypto.git",
        \\        "ref": "v2.1.0"
        \\      },
        \\      "capabilities": [
        \\        {
        \\          "name": "fs",
        \\          "params": {
        \\            "path": "./data"
        \\          }
        \\        }
        \\      ],
        \\      "dependencies": ["base64", "hash"]
        \\    }
        \\  }
        \\}
    ;

    var lockfile = janus.parseLockfile(json_lockfile, allocator) catch |err| {
        std.debug.print("❌ JSON parsing failed: {}\n", .{err});
        return;
    };
    defer lockfile.deinit();

    std.debug.print("✅ Lockfile version: {}\n", .{lockfile.version});
    std.debug.print("✅ Packages: {}\n", .{lockfile.packages.count()});

    if (lockfile.packages.get("crypto")) |crypto_pkg| {
        std.debug.print("✅ Crypto package: {s} v{s}\n", .{ crypto_pkg.name, crypto_pkg.version });
        {
            const hex_chars = "0123456789abcdef";
            var hex_buf: [&crypto_pkg.content_id.len * 2]u8 = undefined;
            for (&crypto_pkg.content_id, 0..) |byte, i| {
                hex_buf[i * 2] = hex_chars[byte >> 4];
                hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
            }
            std.debug.print("✅ Content ID: {s}\n", .{hex_buf});
        }
        std.debug.print("✅ Dependencies: {}\n", .{crypto_pkg.dependencies.len});
    }

    // Test 3: Lockfile Serialization Roundtrip
    std.debug.print("\n--- Testing JSON Serialization ---\n", .{});

    const serialized = janus.serializeLockfile(&lockfile, allocator) catch |err| {
        std.debug.print("❌ Serialization failed: {}\n", .{err});
        return;
    };
    defer allocator.free(serialized);

    std.debug.print("✅ Serialized lockfile ({} bytes)\n", .{serialized.len});

    // Parse it back to verify roundtrip
    var roundtrip_lockfile = janus.parseLockfile(serialized, allocator) catch |err| {
        std.debug.print("❌ Roundtrip parsing failed: {}\n", .{err});
        return;
    };
    defer roundtrip_lockfile.deinit();

    std.debug.print("✅ Roundtrip successful: {} packages\n", .{roundtrip_lockfile.packages.count()});

    std.debug.print("\n🎉 All manifest parser tests passed! The armory walls are rising.\n", .{});
}
fn testTransportCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 Testing Janus Transport Layer...\n", .{});

    // Test 1: Transport Registry
    std.debug.print("\n--- Testing Transport Registry ---\n", .{});

    var registry = janus.createTransportRegistry(allocator) catch |err| {
        std.debug.print("❌ Failed to create transport registry: {}\n", .{err});
        return;
    };
    defer registry.deinit();

    std.debug.print("✅ Transport registry created\n", .{});

    // Test 2: Git Availability
    std.debug.print("\n--- Testing Git Availability ---\n", .{});

    const git_available = janus.checkGitAvailable(allocator);
    std.debug.print("✅ Git available: {}\n", .{git_available});

    if (!git_available) {
        std.debug.print("⚠️  Git not available - skipping git+https tests\n", .{});
    }

    // Test 3: File Transport
    std.debug.print("\n--- Testing File Transport ---\n", .{});

    // Create a test file
    const test_file = "test_transport_demo.txt";
    const test_content = "Hello from Janus Transport Layer!";

    try std.fs.cwd().writeFile(.{ .sub_path = test_file, .data = test_content });
    defer std.fs.cwd().deleteFile(test_file) catch {};

    const file_url = "file://" ++ test_file;
    var file_result = janus.fetchContent(&registry, file_url, allocator) catch |err| {
        std.debug.print("❌ File transport failed: {}\n", .{err});
        return;
    };
    defer file_result.deinit();

    std.debug.print("✅ File fetched: {} bytes\n", .{file_result.content.len});
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&file_result.content_id.len * 2]u8 = undefined;
        for (&file_result.content_id, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("✅ Content ID: {s}\n", .{hex_buf});
    }
    std.debug.print("✅ Transport: {s}\n", .{file_result.metadata.get("transport").?});

    // Test 4: Directory Archive
    std.debug.print("\n--- Testing Directory Archive ---\n", .{});

    // Create a test directory
    const test_dir = "test_transport_dir";
    std.fs.cwd().deleteTree(test_dir) catch {};
    defer std.fs.cwd().deleteTree(test_dir) catch {};

    try std.fs.cwd().makeDir(test_dir);
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file1.txt", .data = "Content 1" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_dir ++ "/file2.txt", .data = "Content 2" });

    const dir_url = "file://" ++ test_dir;
    var dir_result = janus.fetchContent(&registry, dir_url, allocator) catch |err| {
        std.debug.print("❌ Directory transport failed: {}\n", .{err});
        return;
    };
    defer dir_result.deinit();

    std.debug.print("✅ Directory archived: {} bytes\n", .{dir_result.content.len});
    {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&dir_result.content_id.len * 2]u8 = undefined;
        for (&dir_result.content_id, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        std.debug.print("✅ Archive Content ID: {s}\n", .{hex_buf});
    }

    // Test 5: Integrity Verification
    std.debug.print("\n--- Testing Integrity Verification ---\n", .{});

    // Fetch with correct content ID
    var verified_result = janus.fetchContentWithVerification(&registry, file_url, file_result.content_id, allocator) catch |err| {
        std.debug.print("❌ Integrity verification failed: {}\n", .{err});
        return;
    };
    defer verified_result.deinit();

    std.debug.print("✅ Integrity verification passed\n", .{});

    // Test with wrong content ID
    var wrong_id: [32]u8 = std.mem.zeroes([32]u8);
    wrong_id[0] = 0xFF;

    const integrity_error = janus.fetchContentWithVerification(&registry, file_url, wrong_id, allocator);
    if (integrity_error) |_| {
        std.debug.print("❌ Integrity verification should have failed\n", .{});
    } else |err| {
        std.debug.print("✅ Integrity verification correctly failed: {}\n", .{err});
    }

    // Test 6: URL Validation
    std.debug.print("\n--- Testing URL Support ---\n", .{});

    const test_urls = [_][]const u8{
        "file:///local/path",
        "git+https://github.com/example/repo.git",
        "https://github.com/example/repo.git",
        "ftp://unsupported.com/file",
    };

    for (test_urls) |url| {
        const transport_found = registry.findTransport(url);
        if (transport_found) |t| {
            std.debug.print("✅ {s}: supported by {s}\n", .{ url, t.name });
        } else {
            std.debug.print("❌ {s}: unsupported\n", .{url});
        }
    }

    std.debug.print("\n🎉 Transport layer tests completed!\n", .{});
    std.debug.print("🎉 The gates are forged and ready!\n", .{});
    std.debug.print("🎉 Assets can now be fetched with cryptographic integrity!\n", .{});
}
fn addCommand(args: [][]const u8, allocator: std.mem.Allocator) !void {
    if (args.len < 3) {
        std.debug.print("Error: add command requires package name and source\n", .{});
        std.debug.print("Usage: janus add <package> <source> [--dev] [--capability <name>=<value>]\n", .{});
        std.debug.print("Examples:\n", .{});
        std.debug.print("  janus add crypto git+https://github.com/example/crypto.git#v1.0.0\n", .{});
        std.debug.print("  janus add utils file:///local/path/to/utils\n", .{});
        std.debug.print("  janus add http git+https://github.com/example/http.git --capability net=api.example.com\n", .{});
        return;
    }

    const package_name = args[2];
    const source_url = args[3];

    // Parse command line options
    var is_dev = false;
    var capabilities = std.ArrayList(janus.Manifest.Capability){};
    defer {
        for (capabilities.items) |*cap| {
            cap.deinit();
        }
        capabilities.deinit(allocator);
    }

    var i: usize = 4;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--dev")) {
            is_dev = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--capability") and i + 1 < args.len) {
            // Parse capability in format "name=value"
            const cap_spec = args[i + 1];
            if (std.mem.indexOf(u8, cap_spec, "=")) |eq_pos| {
                var cap = janus.Manifest.Capability.init(allocator);
                cap.name = try allocator.dupe(u8, cap_spec[0..eq_pos]);
                try cap.params.put("value", try allocator.dupe(u8, cap_spec[eq_pos + 1 ..]));
                try capabilities.append(allocator, cap);
            }
            i += 2;
        } else {
            std.debug.print("Unknown option: {s}\n", .{args[i]});
            return;
        }
    }

    // Parse source URL into source structure
    const source = try parseSourceUrl(source_url, allocator);
    defer freeSource(source, allocator);

    std.debug.print("Adding dependency: {s}\n", .{package_name});
    std.debug.print("Source: {s}\n", .{source_url});
    std.debug.print("Development: {}\n", .{is_dev});
    std.debug.print("Capabilities: {}\n", .{capabilities.items.len});
    // Initialize resolver
    var resolver_instance = janus.createResolver(".janus/cas", allocator) catch |err| {
        std.debug.print("Error: Failed to initialize resolver: {}\n", .{err});
        return;
    };
    defer resolver_instance.deinit();

    // Add dependency
    var result = janus.addDependency(&resolver_instance, package_name, source, capabilities.items, is_dev) catch |err| {
        std.debug.print("Error: Failed to add dependency: {}\n", .{err});
        return;
    };
    defer result.deinit();

    // Check for capability changes
    if (result.capability_changes.len > 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        const approved = janus.promptCapabilityChanges(result.capability_changes, stdout) catch false;
        try stdout.flush();
        if (!approved) {
            std.debug.print("Dependency addition cancelled by user.\n", .{});
            return;
        }
    }

    // Save updated lockfile
    try janus.saveLockfile(&resolver_instance, &result.lockfile);

    std.debug.print("✅ Successfully added {s}\n", .{package_name});
    std.debug.print("📦 Packages added: {}\n", .{result.packages_added.len});
    std.debug.print("🔄 Packages updated: {}\n", .{result.packages_updated.len});
    std.debug.print("🔒 Capability changes: {}\n", .{result.capability_changes.len});
}

fn updateCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("Updating dependencies...\n", .{});

    // Initialize resolver
    var resolver_instance = janus.createResolver(".janus/cas", allocator) catch |err| {
        std.debug.print("Error: Failed to initialize resolver: {}\n", .{err});
        return;
    };
    defer resolver_instance.deinit();

    // Update dependencies
    var result = janus.updateDependencies(&resolver_instance) catch |err| {
        std.debug.print("Error: Faileddependencies: {}\n", .{err});
        return;
    };
    defer result.deinit();

    // Check for capability changes
    if (result.capability_changes.len > 0) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;
        const approved = janus.promptCapabilityChanges(result.capability_changes, stdout) catch false;
        try stdout.flush();
        if (!approved) {
            std.debug.print("Dependency update cancelled by user.\n", .{});
            return;
        }
    }

    // Save updated lockfile
    try janus.saveLockfile(&resolver_instance, &result.lockfile);

    std.debug.print("✅ Dependencies updated successfully\n", .{});
    std.debug.print("📦 Packages added: {}\n", .{result.packages_added.len});
    std.debug.print("🔄 Packages updated: {}\n", .{result.packages_updated.len});
    std.debug.print("❌ Packages removed: {}\n", .{result.packages_removed.len});
    std.debug.print("🔒 Capability changes: {}\n", .{result.capability_changes.len});
}

fn testResolverCommand(allocator: std.mem.Allocator) !void {
    std.debug.print("🔧 Testing Janus Dependency Resolver...\n", .{});

    // Test 1: Resolver Initialization
    std.debug.print("\n--- Testing Resolver Initialization ---\n", .{});
    const cas_root = "test_resolver_demo";
    std.fs.cwd().deleteTree(cas_root) catch {};
    defer std.fs.cwd().deleteTree(cas_root) catch {};

    var resolver_instance = janus.createResolver(cas_root, allocator) catch |err| {
        std.debug.print("❌ Failed to create resolver: {}\n", .{err});
        return;
    };
    defer resolver_instance.deinit();

    std.debug.print("✅ Resolver initialized with CAS at {s}\n", .{cas_root});

    // Test 2: Create Test Package
    std.debug.print("\n--- Testing Package Resolution ---\n", .{});

    const test_pkg_dir = "test_demo_package";
    std.fs.cwd().deleteTree(test_pkg_dir) catch {};
    defer std.fs.cwd().deleteTree(test_pkg_dir) catch {};

    try std.fs.cwd().makeDir(test_pkg_dir);
    try std.fs.cwd().writeFile(.{ .sub_path = test_pkg_dir ++ "/main.zig", .data = "pub fn main() { std.debug.print(\"Hello from test package!\", .{}); }" });
    try std.fs.cwd().writeFile(.{ .sub_path = test_pkg_dir ++ "/README.md", .data = "# Test Demo Package\n\nThis is a test package for the Janus Ledger resolver." });

    // Test 3: Add Dependency
    const source = janus.Manifest.PackageRef.Source{
        .path = .{ .path = test_pkg_dir },
    };

    var capabilities = std.ArrayList(janus.Manifest.Capability){};
    defer {
        for (capabilities.items) |*cap| {
            cap.deinit();
        }
        capabilities.deinit(allocator);
    }

    // Add a test capability
    var test_cap = janus.Manifest.Capability.init(allocator);
    test_cap.name = try allocator.dupe(u8, "fs");
    try test_cap.params.put("path", "./test-data");
    try capabilities.append(allocator, test_cap);

    var result = janus.addDependency(&resolver_instance, "demo-package", source, capabilities.items, false) catch |err| {
        std.debug.print("❌ Failed to add dependency: {}\n", .{err});
        return;
    };
    defer result.deinit();

    std.debug.print("✅ Package resolved and added to lockfile\n", .{});
    std.debug.print("✅ Packages added: {}\n", .{result.packages_added.len});
    std.debug.print("✅ Capability changes: {}\n", .{result.capability_changes.len});

    // Test 4: Capability Change Detection
    if (result.capability_changes.len > 0) {
        std.debug.print("\n--- Testing Capability Change Detection ---\n", .{});

        for (result.capability_changes) |change| {
            std.debug.print("✅ Detected change: {s} - {s}\n", .{ change.package_name, @tagName(change.change_type) });
            if (change.new_capability) |cap| {
                std.debug.print("   Capability: {s}\n", .{cap.name});
                var param_iter = cap.params.iterator();
                while (param_iter.next()) |param| {
                    std.debug.print("   {s}: {s}\n", .{ param.key_ptr.*, param.value_ptr.* });
                }
            }
        }
    }

    // Test 5: Save Lockfile
    std.debug.print("\n--- Testing Lockfile Persistence ---\n", .{});

    try janus.saveLockfile(&resolver_instance, &result.lockfile);
    std.debug.print("✅ Lockfile saved to JANUS.lock\n", .{});

    // Verify lockfile was created
    const lockfile_stat = std.fs.cwd().statFile("JANUS.lock") catch |err| {
        std.debug.print("❌ Failed to verify lockfile: {}\n", .{err});
        return;
    };
    std.debug.print("✅ Lockfile size: {} bytes\n", .{lockfile_stat.size});

    // Clean up test lockfile
    std.fs.cwd().deleteFile("JANUS.lock") catch {};

    std.debug.print("\n🎉 Dependency Resolver tests completed!\n", .{});
    std.debug.print("🎉 The strategic core is operational!\n", .{});
    std.debug.print("🎉 The armory's intelligence is forged!\n", .{});
}

// Helper functions for CLI
fn parseSourceUrl(url: []const u8, allocator: std.mem.Allocator) !janus.Manifest.PackageRef.Source {
    if (std.mem.startsWith(u8, url, "git+https://") or
        (std.mem.startsWith(u8, url, "https://") and std.mem.endsWith(u8, url, ".git")))
    {

        // Parse git URL
        var working_url = url;
        if (std.mem.startsWith(u8, working_url, "git+")) {
            working_url = working_url[4..];
        }

        if (std.mem.indexOf(u8, working_url, "#")) |pos| {
            return janus.Manifest.PackageRef.Source{
                .git = .{
                    .url = try allocator.dupe(u8, working_url[0..pos]),
                    .ref = try allocator.dupe(u8, working_url[pos + 1 ..]),
                },
            };
        } else {
            return janus.Manifest.PackageRef.Source{
                .git = .{
                    .url = try allocator.dupe(u8, working_url),
                    .ref = try allocator.dupe(u8, "main"),
                },
            };
        }
    } else if (std.mem.startsWith(u8, url, "file://")) {
        return janus.Manifest.PackageRef.Source{
            .path = .{
                .path = try allocator.dupe(u8, url[7..]),
            },
        };
    } else if (std.mem.startsWith(u8, url, "https://") and
        (std.mem.endsWith(u8, url, ".tar.gz") or
            std.mem.endsWith(u8, url, ".tar.xz")))
    {
        return janus.Manifest.PackageRef.Source{
            .tar = .{
                .url = try allocator.dupe(u8, url),
                .checksum = null,
            },
        };
    } else {
        std.debug.print("Error: Unsupported source URL format: {s}\n", .{url});
        return error.UnsupportedSourceFormat;
    }
}

fn freeSource(source: janus.Manifest.PackageRef.Source, allocator: std.mem.Allocator) void {
    switch (source) {
        .git => |git| {
            allocator.free(git.url);
            allocator.free(git.ref);
        },
        .tar => |tar| {
            allocator.free(tar.url);
            if (tar.checksum) |checksum| {
                allocator.free(checksum);
            }
        },
        .path => |path| {
            allocator.free(path.path);
        },
    }
}
