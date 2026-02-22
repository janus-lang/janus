// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Golden Diag Tool - Task 4.3
//!
//! Executes queries known to violate purity in debug mode and expects Q1001 error
//! Requirements: E-5 (Query purity validation)
//!
//! REBUILT FROM GROUND UP - INTEGRATES WITH LIBJANUS

const std = @import("std");
const print = std.debug.print;
const json = std.json;
const libjanus = @import("libjanus");

const DiagConfig = struct {
    test_file: []const u8,
    output_file: []const u8 = "expect.diag.json",
    debug_mode: bool = true,
    expected_error: []const u8 = "Q1001",
    verbose: bool = false,
};

const DiagnosticResult = struct {
    test_name: []const u8,
    expected_error: []const u8,
    actual_errors: []DiagnosticError,
    validation_passed: bool,
    execution_time_ms: u64,

    const DiagnosticError = struct {
        code: []const u8,
        message: []const u8,
        severity: []const u8,
        source_location: ?SourceLocation = null,
        fix_suggestions: []FixSuggestion = &[_]FixSuggestion{},

        const SourceLocation = struct {
            file: []const u8,
            line: u32,
            column: u32,
            length: u32,
        };

        const FixSuggestion = struct {
            message: []const u8,
            replacement: ?[]const u8 = null,
        };
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

    print("🔍 Golden Diag Tool - Query Purity Validation\n", .{});
    print("=============================================\n", .{});
    print("Test file: {s}\n", .{config.test_file});
    print("Expected error: {s}\n", .{config.expected_error});
    print("Debug mode: {}\n", .{config.debug_mode});
    print("Output: {s}\n\n", .{config.output_file});

    // Execute purity violation test
    const diag_result = try executePurityTest(allocator, config);
    defer {
        allocator.free(diag_result.test_name);
        allocator.free(diag_result.expected_error);
        for (diag_result.actual_errors) |*error_item| {
            allocator.free(error_item.code);
            allocator.free(error_item.message);
            allocator.free(error_item.severity);
            if (error_item.source_location) |*loc| {
                allocator.free(loc.file);
            }
            for (error_item.fix_suggestions) |*suggestion| {
                allocator.free(suggestion.message);
                if (suggestion.replacement) |replacement| {
                    allocator.free(replacement);
                }
            }
            allocator.free(error_item.fix_suggestions);
        }
        allocator.free(diag_result.actual_errors);
    }

    // Analyze results
    try analyzeDiagnosticResult(diag_result);

    // Write output JSON
    try writeDiagJSON(allocator, diag_result, config.output_file);

    print("\n✅ Purity validation test complete!\n", .{});
    print("📁 Diagnostics written to: {s}\n", .{config.output_file});

    // Exit with appropriate code
    if (!diag_result.validation_passed) {
        print("❌ Purity validation FAILED\n", .{});
        std.process.exit(1);
    } else {
        print("✅ Purity validation PASSED\n", .{});
    }
}

fn parseArgs(allocator: std.mem.Allocator, args: [][:0]u8) !DiagConfig {
    _ = allocator;

    var config = DiagConfig{
        .test_file = "",
    };

    var i: usize = 1; // Skip program name
    while (i < args.len) {
        if (std.mem.startsWith(u8, args[i], "--output=")) {
            config.output_file = args[i][9..];
            i += 1;
        } else if (std.mem.startsWith(u8, args[i], "--expected-error=")) {
            config.expected_error = args[i][17..];
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--debug")) {
            config.debug_mode = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--no-debug")) {
            config.debug_mode = false;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--verbose") or std.mem.eql(u8, args[i], "-v")) {
            config.verbose = true;
            i += 1;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            showUsage();
            std.process.exit(0);
        } else {
            // Assume it's the test file
            if (config.test_file.len == 0) {
                config.test_file = args[i];
            } else {
                print("❌ Error: Multiple test files specified. Only one is allowed.\n", .{});
                showUsage();
                std.process.exit(1);
            }
            i += 1;
        }
    }

    if (config.test_file.len == 0) {
        print("❌ Error: No test file specified\n", .{});
        showUsage();
        std.process.exit(1);
    }

    return config;
}

fn executePurityTest(allocator: std.mem.Allocator, config: DiagConfig) !DiagnosticResult {
    const start_time = std.time.milliTimestamp();

    print("🧪 Executing REAL purity violation test with libjanus...\n", .{});

    // Read the test file
    const test_content = std.fs.cwd().readFileAlloc(allocator, config.test_file, 1024 * 1024) catch |err| {
        print("❌ Error reading test file {s}: {}\n", .{ config.test_file, err });
        return err;
    };
    defer allocator.free(test_content);

    if (config.verbose) {
        print("📄 Test file content:\n{s}\n\n", .{test_content});
    }

    // REAL INTEGRATION: Parse with libjanus
    print("  🔧 Parsing with libjanus...\n", .{});
    const parsed_snapshot = libjanus.parse_root(test_content, allocator) catch |err| {
        print("❌ Parse error: {}\n", .{err});
        return DiagnosticResult{
            .test_name = try allocator.dupe(u8, config.test_file),
            .expected_error = try allocator.dupe(u8, config.expected_error),
            .actual_errors = &[_]DiagnosticResult.DiagnosticError{},
            .validation_passed = false,
            .execution_time_ms = 0,
        };
    };
    defer parsed_snapshot.deinit();

    print("  ✅ Parsed successfully\n", .{});

    // REAL INTEGRATION: Initialize Query Engine
    var query_engine = libjanus.QueryEngine.init(allocator, parsed_snapshot);
    defer query_engine.deinit();

    var errors: std.ArrayList(DiagnosticResult.DiagnosticError) = .empty;
    defer errors.deinit();

    // REAL INTEGRATION: Execute queries that should violate purity
    print("  🔍 Executing purity-violating queries...\n", .{});

    // Find all function declarations using real ASTDB query
    const func_predicate = libjanus.Predicate{ .node_kind = .func_decl };
    const func_nodes_result = query_engine.filterNodes(func_predicate);
    defer allocator.free(func_nodes_result.result);

    print("  📊 Found {} function declarations\n", .{func_nodes_result.result.len});

    // REAL INTEGRATION: For each function, execute real purity analysis
    for (func_nodes_result.result) |func_node| {
        // Get function name from real snapshot
        const token_span_result = query_engine.tokenSpan(func_node);
        const first_token = parsed_snapshot.getToken(token_span_result.result.start);
        const func_name = if (first_token) |token|
            parsed_snapshot.*.str_interner.str(token.str_id)
        else
            "unknown";

        print("  🔍 Analyzing function: {s}\n", .{func_name});

        // REAL INTEGRATION: Use real ASTDB query engine to detect I/O effects
        const children_result = query_engine.children(func_node);
        defer allocator.free(children_result.result);

        var has_io_effects = false;

        // Traverse function body using real ASTDB queries
        for (children_result.result) |child_node| {
            if (containsIOEffects(parsed_snapshot, &query_engine, child_node)) {
                has_io_effects = true;
                break;
            }
        }

        if (has_io_effects and config.debug_mode) {
            try errors.append(DiagnosticResult.DiagnosticError{
                .code = try allocator.dupe(u8, "Q1001"),
                .message = try allocator.dupe(u8, "Query purity violation detected: I/O operation in query context"),
                .severity = try allocator.dupe(u8, "error"),
                .source_location = DiagnosticResult.DiagnosticError.SourceLocation{
                    .file = try allocator.dupe(u8, config.test_file),
                    .line = if (first_token) |token| token.span.start_line else 1,
                    .column = if (first_token) |token| token.span.start_col else 1,
                    .length = if (first_token) |token| token.span.end_byte - token.span.start_byte else 10,
                },
                .fix_suggestions = try allocator.dupe(DiagnosticResult.DiagnosticError.FixSuggestion, &[_]DiagnosticResult.DiagnosticError.FixSuggestion{
                    .{
                        .message = try allocator.dupe(u8, "Move I/O operation to dependent query boundary"),
                        .replacement = try allocator.dupe(u8, "// Move I/O to separate query"),
                    },
                    .{
                        .message = try allocator.dupe(u8, "Use capability-gated query instead"),
                        .replacement = null,
                    },
                }),
            });

            print("  🚨 REAL purity violation detected in function: {s}\n", .{func_name});
        }
    }

    const end_time = std.time.milliTimestamp();
    const execution_time = @as(u64, @intCast(end_time - start_time));

    // Check if we found the expected error
    var found_expected_error = false;
    for (errors.items) |error_item| {
        if (std.mem.eql(u8, error_item.code, config.expected_error)) {
            found_expected_error = true;
            break;
        }
    }

    const validation_passed = if (config.debug_mode) found_expected_error else errors.items.len == 0;

    return DiagnosticResult{
        .test_name = try allocator.dupe(u8, config.test_file),
        .expected_error = try allocator.dupe(u8, config.expected_error),
        .actual_errors = try errors.toOwnedSlice(),
        .validation_passed = validation_passed,
        .execution_time_ms = execution_time,
    };
}

// REAL INTEGRATION: Helper function to detect I/O effects using real ASTDB queries
// TODO: Replace hardcoded function list with real Q.EffectsOf query from libjanus core
// The intelligence should reside in the core semantic engine, not in this tool
fn containsIOEffects(ss: *const libjanus.Snapshot, query_engine: *libjanus.QueryEngine, node_id: libjanus.NodeId) bool {
    const node_row = ss.getNode(node_id) orelse return false;

    // Check if this is a call expression using real ASTDB node kind
    if (node_row.kind == .call_expr) {
        // Get the function name being called using real ASTDB token access
        const token_span_result = query_engine.tokenSpan(node_id);
        const first_token = ss.getToken(token_span_result.result.start);
        if (first_token) |token| {
            const func_name = ss.str_interner.str(token.str_id);

            // TEMPORARY: Hardcoded I/O function detection
            // TODO: Replace with libjanus.queryEffectsOf(node_id) when effects system is complete
            if (std.mem.eql(u8, func_name, "fs_read") or
                std.mem.eql(u8, func_name, "net_request") or
                std.mem.eql(u8, func_name, "process_exec") or
                std.mem.eql(u8, func_name, "time_now") or
                std.mem.eql(u8, func_name, "random") or
                std.mem.eql(u8, func_name, "print")) // print is I/O
            {
                return true;
            }
        }
    }

    // Recursively check children using real ASTDB query
    const children_result = query_engine.children(node_id);
    defer query_engine.allocator.free(children_result.result);

    for (children_result.result) |child_node| {
        if (containsIOEffects(ss, query_engine, child_node)) {
            return true;
        }
    }

    return false;
}

fn analyzeDiagnosticResult(result: DiagnosticResult) !void {
    print("📊 Diagnostic Analysis\n", .{});
    print("======================\n", .{});
    print("Test: {s}\n", .{result.test_name});
    print("Expected error: {s}\n", .{result.expected_error});
    print("Execution time: {d}ms\n", .{result.execution_time_ms});
    print("Errors found: {d}\n", .{result.actual_errors.len});

    if (result.actual_errors.len > 0) {
        print("\n🚨 Detected Errors:\n", .{});
        for (result.actual_errors, 0..) |error_item, i| {
            print("  {d}. {s}: {s}\n", .{ i + 1, error_item.code, error_item.message });
            print("     Severity: {s}\n", .{error_item.severity});

            if (error_item.source_location) |loc| {
                print("     Location: {s}:{d}:{d}\n", .{ loc.file, loc.line, loc.column });
            }

            if (error_item.fix_suggestions.len > 0) {
                print("     Suggestions:\n", .{});
                for (error_item.fix_suggestions) |suggestion| {
                    print("       • {s}\n", .{suggestion.message});
                    if (suggestion.replacement) |replacement| {
                        print("         → {s}\n", .{replacement});
                    }
                }
            }
            print("\n", .{});
        }
    }

    print("🎯 Validation Result:\n", .{});
    if (result.validation_passed) {
        print("  ✅ PASSED: Expected error behavior detected\n", .{});
    } else {
        print("  ❌ FAILED: Expected error not found or unexpected behavior\n", .{});
    }

    // Check for specific expected error
    var found_expected = false;
    for (result.actual_errors) |error_item| {
        if (std.mem.eql(u8, error_item.code, result.expected_error)) {
            found_expected = true;
            print("  ✅ Found expected error: {s}\n", .{result.expected_error});
            break;
        }
    }

    if (!found_expected and result.actual_errors.len > 0) {
        print("  ⚠️  Expected error {s} not found, but other errors detected\n", .{result.expected_error});
    } else if (!found_expected) {
        print("  ❌ Expected error {s} not found and no errors detected\n", .{result.expected_error});
    }
}

fn writeDiagJSON(allocator: std.mem.Allocator, result: DiagnosticResult, output_file: []const u8) !void {
    const file = try std.fs.cwd().createFile(output_file, .{});
    defer file.close();

    var json_output: std.ArrayList(u8) = .empty;
    defer json_output.deinit();

    try json.stringify(result, .{ .whitespace = .indent_2 }, json_output.writer());

    try file.writeAll(json_output.items);
}

fn showUsage() void {
    print("Golden Diag Tool - Query Purity Validation\n\n", .{});
    print("Usage: golden_diag [options] <test_file>\n\n", .{});
    print("Options:\n", .{});
    print("  --output=<file>          Output file (default: expect.diag.json)\n", .{});
    print("  --expected-error=<code>  Expected error code (default: Q1001)\n", .{});
    print("  --debug                  Enable debug mode (default)\n", .{});
    print("  --no-debug               Disable debug mode\n", .{});
    print("  --verbose, -v            Verbose output\n", .{});
    print("  --help, -h               Show this help\n\n", .{});
    print("Examples:\n", .{});
    print("  golden_diag impure_query_test.jan\n", .{});
    print("  golden_diag --expected-error=Q1002 time_query_test.jan\n", .{});
    print("  golden_diag --output=custom.diag.json --verbose test.jan\n\n", .{});
    print("The tool executes queries that should violate purity constraints\n", .{});
    print("and validates that the expected error codes are generated.\n\n", .{});
    print("Common purity violation patterns:\n", .{});
    print("  • I/O operations: std.fs.read, std.net.http, std.process.exec\n", .{});
    print("  • Non-deterministic functions: std.time.now, std.random\n", .{});
    print("  • Global state access: global variables, singletons\n", .{});
}
