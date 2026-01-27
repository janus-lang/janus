// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Core Filesystem Operations - Exported for Native Grafting
//!
//! This module provides C-exported filesystem functions that Janus can call
//! via `use zig "std/core/fs_ops.zig"`.
//!
//! Design:
//! - All functions use C-compatible types
//! - Paths are passed as ptr + len pairs
//! - Results use out-parameters or return codes
//! - Uses a static allocator for simplicity (single-threaded CLI use)

const std = @import("std");

// Static allocator for directory iteration state
// This is safe for single-threaded CLI tools like jfind
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();

// ============================================================================
// PATH QUERIES (no allocation needed)
// ============================================================================

/// Check if a path exists (file or directory)
/// Returns 1 (true) or 0 (false)
pub export fn fs_exists(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) i32 {
    if (path_len == 0) return 0;
    const path = path_ptr[0..path_len];

    // Need null-terminated path for OS calls
    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= buf.len) return 0;
    @memcpy(buf[0..path_len], path);
    buf[path_len] = 0;

    std.fs.cwd().access(buf[0..path_len :0], .{}) catch return 0;
    return 1;
}

/// Check if path is a directory
/// Returns 1 (true) or 0 (false)
pub export fn fs_is_directory(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) i32 {
    if (path_len == 0) return 0;
    const path = path_ptr[0..path_len];

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= buf.len) return 0;
    @memcpy(buf[0..path_len], path);
    buf[path_len] = 0;

    const stat = std.fs.cwd().statFile(buf[0..path_len :0]) catch return 0;
    return if (stat.kind == .directory) 1 else 0;
}

/// Check if path is a regular file
/// Returns 1 (true) or 0 (false)
pub export fn fs_is_file(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) i32 {
    if (path_len == 0) return 0;
    const path = path_ptr[0..path_len];

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= buf.len) return 0;
    @memcpy(buf[0..path_len], path);
    buf[path_len] = 0;

    const stat = std.fs.cwd().statFile(buf[0..path_len :0]) catch return 0;
    return if (stat.kind == .file) 1 else 0;
}

/// Get file size in bytes
/// Returns size or 0 on error
pub export fn fs_file_size(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) u64 {
    if (path_len == 0) return 0;
    const path = path_ptr[0..path_len];

    var buf: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= buf.len) return 0;
    @memcpy(buf[0..path_len], path);
    buf[path_len] = 0;

    const stat = std.fs.cwd().statFile(buf[0..path_len :0]) catch return 0;
    return stat.size;
}

// ============================================================================
// DIRECTORY ITERATION
// Using opaque handle pattern for iteration state
// ============================================================================

/// Opaque directory iterator handle
const DirIterState = struct {
    dir: std.fs.Dir,
    iter: std.fs.Dir.Iterator,
    current_name: [std.fs.max_name_bytes]u8,
    current_name_len: usize,
    current_is_dir: bool,
    current_size: u64,

    fn deinit(self: *DirIterState) void {
        self.dir.close();
        allocator.destroy(self);
    }
};

/// Open a directory for iteration
/// Returns handle pointer, or null on error
pub export fn fs_dir_open(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) ?*anyopaque {
    if (path_len == 0) return null;
    const path = path_ptr[0..path_len];

    var pathz: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= pathz.len) return null;
    @memcpy(pathz[0..path_len], path);
    pathz[path_len] = 0;

    const state = allocator.create(DirIterState) catch return null;

    state.dir = std.fs.cwd().openDir(pathz[0..path_len :0], .{ .iterate = true }) catch {
        allocator.destroy(state);
        return null;
    };

    state.iter = state.dir.iterate();
    state.current_name_len = 0;
    state.current_is_dir = false;
    state.current_size = 0;

    return state;
}

/// Get next entry from directory iterator
/// Returns 1 if entry available, 0 if done, -1 on error
pub export fn fs_dir_next(
    handle: *anyopaque,
) callconv(.c) i32 {
    const state: *DirIterState = @ptrCast(@alignCast(handle));

    const entry = state.iter.next() catch return -1;

    if (entry) |e| {
        // Copy name
        const name_len = @min(e.name.len, state.current_name.len - 1);
        @memcpy(state.current_name[0..name_len], e.name[0..name_len]);
        state.current_name_len = name_len;
        state.current_is_dir = (e.kind == .directory);

        // Get size for files
        if (e.kind == .file) {
            state.current_size = blk: {
                const stat = state.dir.statFile(e.name) catch break :blk 0;
                break :blk stat.size;
            };
        } else {
            state.current_size = 0;
        }

        return 1;
    }

    return 0; // No more entries
}

