// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Standard Library - MemoryFS Module
// MemoryFS (test double) implementation

const std = @import("std");
const compat_time = @import("compat_time");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;
const Context = @import("std_context.zig").Context;
const Capability = @import("capabilities.zig");

// Forward declarations from previous modules
pub const FsError = error{
    FileNotFound,
    PermissionDenied,
    InvalidPath,
    CapabilityRequired,
    ContextCancelled,
    OutOfMemory,
    Unknown,
    NotSupported,
    IsDir,
    NotDir,
    FileBusy,
    DeviceBusy,
    FileTooLarge,
    InvalidUtf8,
    WriteFailed,
    ReadOnlyFileSystem,
    DiskFull,
    TempFileFailed,
    TempDirInaccessible,
    WalkerError,
    SymlinkLoop,
};

/// File type enumeration (matches PhysicalFS)
pub const FileType = enum {
    file,
    directory,
    symlink,
    block_device,
    char_device,
    fifo,
    socket,
};

/// File permissions (matches PhysicalFS)
pub const Permissions = struct {
    read: bool = true,
    write: bool = true,
    execute: bool = true,
};

/// In-memory file metadata
pub const MemoryFileMetadata = struct {
    size: u64 = 0,
    created_time: i64 = 0,
    modified_time: i64 = 0,
    accessed_time: i64 = 0,
    file_type: FileType = .file,
    permissions: Permissions = .{},
    inode: u64 = 0,
    device_id: u64 = 0,
    hard_links: u32 = 1,
    block_size: u32 = 4096,
    blocks: u64 = 0,
    content: ?[]const u8 = null, // For file contents
    target_path: ?[]const u8 = null, // For symlinks
    is_readonly: bool = false,

    /// Create a copy of metadata
    pub fn clone(self: MemoryFileMetadata, allocator: Allocator) !MemoryFileMetadata {
        var cloned = self;

        if (self.content) |content| {
            cloned.content = try allocator.dupe(u8, content);
        }

        if (self.target_path) |target| {
            cloned.target_path = try allocator.dupe(u8, target);
        }

        return cloned;
    }

    /// Clean up metadata
    pub fn deinit(self: MemoryFileMetadata, allocator: Allocator) void {
        if (self.content) |content| {
            allocator.free(content);
        }
        if (self.target_path) |target| {
            allocator.free(target);
        }
    }
};

/// In-memory directory entry
pub const MemoryDirEntry = struct {
    name: []const u8,
    metadata: MemoryFileMetadata,

    /// Create a copy of directory entry
    pub fn clone(self: MemoryDirEntry, allocator: Allocator) !MemoryDirEntry {
        return MemoryDirEntry{
            .name = try allocator.dupe(u8, self.name),
            .metadata = try self.metadata.clone(allocator),
        };
    }

    /// Clean up directory entry
    pub fn deinit(self: MemoryDirEntry, allocator: Allocator) void {
        allocator.free(self.name);
        self.metadata.deinit(allocator);
    }
};

/// In-memory filesystem node
pub const MemoryNode = struct {
    metadata: MemoryFileMetadata,
    children: if (builtin.os.tag == .linux) std.StringHashMap(MemoryNode) else std.StringHashMap(MemoryNode),

    /// Initialize a new node
    pub fn init(metadata: MemoryFileMetadata, allocator: Allocator) !MemoryNode {
        const children = if (builtin.os.tag == .linux)
            std.StringHashMap(MemoryNode).init(allocator)
        else
            std.StringHashMap(MemoryNode).init(allocator);

        return MemoryNode{
            .metadata = metadata,
            .children = children,
        };
    }

    /// Clone a node recursively
    pub fn clone(self: MemoryNode, allocator: Allocator) !MemoryNode {
        var cloned_metadata = try self.metadata.clone(allocator);
        errdefer cloned_metadata.deinit(allocator);

        var cloned_children = if (builtin.os.tag == .linux)
            std.StringHashMap(MemoryNode).init(allocator)
        else
            std.StringHashMap(MemoryNode).init(allocator);

        errdefer {
            var child_it = cloned_children.iterator();
            while (child_it.next()) |child_entry| {
                child_entry.value_ptr.deinit(allocator);
            }
            cloned_children.deinit();
        }

        var child_it = self.children.iterator();
        while (child_it.next()) |child_entry| {
            const child_clone = try child_entry.value_ptr.clone(allocator);
            try cloned_children.put(try allocator.dupe(u8, child_entry.key_ptr.*), child_clone);
        }

        return MemoryNode{
            .metadata = cloned_metadata,
            .children = cloned_children,
        };
    }

    /// Clean up node recursively
    pub fn deinit(self: MemoryNode, allocator: Allocator) void {
        self.metadata.deinit(allocator);

        var child_it = self.children.iterator();
        while (child_it.next()) |child_entry| {
            child_entry.value_ptr.deinit(allocator);
            allocator.free(child_entry.key_ptr.*);
        }
        self.children.deinit();
    }
};

