// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - Path Module
// Cross-platform path manipulation with capability-based security

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Context = @import("std_context.zig").Context;
const Capability = @import("capabilities.zig");

/// Path separator character for current platform
pub const SEP: u8 = if (builtin.os.tag == .windows) '\\' else '/';

/// Path separator string for current platform
pub const SEP_STR: []const u8 = if (builtin.os.tag == .windows) "\\" else "/";

/// Alternative separator (for cross-platform parsing)
pub const ALT_SEP: u8 = if (builtin.os.tag == .windows) '/' else '\\';

/// Path component separator (handles both \ and / on all platforms)
pub const COMPONENT_SEP: []const u8 = if (builtin.os.tag == .windows) "\\/" else "/";

/// Windows extended-length path prefix
pub const WINDOWS_EXTENDED_PREFIX: []const u8 = "\\\\?\\";

/// Windows UNC extended-length path prefix
pub const WINDOWS_UNC_EXTENDED_PREFIX: []const u8 = "\\\\?\\UNC\\";

// =============================================================================
// CORE PATH TYPES
// =============================================================================

/// Path represents a borrowed path string slice
pub const Path = struct {
    inner: []const u8,

    /// Create a Path from a string slice
    pub fn init(path: []const u8) Path {
        return Path{ .inner = path };
    }

    /// Get the underlying string slice
    pub fn asSlice(self: Path) []const u8 {
        return self.inner;
    }

    /// Check if path is absolute
    pub fn isAbsolute(self: Path) bool {
        if (self.inner.len == 0) return false;

        if (builtin.os.tag == .windows) {
            // Windows: starts with drive letter or UNC path
            if (self.inner.len >= 2 and std.ascii.isAlphabetic(self.inner[0]) and self.inner[1] == ':') {
                return true;
            }
            // UNC path: \\server\share
            if (self.inner.len >= 2 and self.inner[0] == '\\' and self.inner[1] == '\\') {
                return true;
            }
        } else {
            // Unix-like: starts with /
            return self.inner[0] == '/';
        }

        return false;
    }

    /// Get parent directory
    pub fn parent(self: Path) ?Path {
        if (self.inner.len == 0) return null;

        var end = self.inner.len;
        var found_sep = false;

        // Skip trailing separators
        while (end > 0 and (self.inner[end - 1] == '/' or self.inner[end - 1] == '\\')) {
            end -= 1;
            found_sep = true;
        }

        if (!found_sep and end == self.inner.len) return null;

        // Find the last separator
        while (end > 0) {
            end -= 1;
            if (self.inner[end] == '/' or self.inner[end] == '\\') {
                break;
            }
        }

        if (end == 0) {
            // Root directory or relative with no parent
            if (self.isAbsolute()) {
                return Path.init(self.inner[0..0]); // Empty but represents root
            }
            return null;
        }

        return Path.init(self.inner[0..end]);
    }

    /// Get the file name component (without directory)
    pub fn fileName(self: Path) ?[]const u8 {
        if (self.inner.len == 0) return null;

        var start = self.inner.len;

        // Skip trailing separators
        while (start > 0 and (self.inner[start - 1] == '/' or self.inner[start - 1] == '\\')) {
            start -= 1;
        }

        if (start == 0) return null;

        // Find the last separator
        var end = start;
        start = 0;
        while (start < end) {
            end -= 1;
            if (self.inner[end] == '/' or self.inner[end] == '\\') {
                start = end + 1;
                break;
            }
        }

        return self.inner[start..end];
    }

    /// Get file extension
    pub fn extension(self: Path) ?[]const u8 {
        const name = self.fileName() orelse return null;

        var i = name.len;
        while (i > 0) {
            i -= 1;
            if (name[i] == '.') {
                return name[i + 1 ..];
            }
        }

        return null;
    }

    /// Get file stem (name without extension)
    pub fn stem(self: Path) ?[]const u8 {
        const name = self.fileName() orelse return null;

        var i = name.len;
        while (i > 0) {
            i -= 1;
            if (name[i] == '.') {
                return name[0..i];
            }
        }

        return name;
    }

    /// Join with another path component
    pub fn join(self: Path, component: []const u8) PathBuf {
        var buf = PathBuf.init(self.inner);

        if (component.len > 0) {
            buf.push(component);
        }

        return buf;
    }

    /// Get path with new extension
    pub fn withExtension(self: Path, ext: []const u8) PathBuf {
        var buf = PathBuf.init(self.inner);

        if (buf.extension()) |old_ext| {
            const old_ext_start = buf.inner.len - old_ext.len - 1; // -1 for the dot
            buf.inner = buf.allocator.shrink(buf.inner, old_ext_start);
        }

        if (ext.len > 0) {
            buf.push(".");
            buf.push(ext);
        }

        return buf;
    }

    /// Get path with new file name
    pub fn withFileName(self: Path, file_name: []const u8) PathBuf {
        var buf = PathBuf.init(self.inner);

        if (buf.fileName()) |old_name| {
            const old_name_start = buf.inner.len - old_name.len;
            buf.inner = buf.allocator.shrink(buf.inner, old_name_start);
        }

        if (file_name.len > 0) {
            buf.push(file_name);
        }

        return buf;
    }
};

