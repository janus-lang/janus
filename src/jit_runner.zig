// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// JIT Runner - QTJIR → JIT Forge Bridge
//
// This module connects the QTJIR IR to the Prophetic JIT Forge,
// enabling interactive script execution for :script and higher profiles.
//
// Pipeline: Source → ASTDB → QTJIR → JIT Forge → Execution
//
// Doctrine: Engine Orthogonality
// The same IR (QTJIR) serves both AOT (LLVM path) and JIT (Forge path).
// The engine selection is based on profile and execution mode, not IR structure.

const std = @import("std");
const compat_fs = @import("compat_fs");

/// Zig 0.16 compat: read entire file by path using POSIX openat + statx + read.
/// Replaces removed compat_fs.readFileAlloc().
fn readFileFromPath(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0);
    defer _ = std.os.linux.close(fd);
    var stx: std.os.linux.Statx = undefined;
    if (std.os.linux.statx(fd, "", 0x1000, std.os.linux.STATX.BASIC_STATS, &stx) != 0)
        return error.FileNotFound;
    const size: usize = @intCast(stx.size);
    if (size > max_bytes) return error.FileTooBig;
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    var total: usize = 0;
    while (total < size) {
        const rc = std.os.linux.read(fd, buf[total..].ptr, size - total);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) break;
        total += rc;
    }
    return buf[0..total];
}
const compat_time = @import("compat_time");
const janus_lib = @import("janus_lib");
const janus_parser = janus_lib.parser;
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");
const janus_context = @import("janus_context");

// JIT Forge imports
// JIT Forge imports
const jit_forge = @import("jit_forge");
const semantic = jit_forge.semantic;
const speculation = jit_forge.speculation;
const execution = jit_forge.execution;
const interpreter = jit_forge.interpreter;

/// Execution result from JIT compilation
pub const ExecutionResult = struct {
    success: bool,
    exit_code: i32,
    stdout: []const u8,
    stderr: []const u8,
    execution_time_ns: u64,

    pub fn deinit(self: *ExecutionResult, allocator: std.mem.Allocator) void {
        allocator.free(self.stdout);
        allocator.free(self.stderr);
    }
};

/// Result of a single test execution
pub const TestResult = struct {
    name: []const u8,
    passed: bool,
    duration_ns: u64,
    error_msg: ?[]const u8 = null,
};

/// Coverage statistics for the test run
pub const CoverageReport = struct {
    functions_covered: usize,
    total_functions: usize,
    nodes_executed: usize,
};

/// Result of a full test suite
pub const TestSuiteResult = struct {
    passed: usize,
    failed: usize,
    total_duration_ns: u64,
    tests: []TestResult, // Owned slice
    source_cid: []const u8, // Proof of Source
    coverage: ?CoverageReport = null,

    pub fn deinit(self: *TestSuiteResult, allocator: std.mem.Allocator) void {
        if (self.source_cid.len > 0) allocator.free(self.source_cid);
        for (self.tests) |*t| {
            allocator.free(t.name);
            if (t.error_msg) |msg| allocator.free(msg);
        }
        allocator.free(self.tests);
    }
};

/// JIT execution options
pub const RunOptions = struct {
    source_path: []const u8,
    args: []const []const u8 = &.{},
    verbose: bool = false,
    trace_execution: bool = false,
    profile: Profile = .script,
};

/// Execution profiles for JIT
pub const Profile = enum {
    core,
    script,
    service,
    sovereign,

    pub fn toString(self: Profile) []const u8 {
        return switch (self) {
            .core => ":core",
            .script => ":script",
            .service => ":service",
            .sovereign => ":sovereign",
        };
    }
};

/// Error types for JIT execution
pub const RunError = error{
    ParseFailed,
    LoweringFailed,
    JitCompilationFailed,
    ExecutionFailed,
    FileNotFound,
    InvalidSource,
    OutOfMemory,
    ProfileNotSupported,
};

