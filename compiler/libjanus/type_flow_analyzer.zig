// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Type Flow Analyzer
//!
//! Tracks the complete type inference chain to show WHERE type inference
//! diverged from expectations. Unlike Rust's "expected X, found Y", we show:
//!
//! 1. data: [f64; 10]        (literal at line 50)
//! 2. process(data) -> f64   (return type, lib.jan:120)
//! 3. result: f64            (inferred)
//! 4. use_result(result)     (expects i32)  <-- DIVERGENCE
//!
//! This helps users understand WHY a type mismatch occurred, not just THAT
//! it occurred.

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const nextgen = @import("nextgen_diagnostic.zig");
const TypeFlowChain = nextgen.TypeFlowChain;
const InferenceStep = nextgen.InferenceStep;
const InferenceReason = nextgen.InferenceReason;
const SourceSpan = nextgen.SourceSpan;
const SourcePos = nextgen.SourcePos;
const CID = nextgen.CID;
const TypeId = @import("type_registry.zig").TypeId;

/// Configuration for type flow analysis
pub const TypeFlowConfig = struct {
    /// Maximum steps to track in a chain
    max_chain_length: u32 = 20,
    /// Include intermediate coercions
    track_coercions: bool = true,
    /// Track constraint sources
    track_constraints: bool = true,
    /// Simplify chains by removing redundant steps
    simplify_chains: bool = true,
};

/// Type flow event recorded during type inference
pub const TypeFlowEvent = struct {
    location: SourceSpan,
    node_cid: CID,
    type_before: ?TypeId,
    type_after: TypeId,
    reason: InferenceReason,
    constraint_source: ?SourceSpan,
    expression_text: []const u8,
    timestamp: u64, // Inference order

    pub fn clone(self: TypeFlowEvent, allocator: Allocator) !TypeFlowEvent {
        return .{
            .location = try self.location.clone(allocator),
            .node_cid = self.node_cid,
            .type_before = self.type_before,
            .type_after = self.type_after,
            .reason = self.reason,
            .constraint_source = if (self.constraint_source) |cs| try cs.clone(allocator) else null,
            .expression_text = try allocator.dupe(u8, self.expression_text),
            .timestamp = self.timestamp,
        };
    }

    pub fn deinit(self: *TypeFlowEvent, allocator: Allocator) void {
        allocator.free(self.expression_text);
    }
};

/// Type flow recorder - used during type inference to record events
pub const TypeFlowRecorder = struct {
    allocator: Allocator,
    events: ArrayList(TypeFlowEvent),
    config: TypeFlowConfig,
    next_timestamp: u64,
    enabled: bool,

    pub fn init(allocator: Allocator) TypeFlowRecorder {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: TypeFlowConfig) TypeFlowRecorder {
        return .{
            .allocator = allocator,
            .events = .empty,
            .config = config,
            .next_timestamp = 0,
            .enabled = true,
        };
    }

    pub fn deinit(self: *TypeFlowRecorder) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.deinit();
    }

    /// Enable/disable recording
    pub fn setEnabled(self: *TypeFlowRecorder, enabled: bool) void {
        self.enabled = enabled;
    }

    /// Record a type inference event
    pub fn record(
        self: *TypeFlowRecorder,
        location: SourceSpan,
        node_cid: CID,
        type_before: ?TypeId,
        type_after: TypeId,
        reason: InferenceReason,
        expression_text: []const u8,
    ) !void {
        if (!self.enabled) return;
        if (self.events.items.len >= self.config.max_chain_length) return;

        try self.events.append(.{
            .location = try location.clone(self.allocator),
            .node_cid = node_cid,
            .type_before = type_before,
            .type_after = type_after,
            .reason = reason,
            .constraint_source = null,
            .expression_text = try self.allocator.dupe(u8, expression_text),
            .timestamp = self.next_timestamp,
        });

        self.next_timestamp += 1;
    }

    /// Record a type inference event with constraint source
    pub fn recordWithConstraint(
        self: *TypeFlowRecorder,
        location: SourceSpan,
        node_cid: CID,
        type_before: ?TypeId,
        type_after: TypeId,
        reason: InferenceReason,
        expression_text: []const u8,
        constraint_source: SourceSpan,
    ) !void {
        if (!self.enabled) return;
        if (self.events.items.len >= self.config.max_chain_length) return;

        try self.events.append(.{
            .location = try location.clone(self.allocator),
            .node_cid = node_cid,
            .type_before = type_before,
            .type_after = type_after,
            .reason = reason,
            .constraint_source = try constraint_source.clone(self.allocator),
            .expression_text = try self.allocator.dupe(u8, expression_text),
            .timestamp = self.next_timestamp,
        });

        self.next_timestamp += 1;
    }

    /// Clear all recorded events
    pub fn clear(self: *TypeFlowRecorder) void {
        for (self.events.items) |*event| {
            event.deinit(self.allocator);
        }
        self.events.clearRetainingCapacity();
        self.next_timestamp = 0;
    }

    /// Get count of recorded events
    pub fn count(self: *const TypeFlowRecorder) usize {
        return self.events.items.len;
    }
};

