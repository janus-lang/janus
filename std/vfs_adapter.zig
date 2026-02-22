// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");

// VFS Adapter for CLI toolchain: routes filesystem ops through an injectable backend.
// Zig 0.16 compat: std.fs.cwd()/File/Dir removed — all physical ops use raw POSIX/Linux syscalls.

pub const FileType = enum { file, directory, symlink, other };

pub const Stat = struct { size: u64, kind: FileType, mtime: i128 };
pub const DirEntry = struct { name: []const u8, kind: FileType };

pub const Vfs = struct {
    readFileAlloc: *const fn (allocator: std.mem.Allocator, path: []const u8, max: usize) anyerror![]u8,
    writeFile: *const fn (path: []const u8, data: []const u8) anyerror!void,
    writeAtomic: *const fn (path: []const u8, data: []const u8) anyerror!void,
    createFileTruncWrite: *const fn (path: []const u8, data: []const u8) anyerror!void,
    makeDir: *const fn (path: []const u8) anyerror!void,
    statFile: *const fn (path: []const u8) anyerror!Stat,
    deleteFile: *const fn (path: []const u8) anyerror!void,
    deleteTree: *const fn (path: []const u8) anyerror!void,
};

// --- Raw syscall helpers ---

fn writeAllToFd(fd: std.posix.fd_t, data: []const u8) !void {
    var offset: usize = 0;
    while (offset < data.len) {
        const rc = std.os.linux.write(fd, data[offset..].ptr, data.len - offset);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) return error.WriteFailed;
        offset += rc;
    }
}

fn statxByPath(path: []const u8) !std.os.linux.Statx {
    var stx: std.os.linux.Statx = undefined;
    // statx requires null-terminated path — copy to stack buffer
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const rc = std.os.linux.statx(
        std.posix.AT.FDCWD,
        @ptrCast(buf[0..path.len :0]),
        0, // flags
        std.os.linux.STATX.BASIC_STATS,
        &stx,
    );
    if (rc != 0) return error.FileNotFound;
    return stx;
}

fn statxModeToKind(mode: u16) FileType {
    const S_IFMT = 0o170000;
    const S_IFREG = 0o100000;
    const S_IFDIR = 0o040000;
    const S_IFLNK = 0o120000;
    const fmt = mode & S_IFMT;
    if (fmt == S_IFREG) return .file;
    if (fmt == S_IFDIR) return .directory;
    if (fmt == S_IFLNK) return .symlink;
    return .other;
}

// --- Physical VFS functions ---

fn physical_readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0);
    defer _ = std.os.linux.close(fd);
    var stx: std.os.linux.Statx = undefined;
    if (std.os.linux.statx(fd, "", 0x1000, std.os.linux.STATX.BASIC_STATS, &stx) != 0)
        return error.FileNotFound;
    const size: usize = @intCast(stx.size);
    if (size > max) return error.FileTooBig;
    const buf = try allocator.alloc(u8, size);
    errdefer allocator.free(buf);
    var total: usize = 0;
    while (total < size) {
        const rc = std.os.linux.read(fd, buf[total..].ptr, size - total);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) break;
        total += rc;
    }
    return buf[0..total];
}

fn physical_writeFile(path: []const u8, data: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    defer _ = std.os.linux.close(fd);
    try writeAllToFd(fd, data);
}

fn physical_writeAtomic(path: []const u8, data: []const u8) !void {
    // TODO: write to temp file then rename for atomicity
    try physical_writeFile(path, data);
}

fn physical_createFileTruncWrite(path: []const u8, data: []const u8) !void {
    try physical_writeFile(path, data);
}

fn physical_makeDir(path: []const u8) !void {
    // mkdirat requires null-terminated path
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const rc = std.os.linux.mkdirat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0o755);
    const signed: isize = @bitCast(rc);
    if (signed < 0) {
        const errno: std.os.linux.E = @enumFromInt(@as(u16, @intCast(-signed)));
        if (errno == .EXIST) return; // already exists — not an error
        return error.MkdirFailed;
    }
}