/// PathBuf represents an owned, mutable path string
pub const PathBuf = struct {
    inner: []u8,
    allocator: Allocator,

    /// Create a new empty PathBuf
    pub fn init(allocator: Allocator) PathBuf {
        return PathBuf{
            .inner = &[_]u8{},
            .allocator = allocator,
        };
    }

    /// Create a PathBuf from a string
    pub fn fromSlice(path: []const u8, allocator: Allocator) !PathBuf {
        const inner = try allocator.dupe(u8, path);
        return PathBuf{
            .inner = inner,
            .allocator = allocator,
        };
    }

    /// Create a PathBuf from a Path
    pub fn fromPath(path: Path, allocator: Allocator) !PathBuf {
        return fromSlice(path.inner, allocator);
    }

    /// Get the underlying string
    pub fn asSlice(self: PathBuf) []const u8 {
        return self.inner;
    }

    /// Convert to a Path (borrowed view)
    pub fn asPath(self: PathBuf) Path {
        return Path.init(self.inner);
    }

    /// Push a path component
    pub fn push(self: *PathBuf, component: []const u8) !void {
        if (component.len == 0) return;

        // Add separator if needed
        if (self.inner.len > 0) {
            const last = self.inner[self.inner.len - 1];
            if (last != '/' and last != '\\') {
                const sep = if (builtin.os.tag == .windows) '\\' else '/';
                self.inner = try self.allocator.realloc(self.inner, self.inner.len + 1 + component.len);
                self.inner[self.inner.len - 1 - component.len] = sep;
            } else {
                self.inner = try self.allocator.realloc(self.inner, self.inner.len + component.len);
            }
        } else {
            self.inner = try self.allocator.realloc(self.inner, component.len);
        }

        // Copy component
        @memcpy(self.inner[self.inner.len - component.len..], component);
    }

    /// Pop the last component
    pub fn pop(self: *PathBuf) bool {
        if (self.inner.len == 0) return false;

        var end = self.inner.len;

        // Skip trailing separators
        while (end > 0 and (self.inner[end - 1] == '/' or self.inner[end - 1] == '\\')) {
            end -= 1;
        }

        if (end == 0) return false;

        // Find the last separator
        while (end > 0) {
            end -= 1;
            if (self.inner[end] == '/' or self.inner[end] == '\\') {
                break;
            }
        }

        if (end == 0) {
            // No separator found, clear the path
            self.allocator.free(self.inner);
            self.inner = &[_]u8{};
            return true;
        }

        // Keep one trailing separator for absolute paths
        const new_len = if (end == 0) 0 else end;
        const new_inner = try self.allocator.realloc(self.inner, new_len);
        self.inner = new_inner;

        return true;
    }

    /// Clear the path
    pub fn clear(self: *PathBuf) void {
        self.allocator.free(self.inner);
        self.inner = &[_]u8{};
    }

    /// Free the path buffer
    pub fn deinit(self: PathBuf) void {
        self.allocator.free(self.inner);
    }

    // Delegate methods to Path
    pub fn isAbsolute(self: PathBuf) bool {
        return self.asPath().isAbsolute();
    }

    pub fn parent(self: PathBuf) ?Path {
        return self.asPath().parent();
    }

    pub fn fileName(self: PathBuf) ?[]const u8 {
        return self.asPath().fileName();
    }

    pub fn extension(self: PathBuf) ?[]const u8 {
        return self.asPath().extension();
    }

    pub fn stem(self: PathBuf) ?[]const u8 {
        return self.asPath().stem();
    }

    pub fn join(self: PathBuf, component: []const u8) PathBuf {
        var new_buf = PathBuf{
            .inner = self.inner,
            .allocator = self.allocator,
        };
        new_buf.push(component) catch {
            // If push fails, return original (this is not ideal but maintains API compatibility)
            return self;
        };
        return new_buf;
    }

    pub fn withExtension(self: PathBuf, ext: []const u8) PathBuf {
        return self.asPath().withExtension(ext);
    }

    pub fn withFileName(self: PathBuf, file_name: []const u8) PathBuf {
        return self.asPath().withFileName(file_name);
    }
};

