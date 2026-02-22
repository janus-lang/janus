// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const manifest = @import("manifest.zig");
const cas = @import("cas.zig");

// Janus Ledger: Transport Layer - The Untrusted Gates
//
// The transport layer is the untrusted boundary between the Janus Ledger
// and external package sources. All transports are considered hostile and
// their output is verified against expected content IDs.
//
// Phase 1 Transports:
// - git+https: Git repositories over HTTPS (most common, most complex)
// - file: Local filesystem (development and testing)

pub const TransportError = error{
    portedScheme,
    NetworkError,
    AuthenticationFailed,
    ContentNotFound,
    IntegrityCheckFailed,
    InvalidUrl,
    InvalidRef,
    GitCommandFailed,
    TimeoutError,
    OutOfMemory,
};

pub const FetchResult = struct {
    content: []u8,
    content_id: cas.ContentId,
    metadata: std.StringHashMap([]const u8),

    allocator: std.mem.Allocator,

    pub fn deinit(self: *FetchResult) void {
        self.allocator.free(self.content);

        var iterator = self.metadata.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.metadata.deinit();
    }
};

pub const TransportInterface = struct {
    name: []const u8,
    schemes: []const []const u8,

    // Function pointers for transport implementation
    fetchFn: *const fn (url: []const u8, allocator: std.mem.Allocator) TransportError!FetchResult,
    validateUrlFn: *const fn (url: []const u8) bool,

    pub fn fetch(self: *const TransportInterface, url: []const u8, allocator: std.mem.Allocator) TransportError!FetchResult {
        return self.fetchFn(url, allocator);
    }

    pub fn validateUrl(self: *const TransportInterface, url: []const u8) bool {
        return self.validateUrlFn(url);
    }

    pub fn supportsScheme(self: *const TransportInterface, scheme: []const u8) bool {
        for (self.schemes) |supported_scheme| {
            if (std.mem.eql(u8, scheme, supported_scheme)) {
                return true;
            }
        }
        return false;
    }
};

pub const TransportRegistry = struct {
    transports: std.ArrayList(*const TransportInterface),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TransportRegistry {
        return TransportRegistry{
            .transports = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TransportRegistry) void {
        self.transports.deinit();
    }

    pub fn register(self: *TransportRegistry, transport: *const TransportInterface) !void {
        try self.transports.append(transport);
    }

    pub fn findTransport(self: *const TransportRegistry, url: []const u8) ?*const TransportInterface {
        const scheme = extractScheme(url) orelse return null;

        for (self.transports.items) |transport| {
            if (transport.supportsScheme(scheme)) {
                return transport;
            }
        }

        return null;
    }

    pub fn fetch(self: *const TransportRegistry, url: []const u8, allocator: std.mem.Allocator) TransportError!FetchResult {
        const transport = self.findTransport(url) orelse return TransportError.UnsupportedScheme;
        return transport.fetch(url, allocator);
    }
};

// Extract scheme from URL (e.g., "https" from "https://example.com/repo.git")
fn extractScheme(url: []const u8) ?[]const u8 {
    if (std.mem.indexOf(u8, url, "://")) |pos| {
        return url[0..pos];
    }
    return null;
}

// ===== GIT+HTTPS TRANSPORT - THE COMPLEX GATE =====

const GitHttpsTransport = struct {
    pub const interface = TransportInterface{
        .name = "git+https",
        .schemes = &[_][]const u8{ "git+https", "https" },
        .fetchFn = fetchGitHttps,
        .validateUrlFn = validateGitHttpsUrl,
    };
};

const GitUrlParts = struct {
    repo_url: []const u8,
    ref: []const u8,
    ref_type: RefType,

    const RefType = enum {
        branch,
        tag,
        commit,
    };
};

fn fetchGitHttps(url: []const u8, allocator: std.mem.Allocator) TransportError!FetchResult {
    // Parse git URL and ref
    const parsed = parseGitUrl(url, allocator) orelse return TransportError.InvalidUrl;
    defer {
        allocator.free(parsed.repo_url);
        allocator.free(parsed.ref);
    }

    // Create temporary directory for clone
    const temp_dir = try std.fmt.allocPrint(allocator, "/tmp/janus_git_{d}_{d}", .{ std.time.timestamp(), std.Thread.getCurrentId() });
    defer allocator.free(temp_dir);

    // Ensure temp directory is clean
    std.fs.cwd().deleteTree(temp_dir) catch {};

    // Execute git clone with appropriate strategy based on ref type
    const clone_success = switch (parsed.ref_type) {
        .tag => try cloneByTag(parsed.repo_url, parsed.ref, temp_dir, allocator),
        .commit => try cloneByCommit(parsed.repo_url, parsed.ref, temp_dir, allocator),
        .branch => try cloneByBranch(parsed.repo_url, parsed.ref, temp_dir, allocator),
    };

    if (!clone_success) {
        std.fs.cwd().deleteTree(temp_dir) catch {};
        return TransportError.ContentNotFound;
    }

    // Create normalized archive from cloned repository
    const archive_content = createNormalizedArchive(temp_dir, allocator) catch |err| {
        std.fs.cwd().deleteTree(temp_dir) catch {};
        return switch (err) {
            error.OutOfMemory => TransportError.OutOfMemory,
            else => TransportError.NetworkError,
        };
    };

    // Clean up temporary directory
    std.fs.cwd().deleteTree(temp_dir) catch {};

    // Calculate content ID
    const content_id = cas.blake3Hash(archive_content);

    // Create metadata
    var metadata = std.StringHashMap([]const u8).init(allocator);
    try metadata.put(try allocator.dupe(u8, "transport"), try allocator.dupe(u8, "git+https"));
    try metadata.put(try allocator.dupe(u8, "repo_url"), try allocator.dupe(u8, parsed.repo_url));
    try metadata.put(try allocator.dupe(u8, "ref"), try allocator.dupe(u8, parsed.ref));
    try metadata.put(try allocator.dupe(u8, "ref_type"), try allocator.dupe(u8, @tagName(parsed.ref_type)));

    return FetchResult{
        .content = archive_content,
        .content_id = content_id,
        .metadata = metadata,
        .allocator = allocator,
    };
}

fn cloneByTag(repo_url: []const u8, tag: []const u8, temp_dir: []const u8, allocator: std.mem.Allocator) !bool {
    // Clone with specific tag
    const clone_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "clone", "--depth=1", "--branch", tag, repo_url, temp_dir },
    }) catch return false;

    defer {
        allocator.free(clone_result.stdout);
        allocator.free(clone_result.stderr);
    }

    return clone_result.term.Exited == 0;
}

