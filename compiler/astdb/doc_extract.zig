// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
//
//! Sovereign Documentation Extraction Pass — RFC-025 Phase 2
//!
//! Post-parse, pre-sema pass that transforms `///` trivia into structured
//! DocStore rows. Iterates the trivia array, identifies contiguous doc_comment
//! runs, strips prefixes, parses @tags, extracts embedded examples, and links
//! each doc block to the nearest subsequent DeclId by span proximity.
//!
//! Requirements: RFC-025, SPEC-008
//! DOCUMENTATION EXTRACTION IS A COMPILER PASS — NOT A STRING HACK

const std = @import("std");
const core = @import("core.zig");
const doc_types = @import("doc_types.zig");

const DocStore = doc_types.DocStore;
const DocEntry = doc_types.DocEntry;
const DocTag = doc_types.DocTag;
const DocTest = doc_types.DocTest;
const DocKind = doc_types.DocKind;
const SourceSpan = core.SourceSpan;
const DeclId = core.DeclId;
const NodeId = core.NodeId;
const StrId = core.StrId;
const Trivia = core.Trivia;
const TriviaKind = core.Trivia.TriviaKind;
const Decl = core.Decl;
const AstNode = core.AstNode;
const Token = core.Token;
const StrInterner = core.StrInterner;

// ---------------------------------------------------------------------------
// DocExtractor — The extraction pass
// ---------------------------------------------------------------------------

/// Configuration for the doc extraction pass.
pub const ExtractConfig = struct {
    /// Maximum number of blank lines between a doc comment block and its
    /// target declaration before the link is considered broken.
    max_gap_lines: u32 = 1,

    /// Whether to extract embedded ```janus code blocks as DocTests.
    extract_embedded_examples: bool = true,

    /// Whether to link adjacent test blocks as DocTests.
    link_adjacent_tests: bool = true,

    /// Maximum lines between a declaration's end and an adjacent test block.
    max_adjacent_test_gap: u32 = 2,
};