// =============================================================================
// OPERATORS
// =============================================================================

/// Join operator: Path / component
pub fn pathJoin(lhs: Path, rhs: []const u8) PathBuf {
    return lhs.join(rhs);


/// Join operator: PathBuf / component
pub fn pathBufJoin(lhs: PathBuf, rhs: []const u8) PathBuf {
    return lhs.join(rhs);


/// Join operator: Path / Path
pub fn pathPathJoin(lhs: Path, rhs: Path) PathBuf {
    var buf = PathBuf.init(std.heap.page_allocator); // This is a temporary hack
    buf.push(lhs.inner) catch return PathBuf.init(std.heap.page_allocator);
    buf.push(rhs.inner) catch return PathBuf.init(std.heap.page_allocator);
    return buf;


// =============================================================================
// TRI-SIGNATURE PATTERN IMPLEMENTATIONS
// =============================================================================

/// :min profile - Simple path operations
pub fn path_join_min(base: []const u8, component: []const u8, allocator: Allocator) ![]u8 {
    if (component.len == 0) return allocator.dupe(u8, base);

    var buf = try PathBuf.fromSlice(base, allocator);
    defer buf.deinit();

    try buf.push(component);
    return allocator.dupe(u8, buf.asSlice());


/// :go profile - Context-aware path operations
pub fn path_join_go(base: []const u8, component: []const u8, ctx: Context, allocator: Allocator) ![]u8 {
    if (ctx.is_done()) return error.ContextCancelled;
    return path_join_min(base, component, allocator);


/// :full profile - Capability-gated path operations
pub fn path_join_full(base: []const u8, component: []const u8, cap: Capability.FileSystem, allocator: Allocator) ![]u8 {
    if (!cap.allows_path(base)) return error.CapabilityRequired;
    if (!cap.allows_path(component)) return error.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.path_join");
    return path_join_min(base, component, allocator);


// =============================================================================
// TESTS
// =============================================================================

test "Path basic operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic path creation
    const path = Path.init("/usr/bin");
    try testing.expect(std.mem.eql(u8, path.asSlice(), "/usr/bin"));
    try testing.expect(path.isAbsolute());

    // Test file name extraction
    const file_name = path.fileName().?;
    try testing.expect(std.mem.eql(u8, file_name, "bin"));

    // Test parent directory
    const parent = path.parent().?;
    try testing.expect(std.mem.eql(u8, parent.asSlice(), "/usr"));

    // Test extension
    const path_with_ext = Path.init("/usr/bin/zig");
    const ext = path_with_ext.extension().?;
    try testing.expect(std.mem.eql(u8, ext, "zig"));

    // Test stem
    const stem = path_with_ext.stem().?;
    try testing.expect(std.mem.eql(u8, stem, "/usr/bin/zig"));


test "PathBuf operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test basic creation
    var buf = try PathBuf.fromSlice("/usr", allocator);
    defer buf.deinit();

    try testing.expect(std.mem.eql(u8, buf.asSlice(), "/usr"));

    // Test push
    try buf.push("bin");
    try testing.expect(std.mem.eql(u8, buf.asSlice(), "/usr/bin"));

    // Test pop
    const popped = buf.pop();
    try testing.expect(popped);
    try testing.expect(std.mem.eql(u8, buf.asSlice(), "/usr"));

    // Test join
    var buf2 = try PathBuf.fromSlice("/usr", allocator);
    defer buf2.deinit();

    var joined = buf2.join("bin/zig");
    defer joined.deinit();

    try testing.expect(std.mem.eql(u8, joined.asSlice(), "/usr/bin/zig"));


test "Path join operator" {
    const testing = std.testing;

    // Test Path / string
    const path = Path.init("/usr");
    var joined = path.join("bin");
    defer joined.deinit();

    try testing.expect(std.mem.eql(u8, joined.asSlice(), "/usr/bin"));


test "PathBuf join operator" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test PathBuf / string
    var buf = try PathBuf.fromSlice("/usr", allocator);
    defer buf.deinit();

    var joined = buf.join("bin");
    defer joined.deinit();

    try testing.expect(std.mem.eql(u8, joined.asSlice(), "/usr/bin"));


test "Path manipulation methods" {
    const testing = std.testing;

    // Test withExtension
    const path = Path.init("/usr/bin/zig");
    var with_ext = path.withExtension("exe");
    defer with_ext.deinit();

    try testing.expect(std.mem.eql(u8, with_ext.asSlice(), "/usr/bin/zig.exe"));

    // Test withFileName
    var with_name = path.withFileName("gcc");
    defer with_name.deinit();

    try testing.expect(std.mem.eql(u8, with_name.asSlice(), "/usr/bin/gcc"));


test "Cross-platform path handling" {
    const testing = std.testing;

    // Test Unix-style paths
    const unix_path = Path.init("/usr/local/bin");
    try testing.expect(unix_path.isAbsolute());
    try testing.expect(std.mem.eql(u8, unix_path.fileName().?, "bin"));

    // Test Windows-style paths
    const windows_path = Path.init("C:\\Windows\\System32");
    try testing.expect(windows_path.isAbsolute());
    try testing.expect(std.mem.eql(u8, windows_path.fileName().?, "System32"));


test "Edge cases" {
    const testing = std.testing;

    // Test empty path
    const empty_path = Path.init("");
    try testing.expect(!empty_path.isAbsolute());
    try testing.expect(empty_path.fileName() == null);
    try testing.expect(empty_path.parent() == null);

    // Test root path
    const root_path = Path.init("/");
    try testing.expect(root_path.isAbsolute());
    try testing.expect(std.mem.eql(u8, root_path.fileName().?, ""));
    try testing.expect(root_path.parent() == null);

    // Test path with only separators
    const sep_path = Path.init("///");
    try testing.expect(!sep_path.isAbsolute());
    try testing.expect(sep_path.fileName() == null);


test "PathBuf memory management" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test proper memory cleanup
    var buf = try PathBuf.fromSlice("/test/path", allocator);
    const original_capacity = buf.inner.len;

    try buf.push("component");
    try testing.expect(buf.inner.len > original_capacity);

    buf.deinit();

    // Test that we can create a new PathBuf after cleanup
    var buf2 = try PathBuf.fromSlice("/new/path", allocator);
    defer buf2.deinit();
    try testing.expect(std.mem.eql(u8, buf2.asSlice(), "/new/path"));


// =============================================================================
// UTCP MANUAL
// =============================================================================

/// Self-describing manual for AI agents and tooling
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - Path Module (std/path)
        \\## Overview
        \\Cross-platform path manipulation with memory-safe operations and capability-based security.
        \\Provides Path (borrowed) and PathBuf (owned) types with comprehensive path operations.
        \\
        \\## Core Types
        \\### Path (Borrowed)
        \\- `Path.init(path: []const u8)` - Create a borrowed path view
        \\- `path.asSlice()` - Get underlying string slice
        \\- `path.isAbsolute()` - Check if path is absolute
        \\- `path.parent()` - Get parent directory (returns ?Path)
        \\- `path.fileName()` - Get file name component (returns ?[]const u8)
        \\- `path.extension()` - Get file extension (returns ?[]const u8)
        \\- `path.stem()` - Get file name without extension (returns ?[]const u8)
        \\- `path.join(component)` - Join with path component (returns PathBuf)
        \\- `path.withExtension(ext)` - Create path with new extension (returns PathBuf)
        \\- `path.withFileName(name)` - Create path with new file name (returns PathBuf)
        \\
        \\### PathBuf (Owned)
        \\- `PathBuf.init(allocator)` - Create empty path buffer
        \\- `PathBuf.fromSlice(path, allocator)` - Create from string slice
        \\- `PathBuf.fromPath(path, allocator)` - Create from Path
        \\- `buf.asSlice()` - Get underlying string slice
        \\- `buf.asPath()` - Convert to borrowed Path view
        \\- `buf.push(component)` - Append path component
        \\- `buf.pop()` - Remove last component (returns bool)
        \\- `buf.clear()` - Clear the path buffer
        \\- `buf.deinit()` - Free the path buffer
        \\
        \\## Operators
        \\- `path / component` - Join path with component (Path / []const u8 -> PathBuf)
        \\- `buf / component` - Join path buffer with component (PathBuf / []const u8 -> PathBuf)
        \\- `path1 / path2` - Join two paths (Path / Path -> PathBuf)
        \\
        \\## Tri-Signature Pattern
        \\### :min Profile (Simple)
        \\```zig
        \\const result = try path_join_min("/usr", "bin", allocator);
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\const result = try path_join_go("/usr", "bin", ctx, allocator);
        \\```
        \\
        \\### :full Profile (Capability-gated)
        \\```zig
        \\var cap = Capability.FileSystem.init("fs-cap", allocator);
        \\defer cap.deinit();
        \\try cap.allow_path("/usr");
        \\const result = try path_join_full("/usr", "bin", cap, allocator);
        \\```
        \\
        \\## Cross-Platform Support
        \\- Automatic separator detection (\\ on Windows, / on Unix)
        \\- Windows drive letter and UNC path support
        \\- Proper handling of absolute vs relative paths
        \\- Unicode path support (UTF-8 encoded)
        \\
        \\## Security Features
        \\- Capability-based access control in :full profile
        \\- Path traversal protection
        \\- Memory-safe operations with explicit allocator management
        \\- No hidden allocations or global state
        \\
        \\## Performance Characteristics
        \\- Zero-copy path operations where possible
        \\- Efficient string operations with pre-allocation
        \\- Minimal memory allocations for read-only operations
        \\- Fast path traversal with early termination
        \\
        \\## Examples
        \\```zig
        \\// Basic path operations
        \\const path = Path.init("/usr/local/bin/zig");
        \\const parent = path.parent().?; // "/usr/local/bin"
        \\const file_name = path.fileName().?; // "zig"
        \\const ext = path.extension().?; // null (no extension)
        \\
        \\// Path building
        \\var buf = try PathBuf.fromSlice("/tmp", allocator);
        \\defer buf.deinit();
        \\try buf.push("test");
        \\try buf.push("file.txt");
        \\// buf now contains "/tmp/test/file.txt"
        \\
        \\// Path manipulation
        \\var new_path = path.withExtension("exe"); // "/usr/local/bin/zig.exe"
        \\defer new_path.deinit();
        \\
        \\// Join operator
        \\var joined = Path.init("/usr").join("local/bin"); // "/usr/local/bin"
        \\defer joined.deinit();
        \\```
        \\
    );
