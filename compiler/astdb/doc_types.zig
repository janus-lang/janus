// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
//! Sovereign Documentation Types — RFC-025 Phase 1
//!
//! Data structures for the 10th columnar array in CompilationUnit.
//! Documentation is not opaque text; it is structured, queryable,
//! CID-linked data stored as first-class ASTDB rows.
//!
//! Requirements: RFC-025, SPEC-008
//! DOCUMENTATION IS DATA — NOT DECORATION

const std = @import("std");
const core = @import("core.zig");

// Re-export ASTDB ID types used by consumers of this module.
pub const DeclId = core.DeclId;
pub const NodeId = core.NodeId;
pub const StrId = core.StrId;
pub const SourceSpan = core.SourceSpan;

/// Sentinel value: no valid ID.
pub const INVALID_STR_ID: StrId = @enumFromInt(std.math.maxInt(u32));
pub const INVALID_DECL_ID: DeclId = @enumFromInt(std.math.maxInt(u32));
pub const INVALID_NODE_ID: NodeId = @enumFromInt(std.math.maxInt(u32));

// ===========================================================================
// DocEntry — One row per documented declaration
// ===========================================================================

/// A structured documentation entry linked to a declaration via CID.
///
/// Each DocEntry corresponds to a contiguous block of `///` comments
/// immediately preceding a declaration. The entry stores parsed metadata,
/// not raw text blobs. Tags and doctests are stored in separate columnar
/// arrays and referenced via lo/hi index ranges (the ASTDB pattern).
pub const DocEntry = struct {
    /// The DeclId this documentation targets.
    target_decl: DeclId,

    /// The NodeId of the target declaration's AST node.
    target_node: NodeId,

    /// Content-addressed identifier of the target (survives renames).
    /// Populated from the existing `cids` columnar array.
    target_cid: [32]u8,

    /// Raw text of the doc comment block (/// prefixes stripped).
    raw_text: StrId,

    /// First non-empty line or first sentence — the summary.
    summary: StrId,

    /// Source span covering the entire doc comment block.
    span: SourceSpan,

    /// Kind of documented item.
    kind: DocKind,

    /// Range into the DocTag array: [tag_lo..tag_hi)
    tag_lo: u32,

    /// Exclusive upper bound into DocTag array.
    tag_hi: u32,

    /// Range into the DocTest array: [test_lo..test_hi)
    test_lo: u32,

    /// Exclusive upper bound into DocTest array.
    test_hi: u32,

    // -- Convenience accessors --

    /// Number of structured tags on this entry.
    pub fn tagCount(self: DocEntry) u32 {
        return self.tag_hi - self.tag_lo;
    }

    /// Number of doctests (adjacent + embedded) on this entry.
    pub fn testCount(self: DocEntry) u32 {
        return self.test_hi - self.test_lo;
    }

    /// True if this entry has at least one @deprecated tag.
    pub fn isDeprecated(self: DocEntry, tags: []const DocTag) bool {
        for (tags[self.tag_lo..self.tag_hi]) |tag| {
            if (tag.kind == .deprecated) return true;
        }
        return false;
    }

    /// True if this entry has documentation for all parameters.
    /// Requires the declaration's parameter count for comparison.
    pub fn hasCompleteParamDocs(self: DocEntry, tags: []const DocTag, param_count: u32) bool {
        var documented: u32 = 0;
        for (tags[self.tag_lo..self.tag_hi]) |tag| {
            if (tag.kind == .param) documented += 1;
        }
        return documented >= param_count;
    }
};

// ===========================================================================
// DocKind — What kind of declaration is documented
// ===========================================================================

