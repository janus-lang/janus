// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// std/runtime.zig - Runtime implementation for Janus standard library
// Bridges Janus std library to actual system calls

const std = @import("std");
const builtin = @import("builtin");
const interpreter = @import("interpreter.zig");

// ===== COMMAND LINE ARGUMENTS =====

// Simplified args function - return argc/argv style
export fn getArgCount() i32 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch return 0;
    defer std.process.argsFree(allocator, args);

    return @intCast(args.len);
}

export fn getArgAt(index: i32) [*:0]const u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const args = std.process.argsAlloc(allocator) catch return "";
    defer std.process.argsFree(allocator, args);

    if (index < 0 or index >= args.len) return "";

    // This is a simplified version - in a real implementation we'd need to manage memory properly
    return @ptrCast(args[@intCast(index)].ptr);
}

// ===== I/O OPERATIONS =====

export fn printToStdout(bytes_ptr: [*]const u8, bytes_len: usize) i32 {
    const bytes = bytes_ptr[0..bytes_len];
    const stdout = std.fs.File.stdout();

    stdout.writeAll(bytes) catch |err| switch (err) {
        error.BrokenPipe => return 1,
        error.DiskQuota => return 2,
        error.FileTooBig => return 3,
        error.NoSpaceLeft => return 4,
        error.AccessDenied => return 5,
        error.Unexpected => return 6,
        else => return 7,
    };

    return 0; // Success
}

export fn printToStderr(bytes_ptr: [*]const u8, bytes_len: usize) i32 {
    const bytes = bytes_ptr[0..bytes_len];
    const stderr = std.fs.File.stderr();

    stderr.writeAll(bytes) catch |err| switch (err) {
        error.BrokenPipe => return 1,
        error.DiskQuota => return 2,
        error.FileTooBig => return 3,
        error.NoSpaceLeft => return 4,
        error.AccessDenied => return 5,
        error.Unexpected => return 6,
        else => return 7,
    };

    return 0; // Success
}

// ===== FILE SYSTEM OPERATIONS =====

const JanusFileType = enum(u8) {
    file = 0,
    directory = 1,
    symlink = 2,
    block_device = 3,
    char_device = 4,
    fifo = 5,
    socket = 6,
    unknown = 7,
};

const JanusDirEntry = extern struct {
    name_ptr: [*]const u8,
    name_len: usize,
    file_type: JanusFileType,
};

const JanusFileInfo = extern struct {
    name_ptr: [*]const u8,
    name_len: usize,
    path_ptr: [*]const u8,
    path_len: usize,
    file_type: JanusFileType,
    size: u64,
    permissions: u32,
    modified_time: i64,
    created_time: i64,
};

fn zigFileTypeToJanus(zig_type: std.fs.File.Kind) JanusFileType {
    return switch (zig_type) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        .block_device => .block_device,
        .character_device => .char_device,
        .named_pipe => .fifo,
        .unix_domain_socket => .socket,
        else => .unknown,
    };
}

export fn listDirImpl(path_ptr: [*]const u8, path_len: usize, allocator_ptr: *anyopaque) i32 {
    _ = allocator_ptr; // TODO: Use Janus allocator

    const path = path_ptr[0..path_len];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    // Open directory
    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => return 1,
        error.AccessDenied => return 2,
        error.NotDir => return 3,
        else => return 4,
    };
    defer dir.close();

    // Count entries first
    var count: usize = 0;
    var iterator = dir.iterate();
    while (iterator.next() catch null) |_| {
        count += 1;
    }

    // Reset iterator
    iterator = dir.iterate();

    // Allocate result array
    const entries = allocator.alloc(JanusDirEntry, count) catch return 5;

    // Fill entries
    var i: usize = 0;
    while (iterator.next() catch null) |entry| {
        const name_copy = allocator.dupe(u8, entry.name) catch return 6;

        entries[i] = JanusDirEntry{
            .name_ptr = name_copy.ptr,
            .name_len = name_copy.len,
            .file_type = zigFileTypeToJanus(entry.kind),
        };
        i += 1;
    }

    // TODO: Return entries to Janus code
    // For now, just return success
    return 0;
}

