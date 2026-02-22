// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const compat_time = @import("compat_time");
const testing = std.testing;
const IRComparator = @import("ir_comparator.zig").IRComparator;

// Golden Test Framework - Approval Workflow
// Task 6: Create golden reference approval workflow
// Requirements: 2.3, 2.4, 7.2, 7.4

/// Approval workflow for golden reference updates with history tracking
pub const ApprovalWorkflow = struct {
    allocator: std.mem.Allocator,
    approval_log_path: []const u8,

    const Self = @This();

    pub const ApprovalDecision = enum {
        approved,
        rejected,
        pending,

        pub fn toString(self: ApprovalDecision) []const u8 {
            return switch (self) {
                .approved => "approved",
                .rejected => "rejected",
                .pending => "pending",
            };
        }

        pub fn fromString(str: []const u8) ?ApprovalDecision {
            if (std.mem.eql(u8, str, "approved")) return .approved;
            if (std.mem.eql(u8, str, "rejected")) return .rejected;
            if (std.mem.eql(u8, str, "pending")) return .pending;
            return null;
        }
    };

    pub const ApprovalRequest = struct {
        test_name: []const u8,
        platform: []const u8,
        optimization_level: []const u8,
        old_content_hash: []const u8,
        new_content_hash: []const u8,
        difference_summary: DifferenceSummary,
        justification: []const u8,
        requested_by: []const u8,
        requested_at: i64,

        pub const DifferenceSummary = struct {
            total_differences: u32,
            critical_count: u32,
            breaking_count: u32,
            semantic_count: u32,
            cosmetic_count: u32,
            severity_requires_approval: bool,
        };

        pub fn deinit(self: *ApprovalRequest, allocator: std.mem.Allocator) void {
            allocator.free(self.test_name);
            allocator.free(self.platform);
            allocator.free(self.optimization_level);
            allocator.free(self.old_content_hash);
            allocator.free(self.new_content_hash);
            allocator.free(self.justification);
            allocator.free(self.requested_by);
        }
    };

    pub const ApprovalRecord = struct {
        request: ApprovalRequest,
        decision: ApprovalDecision,
        approved_by: ?[]const u8,
        approved_at: ?i64,
        approval_notes: ?[]const u8,

        pub fn deinit(self: *ApprovalRecord, allocator: std.mem.Allocator) void {
            self.request.deinit(allocator);
            if (self.approved_by) |approved_by| {
                allocator.free(approved_by);
            }
            if (self.approval_notes) |notes| {
                allocator.free(notes);
            }
        }
    };

    pub const ApprovalResult = struct {
        requires_approval: bool,
        auto_approved: bool,
        approval_request: ?ApprovalRequest,
        reason: []const u8,

        pub fn deinit(self: *ApprovalResult, allocator: std.mem.Allocator) void {
            if (self.approval_request) |*request| {
                request.deinit(allocator);
            }
            allocator.free(self.reason);
        }
    };

    pub fn init(allocator: std.mem.Allocator, approval_log_path: []const u8) !Self {
        // Ensure approval log directory exists
        if (std.fs.path.dirname(approval_log_path)) |dir_path| {
            compat_fs.makeDir(dir_path) catch |err| switch (err) {
                error.PathAlreadyExists => {},
                else => return err,
            };
        }

        return Self{
            .allocator = allocator,
            .approval_log_path = try allocator.dupe(u8, approval_log_path),
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.approval_log_path);
    }

    /// Detect if approval is required based on difference severity
    pub fn detectApprovalRequired(self: *const Self, comparison_result: *const IRComparator.ComparisonResult) !ApprovalResult {
        const summary = comparison_result.summary;

        // Auto-approve cosmetic changes only
        if (summary.critical_count == 0 and
            summary.breaking_count == 0 and
            summary.semantic_count == 0 and
            summary.cosmetic_count > 0)
        {
            return ApprovalResult{
                .requires_approval = false,
                .auto_approved = true,
                .approval_request = null,
                .reason = try self.allocator.dupe(u8, "Auto-approved: cosmetic changes only"),
            };
        }

        // Require approval for any semantic, breaking, or critical changes
        if (summary.semantic_count > 0 or
            summary.breaking_count > 0 or
            summary.critical_count > 0)
        {
            const reason = try std.fmt.allocPrint(self.allocator, "Approval required: {} critical, {} breaking, {} semantic differences", .{ summary.critical_count, summary.breaking_count, summary.semantic_count });

            return ApprovalResult{
                .requires_approval = true,
                .auto_approved = false,
                .approval_request = null,
                .reason = reason,
            };
        }

        // No differences - no approval needed
        return ApprovalResult{
            .requires_approval = false,
            .auto_approved = true,
            .approval_request = null,
            .reason = try self.allocator.dupe(u8, "No differences detected"),
        };
    }

    /// Create approval request for golden reference update
    pub fn createApprovalRequest(self: *const Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, old_content_hash: []const u8, new_content_hash: []const u8, comparison_result: *const IRComparator.ComparisonResult, justification: []const u8, requested_by: []const u8) !ApprovalRequest {
        const summary = comparison_result.summary;

        return ApprovalRequest{
            .test_name = try self.allocator.dupe(u8, test_name),
            .platform = try self.allocator.dupe(u8, platform),
            .optimization_level = try self.allocator.dupe(u8, optimization_level),
            .old_content_hash = try self.allocator.dupe(u8, old_content_hash),
            .new_content_hash = try self.allocator.dupe(u8, new_content_hash),
            .difference_summary = ApprovalRequest.DifferenceSummary{
                .total_differences = summary.total_differences,
                .critical_count = summary.critical_count,
                .breaking_count = summary.breaking_count,
                .semantic_count = summary.semantic_count,
                .cosmetic_count = summary.cosmetic_count,
                .severity_requires_approval = summary.hasCriticalDifferences(),
            },
            .justification = try self.allocator.dupe(u8, justification),
            .requested_by = try self.allocator.dupe(u8, requested_by),
            .requested_at = compat_time.timestamp(),
        };
    }

    /// Submit approval request and log it
    pub fn submitApprovalRequest(self: *const Self, request: ApprovalRequest) !void {
        const record = ApprovalRecord{
            .request = request,
            .decision = .pending,
            .approved_by = null,
            .approved_at = null,
            .approval_notes = null,
        };

        try self.logApprovalRecord(&record);
    }

    /// Process approval decision
    pub fn processApproval(self: *const Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, decision: ApprovalDecision, approved_by: []const u8, approval_notes: ?[]const u8) !void {
        // Find the pending request
        var records = try self.loadApprovalHistory();
        defer {
            for (records) |*record| {
                record.deinit(self.allocator);
            }
            self.allocator.free(records);
        }

        // Update the matching record
        for (records) |*record| {
            if (std.mem.eql(u8, record.request.test_name, test_name) and
                std.mem.eql(u8, record.request.platform, platform) and
                std.mem.eql(u8, record.request.optimization_level, optimization_level) and
                record.decision == .pending)
            {
                record.decision = decision;
                record.approved_by = try self.allocator.dupe(u8, approved_by);
                record.approved_at = compat_time.timestamp();
                if (approval_notes) |notes| {
                    record.approval_notes = try self.allocator.dupe(u8, notes);
                }

                try self.logApprovalRecord(record);
                break;
            }
        }
    }

    /// Check if a golden reference update is approved
    pub fn isUpdateApproved(self: *const Self, test_name: []const u8, platform: []const u8, optimization_level: []const u8, content_hash: []const u8) !bool {
        const records = try self.loadApprovalHistory();
        defer {
            for (records) |*record| {
                record.deinit(self.allocator);
            }
            self.allocator.free(records);
        }

        for (records) |record| {
            if (std.mem.eql(u8, record.request.test_name, test_name) and
                std.mem.eql(u8, record.request.platform, platform) and
                std.mem.eql(u8, record.request.optimization_level, optimization_level) and
                std.mem.eql(u8, record.request.new_content_hash, content_hash) and
                record.decision == .approved)
            {
                return true;
            }
        }

        return false;
    }

    /// Get approval history for a test
    pub fn getApprovalHistory(self: *const Self, test_name: []const u8) ![]ApprovalRecord {
        const all_records = try self.loadApprovalHistory();
        var matching_records: std.ArrayList(ApprovalRecord) = .empty;

        for (all_records) |record| {
            if (std.mem.eql(u8, record.request.test_name, test_name)) {
                try matching_records.append(record);
            } else {
                // Clean up non-matching records
                var mutable_record = record;
                mutable_record.deinit(self.allocator);
            }
        }

        self.allocator.free(all_records);
        return try matching_records.toOwnedSlice(alloc);
    }

    /// Generate approval report
    pub fn generateApprovalReport(self: *const Self, records: []const ApprovalRecord) ![]const u8 {
        var report: std.ArrayList(u8) = .empty;
        var writer = report.writer();

        try writer.print("Golden Reference Approval Report\n");
        try writer.print("================================\n\n");

        if (records.len == 0) {
            try writer.print("No approval records found.\n");
            return try report.toOwnedSlice(alloc);
        }

        for (records, 0..) |record, i| {
            try writer.print("{}. Test: {s}\n", .{ i + 1, record.request.test_name });
            try writer.print("   Platform: {s}\n", .{record.request.platform});
            try writer.print("   Optimization: {s}\n", .{record.request.optimization_level});
            try writer.print("   Decision: {s}\n", .{record.decision.toString()});
            try writer.print("   Requested by: {s}\n", .{record.request.requested_by});
            try writer.print("   Requested at: {}\n", .{record.request.requested_at});

            if (record.approved_by) |approved_by| {
                try writer.print("   Approved by: {s}\n", .{approved_by});
            }
            if (record.approved_at) |approved_at| {
                try writer.print("   Approved at: {}\n", .{approved_at});
            }
            if (record.approval_notes) |notes| {
                try writer.print("   Notes: {s}\n", .{notes});
            }

            try writer.print("   Differences: {} total ({} critical, {} breaking, {} semantic, {} cosmetic)\n", .{
                record.request.difference_summary.total_differences,
                record.request.difference_summary.critical_count,
                record.request.difference_summary.breaking_count,
                record.request.difference_summary.semantic_count,
                record.request.difference_summary.cosmetic_count,
            });
            try writer.print("   Justification: {s}\n\n", .{record.request.justification});
        }

        return try report.toOwnedSlice(alloc);
    }

    // Private helper functions

    fn logApprovalRecord(self: *const Self, record: *const ApprovalRecord) !void {
        const file = try compat_fs.createFile(self.approval_log_path, .{ .truncate = false });
        defer file.close();

        try file.seekFromEnd(0);

        const log_entry = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "test_name": "{s}",
            \\  "platform": "{s}",
            \\  "optimization_level": "{s}",
            \\  "old_content_hash": "{s}",
            \\  "new_content_hash": "{s}",
            \\  "decision": "{s}",
            \\  "requested_by": "{s}",
            \\  "requested_at": {},
            \\  "approved_by": "{s}",
            \\  "approved_at": {},
            \\  "approval_notes": "{s}",
            \\  "difference_summary": {{
            \\    "total_differences": {},
            \\    "critical_count": {},
            \\    "breaking_count": {},
            \\    "semantic_count": {},
            \\    "cosmetic_count": {}
            \\  }},
            \\  "justification": "{s}"
            \\}}
            \\
        , .{
            record.request.test_name,
            record.request.platform,
            record.request.optimization_level,
            record.request.old_content_hash,
            record.request.new_content_hash,
            record.decision.toString(),
            record.request.requested_by,
            record.request.requested_at,
            record.approved_by orelse "",
            record.approved_at orelse 0,
            record.approval_notes orelse "",
            record.request.difference_summary.total_differences,
            record.request.difference_summary.critical_count,
            record.request.difference_summary.breaking_count,
            record.request.difference_summary.semantic_count,
            record.request.difference_summary.cosmetic_count,
            record.request.justification,
        });
        defer self.allocator.free(log_entry);

        try file.writeAll(log_entry);
    }

    fn loadApprovalHistory(self: *const Self) ![]ApprovalRecord {
        const file = std.fs.cwd().openFile(self.approval_log_path, .{}) catch |err| switch (err) {
            error.FileNotFound => {
                // No history file exists yet
                return &[_]ApprovalRecord{};
            },
            else => return err,
        };
        defer file.close();

        // For now, return empty history - real implementation would parse JSON log
        return &[_]ApprovalRecord{};
    }
};