/// Classification of the documented declaration.
/// Broader than the current DeclKind (7 variants) to support future
/// language features (SPEC-023 enums/unions, SPEC-025 traits/impls).
pub const DocKind = enum(u8) {
    function,
    variable,
    constant,
    parameter,
    type_def,
    field,
    variant,
    // Future: mapped from NodeKind when DeclKind doesn't cover it
    struct_type,
    enum_type,
    union_type,
    trait_type,
    impl_block,
    module,
    test_decl,

    /// Map from core.Decl.DeclKind to DocKind.
    pub fn fromDeclKind(decl_kind: core.Decl.DeclKind) DocKind {
        return switch (decl_kind) {
            .function => .function,
            .variable => .variable,
            .constant => .constant,
            .parameter => .parameter,
            .type_def => .type_def,
            .field => .field,
            .variant => .variant,
        };
    }
};

// ===========================================================================
// DocTag — Structured @tag entries
// ===========================================================================

/// A single structured tag parsed from a doc comment.
///
/// Tags follow the syntax: `@tagname [name] description`
/// They are stored in a flat columnar array; each DocEntry references
/// a [tag_lo..tag_hi) slice into this array.
pub const DocTag = struct {
    /// What kind of tag this is.
    kind: TagKind,

    /// For @param: parameter name. For @error: error type. For @see: target.
    /// For @capability: capability name. For @since: version string.
    /// Null for tags that have no name component (e.g., @returns).
    name: ?StrId,

    /// The tag's content text (description / explanation).
    content: StrId,

    /// Source span of this tag within the doc comment block.
    span: SourceSpan,

    pub const TagKind = enum(u8) {
        param,
        returns,
        err,
        capability,
        since,
        see,
        deprecated,
        safety,
        complexity,
        example,
    };

    /// Parse a tag kind from the string following '@'.
    /// Returns null if the string is not a recognized tag.
    pub fn parseKind(name: []const u8) ?TagKind {
        const map = std.StaticStringMap(TagKind).initComptime(.{
            .{ "param", .param },
            .{ "returns", .returns },
            .{ "return", .returns },
            .{ "error", .err },
            .{ "err", .err },
            .{ "capability", .capability },
            .{ "cap", .capability },
            .{ "since", .since },
            .{ "see", .see },
            .{ "deprecated", .deprecated },
            .{ "safety", .safety },
            .{ "complexity", .complexity },
            .{ "example", .example },
        });
        return map.get(name);
    }
};

// ===========================================================================
// DocTest — Embedded examples and adjacent test blocks
// ===========================================================================

/// A doctest entry: either an embedded ```janus code block or an adjacent
/// `test` declaration immediately following the documented item.
///
/// Stored in a flat columnar array; each DocEntry references
/// a [test_lo..test_hi) slice into this array.
pub const DocTest = struct {
    /// If from an adjacent test block: the NodeId of the test_decl.
    /// Null for embedded examples (which have no AST node yet).
    test_node: ?NodeId,

    /// The source text of the test/example (code content only).
    source_text: StrId,

    /// Where this doctest came from.
    origin: Origin,

    /// Source span covering the doctest.
    span: SourceSpan,

    pub const Origin = enum(u8) {
        /// A `test` block immediately following the documented declaration.
        adjacent_test,
        /// A fenced ```janus code block inside the doc comment.
        embedded_example,
    };
};

// ===========================================================================
// DocStore — The columnar storage container
// ===========================================================================