fn physical_statFile(path: []const u8) !Stat {
    const stx = try statxByPath(path);
    const mtime_sec: i128 = @intCast(stx.mtime.sec);
    const mtime_nsec: i128 = @intCast(stx.mtime.nsec);
    return .{
        .size = stx.size,
        .kind = statxModeToKind(stx.mode),
        .mtime = mtime_sec * 1_000_000_000 + mtime_nsec,
    };
}

fn physical_deleteFile(path: []const u8) !void {
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const rc = std.os.linux.unlinkat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0);
    const signed: isize = @bitCast(rc);
    if (signed < 0) return error.DeleteFailed;
}

fn physical_deleteTree(path: []const u8) !void {
    // Simple recursive delete: for now, just unlink the path.
    // A full recursive implementation needs getdents64 traversal.
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    // Try unlink as file first
    const rc1 = std.os.linux.unlinkat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0);
    if (@as(isize, @bitCast(rc1)) >= 0) return;
    // Try as directory (AT_REMOVEDIR = 0x200)
    const rc2 = std.os.linux.unlinkat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0x200);
    if (@as(isize, @bitCast(rc2)) >= 0) return;
    return error.DeleteTreeFailed;
}

pub fn physical() Vfs {
    return .{
        .readFileAlloc = physical_readFileAlloc,
        .writeFile = physical_writeFile,
        .writeAtomic = physical_writeAtomic,
        .createFileTruncWrite = physical_createFileTruncWrite,
        .makeDir = physical_makeDir,
        .statFile = physical_statFile,
        .deleteFile = physical_deleteFile,
        .deleteTree = physical_deleteTree,
    };
}

// Simple in-memory VFS for tests
pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap([]u8),
    dirs: std.StringHashMap(void),
    file_mtime: std.StringHashMap(i128),
    dir_mtime: std.StringHashMap(i128),
    deterministic: bool = false,
    logical_time: i128 = 0,

    pub fn init(allocator: std.mem.Allocator) MemoryStore {
        return .{
            .allocator = allocator,
            .files = std.StringHashMap([]u8).init(allocator),
            .dirs = std.StringHashMap(void).init(allocator),
            .file_mtime = std.StringHashMap(i128).init(allocator),
            .dir_mtime = std.StringHashMap(i128).init(allocator),
        };
    }

    pub fn deinit(self: *MemoryStore) void {
        var it = self.files.valueIterator();
        while (it.next()) |p| self.allocator.free(p.*);
        self.files.deinit();
        self.dirs.deinit();
        self.file_mtime.deinit();
        self.dir_mtime.deinit();
    }

    fn ensureDir(self: *MemoryStore, path: []const u8) void {
        _ = self.dirs.put(std.mem.dupe(self.allocator, u8, path) catch return, {}) catch {};
        const mt: i128 = if (self.deterministic) blk: {
            self.logical_time += 1;
            break :blk self.logical_time;
        } else @as(i128, @intCast(compat_time.timestamp()));
        _ = self.dir_mtime.put(std.mem.dupe(self.allocator, u8, path) catch return, mt) catch {};
    }
};

fn mem_readFileAlloc(store: *MemoryStore, allocator: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    _ = max;
    if (self_lookup(store, path)) |data| return std.mem.dupe(allocator, u8, data);
    return error.FileNotFound;
}

fn mem_writeFile(store: *MemoryStore, path: []const u8, data: []const u8) !void {
    if (self_lookup(store, path)) |old| {
        store.allocator.free(old);
        _ = store.files.remove(path);
        _ = store.file_mtime.remove(path);
    }
    const dup = try std.mem.dupe(store.allocator, u8, data);
    const key = try std.mem.dupe(store.allocator, u8, path);
    try store.files.put(key, dup);
    const mt: i128 = if (store.deterministic) blk: {
        store.logical_time += 1;
        break :blk store.logical_time;
    } else @as(i128, @intCast(compat_time.timestamp()));
    try store.file_mtime.put(try std.mem.dupe(store.allocator, u8, path), mt);
}

