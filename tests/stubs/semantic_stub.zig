// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Minimal semantic stub for golden integration tests.

const std = @import("std");

pub const ValidationEngine = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, _astdb: anytype) !*ValidationEngine {
        _ = _astdb; // unused in stub
        const self = try allocator.create(ValidationEngine);
        self.* = .{ .allocator = allocator };
        return self;
    }

    pub fn deinit(self: *ValidationEngine) void {
        self.allocator.destroy(self);
    }
};

pub const TypeSystem = struct {};
