// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Temporary ledger system stub for build compatibility
//! This is a minimal implementation to resolve import dependencies

const std = @import("std");

pub const cas = struct {
    pub const ContentId = [32]u8;

    pub fn blake3Hash(data: []const u8) ContentId {
        // Temporary implementation using std.crypto.hash.Blake3
        var hasher = std.crypto.hash.Blake3.init(.{});
        hasher.update(data);
        var result: ContentId = undefined;
        hasher.final(&result);
        return result;
    }

    pub fn contentIdToHex(content_id: ContentId, allocator: std.mem.Allocator) ![]u8 {
        const hex = std.fmt.bytesToHex(content_id, .lower);
        return try allocator.dupe(u8, &hex);
    }

    pub fn hexToContentId(hex: []const u8) !ContentId {
        var result: ContentId = undefined;
        _ = try std.fmt.hexToBytes(&result, hex);
        return result;
    }

    pub fn normalizeArchive(archive_data: []const u8, allocator: std.mem.Allocator) ![]u8 {
        // Temporary: just return a copy
        return try allocator.dupe(u8, archive_data);
    }

    pub fn initializeCAS(cas_root: []const u8) !void {
        _ = cas_root; // Stub implementation
    }

    pub const CAS = struct {
        pub fn init(root_path: []const u8, allocator: std.mem.Allocator) CAS {
            _ = root_path;
            _ = allocator;
            return CAS{};
        }

        pub fn hashArchive(self: *CAS, data: []const u8) !ContentId {
            _ = self;
            return blake3Hash(data);
        }

        pub fn store(self: *CAS, content_id: ContentId, data: []const u8) !void {
            _ = self;
            _ = content_id;
            _ = data;
            // Stub implementation - just succeed
        }

        pub fn exists(self: *CAS, content_id: ContentId) bool {
            _ = self;
            _ = content_id;
            return true; // Stub - always exists
        }

        pub fn retrieve(self: *CAS, content_id: ContentId, allocator: std.mem.Allocator) ![]u8 {
            _ = self;
            _ = content_id;
            return try allocator.dupe(u8, "test content"); // Stub implementation
        }

        pub fn deinit(self: *CAS) void {
            _ = self;
            // Stub implementation - nothing to clean up
        }

        pub fn verify(self: *CAS, content_id: ContentId) !bool {
            _ = self;
            _ = content_id;
            return true; // Stub - always verified
        }
    };
};

// Minimal stubs for other ledger modules
pub const manifest = struct {
    pub const Manifest = struct {
        pub fn init(allocator: std.mem.Allocator) Manifest {
            _ = allocator;
            return Manifest{};
        }
    };

    pub const Lockfile = struct {
        pub fn init(allocator: std.mem.Allocator) Lockfile {
            _ = allocator;
            return Lockfile{};
        }
    };

    pub const PackageRef = struct {
        pub const Source = enum { git, local };
    };

    pub const Capability = struct {};
};

pub const kdl_parser = struct {
    pub fn parseManifest(kdl_input: []const u8, allocator: std.mem.Allocator) !manifest.Manifest {
        _ = kdl_input;
        return manifest.Manifest.init(allocator);
    }
};

// json_parser has been replaced by the new janus.serde framework
// which provides SIMD acceleration and capability-gated operations
pub const json_parser = struct {
    pub fn parseLockfile(json_input: []const u8, allocator: std.mem.Allocator) !manifest.Lockfile {
        _ = json_input;
        return manifest.Lockfile.init(allocator);
    }

    pub fn serializeLockfile(lockfile: *const manifest.Lockfile, allocator: std.mem.Allocator) ![]u8 {
        _ = lockfile;
        return try allocator.dupe(u8, "{}");
    }
};

pub const transport = struct {
    pub const TransportRegistry = struct {};
    pub const FetchResult = struct {};

    pub fn createDefaultRegistry(allocator: std.mem.Allocator) !TransportRegistry {
        _ = allocator;
        return TransportRegistry{};
    }

    pub fn fetchWithVerification(registry: *const TransportRegistry, url: []const u8, expected_content_id: ?cas.ContentId, allocator: std.mem.Allocator) !FetchResult {
        _ = registry;
        _ = url;
        _ = expected_content_id;
        _ = allocator;
        return FetchResult{};
    }

    pub fn checkGitAvailable(allocator: std.mem.Allocator) bool {
        _ = allocator;
        return false;
    }
};

pub const resolver = struct {
    pub const Resolver = struct {
        pub fn init(cas_root: []const u8, allocator: std.mem.Allocator) !Resolver {
            _ = cas_root;
            _ = allocator;
            return Resolver{};
        }

        pub fn addDependency(self: *Resolver, package_name: []const u8, source: manifest.PackageRef.Source, capabilities: []const manifest.Capability, is_dev: bool) !ResolutionResult {
            _ = self;
            _ = package_name;
            _ = source;
            _ = capabilities;
            _ = is_dev;
            return ResolutionResult{};
        }

        pub fn updateDependencies(self: *Resolver) !ResolutionResult {
            _ = self;
            return ResolutionResult{};
        }

        pub fn saveLockfile(self: *Resolver, lockfile: *const manifest.Lockfile) !void {
            _ = self;
            _ = lockfile;
        }

        pub fn promptCapabilityChanges(changes: []const CapabilityChange, writer: anytype) !bool {
            _ = changes;
            _ = writer;
            return false;
        }
    };

    pub const ResolutionResult = struct {};
    pub const CapabilityChange = struct {};
};