fn mem_writeAtomic(store: *MemoryStore, path: []const u8, data: []const u8) !void {
    try mem_writeFile(store, path, data);
}

fn mem_createFileTruncWrite(store: *MemoryStore, path: []const u8, data: []const u8) !void {
    try mem_writeFile(store, path, data);
}

fn mem_makeDir(store: *MemoryStore, path: []const u8) !void { store.ensureDir(path); }

fn mem_statFile(store: *MemoryStore, path: []const u8) !Stat {
    if (self_lookup(store, path)) |data| {
        const mt = store.file_mtime.get(path);
        const mtime_val: i128 = if (mt) |v| v else 0;
        return .{ .size = data.len, .kind = .file, .mtime = mtime_val };
    }
    if (self_dir(store, path)) {
        const mt = store.dir_mtime.get(path);
        const mtime_val: i128 = if (mt) |v| v else 0;
        return .{ .size = 0, .kind = .directory, .mtime = mtime_val };
    }
    return error.FileNotFound;
}

fn self_lookup(store: *MemoryStore, path: []const u8) ?[]u8 {
    return store.files.get(path);
}

fn self_dir(store: *MemoryStore, path: []const u8) bool {
    return store.dirs.contains(path);
}

fn mem_deleteFile(store: *MemoryStore, path: []const u8) !void {
    if (store.files.get(path)) |p| {
        store.allocator.free(p);
        _ = store.files.remove(path);
        _ = store.file_mtime.remove(path);
    } else return error.FileNotFound;
}

fn mem_deleteTree(store: *MemoryStore, path: []const u8) !void {
    var to_del_files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer to_del_files.deinit(store.allocator);
    var to_del_dirs: std.ArrayListUnmanaged([]const u8) = .empty;
    defer to_del_dirs.deinit(store.allocator);
    var fit = store.files.keyIterator();
    while (fit.next()) |k_ptr| {
        const fpath = k_ptr.*;
        if (std.mem.eql(u8, fpath, path) or (fpath.len > path.len and std.mem.startsWith(u8, fpath, path) and fpath[path.len] == '/')) {
            try to_del_files.append(store.allocator, fpath);
        }
    }
    var dit = store.dirs.keyIterator();
    while (dit.next()) |k_ptr| {
        const dpath = k_ptr.*;
        if (std.mem.eql(u8, dpath, path) or (dpath.len > path.len and std.mem.startsWith(u8, dpath, path) and dpath[path.len] == '/')) {
            try to_del_dirs.append(store.allocator, dpath);
        }
    }
    for (to_del_files.items) |f| {
        _ = store.files.remove(f);
        _ = store.file_mtime.remove(f);
    }
    for (to_del_dirs.items) |d| {
        _ = store.dirs.remove(d);
        _ = store.dir_mtime.remove(d);
    }
}

var g_memory_store: ?*MemoryStore = null;

pub fn memory(store: *MemoryStore) Vfs {
    g_memory_store = store;
    return .{
        .readFileAlloc = struct {
            fn f(a: std.mem.Allocator, p: []const u8, m: usize) anyerror![]u8 {
                return mem_readFileAlloc(store, a, p, m);
            }
        }.f,
        .writeFile = struct {
            fn f(p: []const u8, d: []const u8) anyerror!void {
                return mem_writeFile(store, p, d);
            }
        }.f,
        .writeAtomic = struct {
            fn f(p: []const u8, d: []const u8) anyerror!void {
                return mem_writeAtomic(store, p, d);
            }
        }.f,
        .createFileTruncWrite = struct {
            fn f(p: []const u8, d: []const u8) anyerror!void {
                return mem_createFileTruncWrite(store, p, d);
            }
        }.f,
        .makeDir = struct {
            fn f(p: []const u8) anyerror!void {
                return mem_makeDir(store, p);
            }
        }.f,
        .statFile = struct {
            fn f(p: []const u8) anyerror!Stat {
                return mem_statFile(store, p);
            }
        }.f,
        .deleteFile = struct {
            fn f(p: []const u8) anyerror!void {
                return mem_deleteFile(store, p);
            }
        }.f,
        .deleteTree = struct {
            fn f(p: []const u8) anyerror!void {
                return mem_deleteTree(store, p);
            }
        }.f,
    };
}

