// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Semantic Correlator - CID-based Change Detection
//!
//! Uses content-addressed storage (CIDs) to track semantic changes that
//! correlate with errors. When an error occurs, this module can identify:
//!
//! - What changed since the last successful compilation
//! - Which entities have different CIDs than before
//! - Cascade effects (errors caused by other errors)
//! - Root cause identification across multiple errors
//!
//! Example output:
//!
//! Correlated changes detected:
//!
//! CHANGED: UserProfile struct (2026-01-25 14:32:05)
//!   - Before: { name: string, age: i32 }
//!   - After:  { name: string, age: i32, email: Option<string> }
//!   - CID: 7f3a...2b1c -> 9d4e...8f2a
//!
//! UNCHANGED: serialize(UserProfile) implementation
//!   - This expects the OLD UserProfile shape

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const nextgen = @import("nextgen_diagnostic.zig");
const SemanticContext = nextgen.SemanticContext;
const SemanticChange = nextgen.SemanticChange;
const RelatedCID = nextgen.RelatedCID;
const CorrelatedError = nextgen.CorrelatedError;
const ChangeType = nextgen.ChangeType;
const SourceSpan = nextgen.SourceSpan;
const DiagnosticId = nextgen.DiagnosticId;
const CID = nextgen.CID;

/// Configuration for semantic correlation
pub const CorrelationConfig = struct {
    /// Maximum CIDs to track per entity
    max_related_cids: u32 = 50,
    /// Maximum changes to report
    max_changes: u32 = 10,
    /// Enable cascade detection
    enable_cascade_detection: bool = true,
    /// Time window for change detection (seconds)
    change_window_seconds: i64 = 3600, // 1 hour
};

/// Stored CID snapshot for change detection
pub const CIDSnapshot = struct {
    cid: CID,
    entity_name: []const u8,
    entity_kind: EntityKind,
    signature: ?[]const u8,
    timestamp: i64,
    file_path: []const u8,
    line: u32,

    pub const EntityKind = enum {
        function,
        struct_type,
        enum_type,
        trait_type,
        module,
        constant,
        variable,
    };

    pub fn clone(self: CIDSnapshot, allocator: Allocator) !CIDSnapshot {
        return .{
            .cid = self.cid,
            .entity_name = try allocator.dupe(u8, self.entity_name),
            .entity_kind = self.entity_kind,
            .signature = if (self.signature) |sig| try allocator.dupe(u8, sig) else null,
            .timestamp = self.timestamp,
            .file_path = try allocator.dupe(u8, self.file_path),
            .line = self.line,
        };
    }

    pub fn deinit(self: *CIDSnapshot, allocator: Allocator) void {
        allocator.free(self.entity_name);
        if (self.signature) |sig| allocator.free(sig);
        allocator.free(self.file_path);
    }
};

/// Storage for historical CID snapshots
pub const CIDHistory = struct {
    allocator: Allocator,
    /// Map from entity name to historical snapshots
    snapshots: std.StringHashMap(ArrayList(CIDSnapshot)),
    /// Current snapshot (most recent)
    current: std.StringHashMap(CIDSnapshot),

    pub fn init(allocator: Allocator) CIDHistory {
        return .{
            .allocator = allocator,
            .snapshots = std.StringHashMap(ArrayList(CIDSnapshot)).init(allocator),
            .current = std.StringHashMap(CIDSnapshot).init(allocator),
        };
    }

    pub fn deinit(self: *CIDHistory) void {
        var snap_iter = self.snapshots.valueIterator();
        while (snap_iter.next()) |list| {
            for (list.items) |*snapshot| {
                snapshot.deinit(self.allocator);
            }
            list.deinit();
        }
        self.snapshots.deinit();

        var curr_iter = self.current.valueIterator();
        while (curr_iter.next()) |snapshot| {
            var s = snapshot.*;
            s.deinit(self.allocator);
        }
        self.current.deinit();
    }

    /// Record a new CID for an entity
    pub fn recordCID(self: *CIDHistory, snapshot: CIDSnapshot) !void {
        const name = try self.allocator.dupe(u8, snapshot.entity_name);
        errdefer self.allocator.free(name);

        // Check if CID changed
        if (self.current.get(name)) |existing| {
            if (!std.mem.eql(u8, &existing.cid, &snapshot.cid)) {
                // CID changed - archive the old one
                const history_ptr = self.snapshots.getPtr(name) orelse blk: {
                    try self.snapshots.put(name, ArrayList(CIDSnapshot).init(self.allocator));
                    break :blk self.snapshots.getPtr(name).?;
                };
                try history_ptr.append(try existing.clone(self.allocator));
            }
        }

        // Update current
        try self.current.put(name, try snapshot.clone(self.allocator));
    }

    /// Get the previous CID for an entity (if it changed)
    pub fn getPreviousCID(self: *const CIDHistory, entity_name: []const u8) ?CIDSnapshot {
        const history = self.snapshots.get(entity_name) orelse return null;
        if (history.items.len == 0) return null;
        return history.items[history.items.len - 1];
    }

    /// Get current CID for an entity
    pub fn getCurrentCID(self: *const CIDHistory, entity_name: []const u8) ?CIDSnapshot {
        return self.current.get(entity_name);
    }

    /// Check if an entity's CID changed recently
    pub fn hasChangedSince(self: *const CIDHistory, entity_name: []const u8, since_timestamp: i64) bool {
        const current = self.current.get(entity_name) orelse return false;
        return current.timestamp >= since_timestamp;
    }

    /// Get all entities that changed since a timestamp
    pub fn getChangesSince(self: *const CIDHistory, since_timestamp: i64) ![]const CIDSnapshot {
        var changes = ArrayList(CIDSnapshot).init(self.allocator);

        var iter = self.current.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.timestamp >= since_timestamp) {
                try changes.append(entry.value_ptr.*);
            }
        }

        return changes.toOwnedSlice();
    }
};