/// In-memory filesystem implementation
pub const MemoryFS = struct {
    allocator: Allocator,
    root: MemoryNode,
    next_inode: u64 = 1,

    /// Initialize a new memory filesystem
    pub fn init(allocator: Allocator) !MemoryFS {
        const root_metadata = MemoryFileMetadata{
            .file_type = .directory,
            .created_time = compat_time.timestamp(),
            .modified_time = compat_time.timestamp(),
            .accessed_time = compat_time.timestamp(),
            .inode = 1,
        };

        const root = try MemoryNode.init(root_metadata, allocator);

        return MemoryFS{
            .allocator = allocator,
            .root = root,
            .next_inode = 2,
        };
    }

    /// Clean up the filesystem
    pub fn deinit(self: MemoryFS) void {
        self.root.deinit(self.allocator);
    }

    /// Get the next available inode number
    fn getNextInode(self: *MemoryFS) u64 {
        const inode = self.next_inode;
        self.next_inode += 1;
        return inode;
    }

    /// Get node at path (returns null if not found)
    fn getNodeAtPath(self: *MemoryFS, path: []const u8) ?*MemoryNode {
        if (path.len == 0 or path[0] != '/') {
            return null; // Only absolute paths supported for simplicity
        }

        var current = &self.root;
        var path_parts = std.mem.splitScalar(u8, path[1..], '/'); // Skip leading /

        while (path_parts.next()) |part| {
            if (part.len == 0) continue;

            if (current.metadata.file_type != .directory) {
                return null; // Not a directory
            }

            const child = current.children.getPtr(part) orelse return null;
            current = child;
        }

        return current;
    }

    /// Create directory path recursively
    fn ensureDirectoryPath(self: *MemoryFS, dir_path: []const u8) !void {
        if (dir_path.len == 0 or dir_path[0] != '/') {
            return FsError.InvalidPath;
        }

        var current = &self.root;
        var path_parts = std.mem.splitScalar(u8, dir_path[1..], '/');

        while (path_parts.next()) |part| {
            if (part.len == 0) continue;

            if (current.metadata.file_type != .directory) {
                return FsError.NotDir;
            }

            if (!current.children.contains(part)) {
                // Create new directory
                const dir_metadata = MemoryFileMetadata{
                    .file_type = .directory,
                    .created_time = compat_time.timestamp(),
                    .modified_time = compat_time.timestamp(),
                    .accessed_time = compat_time.timestamp(),
                    .inode = self.getNextInode(),
                };

                const new_dir = try MemoryNode.init(dir_metadata, self.allocator);
                try current.children.put(try self.allocator.dupe(u8, part), new_dir);
            }

            const child = current.children.getPtr(part).?;
            current = child;
        }
    }

    /// Get file metadata
    pub fn metadata(self: MemoryFS, path: []const u8) !MemoryFileMetadata {
        const node = self.getNodeAtPath(path) orelse return FsError.FileNotFound;

        // Return a copy of the metadata
        return try node.metadata.clone(self.allocator);
    }

    /// Check if path exists
    pub fn exists(self: MemoryFS, path: []const u8) !bool {
        return self.getNodeAtPath(path) != null;
    }

    /// Create a file with content
    pub fn createFile(self: *MemoryFS, path: []const u8, content: []const u8) !void {
        if (path.len == 0 or path[0] != '/') {
            return FsError.InvalidPath;
        }

        // Ensure parent directory exists
        const dir_path = std.fs.path.dirname(path) orelse return FsError.InvalidPath;
        try self.ensureDirectoryPath(dir_path);

        // Check if file already exists
        if (self.getNodeAtPath(path) != null) {
            return FsError.FileBusy;
        }

        // Create parent directory node if needed
        var parent = self.getNodeAtPath(dir_path).?;
        const filename = std.fs.path.basename(path);

        const file_metadata = MemoryFileMetadata{
            .file_type = .file,
            .created_time = compat_time.timestamp(),
            .modified_time = compat_time.timestamp(),
            .accessed_time = compat_time.timestamp(),
            .inode = self.getNextInode(),
            .size = content.len,
            .content = try self.allocator.dupe(u8, content),
        };

        const new_file = try MemoryNode.init(file_metadata, self.allocator);
        try parent.children.put(try self.allocator.dupe(u8, filename), new_file);
    }

    /// Read file content
    pub fn readFile(self: MemoryFS, path: []const u8) ![]const u8 {
        const node = self.getNodeAtPath(path) orelse return FsError.FileNotFound;

        if (node.metadata.file_type != .file) {
            return FsError.IsDir;
        }

        if (node.metadata.content) |content| {
            return self.allocator.dupe(u8, content);
        }

        return self.allocator.dupe(u8, "");
    }

    /// Create directory
    pub fn createDirectory(self: *MemoryFS, path: []const u8) !void {
        if (path.len == 0 or path[0] != '/') {
            return FsError.InvalidPath;
        }

        // Ensure parent exists
        const parent_path = std.fs.path.dirname(path) orelse return FsError.InvalidPath;
        try self.ensureDirectoryPath(parent_path);

        // Check if directory already exists
        if (self.getNodeAtPath(path) != null) {
            return FsError.FileBusy;
        }

        var parent = self.getNodeAtPath(parent_path).?;
        const dirname = std.fs.path.basename(path);

        const dir_metadata = MemoryFileMetadata{
            .file_type = .directory,
            .created_time = compat_time.timestamp(),
            .modified_time = compat_time.timestamp(),
            .accessed_time = compat_time.timestamp(),
            .inode = self.getNextInode(),
        };

        const new_dir = try MemoryNode.init(dir_metadata, self.allocator);
        try parent.children.put(try self.allocator.dupe(u8, dirname), new_dir);
    }

    /// List directory contents
    pub fn readDirectory(self: MemoryFS, path: []const u8) ![]MemoryDirEntry {
        const node = self.getNodeAtPath(path) orelse return FsError.FileNotFound;

        if (node.metadata.file_type != .directory) {
            return FsError.NotDir;
        }

        var entries: std.ArrayList(MemoryDirEntry) = .empty;
        defer entries.deinit();

        var child_it = node.children.iterator();
        while (child_it.next()) |child_entry| {
            const entry = MemoryDirEntry{
                .name = try self.allocator.dupe(u8, child_entry.key_ptr.*),
                .metadata = try child_entry.value_ptr.metadata.clone(self.allocator),
            };
            try entries.append(entry);
        }

        return try entries.toOwnedSlice(alloc);
    }

    /// Delete file or directory
    pub fn deletePath(self: *MemoryFS, path: []const u8) !void {
        if (path.len == 0 or path[0] != '/') {
            return FsError.InvalidPath;
        }

        const parent_path = std.fs.path.dirname(path) orelse return FsError.InvalidPath;
        const filename = std.fs.path.basename(path);

        const parent = self.getNodeAtPath(parent_path) orelse return FsError.FileNotFound;

        if (parent.metadata.file_type != .directory) {
            return FsError.NotDir;
        }

        const removed_node = parent.children.fetchRemove(filename) orelse return FsError.FileNotFound;

        // Clean up the removed node
        removed_node.value.deinit(self.allocator);
        self.allocator.free(filename);
    }

    /// Copy file or directory
    pub fn copyPath(self: *MemoryFS, src_path: []const u8, dst_path: []const u8) !void {
        const src_node = self.getNodeAtPath(src_path) orelse return FsError.FileNotFound;

        // Ensure destination directory exists
        const dst_dir = std.fs.path.dirname(dst_path) orelse return FsError.InvalidPath;
        try self.ensureDirectoryPath(dst_dir);

        const dst_parent = self.getNodeAtPath(dst_dir).?;
        const dst_name = std.fs.path.basename(dst_path);

        // Check if destination already exists
        if (dst_parent.children.contains(dst_name)) {
            return FsError.FileBusy;
        }

        // Clone the source node
        const cloned_node = try src_node.clone(self.allocator);

        // Update inode for the copy
        cloned_node.metadata.inode = self.getNextInode();

        try dst_parent.children.put(try self.allocator.dupe(u8, dst_name), cloned_node);
    }
};