/// Type Flow Analyzer - analyzes recorded flow to find divergence points
pub const TypeFlowAnalyzer = struct {
    allocator: Allocator,
    config: TypeFlowConfig,

    pub fn init(allocator: Allocator) TypeFlowAnalyzer {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: TypeFlowConfig) TypeFlowAnalyzer {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *TypeFlowAnalyzer) void {
        _ = self;
        // No persistent state
    }

    /// Build a type flow chain from recorded events
    pub fn buildChain(
        self: *TypeFlowAnalyzer,
        recorder: *const TypeFlowRecorder,
        expected_type: TypeId,
        actual_type: TypeId,
    ) !TypeFlowChain {
        if (recorder.events.items.len == 0) {
            return TypeFlowChain{
                .steps = &[_]InferenceStep{},
                .divergence_point = null,
                .expected_type = expected_type,
                .actual_type = actual_type,
            };
        }

        var steps: ArrayList(InferenceStep) = .empty;
        errdefer {
            for (steps.items) |*step| {
                step.deinit(self.allocator);
            }
            steps.deinit();
        }

        // Convert events to steps
        for (recorder.events.items) |event| {
            try steps.append(.{
                .location = try event.location.clone(self.allocator),
                .node_cid = event.node_cid,
                .type_before = event.type_before,
                .type_after = event.type_after,
                .reason = event.reason,
                .constraint_source = if (event.constraint_source) |cs| try cs.clone(self.allocator) else null,
                .expression_text = try self.allocator.dupe(u8, event.expression_text),
            });
        }

        // Simplify if configured
        if (self.config.simplify_chains) {
            self.simplifySteps(&steps);
        }

        // Find divergence point
        var divergence_point: ?usize = null;
        for (steps.items, 0..) |step, i| {
            if (!step.type_after.equals(expected_type)) {
                divergence_point = i;
                break;
            }
        }

        return TypeFlowChain{
            .steps = try steps.toOwnedSlice(),
            .divergence_point = divergence_point,
            .expected_type = expected_type,
            .actual_type = actual_type,
        };
    }

    /// Build a chain specifically for a type mismatch at a given location
    pub fn buildChainForMismatch(
        self: *TypeFlowAnalyzer,
        recorder: *const TypeFlowRecorder,
        mismatch_location: SourceSpan,
        expected_type: TypeId,
        actual_type: TypeId,
    ) !TypeFlowChain {
        // Filter events relevant to the mismatch location
        var relevant_events: ArrayList(TypeFlowEvent) = .empty;
        defer {
            for (relevant_events.items) |*event| {
                event.deinit(self.allocator);
            }
            relevant_events.deinit();
        }

        for (recorder.events.items) |event| {
            // Include events that lead to the mismatch location
            if (isRelevantToLocation(event.location, mismatch_location)) {
                try relevant_events.append(try event.clone(self.allocator));
            }
        }

        // Sort by timestamp
        std.mem.sort(TypeFlowEvent, relevant_events.items, {}, struct {
            fn lessThan(_: void, a: TypeFlowEvent, b: TypeFlowEvent) bool {
                return a.timestamp < b.timestamp;
            }
        }.lessThan);

        // Build chain from filtered events
        var steps: ArrayList(InferenceStep) = .empty;
        errdefer {
            for (steps.items) |*step| {
                step.deinit(self.allocator);
            }
            steps.deinit();
        }

        for (relevant_events.items) |event| {
            try steps.append(.{
                .location = try event.location.clone(self.allocator),
                .node_cid = event.node_cid,
                .type_before = event.type_before,
                .type_after = event.type_after,
                .reason = event.reason,
                .constraint_source = if (event.constraint_source) |cs| try cs.clone(self.allocator) else null,
                .expression_text = try self.allocator.dupe(u8, event.expression_text),
            });
        }

        // Find divergence
        var divergence_point: ?usize = null;
        for (steps.items, 0..) |step, i| {
            if (!step.type_after.equals(expected_type)) {
                divergence_point = i;
                break;
            }
        }

        return TypeFlowChain{
            .steps = try steps.toOwnedSlice(),
            .divergence_point = divergence_point,
            .expected_type = expected_type,
            .actual_type = actual_type,
        };
    }

    /// Analyze a chain and provide insights
    pub fn analyzeChain(self: *TypeFlowAnalyzer, chain: *const TypeFlowChain) ChainAnalysis {
        _ = self;

        var analysis = ChainAnalysis{
            .has_divergence = chain.divergence_point != null,
            .divergence_reason = null,
            .likely_cause = null,
            .suggested_fix_point = null,
        };

        if (chain.divergence_point) |div_idx| {
            if (div_idx < chain.steps.len) {
                const step = chain.steps[div_idx];
                analysis.divergence_reason = step.reason;
                analysis.suggested_fix_point = step.location;

                // Determine likely cause based on divergence reason
                analysis.likely_cause = switch (step.reason) {
                    .literal_value => .wrong_literal_type,
                    .function_return => .wrong_function_called,
                    .variable_binding => .wrong_initialization,
                    .generic_instantiation => .generic_constraint_issue,
                    .coercion => .implicit_coercion_failed,
                    else => .unknown,
                };
            }
        }

        return analysis;
    }

    /// Format chain for human-readable output
    pub fn formatChain(self: *TypeFlowAnalyzer, chain: *const TypeFlowChain) ![]const u8 {
        var output: ArrayList(u8) = .empty;
        const writer = output.writer();

        try writer.writeAll("Type flow chain:\n\n");

        for (chain.steps, 0..) |step, i| {
            const marker = if (chain.divergence_point) |div|
                (if (i == div) " <-- DIVERGENCE" else "")
            else
                "";

            const type_before_str = if (step.type_before) |tb|
                typeIdToName(tb)
            else
                "?";

            try writer.print("   {d}. {s}\n", .{ i + 1, step.expression_text });
            try writer.print("      Type: {s} -> {s} ({s}){s}\n", .{
                type_before_str,
                typeIdToName(step.type_after),
                step.reason.description(),
                marker,
            });
            try writer.print("      Location: {}\n\n", .{step.location});
        }

        if (chain.divergence_point) |div_idx| {
            try writer.print("Divergence at step {d}: expected {s}, got {s}\n", .{
                div_idx + 1,
                typeIdToName(chain.expected_type),
                typeIdToName(chain.actual_type),
            });
        }

        return try output.toOwnedSlice(alloc);
    }

    // =========================================================================
    // Private helpers
    // =========================================================================

    fn simplifySteps(self: *TypeFlowAnalyzer, steps: *ArrayList(InferenceStep)) void {
        if (steps.items.len <= 2) return;

        // Remove consecutive steps with same type (redundant)
        var i: usize = 0;
        while (i + 1 < steps.items.len) {
            const current = steps.items[i];
            const next = steps.items[i + 1];

            if (current.type_after.equals(next.type_after) and
                current.reason == next.reason)
            {
                // Remove the redundant step
                var removed = steps.orderedRemove(i + 1);
                removed.deinit(self.allocator);
            } else {
                i += 1;
            }
        }
    }
};