export fn openDirImpl(path_ptr: [*]const u8, path_len: usize) ?*anyopaque {
    const path = path_ptr[0..path_len];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;

    // Allocate directory handle
    const handle = allocator.create(std.fs.Dir) catch return null;
    handle.* = dir;

    return @ptrCast(handle);
}

// ===== New iterator-centric directory API (one-at-a-time) =====

const DirIterHandle = struct {
    dir: std.fs.Dir,
    it: std.fs.Dir.Iterator,
};

// Open a directory iterator handle
export fn openDirIterImpl(path_ptr: [*]const u8, path_len: usize) ?*anyopaque {
    const path = path_ptr[0..path_len];
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch return null;
    const h = allocator.create(DirIterHandle) catch {
        dir.close();
        return null;
    };
    h.* = .{ .dir = dir, .it = dir.iterate() };
    return @ptrCast(h);
}

// Read next entry. Returns:
// 0 = success (out params set), 1 = end, 2 = buffer alloc failure, 3 = iteration error
// Allocates name with std.c.malloc; caller must free via freeC()
export fn readDirNextImpl(handle: ?*anyopaque, out_name_ptr: *[*]u8, out_name_len: *usize, out_kind: *JanusFileType) i32 {
    if (handle == null) return 3;
    const h: *DirIterHandle = @ptrCast(@alignCast(handle.?));
    const next = h.it.next() catch |err| switch (err) {
        error.AccessDenied => return 3,
        error.NotDir => return 3,
        else => return 3,
    };
    if (next == null) return 1;
    const entry = next.?;

    // Duplicate name using C malloc so the caller can free with only a pointer
    const name_len: usize = entry.name.len;
    const ptr = std.c.malloc(name_len) orelse return 2;
    @memcpy(@as([*]u8, @ptrCast(ptr))[0..name_len], entry.name);

    out_name_ptr.* = @ptrCast(ptr);
    out_name_len.* = name_len;
    out_kind.* = zigFileTypeToJanus(entry.kind);
    return 0;
}

// Close directory iterator handle
export fn closeDirIterImpl(handle: ?*anyopaque) void {
    if (handle == null) return;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const h: *DirIterHandle = @ptrCast(@alignCast(handle.?));
    h.dir.close();
    allocator.destroy(h);
}

// Free name buffers returned by readDirNextImpl
export fn freeC(ptr: [*]u8) void {
    std.c.free(ptr);
}

// Lightweight stat implementation that fills out fields via out params.
// Returns 0 on success; non-zero on error (1 not found, 2 access denied, 3 other).
export fn statPathImpl(path_ptr: [*]const u8, path_len: usize, out_kind: *JanusFileType, out_size: *u64, out_perms: *u32, out_mtime: *i64) i32 {
    const path = path_ptr[0..path_len];
    const st = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return 1,
        error.AccessDenied => return 2,
        else => return 3,
    };

    // Kind
    out_kind.* = switch (st.kind) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        .block_device => .block_device,
        .character_device => .char_device,
        .named_pipe => .fifo,
        .unix_domain_socket => .socket,
        else => .unknown,
    };

    // Size
    out_size.* = st.size;

    // Permissions (POSIX only): best-effort; otherwise 0
    if (@hasField(@TypeOf(st), "mode")) {
        out_perms.* = @intCast(@field(st, "mode"));
    } else {
        out_perms.* = 0;
    }

    // Modified time
    if (@hasField(@TypeOf(st), "mtime")) {
        out_mtime.* = @intCast(@field(st, "mtime"));
    } else {
        out_mtime.* = std.time.timestamp();
    }

    return 0;
}

export fn fileInfoImpl(path_ptr: [*]const u8, path_len: usize, allocator_ptr: *anyopaque) i32 {
    _ = allocator_ptr; // TODO: Use Janus allocator

    const path = path_ptr[0..path_len];

    const file = std.fs.cwd().openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => return 1,
        error.AccessDenied => return 2,
        error.IsDir => {
            // Handle directory case
            var dir = std.fs.cwd().openDir(path, .{}) catch return 3;
            defer dir.close();

            const stat = dir.stat() catch return 4;

            // TODO: Create and return JanusFileInfo
            _ = stat;
            return 0;
        },
        else => return 5,
    };
    defer file.close();

    const stat = file.stat() catch return 6;

    // TODO: Create and return JanusFileInfo
    _ = stat;
    return 0;
}

// ===== TIME OPERATIONS =====