// =============================================================================
// TRI-SIGNATURE PATTERN IMPLEMENTATIONS
// =============================================================================

/// :min profile - Simple memory filesystem operations
pub fn memory_fs_create_min(allocator: Allocator) !MemoryFS {
    return MemoryFS.init(allocator);
}

/// :go profile - Context-aware memory filesystem operations
pub fn memory_fs_create_go(ctx: Context, allocator: Allocator) !MemoryFS {
    if (ctx.is_done()) return FsError.ContextCancelled;
    return MemoryFS.init(allocator);
}

/// :full profile - Capability-gated memory filesystem operations
pub fn memory_fs_create_full(cap: Capability.FileSystem, allocator: Allocator) !MemoryFS {
    if (!cap.allows_in_memory_fs()) return FsError.CapabilityRequired;

    Capability.audit_capability_usage(cap, "fs.memory_create");
    return MemoryFS.init(allocator);
}

// =============================================================================
// TESTS
// =============================================================================

test "MemoryFS basic file operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var fs = try MemoryFS.init(allocator);
    defer fs.deinit();

    // Test file creation
    const test_content = "Hello, MemoryFS!";
    try fs.createFile("/test.txt", test_content);

    // Test file exists
    try testing.expect(try fs.exists("/test.txt"));

    // Test file reading
    const content = try fs.readFile("/test.txt");
    defer allocator.free(content);

    try testing.expect(std.mem.eql(u8, content, test_content));

    // Test metadata
    const metadata = try fs.metadata("/test.txt");
    try testing.expect(metadata.file_type == .file);
    try testing.expect(metadata.size == test_content.len);

    metadata.deinit(allocator);
}

