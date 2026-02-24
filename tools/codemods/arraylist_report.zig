// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Tooling: Catalog std.ArrayList instantiations ahead of Zig 0.15.2 migration.

const std = @import("std");
const compat_fs = @import("compat_fs");

const needle = "std.ArrayList";
const max_file_bytes = 16 * 1024 * 1024;

const StoredOccurrence = struct {
    path: []u8,
    line: u32,
    column: u32,
    kind: []const u8,
    method: ?[]u8,
    context: []u8,
};

const OccurrenceView = struct {
    path: []const u8,
    line: u32,
    column: u32,
    kind: []const u8,
    method: ?[]const u8,
    context: []const u8,
};

const MethodCount = struct {
    method: []const u8,
    count: usize,
};

const Summary = struct {
    total: usize,
    struct_literals: usize,
    method_calls: usize,
    method_counts: []const MethodCount,
};

const Report = struct {
    occurrences: []const OccurrenceView,
    summary: Summary,
};

const SkipComponent = [_][]const u8{
    ".git/",
    ".zig-cache/",
    "zig-cache/",
    "zig-out/",
    "node_modules/",
    "attic/",
    "dist/",
    "third_party/",
    "docs/generated/",
};

const ParseState = enum {
    code,
    line_comment,
    block_comment,
    string,
};