export fn getCurrentTime() i64 {
    return std.time.timestamp();
}

// ===== MEMORY OPERATIONS =====

export fn janusAlloc(size: usize, alignment: u8) ?[*]u8 {
    _ = alignment; // TODO: Handle alignment properly

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    const memory = allocator.alloc(u8, size) catch return null;
    return memory.ptr;
}

export fn janusFree(ptr: [*]u8, size: usize) void {
    _ = ptr;
    _ = size;
    // TODO: Implement proper deallocation
    // For now, we rely on the GPA cleanup
}

// ===== PLATFORM DETECTION =====

export fn getPlatformSeparator() u8 {
    return switch (builtin.os.tag) {
        .windows => '\\',
        else => '/',
    };
}

// ===== FILE HANDLE OPERATIONS =====

const FileHandle = struct {
    file: std.fs.File,
};

// Open file for reading; returns null on error
export fn openFileReadImpl(path_ptr: [*]const u8, path_len: usize) ?*anyopaque {
    const path = path_ptr[0..path_len];
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const file = std.fs.cwd().openFile(path, .{}) catch return null;
    const h = allocator.create(FileHandle) catch {
        // best-effort close
        file.close();
        return null;
    };
    h.* = .{ .file = file };
    return @ptrCast(h);
}

// Read file at offset into provided buffer pointer; writes number of bytes to out_len; returns 0 on success, else OS-like code
export fn readFileAtImpl(handle: ?*anyopaque, offset: u64, out_buf: *[*]u8, out_len: *usize, req_len: usize) i32 {
    if (handle == null) return 9; // EBADF
    const h: *FileHandle = @ptrCast(@alignCast(handle.?));
    // Seek and read
    h.file.seekTo(offset) catch |err| switch (err) {
        error.BadFileDescriptor => return 9,
        else => return 5,
    };
    const buf = out_buf.*[0..req_len];
    const n = h.file.read(buf) catch |err| switch (err) {
        error.AccessDenied => return 13,
        error.EndOfStream => {
            out_len.* = 0;
            return 0;
        },
        else => return 5,
    };
    out_len.* = n;
    return 0;
}

// Close file handle
export fn closeFileImpl(handle: ?*anyopaque) void {
    if (handle == null) return;
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const h: *FileHandle = @ptrCast(@alignCast(handle.?));
    h.file.close();
    allocator.destroy(h);
}

// ===== Write operations =====

fn dirnameOf(path: []const u8) []const u8 {
    var i: isize = @as(isize, @intCast(path.len)) - 1;
    while (i >= 0) : (i -= 1) {
        if (path[@intCast(i)] == '/' or path[@intCast(i)] == '\\') {
            if (i == 0) return path[0..1];
            return path[0..@intCast(i)];
        }
    }
    return ".";
}

export fn renamePathImpl(from_ptr: [*]const u8, from_len: usize, to_ptr: [*]const u8, to_len: usize) i32 {
    const from = from_ptr[0..from_len];
    const to = to_ptr[0..to_len];
    std.fs.cwd().rename(from, to) catch |err| switch (err) {
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        error.CrossDeviceLink => return 18,
        else => return 5,
    };
    return 0;
}

export fn writeAtomicImpl(path_ptr: [*]const u8, path_len: usize, data_ptr: [*]const u8, data_len: usize) i32 {
    const path = path_ptr[0..path_len];
    const data = data_ptr[0..data_len];

    // Resolve parent dir and temp name
    const parent = dirnameOf(path);
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();

    var dir = std.fs.cwd().openDir(parent, .{}) catch |err| switch (err) {
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        else => return 5,
    };
    defer dir.close();

    // Generate a unique temp name in parent dir
    var i: usize = 0;
    var tmp_name_buf: [256]u8 = undefined;
    while (i < 1000) : (i += 1) {
        const tmp_name = std.fmt.bufPrint(&tmp_name_buf, ".tmp-{d}-{d}", .{ std.time.milliTimestamp(), i }) catch return 5;
        const tmp_path = std.fs.path.join(allocator, &[_][]const u8{ parent, tmp_name }) catch return 5;
        defer allocator.free(tmp_path);

        // Try exclusive create
        var file = dir.createFile(tmp_name, .{ .exclusive = true }) catch |err| switch (err) {
            error.PathAlreadyExists => continue,
            error.AccessDenied => return 13,
            else => return 5,
        };
        // Write all data
        file.writeAll(data) catch |err| switch (err) {
            error.AccessDenied => { file.close(); return 13; },
            else => { file.close(); return 5; },
        };
        // Sync file contents
        file.sync() catch { file.close(); return 5; };
        file.close();
        // Rename into destination atomically
        dir.rename(tmp_name, std.fs.path.basename(path)) catch |err| switch (err) {
            error.AccessDenied => return 13,
            error.PathAlreadyExists => {
                // Replace semantics: remove then rename
                dir.deleteFile(std.fs.path.basename(path)) catch {};
                dir.rename(tmp_name, std.fs.path.basename(path)) catch |e2| switch (e2) {
                    error.AccessDenied => return 13,
                    else => return 5,
                };
            },
            error.CrossDeviceLink => return 18,
            else => return 5,
        };
        // Sync directory best-effort
        dir.sync() catch {};
        return 0;
    }
    return 5;
}

