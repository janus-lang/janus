/// Zig 0.16 compat: filesystem functions.
/// Replaces std.fs.cwd(), std.fs.File, std.fs.Dir which were moved to std.Io.
/// Uses raw POSIX/Linux syscalls for portability during migration.
const std = @import("std");

// --- File descriptor operations ---

pub fn readFileAlloc(allocator: std.mem.Allocator, path: []const u8, max_bytes: usize) ![]u8 {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0);
    defer _ = std.os.linux.close(fd);
    var stx: std.os.linux.Statx = undefined;
    if (std.os.linux.statx(fd, "", 0x1000, std.os.linux.STATX.BASIC_STATS, &stx) != 0)
        return error.FileNotFound;
    const size: usize = @intCast(stx.size);
    if (size > max_bytes) return error.FileTooBig;
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

pub fn writeFile(path: []const u8, data: []const u8) !void {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    defer _ = std.os.linux.close(fd);
    try writeAllFd(fd, data);
}

pub fn createFile(path: []const u8, _: anytype) !FdFile {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .WRONLY,
        .CREAT = true,
        .TRUNC = true,
    }, 0o644);
    return FdFile{ .fd = fd };
}

pub fn deleteFile(path: []const u8) !void {
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const rc = std.os.linux.unlinkat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0);
    if (@as(isize, @bitCast(rc)) < 0) return error.DeleteFailed;
}

pub fn deleteTree(path: []const u8) !void {
    // Simple implementation: try unlink as file, then as directory
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const sentinel: [*:0]const u8 = @ptrCast(buf[0..path.len :0]);
    // Try as file
    var rc = std.os.linux.unlinkat(std.posix.AT.FDCWD, sentinel, 0);
    if (@as(isize, @bitCast(rc)) >= 0) return;
    // Try as empty directory (AT_REMOVEDIR = 0x200)
    rc = std.os.linux.unlinkat(std.posix.AT.FDCWD, sentinel, 0x200);
    if (@as(isize, @bitCast(rc)) >= 0) return;
    // Ignore errors for now — full recursive delete needs getdents traversal
}

pub fn makeDir(path: []const u8) !void {
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    const rc = std.os.linux.mkdirat(std.posix.AT.FDCWD, @ptrCast(buf[0..path.len :0]), 0o755);
    const signed: isize = @bitCast(rc);
    if (signed < 0) {
        const errno: std.os.linux.E = @enumFromInt(@as(u16, @intCast(-signed)));
        if (errno == .EXIST) return;
        return error.MkdirFailed;
    }
}

pub const StatResult = struct {
    size: u64,
    mode: u16,
    mtime: i128,

    pub fn isFile(self: StatResult) bool {
        return (self.mode & 0o170000) == 0o100000;
    }
    pub fn isDir(self: StatResult) bool {
        return (self.mode & 0o170000) == 0o040000;
    }
};

pub fn statFile(path: []const u8) !StatResult {
    var buf: [4096]u8 = undefined;
    if (path.len >= buf.len) return error.NameTooLong;
    @memcpy(buf[0..path.len], path);
    buf[path.len] = 0;
    var stx: std.os.linux.Statx = undefined;
    const rc = std.os.linux.statx(
        std.posix.AT.FDCWD,
        @ptrCast(buf[0..path.len :0]),
        0,
        std.os.linux.STATX.BASIC_STATS,
        &stx,
    );
    if (rc != 0) return error.FileNotFound;
    const mtime_sec: i128 = @intCast(stx.mtime.sec);
    const mtime_nsec: i128 = @intCast(stx.mtime.nsec);
    return .{
        .size = stx.size,
        .mode = stx.mode,
        .mtime = mtime_sec * 1_000_000_000 + mtime_nsec,
    };
}