fn cloneByCommit(repo_url: []const u8, commit: []const u8, temp_dir: []const u8, allocator: std.mem.Allocator) !bool {
    // Clone full repository first (commits require full history)
    const clone_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "clone", repo_url, temp_dir },
    }) catch return false;

    defer {
        allocator.free(clone_result.stdout);
        allocator.free(clone_result.stderr);
    }

    if (clone_result.term.Exited != 0) {
        return false;
    }

    // Checkout specific commit
    const checkout_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "-C", temp_dir, "checkout", commit },
    }) catch return false;

    defer {
        allocator.free(checkout_result.stdout);
        allocator.free(checkout_result.stderr);
    }

    return checkout_result.term.Exited == 0;
}

fn cloneByBranch(repo_url: []const u8, branch: []const u8, temp_dir: []const u8, allocator: std.mem.Allocator) !bool {
    // Clone with specific branch
    const clone_result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "clone", "--depth=1", "--branch", branch, repo_url, temp_dir },
    }) catch return false;

    defer {
        allocator.free(clone_result.stdout);
        allocator.free(clone_result.stderr);
    }

    return clone_result.term.Exited == 0;
}

fn validateGitHttpsUrl(url: []const u8) bool {
    // Support both explicit git+https:// and implicit https://*.git
    return std.mem.startsWith(u8, url, "git+https://") or
        (std.mem.startsWith(u8, url, "https://") and std.mem.endsWith(u8, url, ".git"));
}