/// Analysis results for a type flow chain
pub const ChainAnalysis = struct {
    has_divergence: bool,
    divergence_reason: ?InferenceReason,
    likely_cause: ?LikelyCause,
    suggested_fix_point: ?SourceSpan,

    pub const LikelyCause = enum {
        wrong_literal_type,
        wrong_function_called,
        wrong_initialization,
        generic_constraint_issue,
        implicit_coercion_failed,
        unknown,
    };
};

// =============================================================================
// Helper Functions
// =============================================================================

fn isRelevantToLocation(event_loc: SourceSpan, target_loc: SourceSpan) bool {
    // Same file
    if (!std.mem.eql(u8, event_loc.file, target_loc.file)) {
        return false;
    }

    // Event is before or at target location
    if (event_loc.start.line > target_loc.end.line) {
        return false;
    }

    return true;
}

fn typeIdToName(type_id: TypeId) []const u8 {
    return switch (type_id.id) {
        0 => "invalid",
        1 => "i32",
        2 => "f64",
        3 => "bool",
        4 => "string",
        else => "unknown",
    };
}

// =============================================================================
// Integration helpers for semantic analysis
// =============================================================================

/// Context passed during type inference to record flow events
pub const InferenceContext = struct {
    recorder: *TypeFlowRecorder,
    current_file: []const u8,
    constraint_stack: ArrayList(SourceSpan),

    pub fn init(allocator: Allocator, recorder: *TypeFlowRecorder, file: []const u8) InferenceContext {
        return .{
            .recorder = recorder,
            .current_file = file,
            .constraint_stack = .empty,
        };
    }

    pub fn deinit(self: *InferenceContext) void {
        self.constraint_stack.deinit();
    }

    /// Push a constraint source onto the stack
    pub fn pushConstraint(self: *InferenceContext, location: SourceSpan) !void {
        try self.constraint_stack.append(location);
    }

    /// Pop a constraint source from the stack
    pub fn popConstraint(self: *InferenceContext) ?SourceSpan {
        return self.constraint_stack.popOrNull();
    }

    /// Get current constraint source (if any)
    pub fn currentConstraint(self: *const InferenceContext) ?SourceSpan {
        if (self.constraint_stack.items.len == 0) return null;
        return self.constraint_stack.items[self.constraint_stack.items.len - 1];
    }

    /// Record a type inference step
    pub fn recordInference(
        self: *InferenceContext,
        line: u32,
        column: u32,
        node_cid: CID,
        type_before: ?TypeId,
        type_after: TypeId,
        reason: InferenceReason,
        expression_text: []const u8,
    ) !void {
        const location = SourceSpan{
            .file = self.current_file,
            .start = .{ .line = line, .column = column },
            .end = .{ .line = line, .column = column + @as(u32, @intCast(expression_text.len)) },
        };

        if (self.currentConstraint()) |constraint| {
            try self.recorder.recordWithConstraint(
                location,
                node_cid,
                type_before,
                type_after,
                reason,
                expression_text,
                constraint,
            );
        } else {
            try self.recorder.record(
                location,
                node_cid,
                type_before,
                type_after,
                reason,
                expression_text,
            );
        }
    }
};