pub fn realpathAlloc(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    // Use /proc/self/fd trick: open the path, then readlink from /proc/self/fd/N
    const fd = std.posix.openat(std.posix.AT.FDCWD, path, .{}, 0) catch return error.FileNotFound;
    defer _ = std.os.linux.close(fd);
    var proc_buf: [64]u8 = undefined;
    const proc_path = std.fmt.bufPrint(&proc_buf, "/proc/self/fd/{d}", .{fd}) catch return error.FileNotFound;
    var link_buf: [4096]u8 = undefined;
    // readlinkat needs null-terminated path
    var proc_z: [64]u8 = undefined;
    @memcpy(proc_z[0..proc_path.len], proc_path);
    proc_z[proc_path.len] = 0;
    const rc = std.os.linux.readlinkat(
        std.posix.AT.FDCWD,
        @ptrCast(proc_z[0..proc_path.len :0]),
        &link_buf,
        link_buf.len,
    );
    const signed: isize = @bitCast(rc);
    if (signed <= 0) return error.FileNotFound;
    const resolved = link_buf[0..rc];
    return allocator.dupe(u8, resolved);
}

// --- FdFile: minimal replacement for std.fs.File ---

pub const FdFile = struct {
    fd: std.posix.fd_t,

    pub fn close(self: FdFile) void {
        _ = std.os.linux.close(self.fd);
    }

    pub fn writeAll(self: FdFile, data: []const u8) !void {
        try writeAllFd(self.fd, data);
    }

    pub fn read(self: FdFile, buf: []u8) !usize {
        const rc = std.os.linux.read(self.fd, buf.ptr, buf.len);
        const signed: isize = @bitCast(rc);
        if (signed < 0) return error.ReadFailed;
        return rc;
    }
};

// --- Directory operations ---

pub const DirHandle = struct {
    fd: std.posix.fd_t,

    pub fn close(self: *DirHandle) void {
        _ = std.os.linux.close(self.fd);
    }

    pub fn iterate(self: DirHandle) DirIterator {
        return DirIterator{ .fd = self.fd };
    }
};

pub const DirIterator = struct {
    fd: std.posix.fd_t,
    buf: [4096]u8 = undefined,
    pos: usize = 0,
    end: usize = 0,
    done: bool = false,

    pub const Entry = struct {
        name: []const u8,
        kind: Kind,
    };

    pub const Kind = enum { file, directory, sym_link, unknown };

    pub fn next(self: *DirIterator) !?Entry {
        while (true) {
            if (self.pos >= self.end) {
                if (self.done) return null;
                const rc = std.os.linux.getdents64(self.fd, &self.buf, self.buf.len);
                if (@as(isize, @bitCast(rc)) <= 0) {
                    self.done = true;
                    return null;
                }
                self.pos = 0;
                self.end = rc;
            }
            const dirent: *align(1) const LinuxDirent64 = @ptrCast(&self.buf[self.pos]);
            self.pos += dirent.d_reclen;
            const raw_name = std.mem.sliceTo(&dirent.d_name, 0);
            if (std.mem.eql(u8, raw_name, ".") or std.mem.eql(u8, raw_name, ".."))
                continue;
            const kind: Kind = switch (dirent.d_type) {
                4 => .directory,
                8 => .file,
                10 => .sym_link,
                else => .unknown,
            };
            return Entry{ .name = raw_name, .kind = kind };
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

pub fn openDir(path: []const u8) !DirHandle {
    const fd = try std.posix.openat(std.posix.AT.FDCWD, path, .{
        .ACCMODE = .RDONLY,
        .DIRECTORY = true,
    }, 0);
    return DirHandle{ .fd = fd };
}

// --- Stdio file descriptors ---

pub fn stdout() FdFile {
    return FdFile{ .fd = 1 };
}

pub fn stderr() FdFile {
    return FdFile{ .fd = 2 };
}

pub fn stdin() FdFile {
    return FdFile{ .fd = 0 };
}

// --- Internal helpers ---

fn writeAllFd(fd: std.posix.fd_t, data: []const u8) !void {
    var offset: usize = 0;
    while (offset < data.len) {
        const rc = std.os.linux.write(fd, data[offset..].ptr, data.len - offset);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) return error.WriteFailed;
        offset += rc;
    }
}