/// Semantic Correlator for change detection and cascade analysis
pub const SemanticCorrelator = struct {
    allocator: Allocator,
    config: CorrelationConfig,
    history: CIDHistory,
    /// Active diagnostics for cascade detection
    active_diagnostics: ArrayList(ActiveDiagnostic),
    /// Detected cascades (error -> caused errors)
    cascades: std.AutoHashMap(DiagnosticId, ArrayList(DiagnosticId)),

    const ActiveDiagnostic = struct {
        id: DiagnosticId,
        error_site_cid: CID,
        affected_entities: []const []const u8,
        timestamp: i64,
    };

    pub fn init(allocator: Allocator) SemanticCorrelator {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: CorrelationConfig) SemanticCorrelator {
        return .{
            .allocator = allocator,
            .config = config,
            .history = CIDHistory.init(allocator),
            .active_diagnostics = ArrayList(ActiveDiagnostic).init(allocator),
            .cascades = std.AutoHashMap(DiagnosticId, ArrayList(DiagnosticId)).init(allocator),
        };
    }

    pub fn deinit(self: *SemanticCorrelator) void {
        self.history.deinit();

        for (self.active_diagnostics.items) |diag| {
            self.allocator.free(diag.affected_entities);
        }
        self.active_diagnostics.deinit();

        var cascade_iter = self.cascades.valueIterator();
        while (cascade_iter.next()) |list| {
            list.deinit();
        }
        self.cascades.deinit();
    }

    /// Build semantic context for an error
    pub fn buildContext(
        self: *SemanticCorrelator,
        error_site_cid: CID,
        related_entities: []const []const u8,
    ) !SemanticContext {
        // Collect related CIDs
        var related_cids = ArrayList(RelatedCID).init(self.allocator);
        errdefer {
            for (related_cids.items) |*cid| {
                cid.deinit(self.allocator);
            }
            related_cids.deinit();
        }

        for (related_entities) |entity_name| {
            if (self.history.getCurrentCID(entity_name)) |snapshot| {
                try related_cids.append(.{
                    .cid = snapshot.cid,
                    .relationship = entityKindToRelationship(snapshot.entity_kind),
                    .name = try self.allocator.dupe(u8, entity_name),
                    .location = .{
                        .file = snapshot.file_path,
                        .start = .{ .line = snapshot.line, .column = 1 },
                        .end = .{ .line = snapshot.line, .column = 1 },
                    },
                });
            }
        }

        // Detect changes
        const now = std.time.timestamp();
        const window_start = now - self.config.change_window_seconds;

        var detected_changes = ArrayList(SemanticChange).init(self.allocator);
        errdefer {
            for (detected_changes.items) |*change| {
                change.deinit(self.allocator);
            }
            detected_changes.deinit();
        }

        for (related_entities) |entity_name| {
            if (try self.detectChange(entity_name, window_start)) |change| {
                try detected_changes.append(change);

                if (detected_changes.items.len >= self.config.max_changes) {
                    break;
                }
            }
        }

        return SemanticContext{
            .error_site_cid = error_site_cid,
            .related_cids = try related_cids.toOwnedSlice(),
            .detected_changes = try detected_changes.toOwnedSlice(),
            .scope_chain = &[_]SemanticContext.ScopeId{},
        };
    }

    /// Detect if an entity changed and return the change info
    pub fn detectChange(
        self: *SemanticCorrelator,
        entity_name: []const u8,
        since_timestamp: i64,
    ) !?SemanticChange {
        const current = self.history.getCurrentCID(entity_name) orelse return null;
        const previous = self.history.getPreviousCID(entity_name) orelse return null;

        // Check if change is within time window
        if (current.timestamp < since_timestamp) return null;

        // CID changed - determine type of change
        const change_type = self.inferChangeType(previous, current);

        return SemanticChange{
            .entity_cid = current.cid,
            .entity_name = try self.allocator.dupe(u8, entity_name),
            .change_type = change_type,
            .old_signature = if (previous.signature) |sig| try self.allocator.dupe(u8, sig) else null,
            .new_signature = if (current.signature) |sig| try self.allocator.dupe(u8, sig) else null,
            .change_location = .{
                .file = current.file_path,
                .start = .{ .line = current.line, .column = 1 },
                .end = .{ .line = current.line, .column = 1 },
            },
            .timestamp = current.timestamp,
        };
    }

    /// Find correlated errors (errors with shared causes)
    pub fn findCorrelatedErrors(
        self: *SemanticCorrelator,
        diagnostic_id: DiagnosticId,
        error_site_cid: CID,
    ) ![]CorrelatedError {
        var correlated = ArrayList(CorrelatedError).init(self.allocator);
        errdefer correlated.deinit();

        // Look for diagnostics with similar error sites
        for (self.active_diagnostics.items) |diag| {
            if (diag.id.id == diagnostic_id.id) continue; // Skip self

            // Check for CID similarity (same code location)
            if (std.mem.eql(u8, &diag.error_site_cid, &error_site_cid)) {
                try correlated.append(.{
                    .diagnostic_id = diag.id,
                    .correlation_type = .same_root_cause,
                    .shared_cause_probability = 0.9,
                });
            }

            // Check for cascade relationship
            if (self.cascades.get(diag.id)) |caused| {
                for (caused.items) |caused_id| {
                    if (caused_id.id == diagnostic_id.id) {
                        try correlated.append(.{
                            .diagnostic_id = diag.id,
                            .correlation_type = .cascade_effect,
                            .shared_cause_probability = 0.95,
                        });
                        break;
                    }
                }
            }
        }

        return correlated.toOwnedSlice();
    }

    /// Identify the root cause among a group of errors
    pub fn identifyRootCause(
        self: *SemanticCorrelator,
        diagnostic_ids: []const DiagnosticId,
    ) ?DiagnosticId {
        if (diagnostic_ids.len == 0) return null;
        if (diagnostic_ids.len == 1) return diagnostic_ids[0];

        // Find the diagnostic that causes the most cascades
        var root_candidate: ?DiagnosticId = null;
        var max_cascades: usize = 0;

        for (diagnostic_ids) |diag_id| {
            if (self.cascades.get(diag_id)) |caused| {
                if (caused.items.len > max_cascades) {
                    max_cascades = caused.items.len;
                    root_candidate = diag_id;
                }
            }
        }

        if (root_candidate) |root| {
            return root;
        }

        // Fallback: earliest diagnostic is likely root cause
        var earliest: ?DiagnosticId = null;
        var earliest_time: i64 = std.math.maxInt(i64);

        for (self.active_diagnostics.items) |diag| {
            for (diagnostic_ids) |check_id| {
                if (diag.id.id == check_id.id and diag.timestamp < earliest_time) {
                    earliest_time = diag.timestamp;
                    earliest = diag.id;
                }
            }
        }

        return earliest;
    }

    /// Register a new diagnostic for cascade detection
    pub fn registerDiagnostic(
        self: *SemanticCorrelator,
        id: DiagnosticId,
        error_site_cid: CID,
        affected_entities: []const []const u8,
    ) !void {
        // Copy affected entities
        var entities = try self.allocator.alloc([]const u8, affected_entities.len);
        for (affected_entities, 0..) |entity, i| {
            entities[i] = try self.allocator.dupe(u8, entity);
        }

        try self.active_diagnostics.append(.{
            .id = id,
            .error_site_cid = error_site_cid,
            .affected_entities = entities,
            .timestamp = std.time.timestamp(),
        });

        // Check if this is caused by existing errors
        if (self.config.enable_cascade_detection) {
            try self.detectCascades(id, affected_entities);
        }
    }

    /// Record a CID change (called during compilation)
    pub fn recordChange(self: *SemanticCorrelator, snapshot: CIDSnapshot) !void {
        try self.history.recordCID(snapshot);
    }

    /// Clear active diagnostics (call at start of new compilation)
    pub fn clearActiveDiagnostics(self: *SemanticCorrelator) void {
        for (self.active_diagnostics.items) |diag| {
            for (diag.affected_entities) |entity| {
                self.allocator.free(entity);
            }
            self.allocator.free(diag.affected_entities);
        }
        self.active_diagnostics.clearRetainingCapacity();

        var cascade_iter = self.cascades.valueIterator();
        while (cascade_iter.next()) |list| {
            list.deinit();
        }
        self.cascades.clearRetainingCapacity();
    }

    // =========================================================================
    // Private Helpers
    // =========================================================================

    fn inferChangeType(self: *SemanticCorrelator, previous: CIDSnapshot, current: CIDSnapshot) ChangeType {
        _ = self;

        // Check if name changed (renamed)
        if (!std.mem.eql(u8, previous.entity_name, current.entity_name)) {
            return .renamed;
        }

        // Check if visibility changed
        // (Would need more info - for now assume signature change)

        // Check if signature changed
        if (previous.signature) |old_sig| {
            if (current.signature) |new_sig| {
                if (!std.mem.eql(u8, old_sig, new_sig)) {
                    return .signature_changed;
                }
            }
        }

        // Kind changed means type changed
        if (previous.entity_kind != current.entity_kind) {
            return .type_changed;
        }

        // Default to signature change (CID changed for some reason)
        return .signature_changed;
    }

    fn detectCascades(
        self: *SemanticCorrelator,
        new_diag_id: DiagnosticId,
        affected_entities: []const []const u8,
    ) !void {
        // Check if any existing diagnostic's affected entities overlap
        for (self.active_diagnostics.items) |existing| {
            if (existing.id.id == new_diag_id.id) continue;

            // Check for overlap in affected entities
            var has_overlap = false;
            for (existing.affected_entities) |existing_entity| {
                for (affected_entities) |new_entity| {
                    if (std.mem.eql(u8, existing_entity, new_entity)) {
                        has_overlap = true;
                        break;
                    }
                }
                if (has_overlap) break;
            }

            if (has_overlap) {
                // existing error might have caused new error
                var caused = self.cascades.get(existing.id) orelse blk: {
                    const list = ArrayList(DiagnosticId).init(self.allocator);
                    try self.cascades.put(existing.id, list);
                    break :blk self.cascades.get(existing.id).?;
                };
                try caused.append(new_diag_id);
            }
        }
    }
};