var current: Vfs = undefined;
var initialized = false;

pub fn init_default() void {
    if (!initialized) {
        current = physical();
        initialized = true;
    }
}

pub fn set(v: Vfs) void {
    current = v;
    initialized = true;
}

pub fn get() Vfs {
    if (!initialized) init_default();
    return current;
}

// Convenience free functions mirroring common callsites
pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    return try get().readFileAlloc(allocator, path, max);
}

pub fn writeFile(path: []const u8, data: []const u8) !void {
    try get().writeFile(path, data);
}

pub fn createFileTruncWrite(path: []const u8, data: []const u8) !void {
    try get().createFileTruncWrite(path, data);
}

pub fn makeDir(path: []const u8) !void {
    try get().makeDir(path);
}

pub fn statFile(path: []const u8) !Stat {
    return try get().statFile(path);
}

pub fn deleteFile(path: []const u8) !void {
    try get().deleteFile(path);
}

pub fn deleteTree(path: []const u8) !void {
    try get().deleteTree(path);
}

pub fn rename(from: []const u8, to: []const u8) !void {
    try get().rename(from, to);
}

pub fn writeAtomic(path: []const u8, data: []const u8) !void {
    try get().writeAtomic(path, data);
}

// =====================
// Directory Iteration
// =====================

pub const DirIter = struct {
    const Backend = union(enum) {
        physical: struct {
            fd: std.posix.fd_t,
            buf: [4096]u8 = undefined,
            pos: usize = 0,
            end: usize = 0,
            done: bool = false,
        },
        memory: struct { entries: std.ArrayListUnmanaged(DirEntry), index: usize },
    };

    allocator: std.mem.Allocator,
    backend: Backend,
    scratch: std.ArrayListUnmanaged([]u8), // allocated name slices to free on deinit

    pub fn deinit(self: *DirIter) void {
        switch (self.backend) {
            .physical => |*p| {
                _ = std.os.linux.close(p.fd);
            },
            .memory => |*m| {
                m.entries.deinit(self.allocator);
            },
        }
        for (self.scratch.items) |buf| self.allocator.free(buf);
        self.scratch.deinit(self.allocator);
    }

    pub fn next(self: *DirIter) !?DirEntry {
        switch (self.backend) {
            .physical => |*p| {
                while (true) {
                    if (p.pos >= p.end) {
                        if (p.done) return null;
                        const rc = std.os.linux.getdents64(p.fd, &p.buf, p.buf.len);
                        if (@as(isize, @bitCast(rc)) <= 0) {
                            p.done = true;
                            return null;
                        }
                        p.pos = 0;
                        p.end = rc;
                    }
                    // Parse linux_dirent64
                    const dirent: *align(1) const LinuxDirent64 = @ptrCast(&p.buf[p.pos]);
                    p.pos += dirent.d_reclen;

                    // Skip . and ..
                    const raw_name = std.mem.sliceTo(&dirent.d_name, 0);
                    if (std.mem.eql(u8, raw_name, ".") or std.mem.eql(u8, raw_name, ".."))
                        continue;

                    const name_dup = try self.allocator.dupe(u8, raw_name);
                    try self.scratch.append(self.allocator, name_dup);
                    const kind: FileType = switch (dirent.d_type) {
                        4 => .directory, // DT_DIR
                        8 => .file, // DT_REG
                        10 => .symlink, // DT_LNK
                        else => .other,
                    };
                    return DirEntry{ .name = name_dup, .kind = kind };
                }
            },
            .memory => |*m| {
                if (m.index >= m.entries.items.len) return null;
                defer m.index += 1;
                return m.entries.items[m.index];
            },
        }
    }
};