/// Container for all documentation data within a CompilationUnit.
///
/// This is the "10th columnar array" described in RFC-025.
/// In practice it is three parallel arrays (entries, tags, tests)
/// following the same lo/hi range pattern used throughout ASTDB.
///
/// Memory is arena-allocated; the DocStore does not own its allocator.
/// It is freed when the parent CompilationUnit's arena is released (O(1)).
pub const DocStore = struct {
    /// Documentation entries, one per documented declaration.
    entries: std.ArrayList(DocEntry),

    /// Flat array of all structured tags across all entries.
    tags: std.ArrayList(DocTag),

    /// Flat array of all doctests across all entries.
    tests: std.ArrayList(DocTest),

    /// The allocator backing this store (kept for append calls).
    allocator: std.mem.Allocator,

    /// Initialize an empty DocStore on the given allocator.
    /// In production, pass the CompilationUnit's arena allocator.
    pub fn init(allocator: std.mem.Allocator) DocStore {
        return .{
            .entries = .empty,
            .tags = .empty,
            .tests = .empty,
            .allocator = allocator,
        };
    }

    /// Release all memory. In practice this is a no-op when using
    /// arena allocation (the arena frees everything at once).
    pub fn deinit(self: *DocStore) void {
        self.entries.deinit(self.allocator);
        self.tags.deinit(self.allocator);
        self.tests.deinit(self.allocator);
    }

    /// Add a new DocEntry and return its index.
    pub fn addEntry(self: *DocStore, entry: DocEntry) !u32 {
        const idx: u32 = @intCast(self.entries.items.len);
        try self.entries.append(self.allocator, entry);
        return idx;
    }

    /// Add a DocTag and return its index in the tags array.
    pub fn addTag(self: *DocStore, tag: DocTag) !u32 {
        const idx: u32 = @intCast(self.tags.items.len);
        try self.tags.append(self.allocator, tag);
        return idx;
    }

    /// Add a DocTest and return its index in the tests array.
    pub fn addTest(self: *DocStore, doc_test: DocTest) !u32 {
        const idx: u32 = @intCast(self.tests.items.len);
        try self.tests.append(self.allocator, doc_test);
        return idx;
    }

    /// Current tag array length (used as tag_lo before appending tags).
    pub fn currentTagIndex(self: *const DocStore) u32 {
        return @intCast(self.tags.items.len);
    }

    /// Current test array length (used as test_lo before appending tests).
    pub fn currentTestIndex(self: *const DocStore) u32 {
        return @intCast(self.tests.items.len);
    }

    // -- Query helpers --

    /// Get the DocEntry for a given DeclId, or null if undocumented.
    pub fn getByDecl(self: *const DocStore, decl_id: DeclId) ?*const DocEntry {
        for (self.entries.items) |*entry| {
            if (entry.target_decl == decl_id) return entry;
        }
        return null;
    }

    /// Get the tags slice for a DocEntry.
    pub fn tagsFor(self: *const DocStore, entry: *const DocEntry) []const DocTag {
        return self.tags.items[entry.tag_lo..entry.tag_hi];
    }

    /// Get the tests slice for a DocEntry.
    pub fn testsFor(self: *const DocStore, entry: *const DocEntry) []const DocTest {
        return self.tests.items[entry.test_lo..entry.test_hi];
    }

    /// Count of documented declarations.
    pub fn entryCount(self: *const DocStore) u32 {
        return @intCast(self.entries.items.len);
    }

    /// Return all deprecated entries.
    pub fn deprecatedEntries(self: *const DocStore, allocator: std.mem.Allocator) ![]const DocEntry {
        var result: std.ArrayList(DocEntry) = .empty;
        for (self.entries.items) |entry| {
            if (entry.isDeprecated(self.tags.items)) {
                try result.append(allocator, entry);
            }
        }
        return result.toOwnedSlice(allocator);
    }
};

// ===========================================================================
// Tests
// ===========================================================================

test "DocTag.parseKind recognizes all tag names" {
    try std.testing.expectEqual(DocTag.TagKind.param, DocTag.parseKind("param").?);
    try std.testing.expectEqual(DocTag.TagKind.returns, DocTag.parseKind("returns").?);
    try std.testing.expectEqual(DocTag.TagKind.returns, DocTag.parseKind("return").?);
    try std.testing.expectEqual(DocTag.TagKind.err, DocTag.parseKind("error").?);
    try std.testing.expectEqual(DocTag.TagKind.err, DocTag.parseKind("err").?);
    try std.testing.expectEqual(DocTag.TagKind.capability, DocTag.parseKind("capability").?);
    try std.testing.expectEqual(DocTag.TagKind.capability, DocTag.parseKind("cap").?);
    try std.testing.expectEqual(DocTag.TagKind.since, DocTag.parseKind("since").?);
    try std.testing.expectEqual(DocTag.TagKind.see, DocTag.parseKind("see").?);
    try std.testing.expectEqual(DocTag.TagKind.deprecated, DocTag.parseKind("deprecated").?);
    try std.testing.expectEqual(DocTag.TagKind.safety, DocTag.parseKind("safety").?);
    try std.testing.expectEqual(DocTag.TagKind.complexity, DocTag.parseKind("complexity").?);
    try std.testing.expectEqual(DocTag.TagKind.example, DocTag.parseKind("example").?);
    try std.testing.expect(DocTag.parseKind("nonsense") == null);
}

