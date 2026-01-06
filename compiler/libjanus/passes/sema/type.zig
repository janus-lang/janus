// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Minimal stub: semantic type checks
const std = @import("std");

pub fn checkType(allocator: std.mem.Allocator, _ctx: anytype) !void {
    _ = allocator;
    _ = _ctx;
    // No-op for S0; ensures linkage during bootstrap
}
