// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

/// The Janus Allocator VTable (Matches C: JanusAllocatorVTable)
/// This defines the interface for all memory operations in the runtime.
pub const JanusAllocatorVTable = extern struct {
    alloc: *const fn (ctx: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque,
    free: *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.C) void,
};

/// The Janus Allocator Handle (Matches C: JanusAllocator)
/// Passed via Context to every function requiring memory.
pub const JanusAllocator = extern struct {
    ctx: ?*anyopaque,
    vtable: *const JanusAllocatorVTable,

    /// Helper to wrap a Zig Allocator into a JanusAllocator (for tests/internals)
    pub fn fromZig(allocator: std.mem.Allocator) JanusAllocator {
        // This is a stub for MVR.
        // Real implementation would need a stable wrapper context.
        _ = allocator;
        return .{
            .ctx = null,
            .vtable = &ZIG_ALLOCATOR_VTABLE,
        };
    }
};

/// External references to the C Runtime symbols
/// These are the functions LLVM will emit calls to.
pub extern "C" fn janus_default_allocator() *JanusAllocator;
pub extern "C" fn std_array_create(size: usize, allocator: *JanusAllocator) ?*anyopaque;
pub extern "C" fn janus_print(str: ?[*:0]const u8) void;
pub extern "C" fn janus_panic(msg: ?[*:0]const u8) noreturn;
pub extern "C" fn janus_print_int(val: i32) void;

// --- Zig Allocator Shim for Testing (Stub) ---
fn zig_alloc_wrapper(ctx: ?*anyopaque, size: usize) callconv(.C) ?*anyopaque {
    _ = ctx;
    _ = size;
    return null;
}

fn zig_free_wrapper(ctx: ?*anyopaque, ptr: ?*anyopaque) callconv(.C) void {
    _ = ctx;
    _ = ptr;
}

const ZIG_ALLOCATOR_VTABLE = JanusAllocatorVTable{
    .alloc = zig_alloc_wrapper,
    .free = zig_free_wrapper,
};
