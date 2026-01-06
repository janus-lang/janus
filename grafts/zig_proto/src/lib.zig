// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Minimal C-ABI prototype for std.graft bridge experiments.
// Success => return 0; Failure => return non-zero error code.

// Prints the provided UTF-8 bytes to stderr (or debug output), newline-terminated.
// This function intentionally avoids allocator parameters for stability of the first prototype.
// Adapter layer will enforce allocator/capability discipline on the Janus side.
export fn janus_graft_print(ptr: [*]const u8, len: usize) c_int {
    if (len == 0) return 1; // EINVAL
    const slice = ptr[0..len];
    std.debug.print("{s}\n", .{slice});
    return 0;
}

// Optional: simulate a failure for testing by returning an error code when flag!=0
export fn janus_graft_print_maybe_fail(ptr: [*]const u8, len: usize, fail_flag: c_int) c_int {
    if (fail_flag != 0) return 2; // simulated failure
    return janus_graft_print(ptr, len);
}

// Allocator-injection prototype: foreign calls provide an allocation callback usable by this library.
pub const AllocFn = fn (len: usize, ctx: ?*anyopaque) ?*anyopaque;

// Makes a greeting string using the provided allocator callback.
// Returns 0 on success, non-zero on failure.
export fn janus_graft_make_greeting(
    alloc_cb: ?*const AllocFn,
    alloc_ctx: ?*anyopaque,
    name_ptr: [*]const u8,
    name_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) c_int {
    if (name_len == 0) return 1; // InvalidArgument
    if (alloc_cb == null) return 3; // No allocator provided
    const cb = alloc_cb.?;
    // Compute greeting: "Hello, " + name
    const prefix = "Hello, ";
    const total: usize = prefix.len + name_len;
    const mem = cb(total, alloc_ctx) orelse return 3; // allocation failed
    const buf = @as([*]u8, @ptrCast(mem))[0..total];
    @memcpy(buf[0..prefix.len], prefix);
    @memcpy(buf[prefix.len..], name_ptr[0..name_len]);
    out_ptr.* = buf.ptr;
    out_len.* = total;
    return 0;
}

// Read a file fully using the provided allocation callback. Returns 0 on success.
export fn janus_graft_read_file(
    alloc_cb: ?*const AllocFn,
    alloc_ctx: ?*anyopaque,
    path_ptr: [*]const u8,
    path_len: usize,
    out_ptr: *[*]u8,
    out_len: *usize,
) c_int {
    if (path_len == 0) return 1; // InvalidArgument
    if (alloc_cb == null) return 3; // allocator missing
    const cb = alloc_cb.?;

    const path = path_ptr[0..path_len];
    var cwd = std.fs.cwd();
    const file = cwd.openFile(path, .{}) catch return 2; // ForeignError on IO
    defer file.close();

    const stat = file.stat() catch return 2;
    // Guard extremely large files; cap at usize max already, but keep simple
    const size: usize = @intCast(stat.size);
    const mem = cb(size, alloc_ctx) orelse return 3;
    const buf = @as([*]u8, @ptrCast(mem))[0..size];
    const n = file.readAll(buf) catch return 2;
    if (n != size) {
        // shrink length to read bytes; still success
        out_ptr.* = buf.ptr;
        out_len.* = n;
        return 0;
    }
    out_ptr.* = buf.ptr;
    out_len.* = size;
    return 0;
}