/// Convert entity kind to CID relationship
fn entityKindToRelationship(kind: CIDSnapshot.EntityKind) RelatedCID.Relationship {
    return switch (kind) {
        .function => .definition,
        .struct_type, .enum_type, .trait_type => .definition,
        .module => .dependency,
        .constant, .variable => .usage,
    };
}

// =============================================================================
// Formatting Helpers
// =============================================================================

/// Format semantic context for display
pub fn formatSemanticContext(allocator: Allocator, context: SemanticContext) ![]const u8 {
    var output = ArrayList(u8).init(allocator);
    const writer = output.writer();

    if (context.detected_changes.len > 0) {
        try writer.writeAll("Correlated changes detected:\n\n");

        for (context.detected_changes) |change| {
            try writer.print("CHANGED: {s} ({s})\n", .{ change.entity_name, change.change_type.description() });

            if (change.old_signature) |old| {
                try writer.print("  - Before: {s}\n", .{old});
            }
            if (change.new_signature) |new| {
                try writer.print("  - After:  {s}\n", .{new});
            }
            try writer.writeAll("\n");
        }
    }

    if (context.related_cids.len > 0) {
        try writer.writeAll("Related entities:\n");
        for (context.related_cids) |related| {
            try writer.print("  - {s} ({s})\n", .{ related.name, @tagName(related.relationship) });
        }
    }

    return output.toOwnedSlice();
}