/// The doc extraction pass. Stateless; operates on input arrays and writes
/// to a DocStore.
pub const DocExtractor = struct {
    config: ExtractConfig,
    interner: *StrInterner,
    allocator: std.mem.Allocator,

    pub fn init(
        allocator: std.mem.Allocator,
        interner: *StrInterner,
        config: ExtractConfig,
    ) DocExtractor {
        return .{
            .config = config,
            .interner = interner,
            .allocator = allocator,
        };
    }

    // -----------------------------------------------------------------------
    // Main extraction entry point
    // -----------------------------------------------------------------------

    /// Run the doc extraction pass over a CompilationUnit's trivia and decls.
    ///
    /// This is the Phase 2 algorithm from RFC-025 §3.3:
    /// 1. Identify contiguous doc_comment trivia runs
    /// 2. Strip /// prefixes, join into raw text
    /// 3. Extract summary, @tags, embedded examples
    /// 4. Link to nearest subsequent DeclId by span proximity
    /// 5. Optionally link adjacent test blocks
    ///
    /// Unlike the stub version, this resolves declaration spans via the
    /// node → first_token → token.span chain, since Decl has no span field.
    pub fn extract(
        self: *DocExtractor,
        store: *DocStore,
        source: []const u8,
        trivia: []const Trivia,
        decls: []const Decl,
        nodes: []const AstNode,
        tokens: []const Token,
        cids: [][32]u8,
    ) !void {
        // Step 1: Find contiguous doc_comment runs
        var i: usize = 0;
        while (i < trivia.len) {
            if (trivia[i].kind != .doc_comment) {
                i += 1;
                continue;
            }

            // Found the start of a doc block. Collect contiguous doc_comments.
            const block_start = i;
            var block_end = i;
            while (block_end < trivia.len and trivia[block_end].kind == .doc_comment) {
                block_end += 1;
            }

            // Step 2: Compute block span from first and last trivia entries
            const block_span = SourceSpan{
                .start = trivia[block_start].span.start,
                .end = trivia[block_end - 1].span.end,
                .line = trivia[block_start].span.line,
                .column = trivia[block_start].span.column,
            };
            // We need the line of the last trivia for gap calculation.
            const block_end_line = trivia[block_end - 1].span.line;

            const raw_text = try self.extractRawText(source, trivia[block_start..block_end]);
            defer self.allocator.free(raw_text);

            // Step 3: Find the nearest subsequent declaration
            const target = self.findTargetDecl(
                block_span,
                block_end_line,
                decls,
                nodes,
                tokens,
            );
            if (target == null) {
                // Orphaned doc comment; no declaration follows. Skip.
                i = block_end;
                continue;
            }

            const decl_index = target.?;
            const decl = &decls[decl_index];
            const decl_id: DeclId = @enumFromInt(@as(u32, @intCast(decl_index)));

            // Step 4: Parse the doc block into structured data
            const raw_text_id = try self.interner.intern(raw_text);
            const summary = extractSummary(raw_text);
            const summary_id = try self.interner.intern(summary);

            // Parse @tags
            const tag_lo = store.currentTagIndex();
            try self.parseTags(store, raw_text);
            const tag_hi = store.currentTagIndex();

            // Extract embedded examples
            const test_lo = store.currentTestIndex();
            if (self.config.extract_embedded_examples) {
                try self.extractEmbeddedExamples(store, raw_text);
            }
            const test_hi = store.currentTestIndex();

            // Resolve CID via node index
            const node_index = @intFromEnum(decl.node);
            var target_cid: [32]u8 = [_]u8{0} ** 32;
            if (node_index < cids.len) {
                target_cid = cids[node_index];
            }

            // Step 5: Create the DocEntry
            _ = try store.addEntry(.{
                .target_decl = decl_id,
                .target_node = decl.node,
                .target_cid = target_cid,
                .raw_text = raw_text_id,
                .summary = summary_id,
                .span = block_span,
                .kind = DocKind.fromDeclKind(decl.kind),
                .tag_lo = tag_lo,
                .tag_hi = tag_hi,
                .test_lo = test_lo,
                .test_hi = test_hi,
            });

            i = block_end;
        }
    }

    // -----------------------------------------------------------------------
    // Raw text extraction
    // -----------------------------------------------------------------------

    /// Strip `///` prefixes from each trivia entry and join into a single string.
    fn extractRawText(
        self: *DocExtractor,
        source: []const u8,
        block: []const Trivia,
    ) ![]const u8 {
        var lines: std.ArrayList(u8) = .empty;
        defer lines.deinit(self.allocator);

        for (block, 0..) |trivia_entry, idx| {
            if (trivia_entry.span.start >= source.len) continue;
            const end = @min(trivia_entry.span.end, @as(u32, @intCast(source.len)));
            const raw_line = source[trivia_entry.span.start..end];
            const stripped = stripDocPrefix(raw_line);

            try lines.appendSlice(self.allocator, stripped);
            if (idx < block.len - 1) {
                try lines.append(self.allocator, '\n');
            }
        }

        return try self.allocator.dupe(u8, lines.items);
    }

    /// Strip the `///` prefix (and optional single space) from a line.
    pub fn stripDocPrefix(line: []const u8) []const u8 {
        if (line.len >= 4 and std.mem.startsWith(u8, line, "/// ")) {
            return line[4..];
        }
        if (line.len >= 3 and std.mem.startsWith(u8, line, "///")) {
            return line[3..];
        }
        return line;
    }

    // -----------------------------------------------------------------------
    // Summary extraction
    // -----------------------------------------------------------------------

    /// Extract the summary: first non-empty line, or up to the first period.
    pub fn extractSummary(raw_text: []const u8) []const u8 {
        // Find first non-empty line
        var iter = std.mem.splitScalar(u8, raw_text, '\n');
        while (iter.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0) continue;

            // Return up to first period+space or first period+end
            if (std.mem.indexOfScalar(u8, trimmed, '.')) |dot_pos| {
                if (dot_pos + 1 >= trimmed.len or trimmed[dot_pos + 1] == ' ') {
                    return trimmed[0 .. dot_pos + 1];
                }
            }
            return trimmed;
        }
        return raw_text;
    }

    // -----------------------------------------------------------------------
    // @tag parsing
    // -----------------------------------------------------------------------

    /// Parse all @tag lines from the raw text and append to the DocStore.
    fn parseTags(self: *DocExtractor, store: *DocStore, raw_text: []const u8) !void {
        var line_iter = std.mem.splitScalar(u8, raw_text, '\n');
        var line_offset: u32 = 0;

        while (line_iter.next()) |line| {
            defer line_offset += @as(u32, @intCast(line.len)) + 1;

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len < 2 or trimmed[0] != '@') continue;

            // Parse: @tagname [name] description
            const tag_body = trimmed[1..]; // skip '@'

            // Find tag name (word after @)
            const tag_name_end = std.mem.indexOfAny(u8, tag_body, " \t") orelse tag_body.len;
            const tag_name = tag_body[0..tag_name_end];

            const kind = DocTag.parseKind(tag_name) orelse continue;

            // Remaining content after tag name
            const rest = if (tag_name_end < tag_body.len)
                std.mem.trim(u8, tag_body[tag_name_end..], " \t")
            else
                "";

            // For tags that have a name component (param, error, capability, see, since)
            var name_str: ?StrId = null;
            var content_str: []const u8 = rest;

            switch (kind) {
                .param, .err, .capability, .see, .since => {
                    // First word is the name, rest is description
                    if (rest.len > 0) {
                        const name_end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
                        const name_text = rest[0..name_end];
                        name_str = try self.interner.intern(name_text);
                        content_str = if (name_end < rest.len)
                            std.mem.trim(u8, rest[name_end..], " \t")
                        else
                            "";
                    }
                },
                else => {},
            }

            const content_id = try self.interner.intern(content_str);
            const tag_span = SourceSpan{
                .start = line_offset,
                .end = line_offset + @as(u32, @intCast(line.len)),
                .line = 0,
                .column = 0,
            };

            _ = try store.addTag(.{
                .kind = kind,
                .name = name_str,
                .content = content_id,
                .span = tag_span,
            });
        }
    }

    // -----------------------------------------------------------------------
    // Embedded example extraction
    // -----------------------------------------------------------------------

    /// Extract fenced ```janus code blocks from raw text as DocTests.
    fn extractEmbeddedExamples(self: *DocExtractor, store: *DocStore, raw_text: []const u8) !void {
        const fence_open = "```janus";
        const fence_close = "```";

        var pos: usize = 0;
        while (pos < raw_text.len) {
            // Find opening fence
            const open_start = std.mem.indexOf(u8, raw_text[pos..], fence_open) orelse break;
            const abs_open = pos + open_start;
            const code_start = abs_open + fence_open.len;

            // Skip to next line after fence
            const line_start = if (std.mem.indexOfScalar(u8, raw_text[code_start..], '\n')) |nl|
                code_start + nl + 1
            else
                break;

            // Find closing fence
            const close_start = std.mem.indexOf(u8, raw_text[line_start..], fence_close) orelse break;
            const abs_close = line_start + close_start;

            // Extract code content (trim trailing whitespace)
            const code = std.mem.trim(u8, raw_text[line_start..abs_close], " \t\r\n");

            if (code.len > 0) {
                const source_id = try self.interner.intern(code);
                const example_span = SourceSpan{
                    .start = @intCast(abs_open),
                    .end = @intCast(abs_close + fence_close.len),
                    .line = 0,
                    .column = 0,
                };
                _ = try store.addTest(.{
                    .test_node = null,
                    .source_text = source_id,
                    .origin = .embedded_example,
                    .span = example_span,
                });
            }

            pos = abs_close + fence_close.len;
        }
    }

    // -----------------------------------------------------------------------
    // Declaration linking — span resolution via node → token chain
    // -----------------------------------------------------------------------

    /// Resolve a declaration's source span through the AST node → token chain.
    /// Returns the SourceSpan of the first token in the declaration's AST node.
    fn resolveDeclSpan(
        decl: *const Decl,
        nodes: []const AstNode,
        tokens: []const Token,
    ) ?SourceSpan {
        const node_index = @intFromEnum(decl.node);
        if (node_index >= nodes.len) return null;
        const node = &nodes[node_index];

        const first_tok_index = @intFromEnum(node.first_token);
        if (first_tok_index >= tokens.len) return null;
        return tokens[first_tok_index].span;
    }

    /// Resolve a declaration's end span (last token).
    fn resolveDeclEndLine(
        decl: *const Decl,
        nodes: []const AstNode,
        tokens: []const Token,
    ) ?u32 {
        const node_index = @intFromEnum(decl.node);
        if (node_index >= nodes.len) return null;
        const node = &nodes[node_index];

        const last_tok_index = @intFromEnum(node.last_token);
        if (last_tok_index >= tokens.len) return null;
        return tokens[last_tok_index].span.line;
    }

    /// Find the nearest declaration whose span starts after the doc block ends.
    /// Returns the index into decls[], or null if no match.
    ///
    /// This implements RFC-025 §3.3 step 3: link by span proximity.
    /// Since Decl has no span field, we resolve through node → first_token → span.
    fn findTargetDecl(
        self: *DocExtractor,
        doc_span: SourceSpan,
        doc_end_line: u32,
        decls: []const Decl,
        nodes: []const AstNode,
        tokens: []const Token,
    ) ?usize {
        var best: ?usize = null;
        var best_distance: u32 = std.math.maxInt(u32);

        for (decls, 0..) |*decl, idx| {
            // Resolve span through node → first_token chain
            const decl_span = resolveDeclSpan(decl, nodes, tokens) orelse continue;

            // Declaration must start after doc comment ends
            if (decl_span.start < doc_span.end) continue;

            const distance = decl_span.start - doc_span.end;

            // Check gap constraint (line-based)
            if (decl_span.line > doc_end_line + self.config.max_gap_lines + 1) continue;

            if (distance < best_distance) {
                best_distance = distance;
                best = idx;
            }
        }

        return best;
    }
};