// Create single-level directory at path; returns 0 on success
export fn createDirImpl(path_ptr: [*]const u8, path_len: usize) i32 {
    const path = path_ptr[0..path_len];
    std.fs.cwd().makeDir(path) catch |err| switch (err) {
        error.PathAlreadyExists => return 17,
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        else => return 5,
    };
    return 0;
}

// Create a file symlink (POSIX). On unsupported platforms, returns ENOSYS (38).
export fn createSymlinkFileImpl(target_ptr: [*]const u8, target_len: usize, link_ptr: [*]const u8, link_len: usize) i32 {
    const target = target_ptr[0..target_len];
    const link = link_ptr[0..link_len];
    std.fs.cwd().symLink(target, link, .{ .is_directory = false }) catch |err| switch (err) {
        error.PathAlreadyExists => return 17,
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        error.OperationNotSupported => return 38,
        else => return 5,
    };
    return 0;
}

// Create a directory symlink (POSIX). On unsupported platforms, returns ENOSYS (38).
export fn createSymlinkDirImpl(target_ptr: [*]const u8, target_len: usize, link_ptr: [*]const u8, link_len: usize) i32 {
    const target = target_ptr[0..target_len];
    const link = link_ptr[0..link_len];
    std.fs.cwd().symLink(target, link, .{ .is_directory = true }) catch |err| switch (err) {
        error.PathAlreadyExists => return 17,
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        error.OperationNotSupported => return 38,
        else => return 5,
    };
    return 0;
}

// Query presence of an environment variable; returns 1 if present, 0 otherwise
export fn hasEnvVarImpl(name_ptr: [*]const u8, name_len: usize) i32 {
    const name = name_ptr[0..name_len];
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const val = std.process.getEnvVarOwned(allocator, name) catch |err| switch (err) {
        error.EnvironmentVariableNotFound => return 0,
        else => return 0,
    };
    allocator.free(val);
    return 1;
}

// Probe symlink creation support in a base directory: returns
// 1 supported, 2 access denied, 3 operation not supported, 0 other
export fn symlinkSupportStatusImpl(base_ptr: [*]const u8, base_len: usize) i32 {
    const base = base_ptr[0..base_len];
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    // Prepare target and link names
    const target_name = "symlink-probe-target.txt";
    const link_name = "symlink-probe-link.txt";
    const target_path = std.fs.path.join(allocator, &[_][]const u8{ base, target_name }) catch return 0;
    const link_path = std.fs.path.join(allocator, &[_][]const u8{ base, link_name }) catch { allocator.free(target_path); return 0; };
    defer allocator.free(target_path);
    defer allocator.free(link_path);

    // Create target file
    var dir = std.fs.cwd().openDir(base, .{}) catch return 0;
    var f = dir.createFile(target_name, .{}) catch { dir.close(); return 2; };
    _ = f.write("x") catch {};
    f.close();

    // Attempt symlink creation
    const rc = std.fs.cwd().symLink(target_path, link_path, .{}) catch |err| switch (err) {
        error.AccessDenied => 2,
        error.OperationNotSupported => 3,
        else => 0,
    };
    if (rc != 0) { dir.deleteFile(target_name) catch {}; dir.close(); return rc; }

    // Cleanup
    dir.deleteFile(link_name) catch {};
    dir.deleteFile(target_name) catch {};
    dir.close();
    return 1;
}