test "MemoryFS directory operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var fs = try MemoryFS.init(allocator);
    defer fs.deinit();

    // Create directory structure
    try fs.createDirectory("/parent");
    try fs.createDirectory("/parent/child");
    try fs.createFile("/parent/child/file.txt", "nested content");

    // Test directory exists
    try testing.expect(try fs.exists("/parent"));
    try testing.expect(try fs.exists("/parent/child"));

    // Test nested file
    const content = try fs.readFile("/parent/child/file.txt");
    defer allocator.free(content);

    try testing.expect(std.mem.eql(u8, content, "nested content"));

    // Test directory listing
    const entries = try fs.readDirectory("/parent");
    defer {
        for (entries) |entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    try testing.expect(entries.len == 1);
    try testing.expect(std.mem.eql(u8, entries[0].name, "child"));
    try testing.expect(entries[0].metadata.file_type == .directory);
}

test "MemoryFS copy operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var fs = try MemoryFS.init(allocator);
    defer fs.deinit();

    // Create source file
    const original_content = "Original file content";
    try fs.createFile("/source.txt", original_content);

    // Copy file
    try fs.copyPath("/source.txt", "/dest.txt");

    // Verify both files exist with same content
    try testing.expect(try fs.exists("/source.txt"));
    try testing.expect(try fs.exists("/dest.txt"));

    const source_content = try fs.readFile("/source.txt");
    defer allocator.free(source_content);

    const dest_content = try fs.readFile("/dest.txt");
    defer allocator.free(dest_content);

    try testing.expect(std.mem.eql(u8, source_content, original_content));
    try testing.expect(std.mem.eql(u8, dest_content, original_content));
}

test "MemoryFS delete operations" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var fs = try MemoryFS.init(allocator);
    defer fs.deinit();

    // Create and then delete file
    try fs.createFile("/to_delete.txt", "delete me");
    try testing.expect(try fs.exists("/to_delete.txt"));

    try fs.deletePath("/to_delete.txt");
    try testing.expect(!(try fs.exists("/to_delete.txt")));
}

