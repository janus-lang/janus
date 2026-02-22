// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// VFS Adapter for CLI toolchain: routes filesystem ops through an injectable backend.

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

fn mapKind(k: std.fs.File.Kind) FileType {
    return switch (k) {
        .file => .file,
        .directory => .directory,
        .sym_link => .symlink,
        else => .other,
    };
}

fn physical_readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max: usize) ![]u8 {
    return try std.fs.cwd().readFileAlloc(allocator, path, max);
}

fn physical_writeFile(path: []const u8, data: []const u8) !void {
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
}

fn physical_writeAtomic(path: []const u8, data: []const u8) !void {
    try std.fs.cwd().writeFile(.{ .sub_path = path, .data = data });
}

fn physical_createFileTruncWrite(path: []const u8, data: []const u8) !void {
    var f = try std.fs.cwd().createFile(path, .{ .truncate = true });
    defer f.close();
    try f.writeAll(data);
}

fn physical_makeDir(path: []const u8) !void {
    try std.fs.cwd().makeDir(path);
}

fn physical_statFile(path: []const u8) !Stat {
    const st = try std.fs.cwd().statFile(path);
    var mt: i128 = 0;
    if (@hasField(@TypeOf(st), "mtime")) {
        mt = @as(i128, @intCast(@field(st, "mtime")));
    }
    return .{ .size = st.size, .kind = mapKind(st.kind), .mtime = mt };
}

pub fn physical() Vfs {
    return .{
        .readFileAlloc = physical_readFileAlloc,
        .writeFile = physical_writeFile,
        .writeAtomic = physical_writeAtomic,
        .createFileTruncWrite = physical_createFileTruncWrite,
        .makeDir = physical_makeDir,
        .statFile = physical_statFile,
        .deleteFile = struct { fn f(p: []const u8) anyerror!void { try std.fs.cwd().deleteFile(p); } }.f,
        .deleteTree = struct { fn f(p: []const u8) anyerror!void { try std.fs.cwd().deleteTree(p); } }.f,
    };
}

// Simple in-memory VFS for tests
pub const MemoryStore = struct {
    allocator: std.mem.Allocator,
    files: std.StringHashMap([]u8),
    dirs: std.StringHashMap(void),
    file_mtime: std.StringHashMap(i128),
    dir_mtime: std.StringHashMap(i128),

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
        const mt: i128 = if (self.deterministic) blk: { self.logical_time += 1; break :blk self.logical_time; } else @as(i128, @intCast(std.time.timestamp()));
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
    const mt: i128 = if (store.deterministic) blk: { store.logical_time += 1; break :blk store.logical_time; } else @as(i128, @intCast(std.time.timestamp()));
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
        const mt = store.file_mtime.get(path) orelse null;
        const mtime_val: i128 = if (mt) |p| p.* else 0;
        return .{ .size = data.len, .kind = .file, .mtime = mtime_val };
    }
    if (self_dir(store, path)) {
        const mt = store.dir_mtime.get(path) orelse null;
        const mtime_val: i128 = if (mt) |p| p.* else 0;
        return .{ .size = 0, .kind = .directory, .mtime = mtime_val };
    }
    return error.FileNotFound;
}

fn self_lookup(store: *MemoryStore, path: []const u8) ?[]u8 {
    if (store.files.get(path)) |p| {
        return p.*;
    } else {
        return null;
    }
}

fn self_dir(store: *MemoryStore, path: []const u8) bool {
    return store.dirs.contains(path);
}

fn mem_deleteFile(store: *MemoryStore, path: []const u8) !void {
    if (store.files.get(path)) |p| {
        store.allocator.free(p.*);
        _ = store.files.remove(path);
        _ = store.file_mtime.remove(path);
    } else return error.FileNotFound;
}

fn mem_deleteTree(store: *MemoryStore, path: []const u8) !void {
    var to_del_files: std.ArrayList([]const u8) = .empty;
    defer to_del_files.deinit();
    var to_del_dirs: std.ArrayList([]const u8) = .empty;
    defer to_del_dirs.deinit();
    var fit = store.files.keyIterator();
    while (fit.next()) |k_ptr| {
        const fpath = k_ptr.*;
        if (std.mem.eql(u8, fpath, path) or (fpath.len > path.len and std.mem.startsWith(u8, fpath, path) and fpath[path.len] == '/')) {
            try to_del_files.append(fpath);
        }
    }
    var dit = store.dirs.keyIterator();
    while (dit.next()) |k_ptr| {
        const dpath = k_ptr.*;
        if (std.mem.eql(u8, dpath, path) or (dpath.len > path.len and std.mem.startsWith(u8, dpath, path) and dpath[path.len] == '/')) {
            try to_del_dirs.append(dpath);
        }
    }
    for (to_del_files.items) |f| { _ = store.files.remove(f); _ = store.file_mtime.remove(f); }
    for (to_del_dirs.items) |d| { _ = store.dirs.remove(d); _ = store.dir_mtime.remove(d); }
}