// Rename with cross-device-safe fallback: if EXDEV, copy+fsync+atomic swap then unlink source.
// flags bitfield: 0x1 recursive, 0x2 follow_symlinks, 0x4 replace
export fn renameOrCopyExImpl(from_ptr: [*]const u8, from_len: usize, to_ptr: [*]const u8, to_len: usize, flags: u32) i32 {
    const from = from_ptr[0..from_len];
    const to = to_ptr[0..to_len];
    const recursive = (flags & 1) != 0;
    const follow_symlinks = (flags & 2) != 0;
    const replace = (flags & 4) != 0;
    const preserve_symlinks = (flags & 8) != 0;
    // First try direct rename
    std.fs.cwd().rename(from, to) catch |err| switch (err) {
        error.CrossDeviceLink => {
            return xdevFallback(from, to, recursive, follow_symlinks, replace, preserve_symlinks);
        },
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        else => return 5,
    };
    return 0;
}

fn copyFileTo(src_path: []const u8, dst_dir: std.fs.Dir, dst_name: []const u8) !void {
    var src = try std.fs.cwd().openFile(src_path, .{});
    defer src.close();
    var tmp = try dst_dir.createFile(dst_name, .{ .exclusive = true });
    var buf: [64 * 1024]u8 = undefined;
    defer tmp.close();
    while (true) {
        const n = try src.read(&buf);
        if (n == 0) break;
        try tmp.writeAll(buf[0..n]);
    }
    try tmp.sync();
}