/// The JIT Runner - connects QTJIR to JIT Forge
pub const JitRunner = struct {
    allocator: std.mem.Allocator,
    options: RunOptions,

    pub fn init(allocator: std.mem.Allocator, options: RunOptions) JitRunner {
        return JitRunner{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Execute a Janus source file using JIT compilation
    pub fn run(self: *JitRunner) RunError!ExecutionResult {
        const allocator = self.allocator;
        const timer_start = compat_time.nanoTimestamp();

        // ========== STAGE 1: READ SOURCE ==========
        if (self.options.verbose) {
            std.debug.print("[JIT] Reading source: {s}\n", .{self.options.source_path});
        }

        const source = readFileFromPath(allocator, self.options.source_path, 10 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return RunError.FileNotFound,
            else => return RunError.InvalidSource,
        };
        defer allocator.free(source);

        // ========== STAGE 2: PARSE SOURCE → ASTDB ==========
        if (self.options.verbose) {
            std.debug.print("[JIT] Parsing source...\n", .{});
        }

        var parser = janus_parser.Parser.init(allocator);
        defer parser.deinit();

        const snapshot = parser.parseWithSource(source) catch return RunError.ParseFailed;
        defer snapshot.deinit();

        if (snapshot.nodeCount() == 0) {
            return RunError.InvalidSource;
        }

        // ========== STAGE 3: LOWER ASTDB → QTJIR ==========
        if (self.options.verbose) {
            std.debug.print("[JIT] Lowering to QTJIR...\n", .{});
        }

        const unit_id: astdb_core.UnitId = @enumFromInt(0);
        var ir_graphs = qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id) catch |err| {
            std.debug.print("[JIT] Lowering error: {}\n", .{err});
            return RunError.LoweringFailed;
        };
        defer {
            for (ir_graphs.items) |*g| g.deinit();
            ir_graphs.deinit(allocator);
        }

        if (ir_graphs.items.len == 0) {
            return RunError.LoweringFailed;
        }

        // ========== STAGE 4: INTERPRETER EXECUTION ==========
        if (self.options.verbose) {
            std.debug.print("[JIT] Registering {} function(s)...\n", .{ir_graphs.items.len});
        }

        var compile_success = true;

        var exit_code: i32 = 0;

        // Initialize capability system
        var caps = janus_context.CapabilitySet.init(allocator);
        defer caps.deinit();

        // Grant I/O capabilities for :script profile
        caps.grantStdoutWrite();
        caps.grantStderrWrite();
        caps.grantFsRead();
        caps.grantFsWrite();

        // Create execution context
        var ctx = janus_context.Context.init(allocator, &caps);
        defer ctx.deinit();

        // Initialize interpreter once with all graphs
        var interp = interpreter.Interpreter.init(allocator);
        defer interp.deinit();
        interp.setVerbose(self.options.trace_execution);
        interp.setContext(&ctx); // Inject capability context

        // Register ALL functions in the function table
        for (ir_graphs.items) |*graph| {
            if (self.options.trace_execution) {
                std.debug.print("[JIT] Registering function: {s} ({} nodes)\n", .{
                    graph.function_name,
                    graph.nodes.items.len,
                });
            }
            interp.registerFunction(qtjir.QTJIRGraph, graph.function_name, graph) catch {
                compile_success = false;
                continue;
            };
        }

        if (!compile_success) {
            return RunError.LoweringFailed;
        }

        // Run starting from "main" entry point
        if (self.options.verbose) {
            std.debug.print("[JIT] Running from entry point: main\n", .{});
        }

        const result = interp.run(qtjir.QTJIRGraph, "main");
        exit_code = result.exit_code;

        if (!compile_success) {
            return RunError.JitCompilationFailed;
        }

        const timer_end = compat_time.nanoTimestamp();
        const execution_time = @as(u64, @intCast(timer_end - timer_start));

        if (self.options.verbose) {
            std.debug.print("[JIT] ✅ Execution complete ({d:.3}ms)\n", .{
                @as(f64, @floatFromInt(execution_time)) / 1_000_000.0,
            });
        }

        return ExecutionResult{
            .success = compile_success,
            .exit_code = exit_code,
            .stdout = try allocator.dupe(u8, ""),
            .stderr = try allocator.dupe(u8, ""),
            .execution_time_ns = execution_time,
        };
    }

    /// Validate a QTJIR graph for JIT compilation
    fn validateGraph(self: *JitRunner, graph: *const qtjir.QTJIRGraph) bool {
        _ = self;
        // Basic structural validation - must have at least one node
        if (graph.nodes.items.len == 0) {
            return false;
        }
        return true;
    }

    /// Execute all verified tests in the source file
    pub fn runTests(self: *JitRunner) RunError!TestSuiteResult {
        const allocator = self.allocator;
        const timer_suite_start = compat_time.nanoTimestamp();

        // ========== STAGE 1 & 2: COMPILE ==========
        // (Similar to run(), but we keep the graphs)
        if (self.options.verbose) std.debug.print("[JIT] Compiling tests: {s}\n", .{self.options.source_path});

        const source = readFileFromPath(allocator, self.options.source_path, 1_000_000) catch |err| {
            if (err == error.FileNotFound) return RunError.FileNotFound;
            return RunError.ExecutionFailed;
        };
        defer allocator.free(source);

        // Compute Proof of Source
        const source_hash = janus_lib.blake3Hash(source);
        const source_cid = try janus_lib.contentIdToHex(source_hash, allocator);
        errdefer allocator.free(source_cid);

        const snapshot = janus_lib.api.parse_root(source, allocator) catch return RunError.ParseFailed;
        defer snapshot.deinit();

        // Check for errors (syntax)
        // TODO: Access diagnostics?

        const unit_id: astdb_core.UnitId = @enumFromInt(0);
        var ir_graphs = qtjir.lower.lowerUnit(allocator, &snapshot.core_snapshot, unit_id) catch |err| {
            if (self.options.verbose) std.debug.print("[JIT] Test Lowering error: {}\n", .{err});
            return RunError.LoweringFailed;
        };

        defer {
            for (ir_graphs.items) |*g| {
                if (std.mem.startsWith(u8, g.function_name, "test:")) {
                    allocator.free(g.function_name);
                }
                g.deinit();
            }
            ir_graphs.deinit(allocator);
        }

        // Initialize interpreter
        var interp = interpreter.Interpreter.init(allocator);
        defer interp.deinit();
        interp.setVerbose(self.options.trace_execution);

        // Register ALL functions
        for (ir_graphs.items) |*graph| {
            interp.registerFunction(qtjir.QTJIRGraph, graph.function_name, graph) catch |err| {
                if (self.options.verbose) std.debug.print("[JIT] RegisterFunction Error: {s} -> {}\n", .{ graph.function_name, err });
                return RunError.JitCompilationFailed;
            };
            if (self.options.verbose) std.debug.print("Registering: '{s}'\n", .{graph.function_name});
        }

        // ========== STAGE 3: EXECUTE TESTS ==========
        // Coverage capture placeholder (Epic 2.6)
        // TODO: Connect to interpreter node counters when implemented
        const coverage: ?CoverageReport = null;

        var results = std.ArrayListUnmanaged(TestResult){};
        errdefer {
            for (results.items) |*t| {
                allocator.free(t.name);
                if (t.error_msg) |m| allocator.free(m);
            }
            results.deinit(allocator);
        }

        var passed_count: usize = 0;
        var failed_count: usize = 0;

        for (ir_graphs.items) |*graph| {
            if (std.mem.startsWith(u8, graph.function_name, "test:")) {
                const test_name = graph.function_name[5..]; // Skip "test:"
                if (self.options.verbose) std.debug.print("[TEST] Running: {s}\n", .{test_name});

                const t_start = compat_time.nanoTimestamp();
                const res = interp.run(qtjir.QTJIRGraph, graph.function_name);
                const t_end = compat_time.nanoTimestamp();

                const passed = (res.exit_code == 0);
                if (passed) passed_count += 1 else failed_count += 1;

                const duration = @as(u64, @intCast(t_end - t_start));

                // Capture error message (stder? or just "Assertion failed"?)
                // For now, if exit_code != 0, we assume assertion failed.
                // We can't easily capture stderr here unless we pipe it.
                // But interpreter prints to stderr.
                // We'll trust the user sees it in console for now.

                try results.append(allocator, TestResult{
                    .name = try allocator.dupe(u8, test_name),
                    .passed = passed,
                    .duration_ns = duration,
                    .error_msg = if (!passed) try allocator.dupe(u8, "Assertion failed") else null,
                });
            }
        }

        const suite_duration = @as(u64, @intCast(compat_time.nanoTimestamp() - timer_suite_start));

        return TestSuiteResult{
            .passed = passed_count,
            .failed = failed_count,
            .total_duration_ns = suite_duration,
            .source_cid = source_cid,
            .tests = try results.toOwnedSlice(allocator),
            .coverage = coverage,
        };
    }
};

// =============================================================================
// Convenience Functions
// =============================================================================

/// Run a Janus script with default options
pub fn runScript(source_path: []const u8, allocator: std.mem.Allocator) !ExecutionResult {
    var runner = JitRunner.init(allocator, .{
        .source_path = source_path,
        .profile = .script,
    });
    return runner.run();
}

/// Run a Janus script in verbose mode
pub fn runScriptVerbose(source_path: []const u8, allocator: std.mem.Allocator) !ExecutionResult {
    var runner = JitRunner.init(allocator, .{
        .source_path = source_path,
        .profile = .script,
        .verbose = true,
        .trace_execution = true,
    });
    return runner.run();
}

// =============================================================================
// Tests
// =============================================================================

test "JitRunner: basic initialization" {
    const allocator = std.testing.allocator;

    const runner = JitRunner.init(allocator, .{
        .source_path = "test.jan",
        .profile = .script,
    });

    try std.testing.expectEqualStrings("test.jan", runner.options.source_path);
    try std.testing.expectEqual(Profile.script, runner.options.profile);
}

test "JitRunner: profile strings" {
    try std.testing.expectEqualStrings(":core", Profile.core.toString());
    try std.testing.expectEqualStrings(":script", Profile.script.toString());
    try std.testing.expectEqualStrings(":service", Profile.service.toString());
    try std.testing.expectEqualStrings(":sovereign", Profile.sovereign.toString());
}