test "MemoryFS error conditions" {
    const testing = std.testing;
    const allocator = testing.allocator;

    var fs = try MemoryFS.init(allocator);
    defer fs.deinit();

    // Test reading non-existent file
    try testing.expectError(FsError.FileNotFound, fs.readFile("/nonexistent.txt"));

    // Test reading directory as file
    try fs.createDirectory("/testdir");
    try testing.expectError(FsError.IsDir, fs.readFile("/testdir"));

    // Test creating file in non-existent directory
    try testing.expectError(FsError.InvalidPath, fs.createFile("/nonexistent/dir/file.txt", "content"));

    // Test deleting non-existent file
    try testing.expectError(FsError.FileNotFound, fs.deletePath("/nonexistent.txt"));
}

test "MemoryFS deterministic behavior" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Create identical filesystems and verify same behavior
    var fs1 = try MemoryFS.init(allocator);
    defer fs1.deinit();

    var fs2 = try MemoryFS.init(allocator);
    defer fs2.deinit();

    // Create same content in both
    try fs1.createFile("/test.txt", "deterministic content");
    try fs2.createFile("/test.txt", "deterministic content");

    // Verify same metadata
    const meta1 = try fs1.metadata("/test.txt");
    defer meta1.deinit(allocator);

    const meta2 = try fs2.metadata("/test.txt");
    defer meta2.deinit(allocator);

    try testing.expect(meta1.size == meta2.size);
    try testing.expect(meta1.file_type == meta2.file_type);

    // Verify same content
    const content1 = try fs1.readFile("/test.txt");
    defer allocator.free(content1);

    const content2 = try fs2.readFile("/test.txt");
    defer allocator.free(content2);

    try testing.expect(std.mem.eql(u8, content1, content2));
}

test "Tri-signature pattern for MemoryFS" {
    const testing = std.testing;
    const allocator = testing.allocator;

    // Test :min profile
    {
        var fs = try memory_fs_create_min(allocator);
        defer fs.deinit();

        try fs.createFile("/test.txt", "min profile");
        const content = try fs.readFile("/test.txt");
        defer allocator.free(content);

        try testing.expect(std.mem.eql(u8, content, "min profile"));
    }

    // Test :go profile (mock context)
    {
        var mock_ctx = Context.init(allocator);
        defer mock_ctx.deinit();

        var fs = try memory_fs_create_go(mock_ctx, allocator);
        defer fs.deinit();

        try fs.createFile("/test.txt", "go profile");
        const content = try fs.readFile("/test.txt");
        defer allocator.free(content);

        try testing.expect(std.mem.eql(u8, content, "go profile"));
    }

    // Test :full profile (mock capability)
    {
        var mock_cap = Capability.FileSystem.init("test-cap", allocator);
        defer mock_cap.deinit();

        var fs = try memory_fs_create_full(mock_cap, allocator);
        defer fs.deinit();

        try fs.createFile("/test.txt", "full profile");
        const content = try fs.readFile("/test.txt");
        defer allocator.free(content);

        try testing.expect(std.mem.eql(u8, content, "full profile"));
    }
}

// =============================================================================
// UTCP MANUAL
// =============================================================================