// ===========================================================================
// Tests
// ===========================================================================

test "stripDocPrefix removes /// correctly" {
    try std.testing.expectEqualStrings("hello world", DocExtractor.stripDocPrefix("/// hello world"));
    try std.testing.expectEqualStrings("", DocExtractor.stripDocPrefix("///"));
    try std.testing.expectEqualStrings("no prefix", DocExtractor.stripDocPrefix("no prefix"));
    try std.testing.expectEqualStrings("@param x The value", DocExtractor.stripDocPrefix("/// @param x The value"));
}

test "extractSummary returns first sentence" {
    try std.testing.expectEqualStrings(
        "Open a file at the given path.",
        DocExtractor.extractSummary("Open a file at the given path. Returns a handle."),
    );
    try std.testing.expectEqualStrings(
        "Single line without period",
        DocExtractor.extractSummary("Single line without period"),
    );
    try std.testing.expectEqualStrings(
        "First line.",
        DocExtractor.extractSummary("First line.\n\nSecond paragraph."),
    );
}

test "DocStore tag parsing via extractor" {
    const allocator = std.testing.allocator;

    var interner = StrInterner.initWithMode(allocator, true);
    defer interner.deinit();

    var store = DocStore.init(allocator);
    defer store.deinit();

    var extractor = DocExtractor.init(allocator, &interner, .{});

    const raw_text =
        \\@param path Filesystem path to open
        \\@returns File handle
        \\@error FsError.NotFound Path does not exist
        \\@capability CapFsRead Required for read mode
        \\@since 0.3.0
    ;

    try extractor.parseTags(&store, raw_text);

    // Verify 5 tags were parsed
    try std.testing.expectEqual(@as(u32, 5), store.currentTagIndex());

    const tags = store.tags.items;
    try std.testing.expectEqual(DocTag.TagKind.param, tags[0].kind);
    try std.testing.expectEqual(DocTag.TagKind.returns, tags[1].kind);
    try std.testing.expectEqual(DocTag.TagKind.err, tags[2].kind);
    try std.testing.expectEqual(DocTag.TagKind.capability, tags[3].kind);
    try std.testing.expectEqual(DocTag.TagKind.since, tags[4].kind);

    // @param should have name "path"
    try std.testing.expect(tags[0].name != null);
    const param_name = interner.get(tags[0].name.?) orelse unreachable;
    try std.testing.expectEqualStrings("path", param_name);
}

test "embedded example extraction" {
    const allocator = std.testing.allocator;

    var interner = StrInterner.initWithMode(allocator, true);
    defer interner.deinit();

    var store = DocStore.init(allocator);
    defer store.deinit();

    var extractor = DocExtractor.init(allocator, &interner, .{});

    const raw_text =
        \\Some documentation text.
        \\
        \\```janus
        \\let x = 42
        \\println(x)
        \\```
        \\
        \\More text.
    ;

    try extractor.extractEmbeddedExamples(&store, raw_text);

    try std.testing.expectEqual(@as(u32, 1), store.currentTestIndex());
    const doc_test = store.tests.items[0];
    try std.testing.expectEqual(DocTest.Origin.embedded_example, doc_test.origin);
    try std.testing.expect(doc_test.test_node == null);

    const code = interner.get(doc_test.source_text) orelse unreachable;
    try std.testing.expect(std.mem.startsWith(u8, code, "let x = 42"));
}