fn xdevFallback(from: []const u8, to: []const u8, recursive: bool, follow_symlinks: bool, replace: bool, preserve_symlinks: bool) i32 {
    // If preserving symlink at top-level, and source is a symlink, create corresponding symlink at destination and remove source
    if (preserve_symlinks) {
        const st0 = std.fs.cwd().statFile(from) catch |e| switch (e) {
            error.FileNotFound => return 2,
            else => null,
        };
        if (st0) |stx| {
            if (stx.kind == .sym_link) {
                // Replace policy
                const parent = dirnameOf(to);
                var dir = std.fs.cwd().openDir(parent, .{}) catch |e4| switch (e4) {
                    error.FileNotFound => return 2,
                    error.AccessDenied => return 13,
                    else => return 5,
                };
                defer dir.close();
                const base = std.fs.path.basename(to);
                if (!replace) {
                    if (dir.statFile(base)) |_| { return 17; } else |se| switch (se) {
                        error.FileNotFound => {},
                        error.AccessDenied => return 13,
                        else => return 5,
                    }
                } else {
                    dir.deleteTree(base) catch {};
                }
                // Read original link text from source's parent dir
                const parent_from = dirnameOf(from);
                var src_dir = std.fs.cwd().openDir(parent_from, .{}) catch return 5;
                defer src_dir.close();
                var lbuf: [4096]u8 = undefined;
                const link_name = std.fs.path.basename(from);
                const try_llen = src_dir.readLink(link_name, &lbuf) catch 0;
                var dyn_target: ?[]u8 = null;
                var gpa0 = std.heap.GeneralPurposeAllocator(.{}){};
                const alloc0 = gpa0.allocator();
                if (try_llen == 0 or try_llen == lbuf.len) {
                    // Attempt dynamic growth
                    var cap: usize = 8192;
                    while (cap <= 1 << 20) : (cap *= 2) {
                        const buf = alloc0.alloc(u8, cap) catch break;
                        const llen2 = src_dir.readLink(link_name, buf) catch {
                            alloc0.free(buf);
                            break;
                        };
                        if (llen2 > 0 and llen2 <= cap) {
                            dyn_target = buf[0..llen2];
                            break;
                        }
                        alloc0.free(buf);
                    }
                }
                const target = if (dyn_target) |dt| dt else lbuf[0..try_llen];
                const rc = std.fs.cwd().symLink(target, to, .{}) catch |err| switch (err) {
                    error.AccessDenied => 13,
                    error.OperationNotSupported => 38,
                    else => 5,
                };
                if (rc != 0) return rc;
                if (dyn_target) |dt| alloc0.free(dt);
                std.fs.cwd().deleteFile(from) catch {};
                return 0;
            }
        }
    }
    // Resolve symlinks if requested for top-level source
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    var from_resolved_opt: ?[]u8 = null;
    if (follow_symlinks) {
        if (std.fs.cwd().realpathAlloc(allocator, from)) |rp| {
            from_resolved_opt = rp;
        } else |e| {}
    }
    const from_use = if (from_resolved_opt) |rp| rp else from;

    // Determine source kind: directory vs file
    var is_dir_src = false;
    var src_dir_opt: ?std.fs.Dir = null;
    if (std.fs.cwd().openDir(from_use, .{ .iterate = true })) |d| {
        src_dir_opt = d;
        is_dir_src = true;
    } else |err| {}

    if (!is_dir_src) {
        const st = std.fs.cwd().statFile(from_use) catch |e2| switch (e2) {
            error.FileNotFound => return 2,
            error.IsDir => return 22,
            else => return 5,
        };
        // File copy fallback
        const parent = dirnameOf(to);
        var dir = std.fs.cwd().openDir(parent, .{ .iterate = true }) catch |e4| switch (e4) {
            error.FileNotFound => return 2,
            error.AccessDenied => return 13,
            else => return 5,
        };
        defer dir.close();
        const base = std.fs.path.basename(to);
        if (!replace) {
            // Check destination existence
            if (dir.statFile(base)) |_| { return 17; } else |se| switch (se) {
                error.FileNotFound => {},
                error.AccessDenied => return 13,
                else => return 5,
            }
        } else {
            dir.deleteFile(base) catch {};
        }
        copyFileTo(from_use, dir, base) catch return 5;
        dir.rename(base, base) catch {};
        dir.sync() catch {};
        std.fs.cwd().deleteFile(from) catch {};
        if (from_resolved_opt) |rp| allocator.free(rp);
        return 0;
    }

    // Directory recursive fallback
    if (!recursive) { if (src_dir_opt) |*sd| sd.close(); return 22; }

    const parent_to = dirnameOf(to);
    var target_parent = std.fs.cwd().openDir(parent_to, .{ .iterate = true }) catch |e| switch (e) {
        error.FileNotFound => return 2,
        error.AccessDenied => return 13,
        else => return 5,
    };
    defer target_parent.close();

    // Create temp dir under parent_to
    var tmp_name_buf: [256]u8 = undefined;
    var i: usize = 0;
    while (i < 1000) : (i += 1) {
        const tmp_name = std.fmt.bufPrint(&tmp_name_buf, ".tmp-xdev-dir-{d}-{d}", .{ std.time.milliTimestamp(), i }) catch return 5;
        target_parent.makeDir(tmp_name) catch |ce| switch (ce) {
            error.PathAlreadyExists => continue,
            else => return 5,
        };
        // Copy tree
        const base = std.fs.path.basename(from);
        // We want destination name = basename(to)
        const dst_name = std.fs.path.basename(to);
        var dst_tmp = target_parent.openDir(tmp_name, .{ .iterate = true }) catch return 5;
        defer dst_tmp.close();
        // Create top-level dst_name inside tmp
        dst_tmp.makeDir(dst_name) catch |e2| switch (e2) { error.PathAlreadyExists => {}, else => return 5 };
        var dst_root = dst_tmp.openDir(dst_name, .{ .iterate = true }) catch return 5;
        defer dst_root.close();

        // Recursively copy contents from 'from' into dst_root
        if (src_dir_opt) |*sd| {
            const from_copy = if (from_resolved_opt) |rp| rp else from;
            const rc = copyDirRecursive(from_copy, &dst_root, follow_symlinks, preserve_symlinks);
            sd.close();
            if (rc != 0) return rc;
        }

        // Atomic swap: rename tmp/tmp_dir/dst_name to final name under parent
        if (!replace) {
            // Refuse if destination already exists
            if (std.fs.cwd().openDir(to, .{ .iterate = true })) |d| { d.close(); return 17; } else |e| switch (e) {
                error.NotDir => return 17,
                error.FileNotFound => {},
                else => return 5,
            }
        } else {
            target_parent.deleteTree(to) catch {};
        }
        // First move dst_name out of tmp into parent as final 'to'
        // Not directly supported; we can rename tmp/<dst_name> to final by path string
        const tmpdst_path = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ parent_to, tmp_name, dst_name }) catch return 5;
        defer std.heap.page_allocator.free(tmpdst_path);
        std.fs.cwd().rename(tmpdst_path, to) catch |re| switch (re) { else => return 5 };
        target_parent.sync() catch {};
        // Remove tmp container
        target_parent.deleteTree(std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ parent_to, tmp_name }) catch return 0) catch {};
        if (from_resolved_opt) |rp| allocator.free(rp);
        return 0;
    }
    return 5;
}