const LineIndex = struct {
    starts: []usize,

    pub fn init(allocator: std.mem.Allocator, contents: []const u8) !LineIndex {
        var starts = std.ArrayList(usize){};
        errdefer starts.deinit(allocator);

        try starts.append(allocator, 0);
        for (contents, 0..) |ch, idx| {
            if (ch == '\n') {
                try starts.append(allocator, idx + 1);
            }
        }

        return LineIndex{ .starts = try starts.toOwnedSlice(allocator) };
    }

    pub fn deinit(self: *LineIndex, allocator: std.mem.Allocator) void {
        allocator.free(self.starts);
        self.starts = &[_]usize{};
    }

    pub fn locate(self: LineIndex, offset: usize) struct {
        line: usize,
        column: usize,
        line_start: usize,
        next_start: ?usize,
    } {
        std.debug.assert(self.starts.len != 0);

        var low: usize = 0;
        var high: usize = self.starts.len;
        while (low < high) {
            const mid = (low + high) / 2;
            if (self.starts[mid] <= offset) {
                low = mid + 1;
            } else {
                high = mid;
            }
        }

        const line_index = if (low == 0) 0 else low - 1;
        const start = self.starts[line_index];
        const next = if (low < self.starts.len) self.starts[low] else null;
        const column = (offset - start) + 1;

        return .{
            .line = line_index + 1,
            .column = column,
            .line_start = start,
            .next_start = next,
        };
    }

    pub fn slice(self: LineIndex, contents: []const u8, line: usize) []const u8 {
        std.debug.assert(line >= 1);
        std.debug.assert(line - 1 < self.starts.len);

        const start = self.starts[line - 1];
        const next = if (line < self.starts.len) self.starts[line] else contents.len;
        var line_slice = contents[start..next];

        while (line_slice.len != 0 and (line_slice[line_slice.len - 1] == '\n' or line_slice[line_slice.len - 1] == '\r')) {
            line_slice = line_slice[0 .. line_slice.len - 1];
        }
        return line_slice;
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer {
        const leaked = gpa.deinit();
        std.debug.assert(!leaked);
    }
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const roots = if (args.len > 1) args[1..] else &[_][]const u8{"."};

    var results = std.ArrayList(StoredOccurrence){};
    defer deinitOccurrences(allocator, &results);

    for (roots) |root_path| {
        try scanRoot(allocator, root_path, &results);
    }

    std.sort.sort(StoredOccurrence, results.items, {}, occurrenceLessThan);

    try emitReport(allocator, results.items);
}

fn emitReport(allocator: std.mem.Allocator, occurrences: []StoredOccurrence) !void {
    var struct_literals: usize = 0;
    var method_calls: usize = 0;
    var method_counts = std.StringHashMap(usize).init(allocator);
    defer method_counts.deinit();

    for (occurrences) |occ| {
        if (std.mem.eql(u8, occ.kind, "struct_literal")) {
            struct_literals += 1;
            continue;
        }
        if (std.mem.eql(u8, occ.kind, "method_call")) {
            method_calls += 1;
            const method_name = occ.method orelse continue;
            const entry = try method_counts.getOrPut(method_name);
            if (!entry.found_existing) entry.value_ptr.* = 0;
            entry.value_ptr.* += 1;
        }
    }

    var method_breakdown = std.ArrayList(MethodCount){};
    defer method_breakdown.deinit(allocator);

    var method_iter = method_counts.iterator();
    while (method_iter.next()) |entry| {
        try method_breakdown.append(allocator, .{
            .method = entry.key_ptr.*,
            .count = entry.value_ptr.*,
        });
    }

    std.sort.sort(MethodCount, method_breakdown.items, {}, struct {
        fn lessThan(_: void, lhs: MethodCount, rhs: MethodCount) bool {
            const ord = std.mem.order(u8, lhs.method, rhs.method);
            if (ord == .lt) return true;
            if (ord == .gt) return false;
            return lhs.count < rhs.count;
        }
    }.lessThan);

    var views = try allocator.alloc(OccurrenceView, occurrences.len);
    defer allocator.free(views);

    for (occurrences, 0..) |occ, idx| {
        views[idx] = .{
            .path = occ.path,
            .line = occ.line,
            .column = occ.column,
            .kind = occ.kind,
            .method = if (occ.method) |m| m else null,
            .context = occ.context,
        };
    }

    const summary = Summary{
        .total = occurrences.len,
        .struct_literals = struct_literals,
        .method_calls = method_calls,
        .method_counts = method_breakdown.items,
    };

    const report = Report{
        .occurrences = views,
        .summary = summary,
    };

    var stdout_file = std.io.getStdOut();
    var writer = stdout_file.writer();
    try std.json.stringify(report, .{ .whitespace = .indent_2 }, writer);
    try writer.writeByte('\n');
}

fn deinitOccurrences(allocator: std.mem.Allocator, list: *std.ArrayList(StoredOccurrence)) void {
    for (list.items) |occ| {
        allocator.free(occ.path);
        allocator.free(occ.context);
        if (occ.method) |m| allocator.free(m);
    }
    list.deinit(allocator);
}

fn scanRoot(
    allocator: std.mem.Allocator,
    root_path: []const u8,
    results: *std.ArrayList(StoredOccurrence),
) !void {
    var dir = try compat_fs.openDir(root_path, .{ .iterate = true });
    defer dir.close();

    const base = if (std.mem.eql(u8, root_path, ".")) "" else root_path;
    try scanDir(allocator, &dir, base, results);
}

fn scanDir(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    prefix: []const u8,
    results: *std.ArrayList(StoredOccurrence),
) !void {
    var iter = dir.iterate();
    while (try iter.next()) |entry| {
        const rel_path = try joinPath(allocator, prefix, entry.name);
        defer allocator.free(rel_path);

        switch (entry.kind) {
            .directory => {
                if (shouldSkip(rel_path)) continue;

                var child = try dir.openDir(entry.name, .{ .iterate = true });
                defer child.close();

                try scanDir(allocator, &child, rel_path, results);
            },
            .file => {
                if (!std.mem.endsWith(u8, entry.name, ".zig")) continue;
                if (shouldSkip(rel_path)) continue;
                try processFile(allocator, dir, entry.name, rel_path, results);
            },
            else => {},
        }
    }
}

fn processFile(
    allocator: std.mem.Allocator,
    dir: *std.fs.Dir,
    file_name: []const u8,
    rel_path: []const u8,
    results: *std.ArrayList(StoredOccurrence),
) !void {
    const contents = try dir.readFileAlloc(allocator, file_name, max_file_bytes);
    defer allocator.free(contents);

    var line_index = try LineIndex.init(allocator, contents);
    defer line_index.deinit(allocator);

    try analyzeSource(allocator, rel_path, contents, &line_index, results);
}

fn analyzeSource(
    allocator: std.mem.Allocator,
    rel_path: []const u8,
    contents: []const u8,
    line_index: *const LineIndex,
    results: *std.ArrayList(StoredOccurrence),
) !void {
    var state = ParseState.code;
    var i: usize = 0;
    var block_depth: usize = 0;
    var string_delim: u8 = 0;

    while (i < contents.len) {
        const ch = contents[i];
        switch (state) {
            .code => {
                if (ch == '"') {
                    state = .string;
                    string_delim = '"';
                    i += 1;
                    continue;
                }
                if (ch == '\'') {
                    state = .string;
                    string_delim = '\'';
                    i += 1;
                    continue;
                }
                if (ch == '/' and i + 1 < contents.len) {
                    const next = contents[i + 1];
                    if (next == '/') {
                        state = .line_comment;
                        i += 2;
                        continue;
                    } else if (next == '*') {
                        state = .block_comment;
                        block_depth = 1;
                        i += 2;
                        continue;
                    }
                }

                if (ch == 's' and i + needle.len <= contents.len) {
                    if (std.mem.eql(u8, contents[i .. i + needle.len], needle)) {
                        try handleNeedle(allocator, rel_path, contents, line_index.*, results, i);
                        i += needle.len;
                        continue;
                    }
                }
                i += 1;
            },
            .line_comment => {
                if (ch == '\n') {
                    state = .code;
                }
                i += 1;
            },
            .block_comment => {
                if (ch == '/' and i + 1 < contents.len and contents[i + 1] == '*') {
                    block_depth += 1;
                    i += 2;
                    continue;
                }
                if (ch == '*' and i + 1 < contents.len and contents[i + 1] == '/') {
                    block_depth -= 1;
                    i += 2;
                    if (block_depth == 0) state = .code;
                    continue;
                }
                i += 1;
            },
            .string => {
                if (ch == '\\') {
                    if (i + 1 < contents.len) {
                        i += 2;
                    } else {
                        i += 1;
                    }
                    continue;
                }
                if (ch == string_delim) {
                    state = .code;
                    string_delim = 0;
                }
                i += 1;
            },
        }
    }
}

fn handleNeedle(
    allocator: std.mem.Allocator,
    rel_path: []const u8,
    contents: []const u8,
    line_index: LineIndex,
    results: *std.ArrayList(StoredOccurrence),
    start: usize,
) !void {
    if (start > 0) {
        const prev = contents[start - 1];
        if (std.ascii.isAlphanumeric(prev) or prev == '_' or prev == '.') return;
    }

    var pos = start + needle.len;
    pos = skipWhitespace(contents, pos);
    if (pos >= contents.len or contents[pos] != '(') return;

    const closing = findClosingParen(contents, pos) orelse return;
    var after = skipWhitespace(contents, closing + 1);
    if (after >= contents.len) return;

    if (contents[after] == '{') {
        try recordOccurrence(allocator, rel_path, contents, line_index, results, start, "struct_literal", null);
        return;
    }

    if (contents[after] != '.') return;

    var method_start = after + 1;
    while (method_start < contents.len and contents[method_start] == '.') {
        // Skip potential chaining (unlikely) but guard against `std.ArrayList(T)..`.
        method_start += 1;
    }

    var method_end = method_start;
    while (method_end < contents.len and isIdentChar(contents[method_end])) {
        method_end += 1;
    }
    if (method_end == method_start) return;

    after = skipWhitespace(contents, method_end);
    if (after >= contents.len or contents[after] != '(') return;

    const method_slice = contents[method_start..method_end];
    const method_copy = try allocator.dupe(u8, method_slice);
    errdefer allocator.free(method_copy);

    try recordOccurrence(allocator, rel_path, contents, line_index, results, start, "method_call", method_copy);
}

fn recordOccurrence(
    allocator: std.mem.Allocator,
    rel_path: []const u8,
    contents: []const u8,
    line_index: LineIndex,
    results: *std.ArrayList(StoredOccurrence),
    start: usize,
    kind: []const u8,
    method: ?[]u8,
) !void {
    const loc = line_index.locate(start);
    const line_slice = line_index.slice(contents, loc.line);

    const path_copy = try allocator.dupe(u8, rel_path);
    errdefer allocator.free(path_copy);

    const context_copy = try allocator.dupe(u8, line_slice);
    errdefer allocator.free(context_copy);

    try results.append(allocator, .{
        .path = path_copy,
        .line = @as(u32, @intCast(loc.line)),
        .column = @as(u32, @intCast(loc.column)),
        .kind = kind,
        .method = method,
        .context = context_copy,
    });
}

fn skipWhitespace(contents: []const u8, start: usize) usize {
    var pos = start;
    while (pos < contents.len) {
        const ch = contents[pos];
        switch (ch) {
            ' ', '\t', '\n', '\r' => pos += 1,
            else => return pos,
        }
    }
    return pos;
}

fn findClosingParen(contents: []const u8, open_paren: usize) ?usize {
    std.debug.assert(contents[open_paren] == '(');
    var depth: usize = 0;
    var i = open_paren;
    while (i < contents.len) {
        const ch = contents[i];
        switch (ch) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return i;
            },
            '"', '\'' => {
                const delim = ch;
                i += 1;
                while (i < contents.len) {
                    const inner = contents[i];
                    if (inner == '\\') {
                        i += 2;
                        continue;
                    }
                    if (inner == delim) break;
                    i += 1;
                }
            },
            '/' => {
                if (i + 1 >= contents.len) break;
                const next = contents[i + 1];
                if (next == '/') {
                    i += 2;
                    while (i < contents.len and contents[i] != '\n') {
                        i += 1;
                    }
                    continue;
                }
                if (next == '*') {
                    i += 2;
                    var depth_block: usize = 1;
                    while (i < contents.len and depth_block != 0) {
                        if (i + 1 < contents.len and contents[i] == '/' and contents[i + 1] == '*') {
                            depth_block += 1;
                            i += 2;
                            continue;
                        }
                        if (i + 1 < contents.len and contents[i] == '*' and contents[i + 1] == '/') {
                            depth_block -= 1;
                            i += 2;
                            continue;
                        }
                        i += 1;
                    }
                    continue;
                }
            },
            else => {},
        }
        i += 1;
    }
    return null;
}