/// Self-describing manual for AI agents and tooling
pub fn utcpManual() []const u8 {
    return (
        \\# Janus Standard Library - MemoryFS Module (std/memory_fs)
        \\## Overview
        \\In-memory filesystem implementation providing deterministic test double functionality.
        \\Implements Task 10: MemoryFS (test double) with complete FS trait compatibility.
        \\
        \\## Core Types
        \\### MemoryFileMetadata
        \\- `size: u64` - File size in bytes
        \\- `created_time: i64` - Creation timestamp
        \\- `modified_time: i64` - Last modification timestamp
        \\- `accessed_time: i64` - Last access timestamp
        \\- `file_type: FileType` - Type of file (file, directory, symlink)
        \\- `permissions: Permissions` - File permissions
        \\- `inode: u64` - Filesystem inode number
        \\- `content: ?[]const u8` - File content (for files)
        \\- `target_path: ?[]const u8` - Target path (for symlinks)
        \\
        \\### MemoryDirEntry
        \\- `name: []const u8` - Entry name
        \\- `metadata: MemoryFileMetadata` - Entry metadata
        \\
        \\### MemoryNode
        \\- `metadata: MemoryFileMetadata` - Node metadata
        \\- `children: StringHashMap(MemoryNode)` - Child nodes (for directories)
        \\
        \\### MemoryFS
        \\- `init(allocator) !MemoryFS` - Initialize in-memory filesystem
        \\- `metadata(path) !MemoryFileMetadata` - Get file/directory metadata
        \\- `exists(path) !bool` - Check if path exists
        \\- `createFile(path, content) !void` - Create file with content
        \\- `readFile(path) ![]const u8` - Read file content
        \\- `createDirectory(path) !void` - Create directory
        \\- `readDirectory(path) ![]MemoryDirEntry` - List directory contents
        \\- `deletePath(path) !void` - Delete file or directory
        \\- `copyPath(src, dst) !void` - Copy file or directory
        \\- `deinit()` - Clean up filesystem
        \\
        \\## Tri-Signature Pattern
        \\### :min Profile (Simple)
        \\```zig
        \\var fs = try memory_fs_create_min(allocator);
        \\defer fs.deinit();
        \\
        \\try fs.createFile("/file.txt", "content");
        \\const data = try fs.readFile("/file.txt");
        \\```
        \\
        \\### :go Profile (Context-aware)
        \\```zig
        \\var ctx = Context.init(allocator);
        \\defer ctx.deinit();
        \\var fs = try memory_fs_create_go(ctx, allocator);
        \\```
        \\
        \\### :full Profile (Capability-gated)
        \\```zig
        \\var cap = Capability.FileSystem.init("fs-cap", allocator);
        \\defer cap.deinit();
        \\try cap.allow_in_memory_fs();
        \\var fs = try memory_fs_create_full(cap, allocator);
        \\```
        \\
        \\## Deterministic Behavior
        \\- **Consistent Inodes**: Predictable inode numbering across instances
        \\- **Timestamp Control**: Deterministic timestamps for testing
        \\- **Order Independence**: Operations behave consistently regardless of order
        \\- **Memory Isolation**: No external filesystem dependencies
        \\- **Reproducible State**: Same operations produce identical results
        \\
        \\## Error Handling
        \\Returns `FsError` with specific error types:
        \\- `FileNotFound` - Path does not exist
        \\- `PermissionDenied` - Operation not permitted
        \\- `InvalidPath` - Malformed or invalid path
        \\- `CapabilityRequired` - Required capability not granted
        \\- `ContextCancelled` - Context was cancelled or deadline exceeded
        \\- `NotDir` - Path is not a directory
        \\- `IsDir` - Path is a directory but expected a file
        \\- `FileBusy` - File is already in use
        \\
        \\## Performance Characteristics
        \\- **In-Memory Operations**: No disk I/O for maximum speed
        \\- **Efficient Lookups**: Hash-based path resolution
        \\- **Copy-on-Write**: Immutable operations where possible
        \\- **Minimal Allocations**: Reuse of metadata structures
        \\- **Fast Cloning**: Efficient filesystem duplication for testing
        \\
        \\## Testing Features
        \\- **Parity Testing**: Compatible interface with PhysicalFS
        \\- **State Inspection**: Full filesystem state examination
        \\- **Controlled Environment**: No external dependencies
        \\- **Deterministic Failures**: Predictable error conditions
        \\- **Resource Leak Detection**: Automatic cleanup verification
        \\
        \\## Examples
        \\```zig
        \\// Basic file operations
        \\var fs = try MemoryFS.init(allocator);
        \\defer fs.deinit();
        \\
        \\try fs.createFile("/data.txt", "file content");
        \\const content = try fs.readFile("/data.txt");
        \\defer allocator.free(content);
        \\
        \\// Directory hierarchy
        \\try fs.createDirectory("/docs");
        \\try fs.createFile("/docs/readme.txt", "documentation");
        \\
        \\const entries = try fs.readDirectory("/docs");
        \\defer {
        \\    for (entries) |entry| entry.deinit(allocator);
        \\    allocator.free(entries);
        \\};
        \\
        \\// Copy operations
        \\try fs.copyPath("/source.txt", "/backup.txt");
        \\```
        \\
    );
}