fn parseGitUrl(url: []const u8, allocator: std.mem.Allocator) ?GitUrlParts {
    // Handle git+https://repo.git#ref format
    var working_url = url;

    // Strip git+ prefix if present
    if (std.mem.startsWith(u8, working_url, "git+")) {
        working_url = working_url[4..];
    }

    // Split URL and ref
    if (std.mem.indexOf(u8, working_url, "#")) |pos| {
        const repo_url = allocator.dupe(u8, working_url[0..pos]) catch return null;
        const ref_part = working_url[pos + 1 ..];

        // Determine ref type and extract ref
        if (std.mem.startsWith(u8, ref_part, "tag=")) {
            const ref = allocator.dupe(u8, ref_part[4..]) catch {
                allocator.free(repo_url);
                return null;
            };
            return GitUrlParts{
                .repo_url = repo_url,
                .ref = ref,
                .ref_type = .tag,
            };
        } else if (std.mem.startsWith(u8, ref_part, "branch=")) {
            const ref = allocator.dupe(u8, ref_part[7..]) catch {
                allocator.free(repo_url);
                return null;
            };
            return GitUrlParts{
                .repo_url = repo_url,
                .ref = ref,
                .ref_type = .branch,
            };
        } else if (std.mem.startsWith(u8, ref_part, "commit=")) {
            const ref = allocator.dupe(u8, ref_part[7..]) catch {
                allocator.free(repo_url);
                return null;
            };
            return GitUrlParts{
                .repo_url = repo_url,
                .ref = ref,
                .ref_type = .commit,
            };
        } else {
            // Default to treating as tag
            const ref = allocator.dupe(u8, ref_part) catch {
                allocator.free(repo_url);
                return null;
            };
            return GitUrlParts{
                .repo_url = repo_url,
                .ref = ref,
                .ref_type = .tag,
            };
        }
    } else {
        // No ref specified, default to main branch
        const repo_url = allocator.dupe(u8, working_url) catch return null;
        const ref = allocator.dupe(u8, "main") catch {
            allocator.free(repo_url);
            return null;
        };
        return GitUrlParts{
            .repo_url = repo_url,
            .ref = ref,
            .ref_type = .branch,
        };
    }
}

// ===== FILE TRANSPORT - THE LOCAL GATE =====

const FileTransport = struct {
    pub const interface = TransportInterface{
        .name = "file",
        .schemes = &[_][]const u8{"file"},
        .fetchFn = fetchFile,
        .validateUrlFn = validateFileUrl,
    };
};

fn fetchFile(url: []const u8, allocator: std.mem.Allocator) TransportError!FetchResult {
    // Extract path from file:// URL
    const path = if (std.mem.startsWith(u8, url, "file://"))
        url[7..]
    else
        return TransportError.InvalidUrl;

    // Check if path is a directory or file
    const stat = std.fs.cwd().statFile(path) catch |err| switch (err) {
        error.FileNotFound => return TransportError.ContentNotFound,
        else => return TransportError.NetworkError,
    };

    const content = if (stat.kind == .directory) blk: {
        // Create archive from directory
        break :blk createNormalizedArchive(path, allocator) catch |err| switch (err) {
            error.OutOfMemory => return TransportError.OutOfMemory,
            else => return TransportError.NetworkError,
        };
    } else blk: {
        // Read file content directly
        break :blk std.fs.cwd().readFileAlloc(allocator, path, 100 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return TransportError.ContentNotFound,
            error.OutOfMemory => return TransportError.OutOfMemory,
            else => return TransportError.NetworkError,
        };
    };

    // Calculate content ID
    const content_id = cas.blake3Hash(content);

    // Create metadata
    var metadata = std.StringHashMap([]const u8).init(allocator);
    try metadata.put(try allocator.dupe(u8, "transport"), try allocator.dupe(u8, "file"));
    try metadata.put(try allocator.dupe(u8, "path"), try allocator.dupe(u8, path));
    try metadata.put(try allocator.dupe(u8, "url"), try allocator.dupe(u8, url));
    try metadata.put(try allocator.dupe(u8, "kind"), try allocator.dupe(u8, if (stat.kind == .directory) "directory" else "file"));

    return FetchResult{
        .content = content,
        .content_id = content_id,
        .metadata = metadata,
        .allocator = allocator,
    };
}

fn validateFileUrl(url: []const u8) bool {
    return std.mem.startsWith(u8, url, "file://");
}

// ===== ARCHIVE CREATION - THE NORMALIZATION ENGINE =====