/// Get current entry name
/// Returns pointer and sets length via out-parameter
pub export fn fs_dir_entry_name(
    handle: *anyopaque,
    out_len: *usize,
) callconv(.c) [*]const u8 {
    const state: *DirIterState = @ptrCast(@alignCast(handle));
    out_len.* = state.current_name_len;
    return &state.current_name;
}

/// Get current entry name length
pub export fn fs_dir_entry_name_len(
    handle: *anyopaque,
) callconv(.c) usize {
    const state: *DirIterState = @ptrCast(@alignCast(handle));
    return state.current_name_len;
}

/// Check if current entry is a directory
/// Returns 1 (true) or 0 (false)
pub export fn fs_dir_entry_is_dir(
    handle: *anyopaque,
) callconv(.c) i32 {
    const state: *DirIterState = @ptrCast(@alignCast(handle));
    return if (state.current_is_dir) 1 else 0;
}

/// Get current entry file size (0 for directories)
pub export fn fs_dir_entry_size(
    handle: *anyopaque,
) callconv(.c) u64 {
    const state: *DirIterState = @ptrCast(@alignCast(handle));
    return state.current_size;
}

/// Close directory iterator and free resources
pub export fn fs_dir_close(
    handle: *anyopaque,
) callconv(.c) void {
    const state: *DirIterState = @ptrCast(@alignCast(handle));
    state.deinit();
}

// ============================================================================
// FILE READING
// ============================================================================

/// Read file into caller-provided buffer
/// Returns number of bytes read, or -1 on error
pub export fn fs_read_file(
    path_ptr: [*]const u8,
    path_len: usize,
    buf_ptr: [*]u8,
    buf_len: usize,
) callconv(.c) i64 {
    if (path_len == 0 or buf_len == 0) return -1;
    const path = path_ptr[0..path_len];

    var pathz: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= pathz.len) return -1;
    @memcpy(pathz[0..path_len], path);
    pathz[path_len] = 0;

    const file = std.fs.cwd().openFile(pathz[0..path_len :0], .{}) catch return -1;
    defer file.close();

    const bytes_read = file.readAll(buf_ptr[0..buf_len]) catch return -1;
    return @intCast(bytes_read);
}

/// Write buffer to file (creates or overwrites)
/// Returns 0 on success, -1 on error
pub export fn fs_write_file(
    path_ptr: [*]const u8,
    path_len: usize,
    content_ptr: [*]const u8,
    content_len: usize,
) callconv(.c) i32 {
    if (path_len == 0) return -1;
    const path = path_ptr[0..path_len];

    var pathz: [std.fs.max_path_bytes]u8 = undefined;
    if (path_len >= pathz.len) return -1;
    @memcpy(pathz[0..path_len], path);
    pathz[path_len] = 0;

    const file = std.fs.cwd().createFile(pathz[0..path_len :0], .{}) catch return -1;
    defer file.close();

    file.writeAll(content_ptr[0..content_len]) catch return -1;
    return 0;
}

// ============================================================================
// PATH OPERATIONS
// ============================================================================

/// Get current working directory
/// Returns length written, or 0 on error
pub export fn fs_getcwd(
    buf_ptr: [*]u8,
    buf_len: usize,
) callconv(.c) usize {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path = std.fs.cwd().realpath(".", &path_buf) catch return 0;

    if (path.len > buf_len) return 0;
    @memcpy(buf_ptr[0..path.len], path);
    return path.len;
}

/// Join two path components
/// Returns length of result, or 0 if buffer too small
pub export fn fs_path_join(
    base_ptr: [*]const u8,
    base_len: usize,
    name_ptr: [*]const u8,
    name_len: usize,
    out_ptr: [*]u8,
    out_len: usize,
) callconv(.c) usize {
    // Simple join: base + "/" + name
    const total = base_len + 1 + name_len;
    if (total > out_len) return 0;

    @memcpy(out_ptr[0..base_len], base_ptr[0..base_len]);
    out_ptr[base_len] = '/';
    @memcpy(out_ptr[base_len + 1 .. total], name_ptr[0..name_len]);

    return total;
}