// Tests
test "ApprovalWorkflow initialization" {
    var workflow = try ApprovalWorkflow.init(testing.allocator, "test_approval.log");
    defer workflow.deinit();

    try testing.expect(std.mem.eql(u8, workflow.approval_log_path, "test_approval.log"));
}

test "Approval detection for cosmetic changes" {
    const workflow = ApprovalWorkflow.init(testing.allocator, "test_approval.log");

    const comparison_result = IRComparator.ComparisonResult{
        .equivalent = true,
        .differences = &[_]IRComparator.IRDifference{},
        .summary = IRComparator.ComparisonResult.ComparisonSummary{
            .total_differences = 1,
            .cosmetic_count = 1,
            .semantic_count = 0,
            .breaking_count = 0,
            .critical_count = 0,
        },
    };

    var result = try workflow.detectApprovalRequired(&comparison_result);
    defer result.deinit(testing.allocator);

    try testing.expect(!result.requires_approval);
    try testing.expect(result.auto_approved);
}

test "Approval detection for critical changes" {
    const workflow = ApprovalWorkflow.init(testing.allocator, "test_approval.log");

    const comparison_result = IRComparator.ComparisonResult{
        .equivalent = false,
        .differences = &[_]IRComparator.IRDifference{},
        .summary = IRComparator.ComparisonResult.ComparisonSummary{
            .total_differences = 1,
            .cosmetic_count = 0,
            .semantic_count = 0,
            .breaking_count = 0,
            .critical_count = 1,
        },
    };

    var result = try workflow.detectApprovalRequired(&comparison_result);
    defer result.deinit(testing.allocator);

    try testing.expect(result.requires_approval);
    try testing.expect(!result.auto_approved);
}