/// Format a CID as a short hex string
pub fn formatCIDShort(cid: CID) [8]u8 {
    const hex_chars = "0123456789abcdef";
    var result: [8]u8 = undefined;

    for (0..4) |i| {
        result[i * 2] = hex_chars[cid[i] >> 4];
        result[i * 2 + 1] = hex_chars[cid[i] & 0x0f];
    }

    return result;
}

// =============================================================================
// Tests
// =============================================================================

test "CIDHistory basic operations" {
    const allocator = std.testing.allocator;

    var history = CIDHistory.init(allocator);
    defer history.deinit();

    const snapshot = CIDSnapshot{
        .cid = [_]u8{1} ** 32,
        .entity_name = "test_func",
        .entity_kind = .function,
        .signature = "func test_func(i32) -> i32",
        .timestamp = 1000,
        .file_path = "test.jan",
        .line = 10,
    };

    try history.recordCID(snapshot);

    const current = history.getCurrentCID("test_func");
    try std.testing.expect(current != null);
    try std.testing.expectEqualStrings("test_func", current.?.entity_name);
}

test "CIDHistory detects changes" {
    const allocator = std.testing.allocator;

    var history = CIDHistory.init(allocator);
    defer history.deinit();

    // Record initial version
    try history.recordCID(.{
        .cid = [_]u8{1} ** 32,
        .entity_name = "my_struct",
        .entity_kind = .struct_type,
        .signature = "{ x: i32 }",
        .timestamp = 1000,
        .file_path = "test.jan",
        .line = 5,
    });

    // Record changed version
    try history.recordCID(.{
        .cid = [_]u8{2} ** 32, // Different CID
        .entity_name = "my_struct",
        .entity_kind = .struct_type,
        .signature = "{ x: i32, y: f64 }",
        .timestamp = 2000,
        .file_path = "test.jan",
        .line = 5,
    });

    // Should have previous version
    const previous = history.getPreviousCID("my_struct");
    try std.testing.expect(previous != null);
    try std.testing.expectEqualStrings("{ x: i32 }", previous.?.signature.?);

    // Current should be new version
    const current = history.getCurrentCID("my_struct");
    try std.testing.expect(current != null);
    try std.testing.expectEqualStrings("{ x: i32, y: f64 }", current.?.signature.?);
}