fn copyDirRecursive(src_path: []const u8, dst: *std.fs.Dir, follow_symlinks: bool, preserve_symlinks: bool) i32 {
    // Open src dir
    var sd = std.fs.cwd().openDir(src_path, .{ .iterate = true }) catch return 5;
    defer sd.close();
    var it = sd.iterate();
    while (true) {
        const next = it.next() catch return 5;
        if (next == null) break;
        const e = next.?;
        const name = e.name;
        switch (e.kind) {
            .directory => {
                dst.makeDir(name) catch |e2| switch (e2) { error.PathAlreadyExists => {}, else => return 5 };
                var sub_dst = dst.openDir(name, .{ .iterate = true }) catch return 5;
                defer sub_dst.close();
                const child_src = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ src_path, name }) catch return 5;
                const rc = copyDirRecursive(child_src, &sub_dst, follow_symlinks);
                std.heap.page_allocator.free(child_src);
                if (rc != 0) return rc;
            },
            .file => {
                const full_src = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ src_path, name }) catch return 5;
                const rc = (copyFileTo(full_src, dst.*, name) catch { std.heap.page_allocator.free(full_src); return 5; }, 0);
                std.heap.page_allocator.free(full_src);
                if (rc != 0) return rc;
            },
            .sym_link => {
                if (preserve_symlinks) {
                    // Read link text relative to src_path; grow buffer if needed
                    var sdir = std.fs.cwd().openDir(src_path, .{}) catch return 5;
                    defer sdir.close();
                    var lbuf: [4096]u8 = undefined;
                    const try_len = sdir.readLink(name, &lbuf) catch 0;
                    var gpa1 = std.heap.GeneralPurposeAllocator(.{}){};
                    const alloc1 = gpa1.allocator();
                    var dyn: ?[]u8 = null;
                    if (try_len == 0 or try_len == lbuf.len) {
                        var cap: usize = 8192;
                        while (cap <= 1 << 20) : (cap *= 2) {
                            const buf = alloc1.alloc(u8, cap) catch break;
                            const llen2 = sdir.readLink(name, buf) catch {
                                alloc1.free(buf);
                                break;
                            };
                            if (llen2 > 0 and llen2 <= cap) {
                                dyn = buf[0..llen2];
                                break;
                            }
                            alloc1.free(buf);
                        }
                    }
                    const target = if (dyn) |d| d else lbuf[0..try_len];
                    const rc = (dst.symLink(target, name, .{}) catch |e| switch (e) {
                        error.OperationNotSupported => 38,
                        error.AccessDenied => 13,
                        else => 5,
                    }, 0);
                    if (dyn) |d| alloc1.free(d);
                    if (rc != 0) return rc;
                } else {
                    const full_src = std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ src_path, name }) catch return 5;
                    if (!follow_symlinks) { std.heap.page_allocator.free(full_src); return 22; }
                    // Follow link by attempting file copy or recurse for directory
                    var f = std.fs.cwd().openFile(full_src, .{}) catch {
                        // If not a file, try directory path (recurse)
                        var sub_dst = dst.openDir(name, .{ .iterate = true }) catch {
                            dst.makeDir(name) catch {};
                            dst.openDir(name, .{ .iterate = true }) catch return 5;
                        };
                        defer sub_dst.close();
                        const rc2 = copyDirRecursive(full_src, &sub_dst, follow_symlinks, preserve_symlinks);
                        std.heap.page_allocator.free(full_src);
                        if (rc2 != 0) return rc2;
                        continue;
                    };
                    f.close();
                    const rc3 = (copyFileTo(full_src, dst.*, name) catch { std.heap.page_allocator.free(full_src); return 5; }, 0);
                    std.heap.page_allocator.free(full_src);
                    if (rc3 != 0) return rc3;
                }
            },
            else => {},
        }
    }
    return 0;
}