test "Approval request creation" {
    const workflow = ApprovalWorkflow.init(testing.allocator, "test_approval.log");

    const comparison_result = IRComparator.ComparisonResult{
        .equivalent = false,
        .differences = &[_]IRComparator.IRDifference{},
        .summary = IRComparator.ComparisonResult.ComparisonSummary{
            .total_differences = 1,
            .cosmetic_count = 0,
            .semantic_count = 1,
            .breaking_count = 0,
            .critical_count = 0,
        },
    };

    var request = try workflow.createApprovalRequest("test_function", "linux-x86_64", "release_safe", "old_hash_123", "new_hash_456", &comparison_result, "Updated for performance optimization", "developer@example.com");
    defer request.deinit(testing.allocator);

    try testing.expectEqualStrings("test_function", request.test_name);
    try testing.expectEqualStrings("linux-x86_64", request.platform);
    try testing.expect(request.difference_summary.semantic_count == 1);
}

test "Approval report generation" {
    const workflow = ApprovalWorkflow.init(testing.allocator, "test_approval.log");

    const records = &[_]ApprovalWorkflow.ApprovalRecord{};

    const report = try workflow.generateApprovalReport(records);
    defer testing.allocator.free(report);

    try testing.expect(std.mem.indexOf(u8, report, "Golden Reference Approval Report") != null);
    try testing.expect(std.mem.indexOf(u8, report, "No approval records found") != null);
}