test "SemanticCorrelator builds context" {
    const allocator = std.testing.allocator;

    var correlator = SemanticCorrelator.init(allocator);
    defer correlator.deinit();

    // Record a change
    try correlator.recordChange(.{
        .cid = [_]u8{1} ** 32,
        .entity_name = "UserProfile",
        .entity_kind = .struct_type,
        .signature = "{ name: string }",
        .timestamp = std.time.timestamp() - 100, // Recent change
        .file_path = "models.jan",
        .line = 10,
    });

    var context = try correlator.buildContext(
        [_]u8{0} ** 32,
        &[_][]const u8{"UserProfile"},
    );
    defer context.deinit(allocator);

    try std.testing.expect(context.related_cids.len > 0);
}

test "SemanticCorrelator detects cascades" {
    const allocator = std.testing.allocator;

    var correlator = SemanticCorrelator.init(allocator);
    defer correlator.deinit();

    // Register first error
    try correlator.registerDiagnostic(
        .{ .id = 1 },
        [_]u8{1} ** 32,
        &[_][]const u8{"shared_entity"},
    );

    // Register second error affecting same entity
    try correlator.registerDiagnostic(
        .{ .id = 2 },
        [_]u8{2} ** 32,
        &[_][]const u8{"shared_entity"},
    );

    // First error should cause second error
    if (correlator.cascades.get(.{ .id = 1 })) |caused| {
        try std.testing.expectEqual(@as(usize, 1), caused.items.len);
        try std.testing.expectEqual(@as(u64, 2), caused.items[0].id);
    }
}

test "SemanticCorrelator identifies root cause" {
    const allocator = std.testing.allocator;

    var correlator = SemanticCorrelator.init(allocator);
    defer correlator.deinit();

    // Register chain of errors
    try correlator.registerDiagnostic(.{ .id = 1 }, [_]u8{1} ** 32, &[_][]const u8{"entity_a"});
    try correlator.registerDiagnostic(.{ .id = 2 }, [_]u8{2} ** 32, &[_][]const u8{"entity_a"});
    try correlator.registerDiagnostic(.{ .id = 3 }, [_]u8{3} ** 32, &[_][]const u8{"entity_a"});

    const root = correlator.identifyRootCause(&[_]DiagnosticId{
        .{ .id = 1 },
        .{ .id = 2 },
        .{ .id = 3 },
    });

    try std.testing.expect(root != null);
    try std.testing.expectEqual(@as(u64, 1), root.?.id);
}