/// Get file extension (returns position and length)
/// Returns -1 if no extension
pub export fn fs_path_extension(
    path_ptr: [*]const u8,
    path_len: usize,
    out_start: *usize,
    out_len: *usize,
) callconv(.c) i32 {
    const path = path_ptr[0..path_len];

    // Find last dot
    var i: usize = path_len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') {
            // No extension found before directory separator
            return -1;
        }
        if (path[i] == '.') {
            if (i == 0 or path[i - 1] == '/') {
                // Dot at start of name (hidden file, not extension)
                return -1;
            }
            out_start.* = i + 1; // After the dot
            out_len.* = path_len - i - 1;
            return 0;
        }
    }

    return -1; // No extension
}

/// Get filename from path (basename)
/// Returns start position and length
pub export fn fs_path_basename(
    path_ptr: [*]const u8,
    path_len: usize,
    out_start: *usize,
    out_len: *usize,
) callconv(.c) void {
    if (path_len == 0) {
        out_start.* = 0;
        out_len.* = 0;
        return;
    }

    const path = path_ptr[0..path_len];

    // Find last slash
    var i: usize = path_len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') {
            out_start.* = i + 1;
            out_len.* = path_len - i - 1;
            return;
        }
    }

    // No slash found - entire path is the basename
    out_start.* = 0;
    out_len.* = path_len;
}

/// Get directory name from path (dirname)
/// Returns length of dirname (0 if no directory component)
pub export fn fs_path_dirname(
    path_ptr: [*]const u8,
    path_len: usize,
) callconv(.c) usize {
    if (path_len == 0) return 0;

    const path = path_ptr[0..path_len];

    // Find last slash
    var i: usize = path_len;
    while (i > 0) {
        i -= 1;
        if (path[i] == '/') {
            return i;
        }
    }

    return 0; // No directory component
}

// ============================================================================
// TESTS
// ============================================================================

test "fs_exists" {
    // Current directory should exist
    try std.testing.expectEqual(@as(i32, 1), fs_exists(".", 1));

    // Non-existent path
    const fake = "__nonexistent_12345__";
    try std.testing.expectEqual(@as(i32, 0), fs_exists(fake.ptr, fake.len));
}

test "fs_is_directory" {
    try std.testing.expectEqual(@as(i32, 1), fs_is_directory(".", 1));
}

test "fs_dir_iteration" {
    const handle = fs_dir_open(".", 1);
    try std.testing.expect(handle != null);

    var count: usize = 0;
    while (fs_dir_next(handle.?) == 1) {
        count += 1;
        var name_len: usize = undefined;
        const name_ptr = fs_dir_entry_name(handle.?, &name_len);
        _ = name_ptr;
        _ = fs_dir_entry_is_dir(handle.?);
    }

    try std.testing.expect(count > 0);

    fs_dir_close(handle.?);
}

test "fs_path_extension" {
    const path = "file.txt";
    var start: usize = undefined;
    var len: usize = undefined;
    const result = fs_path_extension(path.ptr, path.len, &start, &len);

    try std.testing.expectEqual(@as(i32, 0), result);
    try std.testing.expectEqual(@as(usize, 5), start);
    try std.testing.expectEqual(@as(usize, 3), len);
}

test "fs_path_basename" {
    const path = "/home/user/file.txt";
    var start: usize = undefined;
    var len: usize = undefined;
    fs_path_basename(path.ptr, path.len, &start, &len);

    try std.testing.expectEqual(@as(usize, 11), start);
    try std.testing.expectEqual(@as(usize, 8), len);
}

test "fs_path_join" {
    var buf: [100]u8 = undefined;
    const base = "/home/user";
    const name = "file.txt";
    const len = fs_path_join(base.ptr, base.len, name.ptr, name.len, &buf, buf.len);

    try std.testing.expectEqualStrings("/home/user/file.txt", buf[0..len]);
}
