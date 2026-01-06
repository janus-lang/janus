// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const GrepEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) GrepEngine {
        return .{ .allocator = allocator };
    }

    pub fn search(self: *GrepEngine, haystack: []const u8, needle: []const u8) !bool {
        _ = self;
        return std.mem.indexOf(u8, haystack, needle) != null;
    }
};
