// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");

pub const TL = struct {
    path: []const u8,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, path: []const u8) TL {
        return .{ .allocator = allocator, .path = path };
    }

    pub fn defaultPath(allocator: std.mem.Allocator) ![]u8 {
        const home = try std.process.getEnvVarOwned(allocator, "HOME");
        defer allocator.free(home);
        return try std.fs.path.join(allocator, &.{ home, ".hinge", "transparency.log" });
    }

    pub fn append(self: *TL, statement: []const u8) !void {
        // Ensure directory
        if (std.fs.path.dirname(self.path)) |dirp| {
            try compat_fs.makeDir(dirp);
        }
        var f = compat_fs.createFile(self.path, .{ .truncate = false }) catch |e| switch (e) {
            error.PathAlreadyExists => try std.fs.cwd().openFile(self.path, .{ .mode = .read_write }),
            else => return e,
        };
        defer f.close();
        try f.seekFromEnd(0);
        try f.writeAll(statement);
        try f.writeAll("\n");
    }

    pub fn computeRoot(self: *TL) ![32]u8 {
        const lines = try self.readLines();
        defer self.freeLines(lines);
        const leaves = try self.hashLines(lines);
        defer self.allocator.free(leaves);
        return merkleRoot(leaves);
    }

    pub fn inclusion(self: *TL, needle: []const u8) !?usize {
        const lines = try self.readLines();
        defer self.freeLines(lines);
        for (lines, 0..) |line, i| {
            if (std.mem.eql(u8, line, needle)) return i;
        }
        return null;
    }

    pub const Proof = struct {
        index: usize,
        total: usize,
        siblings: []const [32]u8,
    };

    pub fn proofForStatement(self: *TL, statement: []const u8) !?Proof {
        const lines = try self.readLines();
        defer self.freeLines(lines);
        var idx_opt: ?usize = null;
        for (lines, 0..) |line, i| {
            if (std.mem.eql(u8, line, statement)) {
                idx_opt = i;
                break;
            }
        }
        const idx0 = idx_opt orelse return null;
        const total = lines.len;
        const leaves = try self.hashLines(lines);
        // Build sibling list from leaves upward
        var siblings: std.ArrayList([32]u8) = .empty;
        errdefer siblings.deinit(self.allocator);

        var idx = idx0;
        var level = leaves;
        while (level.len > 1) {
            const sib_idx: usize = if ((idx & 1) == 0) @min(idx + 1, level.len - 1) else idx - 1;
            try siblings.append(self.allocator, level[sib_idx]);
            // Compute parent level
            const out_len = (level.len + 1) / 2;
            var next = try self.allocator.alloc([32]u8, out_len);
            var j: usize = 0;
            var i: usize = 0;
            while (i < level.len) : (i += 2) {
                var h = std.crypto.hash.Blake3.init(.{});
                h.update(&level[i]);
                const k = if (i + 1 < level.len) &level[i + 1] else &level[i];
                h.update(k);
                h.final(&next[j]);
                j += 1;
            }
            self.allocator.free(level);
            level = next;
            idx = idx / 2;
        }
        const sibs_owned = try siblings.toOwnedSlice(self.allocator);
        return Proof{ .index = idx0, .total = total, .siblings = sibs_owned };
    }

    pub fn verifyProof(statement: []const u8, proof: Proof) [32]u8 {
        // Recompute root from statement leaf and sibling list
        var leaf_hash: [32]u8 = undefined;
        var h0 = std.crypto.hash.Blake3.init(.{});
        h0.update(statement);
        h0.final(&leaf_hash);
        var acc = leaf_hash;
        var idx = proof.index;
        for (proof.siblings) |sib| {
            var h = std.crypto.hash.Blake3.init(.{});
            if ((idx & 1) == 0) {
                h.update(&acc);
                h.update(&sib);
            } else {
                h.update(&sib);
                h.update(&acc);
            }
            h.final(&acc);
            idx >>= 1;
        }
        return acc;
    }

    fn readLines(self: *TL) ![][]u8 {
        if (std.fs.cwd().openFile(self.path, .{})) |f| {
            defer f.close();
            const content = try f.readToEndAlloc(self.allocator, 64 * 1024 * 1024);
            var it = std.mem.splitScalar(u8, content, '\n');
            var arr: std.ArrayList([]u8) = .empty;
            while (it.next()) |line| {
                if (line.len == 0) continue;
                try arr.append(self.allocator, try self.allocator.dupe(u8, line));
            }
            return try arr.toOwnedSlice(self.allocator);
        } else |_| {
            return self.allocator.alloc([]u8, 0);
        }
    }

    fn freeLines(self: *TL, lines: [][]u8) void {
        for (lines) |l| self.allocator.free(l);
        self.allocator.free(lines);
    }

    fn hashLines(self: *TL, lines: [][]u8) ![]const [32]u8 {
        var arr = try self.allocator.alloc([32]u8, lines.len);
        for (lines, 0..) |l, i| {
            var h = std.crypto.hash.Blake3.init(.{});
            h.update(l);
            h.final(&arr[i]);
        }
        return arr;
    }
};

pub fn merkleRoot(leaves: []const [32]u8) [32]u8 {
    if (leaves.len == 0) return .{0} ** 32;
    var arena_buffer: [64][32]u8 = undefined; // small temp if needed
    var stack = leaves;
    var tmp_slice: [][32]u8 = &arena_buffer;
    while (stack.len > 1) {
        const out_len = (stack.len + 1) / 2;
        if (out_len > tmp_slice.len) {
            // fallback reuse: alias to a writable slice
            tmp_slice = (@constCast(stack))[0..out_len];
        }
        var j: usize = 0;
        var i: usize = 0;
        while (i < stack.len) : (i += 2) {
            var h = std.crypto.hash.Blake3.init(.{});
            h.update(&stack[i]);
            const k = if (i + 1 < stack.len) &stack[i + 1] else &stack[i];
            h.update(k);
            h.final(&tmp_slice[j]);
            j += 1;
        }
        stack = tmp_slice[0..out_len];
    }
    return stack[0];
}