// =============================================================================
// Tests
// =============================================================================

test "TypeFlowRecorder basic recording" {
    const allocator = std.testing.allocator;

    var recorder = TypeFlowRecorder.init(allocator);
    defer recorder.deinit();

    try recorder.record(
        .{ .file = "test.jan", .start = .{ .line = 1, .column = 1 }, .end = .{ .line = 1, .column = 10 } },
        std.mem.zeroes(CID),
        null,
        TypeId.I32,
        .literal_value,
        "42",
    );

    try std.testing.expectEqual(@as(usize, 1), recorder.count());
}

test "TypeFlowAnalyzer builds chain" {
    const allocator = std.testing.allocator;

    var recorder = TypeFlowRecorder.init(allocator);
    defer recorder.deinit();

    // Record a simple flow: literal -> variable -> usage
    try recorder.record(
        .{ .file = "test.jan", .start = .{ .line = 1, .column = 1 }, .end = .{ .line = 1, .column = 3 } },
        std.mem.zeroes(CID),
        null,
        TypeId.F64,
        .literal_value,
        "3.14",
    );

    try recorder.record(
        .{ .file = "test.jan", .start = .{ .line = 2, .column = 1 }, .end = .{ .line = 2, .column = 10 } },
        std.mem.zeroes(CID),
        TypeId.F64,
        TypeId.F64,
        .variable_binding,
        "let x = 3.14",
    );

    var analyzer = TypeFlowAnalyzer.init(allocator);
    defer analyzer.deinit();

    var chain = try analyzer.buildChain(&recorder, TypeId.I32, TypeId.F64);
    defer chain.deinit(allocator);

    try std.testing.expectEqual(@as(usize, 2), chain.steps.len);
    try std.testing.expect(chain.divergence_point != null);
}

