// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const caps = @import("std_caps");

pub const GraftError = error{
    CapabilityMissing,
    InvalidArgument,
    ForeignError,
    LinkError,
    ForeignPanic,
};

extern fn janus_graft_print(ptr: [*]const u8, len: usize) c_int;
extern fn janus_graft_print_maybe_fail(ptr: [*]const u8, len: usize, fail_flag: c_int) c_int;
extern fn janus_graft_make_greeting(
    alloc_cb: ?*const fn (len: usize, ctx: ?*anyopaque) ?*anyopaque,
    alloc_ctx: ?*anyopaque,
    name_ptr: [*]const u8,
    name_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) c_int;

extern fn janus_graft_read_file(
    alloc_cb: ?*const fn (len: usize, ctx: ?*anyopaque) ?*anyopaque,
    alloc_ctx: ?*anyopaque,
    path_ptr: [*]const u8,
    path_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) c_int;

fn map_rc(rc: c_int) GraftError!void {
    return switch (rc) {
        0 => {},
        1 => GraftError.InvalidArgument,
        2 => GraftError.ForeignError,
        else => GraftError.ForeignError,
    };
}

/// Prototype wrapper for a grafted Zig function.
/// Enforces capability presence and converts foreign return codes to structured errors.
pub fn print_line(cap_stderr: *const caps.Capability, allocator: std.mem.Allocator, msg: []const u8) GraftError!void {
    _ = cap_stderr;
    _ = allocator; // prototype does not allocate; kept for tri-signature symmetry
    if (msg.len == 0) return; // no-op
    const rc: c_int = janus_graft_print(msg.ptr, msg.len);
    try map_rc(rc);
}

/// Same as print_line, but allows simulated failure code paths for testing error conversion.
pub fn print_line_checked(cap_stderr: *const caps.Capability, allocator: std.mem.Allocator, msg: []const u8, fail_flag: c_int) GraftError!void {
    _ = cap_stderr;
    _ = allocator;
    const rc: c_int = janus_graft_print_maybe_fail(msg.ptr, msg.len, fail_flag);
    try map_rc(rc);
}

// Owned buffer result with allocator ownership.
pub const OwnedBuffer = struct {
    ptr: [*]u8,
    len: usize,
    allocator: std.mem.Allocator,
    pub fn slice(self: OwnedBuffer) []u8 {
        return self.ptr[0..self.len];
    }
    pub fn deinit(self: OwnedBuffer) void {
        self.allocator.free(self.ptr[0..self.len]);
    }
};

// C-ABI allocator shim: uses the provided Zig allocator (passed via ctx) to allocate bytes.
fn adapter_alloc(len: usize, ctx: ?*anyopaque) ?*anyopaque {
    if (ctx == null) return null;
    const alloc_ptr = @as(*std.mem.Allocator, @alignCast(@ptrCast(ctx.?)));
    const slice = alloc_ptr.alloc(u8, len) catch return null;
    return @as(?*anyopaque, @ptrCast(slice.ptr));
}

/// Example of allocator-injected foreign call that returns an owned buffer.
pub fn make_greeting(cap_stdout: *const caps.Capability, allocator: std.mem.Allocator, name: []const u8) GraftError!OwnedBuffer {
    _ = cap_stdout;
    var out_ptr: [*]u8 = undefined;
    var out_len: usize = 0;
    const ctx: ?*anyopaque = @ptrCast(@constCast(&allocator));
    const rc = janus_graft_make_greeting(&adapter_alloc, ctx, name.ptr, name.len, &out_ptr, &out_len);
    try map_rc(rc);
    return OwnedBuffer{ .ptr = out_ptr, .len = out_len, .allocator = allocator };
}

/// Read a file into an owned buffer via the foreign graft, using allocator injection.
pub fn read_file(cap_fs_read: *const caps.FileSystem, allocator: std.mem.Allocator, path: []const u8) GraftError!OwnedBuffer {
    if (path.len == 0) return GraftError.InvalidArgument;
    if (!cap_fs_read.allows_path(path)) return GraftError.CapabilityMissing;
    var out_ptr: [*]u8 = undefined;
    var out_len: usize = 0;
    const ctx: ?*anyopaque = @ptrCast(@constCast(&allocator));
    const rc = janus_graft_read_file(&adapter_alloc, ctx, path.ptr, path.len, &out_ptr, &out_len);
    try map_rc(rc);
    return OwnedBuffer{ .ptr = out_ptr, .len = out_len, .allocator = allocator };
}