const LinuxDirent64 = extern struct {
    d_ino: u64,
    d_off: i64,
    d_reclen: u16,
    d_type: u8,
    d_name: [256]u8,
};

fn pathDirname(path: []const u8) []const u8 {
    if (path.len == 0) return path;
    var i: isize = @as(isize, @intCast(path.len)) - 1;
    while (i >= 0) : (i -= 1) {
        if (path[@as(usize, @intCast(i))] == '/') {
            if (i == 0) return path[0..1];
            return path[0..@as(usize, @intCast(i))];
        }
    }
    return ".";
}

fn pathBasename(path: []const u8) []const u8 {
    var i: isize = @as(isize, @intCast(path.len)) - 1;
    var start: usize = 0;
    while (i >= 0) : (i -= 1) {
        if (path[@as(usize, @intCast(i))] == '/') {
            start = @as(usize, @intCast(i)) + 1;
            break;
        }
    }
    return path[start..];
}

pub fn openDirIter(allocator: std.mem.Allocator, path: []const u8) !DirIter {
    if (!initialized) init_default();
    return try openDirIter_impl(allocator, path);
}

fn openDirIter_impl(allocator: std.mem.Allocator, path: []const u8) !DirIter {
    if (@intFromPtr(current.readFileAlloc) == @intFromPtr(&physical_readFileAlloc)) {
        // Physical backend: open directory fd and use getdents64
        const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{
            .ACCMODE = .RDONLY,
            .DIRECTORY = true,
        }, 0) catch |e| switch (e) {
            error.FileNotFound, error.NotDir => {
                return DirIter{
                    .allocator = allocator,
                    .backend = .{ .memory = .{ .entries = .empty, .index = 0 } },
                    .scratch = .empty,
                };
            },
            else => return e,
        };
        return DirIter{
            .allocator = allocator,
            .backend = .{ .physical = .{ .fd = fd } },
            .scratch = .empty,
        };
    }
    // Memory backend: list entries from active MemoryStore
    var entries: std.ArrayListUnmanaged(DirEntry) = .empty;
    var scratch: std.ArrayListUnmanaged([]u8) = .empty;
    if (g_memory_store) |store| {
        var seen = std.StringHashMap(void).init(allocator);
        defer seen.deinit();
        var dit = store.dirs.keyIterator();
        while (dit.next()) |k_ptr| {
            const dpath = k_ptr.*;
            if (std.mem.eql(u8, dpath, path)) continue;
            if (std.mem.eql(u8, pathDirname(dpath), path)) {
                const name = try allocator.dupe(u8, pathBasename(dpath));
                try scratch.append(allocator, name);
                if (!seen.contains(name)) {
                    try seen.put(name, {});
                    try entries.append(allocator, .{ .name = name, .kind = .directory });
                }
            }
        }
        var fit = store.files.keyIterator();
        while (fit.next()) |k_ptr| {
            const fpath = k_ptr.*;
            if (std.mem.eql(u8, pathDirname(fpath), path)) {
                const name = try allocator.dupe(u8, pathBasename(fpath));
                try scratch.append(allocator, name);
                if (!seen.contains(name)) {
                    try seen.put(name, {});
                    try entries.append(allocator, .{ .name = name, .kind = .file });
                }
            }
        }
    }
    return DirIter{
        .allocator = allocator,
        .backend = .{ .memory = .{ .entries = entries, .index = 0 } },
        .scratch = scratch,
    };
}