test "TypeFlowAnalyzer finds divergence" {
    const allocator = std.testing.allocator;

    var recorder = TypeFlowRecorder.init(allocator);
    defer recorder.deinit();

    // First step: i32 (matches expected)
    try recorder.record(
        .{ .file = "test.jan", .start = .{ .line = 1, .column = 1 }, .end = .{ .line = 1, .column = 2 } },
        std.mem.zeroes(CID),
        null,
        TypeId.I32,
        .literal_value,
        "42",
    );

    // Second step: f64 (diverges from expected i32)
    try recorder.record(
        .{ .file = "test.jan", .start = .{ .line = 2, .column = 1 }, .end = .{ .line = 2, .column = 10 } },
        std.mem.zeroes(CID),
        TypeId.I32,
        TypeId.F64,
        .function_return,
        "toFloat(42)",
    );

    var analyzer = TypeFlowAnalyzer.init(allocator);
    defer analyzer.deinit();

    var chain = try analyzer.buildChain(&recorder, TypeId.I32, TypeId.F64);
    defer chain.deinit(allocator);

    try std.testing.expectEqual(@as(?usize, 1), chain.divergence_point);

    const analysis = analyzer.analyzeChain(&chain);
    try std.testing.expect(analysis.has_divergence);
    try std.testing.expectEqual(InferenceReason.function_return, analysis.divergence_reason.?);
}

test "InferenceContext constraint tracking" {
    const allocator = std.testing.allocator;

    var recorder = TypeFlowRecorder.init(allocator);
    defer recorder.deinit();

    var ctx = InferenceContext.init(allocator, &recorder, "test.jan");
    defer ctx.deinit();

    // Push a constraint from a function signature
    try ctx.pushConstraint(.{
        .file = "lib.jan",
        .start = .{ .line = 10, .column = 1 },
        .end = .{ .line = 10, .column = 20 },
    });

    try ctx.recordInference(
        5,
        1,
        std.mem.zeroes(CID),
        null,
        TypeId.I32,
        .expected_type,
        "arg",
    );

    // The recorded event should have the constraint source
    try std.testing.expectEqual(@as(usize, 1), recorder.count());

    const event = recorder.events.items[0];
    try std.testing.expect(event.constraint_source != null);
    try std.testing.expectEqual(@as(u32, 10), event.constraint_source.?.start.line);
}