test "DocStore basic operations" {
    const allocator = std.testing.allocator;
    var store = DocStore.init(allocator);
    defer store.deinit();

    const dummy_span = SourceSpan{ .start = 0, .end = 0, .line = 0, .column = 0 };

    // Add tags
    const tag_lo = store.currentTagIndex();
    _ = try store.addTag(.{
        .kind = .param,
        .name = @enumFromInt(42),
        .content = @enumFromInt(43),
        .span = dummy_span,
    });
    _ = try store.addTag(.{
        .kind = .returns,
        .name = null,
        .content = @enumFromInt(44),
        .span = dummy_span,
    });
    const tag_hi = store.currentTagIndex();

    // Add an entry
    const test_lo = store.currentTestIndex();
    const test_hi = store.currentTestIndex();

    _ = try store.addEntry(.{
        .target_decl = @enumFromInt(0),
        .target_node = @enumFromInt(0),
        .target_cid = [_]u8{0} ** 32,
        .raw_text = @enumFromInt(100),
        .summary = @enumFromInt(101),
        .span = dummy_span,
        .kind = .function,
        .tag_lo = tag_lo,
        .tag_hi = tag_hi,
        .test_lo = test_lo,
        .test_hi = test_hi,
    });

    try std.testing.expectEqual(@as(u32, 1), store.entryCount());

    const entry = &store.entries.items[0];
    try std.testing.expectEqual(@as(u32, 2), entry.tagCount());
    try std.testing.expectEqual(@as(u32, 0), entry.testCount());

    const tags = store.tagsFor(entry);
    try std.testing.expectEqual(@as(usize, 2), tags.len);
    try std.testing.expectEqual(DocTag.TagKind.param, tags[0].kind);
    try std.testing.expectEqual(DocTag.TagKind.returns, tags[1].kind);
}

test "DocStore.getByDecl finds entry" {
    const allocator = std.testing.allocator;
    var store = DocStore.init(allocator);
    defer store.deinit();

    const dummy_span = SourceSpan{ .start = 0, .end = 0, .line = 0, .column = 0 };

    _ = try store.addEntry(.{
        .target_decl = @enumFromInt(7),
        .target_node = @enumFromInt(0),
        .target_cid = [_]u8{0} ** 32,
        .raw_text = @enumFromInt(0),
        .summary = @enumFromInt(0),
        .span = dummy_span,
        .kind = .function,
        .tag_lo = 0,
        .tag_hi = 0,
        .test_lo = 0,
        .test_hi = 0,
    });

    try std.testing.expect(store.getByDecl(@enumFromInt(7)) != null);
    try std.testing.expect(store.getByDecl(@enumFromInt(99)) == null);
}

test "DocKind.fromDeclKind maps all variants" {
    try std.testing.expectEqual(DocKind.function, DocKind.fromDeclKind(.function));
    try std.testing.expectEqual(DocKind.variable, DocKind.fromDeclKind(.variable));
    try std.testing.expectEqual(DocKind.constant, DocKind.fromDeclKind(.constant));
    try std.testing.expectEqual(DocKind.parameter, DocKind.fromDeclKind(.parameter));
    try std.testing.expectEqual(DocKind.type_def, DocKind.fromDeclKind(.type_def));
    try std.testing.expectEqual(DocKind.field, DocKind.fromDeclKind(.field));
    try std.testing.expectEqual(DocKind.variant, DocKind.fromDeclKind(.variant));
}