fn joinPath(allocator: std.mem.Allocator, prefix: []const u8, name: []const u8) ![]u8 {
    if (prefix.len == 0) return allocator.dupe(u8, name);
    return std.mem.concat(allocator, u8, &[_][]const u8{ prefix, "/", name });
}

fn shouldSkip(path: []const u8) bool {
    for (SkipComponent) |component| {
        if (std.mem.indexOf(u8, path, component) != null) return true;
    }
    return false;
}

fn occurrenceLessThan(_: void, lhs: StoredOccurrence, rhs: StoredOccurrence) bool {
    const order = std.mem.order(u8, lhs.path, rhs.path);
    if (order == .lt) return true;
    if (order == .gt) return false;
    if (lhs.line < rhs.line) return true;
    if (lhs.line > rhs.line) return false;
    return lhs.column < rhs.column;
}

fn isIdentChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '_';
}

test "analyzeSource reports ArrayList instantiations and skips types/comments" {
    const allocator = std.testing.allocator;
    const source =
        \\const std = @import("std");
        \\
        \\pub fn sample(allocator: std.mem.Allocator) void {
        \\    var list_a: std.ArrayList(u8) = .empty;
        \\    var list_b = std.ArrayList(u8)
        \\        .initCapacity(allocator, 16);
        \\    var list_c = std.ArrayList(struct {
        \\        name: []const u8,
        \\    }){};
        \\    const TypeAlias = std.ArrayList(u8);
        \\    // std.ArrayList(u8).empty;
        \\    const literal = "std.ArrayList(u8).empty";
        \\    const init_fn = std.ArrayList(u8).init;
        \\}
    ;

    var results = std.ArrayList(StoredOccurrence){};
    defer deinitOccurrences(allocator, &results);

    var line_index = try LineIndex.init(allocator, source);
    defer line_index.deinit(allocator);

    try analyzeSource(allocator, "test.zig", source, &line_index, &results);

    try std.testing.expectEqual(@as(usize, 2), results.items.len);

    try std.testing.expect(std.mem.eql(u8, "test.zig", results.items[0].path));
    try std.testing.expect(std.mem.eql(u8, "method_call", results.items[0].kind));
    try std.testing.expect(std.mem.eql(u8, "initCapacity", results.items[0].method.?));

    try std.testing.expect(std.mem.eql(u8, "struct_literal", results.items[1].kind));
    try std.testing.expect(results.items[1].method == null);
}

test "findClosingParen handles nested parentheses and comments" {
    const source = "std.ArrayList(std.ArrayList(u8).Sentinel).init(/* comment ( */ allocator /* ) */);";
    const open_idx = std.mem.indexOfScalar(u8, source, '(').?;
    const close_idx = findClosingParen(source, open_idx) orelse unreachable;
    try std.testing.expect(close_idx > open_idx);
    try std.testing.expectEqual(@as(u8, ')'), source[close_idx]);
}
