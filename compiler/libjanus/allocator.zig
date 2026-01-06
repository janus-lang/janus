// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const rt = @import("runtime_defs.zig");

pub const Allocator = struct {
    handle: *rt.JanusAllocator,

    pub fn init(handle: *rt.JanusAllocator) Allocator {
        return .{ .handle = handle };
    }

    pub fn create(self: Allocator, T: type) !*T {
        // This maps to the runtime alloc function
        // Note: For objects, we need sizeof(T)
        // This is a high-level wrapper that would be used by LibJanus implementation
        const ptr = self.handle.vtable.alloc(self.handle.ctx, @sizeOf(T));
        if (ptr) |p| {
            return @as(*T, @ptrCast(@alignCast(p)));
        }
        return error.OutOfMemory;
    }

    // Helper to get default
    pub fn getDefault() Allocator {
        return init(rt.janus_default_allocator());
    }
};