fn createNormalizedArchive(dir_path: []const u8, allocator: std.mem.Allocator) ![]u8 {
    // Create a normalized, reproducible archive from directory contents
    // This ensures identical content produces identical hashes regardless of:
    // - File timestamps
    // - File permissions (beyond executable bit)
    // - Directory traversal order
    // - Line ending differences

    var files: std.ArrayList(ArchiveEntry) = .empty;
    defer {
        for (files.items) |*entry| {
            allocator.free(entry.path);
            allocator.free(entry.content);
        }
        files.deinit();
    }

    // Collect all files recursively
    try collectFiles(dir_path, "", &files, allocator);

    // Sort files by path for deterministic ordering
    std.sort.insertion(ArchiveEntry, files.items, {}, compareArchiveEntries);

    // Create normalized archive
    var archive: std.ArrayList(u8) = .empty;
    defer archive.deinit();

    for (files.items) |entry| {
        // Write entry header: path_length:u32, path:[]u8, content_length:u32, is_executable:u8
        const path_len: u32 = @intCast(entry.path.len);
        const content_len: u32 = @intCast(entry.content.len);
        const executable: u8 = if (entry.is_executable) 1 else 0;

        try archive.appendSlice(std.mem.asBytes(&path_len));
        try archive.appendSlice(entry.path);
        try archive.appendSlice(std.mem.asBytes(&content_len));
        try archive.append(executable);
        try archive.appendSlice(entry.content);
    }

    return try archive.toOwnedSlice(alloc);
}

const ArchiveEntry = struct {
    path: []u8,
    content: []u8,
    is_executable: bool,
};

fn compareArchiveEntries(context: void, a: ArchiveEntry, b: ArchiveEntry) bool {
    _ = context;
    return std.mem.lessThan(u8, a.path, b.path);
}

fn collectFiles(base_path: []const u8, rel_path: []const u8, files: *std.ArrayList(ArchiveEntry), allocator: std.mem.Allocator) !void {
    const full_path = if (rel_path.len == 0)
        try allocator.dupe(u8, base_path)
    else
        try std.fs.path.join(allocator, &[_][]const u8{ base_path, rel_path });
    defer allocator.free(full_path);

    var dir = std.fs.cwd().openDir(full_path, .{ .iterate = true }) catch return;
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        // Skip .git directory and other VCS artifacts
        if (std.mem.eql(u8, entry.name, ".git") or
            std.mem.eql(u8, entry.name, ".svn") or
            std.mem.eql(u8, entry.name, ".hg") or
            std.mem.startsWith(u8, entry.name, "."))
        {
            continue;
        }

        const entry_rel_path = if (rel_path.len == 0)
            try allocator.dupe(u8, entry.name)
        else
            try std.fs.path.join(allocator, &[_][]const u8{ rel_path, entry.name });

        switch (entry.kind) {
            .file => {
                // Read and normalize file content
                const file_content = try dir.readFileAlloc(allocator, entry.name, 10 * 1024 * 1024);
                const normalized_content = try cas.normalizeArchive(file_content, allocator);
                allocator.free(file_content);

                // Check if file is executable
                const file_stat = try dir.statFile(entry.name);
                const is_executable = (file_stat.mode & 0o111) != 0;

                try files.append(ArchiveEntry{
                    .path = entry_rel_path,
                    .content = normalized_content,
                    .is_executable = is_executable,
                });
            },
            .directory => {
                // Recurse into subdirectory
                try collectFiles(base_path, entry_rel_path, files, allocator);
                allocator.free(entry_rel_path);
            },
            else => {
                // Skip other file types (symlinks, devices, etc.)
                allocator.free(entry_rel_path);
            },
        }
    }
}

// ===== PUBLIC API =====

pub fn createDefaultRegistry(allocator: std.mem.Allocator) !TransportRegistry {
    var registry = TransportRegistry.init(allocator);

    // Register Phase 1 transports
    try registry.register(&GitHttpsTransport.interface);
    try registry.register(&FileTransport.interface);

    return registry;
}

// Fetch content from URL with integrity verification
pub fn fetchWithVerification(
    registry: *const TransportRegistry,
    url: []const u8,
    expected_content_id: ?cas.ContentId,
    allocator: std.mem.Allocator,
) !FetchResult {
    var result = try registry.fetch(url, allocator);

    // Verify content integrity if expected hash provided
    if (expected_content_id) |expected| {
        if (!std.mem.eql(u8, &result.content_id, &expected)) {
            result.deinit();
            return TransportError.IntegrityCheckFailed;
        }
    }

    return result;
}

// Check if git command is available
pub fn checkGitAvailable(allocator: std.mem.Allocator) bool {
    const result = std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "--version" },
    }) catch return false;

    defer {
        allocator.free(result.stdout);
        allocator.free(result.stderr);
    }

    return result.term.Exited == 0;
}