var g_memory_store: ?*MemoryStore = null;

pub fn memory(store: *MemoryStore) Vfs {
    // record active memory store for iterator support
    g_memory_store = store;
    return .{
        .readFileAlloc = struct { fn f(a: std.mem.Allocator, p: []const u8, m: usize) anyerror![]u8 { return mem_readFileAlloc(store, a, p, m); } }.f,
        .writeFile = struct { fn f(p: []const u8, d: []const u8) anyerror!void { return mem_writeFile(store, p, d); } }.f,
        .writeAtomic = struct { fn f(p: []const u8, d: []const u8) anyerror!void { return mem_writeAtomic(store, p, d); } }.f,
        .createFileTruncWrite = struct { fn f(p: []const u8, d: []const u8) anyerror!void { return mem_createFileTruncWrite(store, p, d); } }.f,
        .makeDir = struct { fn f(p: []const u8) anyerror!void { return mem_makeDir(store, p); } }.f,
        .statFile = struct { fn f(p: []const u8) anyerror!Stat { return mem_statFile(store, p); } }.f,
        .deleteFile = struct { fn f(p: []const u8) anyerror!void { return mem_deleteFile(store, p); } }.f,
        .deleteTree = struct { fn f(p: []const u8) anyerror!void { return mem_deleteTree(store, p); } }.f,
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

pub fn rename(from: []const u8, to: []const u8) !void { try get().rename(from, to); }
pub fn writeAtomic(path: []const u8, data: []const u8) !void { try get().writeAtomic(path, data); }

// =====================
// Directory Iteration
// =====================

pub const DirIter = struct {
    const Backend = union(enum) {
        physical: struct { dir: std.fs.Dir, it: std.fs.Dir.Iterator },
        memory: struct { entries: std.ArrayList(DirEntry), index: usize },
    };

    allocator: std.mem.Allocator,
    backend: Backend,
    scratch: std.ArrayList([]u8), // allocated name slices to free on deinit

    pub fn deinit(self: *DirIter) void {
        // Close resources
        switch (self.backend) {
            .physical => |*p| { p.dir.close(); },
            .memory => |*m| { m.entries.deinit(self.allocator); },
        }
        // Free scratch names
        for (self.scratch.items) |buf| self.allocator.free(buf);
        self.scratch.deinit(self.allocator);
    }

    pub fn next(self: *DirIter) !?DirEntry {
        switch (self.backend) {
            .physical => |*p| {
                const ent = try p.it.next();
                if (ent == null) return null;
                const name_dup = try self.allocator.dupe(u8, ent.?.name);
                try self.scratch.append(self.allocator, name_dup);
                return DirEntry{ .name = name_dup, .kind = mapKind(ent.?.kind) };
            },
            .memory => |*m| {
                if (m.index >= m.entries.items.len) return null;
                defer m.index += 1;
                return m.entries.items[m.index];
            },
        }
    }
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
        if (path[@as(usize, @intCast(i))] == '/') { start = @as(usize, @intCast(i)) + 1; break; }
    }
    return path[start..];
}

pub fn openDirIter(allocator: std.mem.Allocator, path: []const u8) !DirIter {
    if (!initialized) init_default();
    // Detect if current is physical via function pointers equality is awkward; assume physical if current.readFileAlloc == physical_readFileAlloc
    // Instead, try physical open and fallback to memory if it fails and memory contains entries.
    // Branch on available storage: if using MemoryStore (current == memory), we rely on the following helper.
    return try openDirIter_impl(allocator, path);
}

fn openDirIter_impl(allocator: std.mem.Allocator, path: []const u8) !DirIter {
    // Heuristic: attempt physical open; if fails with NotDir/FileNotFound, still build empty iterator
    if (current.readFileAlloc == physical_readFileAlloc) {
        var dir = std.fs.cwd().openDir(path, .{ .iterate = true }) catch |e| switch (e) {
            error.FileNotFound, error.NotDir => {
                const it_mem = std.ArrayList(DirEntry).initCapacity(allocator, 0) catch unreachable;
                const scratch = std.ArrayList([]u8).initCapacity(allocator, 0) catch unreachable;
                return DirIter{ .allocator = allocator, .backend = .{ .memory = .{ .entries = it_mem, .index = 0 } }, .scratch = scratch };
            },
            else => return e,
        };
        const scratch = std.ArrayList([]u8).initCapacity(allocator, 0) catch unreachable;
        return DirIter{ .allocator = allocator, .backend = .{ .physical = .{ .dir = dir, .it = dir.iterate() } }, .scratch = scratch };
    }
    // Memory backend: list entries from active MemoryStore
    var entries = try std.ArrayList(DirEntry).initCapacity(allocator, 0);
    var scratch = try std.ArrayList([]u8).initCapacity(allocator, 0);
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
    return DirIter{ .allocator = allocator, .backend = .{ .memory = .{ .entries = entries, .index = 0 } }, .scratch = scratch };
}
