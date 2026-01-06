// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Janus Ledger: Manifest and Lockfile Data Structures
//
// This module defines the core data structures for:
// - janus.pkg (KDL format, human-authored)
// - JANUS.lock (JSON format, machine-authoritative)
//
// The manifest represents human intent, the lockfile represents resolved state.

// Package reference in janus.pkg
pub const PackageRef = struct {
    name: []const u8,
    source: Source,
    capabilities: []const Capability,

    pub const Source = union(enum) {
        git: GitSource,
        tar: TarSource,
        path: PathSource,

        pub const GitSource = struct {
            url: []const u8,
            ref: []const u8, // tag, branch, or commit
        };

        pub const TarSource = struct {
            url: []const u8,
            checksum: ?[]const u8 = null, // optional sha256
        };

        pub const PathSource = struct {
            path: []const u8,
        };
    };
};

// Capability grant in janus.pkg
pub const Capability = struct {
    name: []const u8,
    params: std.StringHashMap([]const u8),

    pub fn init(allocator: std.mem.Allocator) Capability {
        return Capability{
            .name = "",
            .params = std.StringHashMap([]const u8).init(allocator),
        };
    }

    pub fn deinit(self: *Capability) void {
        self.params.deinit();
    }
};

// Complete janus.pkg manifest
pub const Manifest = struct {
    name: []const u8,
    version: []const u8,
    dependencies: []PackageRef,
    dev_dependencies: []PackageRef,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Manifest {
        return Manifest{
            .name = "",
            .version = "",
            .dependencies = &[_]PackageRef{},
            .dev_dependencies = &[_]PackageRef{},
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Manifest) void {
        // Free all allocated strings and arrays
        for (self.dependencies) |*dep| {
            for (dep.capabilities) |*cap| {
                cap.deinit();
            }
        }
        for (self.dev_dependencies) |*dep| {
            for (dep.capabilities) |*cap| {
                cap.deinit();
            }
        }
    }
};

// Resolved package in JANUS.lock
pub const ResolvedPackage = struct {
    name: []const u8,
    version: []const u8,
    content_id: [32]u8, // BLAKE3 hash
    source: PackageRef.Source,
    capabilities: []const Capability,
    dependencies: []const []const u8, // names of dependencies
};

// Complete JANUS.lock lockfile
pub const Lockfile = struct {
    version: u32 = 1, // lockfile format version
    packages: std.StringHashMap(ResolvedPackage),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Lockfile {
        return Lockfile{
            .packages = std.StringHashMap(ResolvedPackage).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Lockfile) void {
        var iterator = self.packages.iterator();
        while (iterator.next()) |entry| {
            const pkg = entry.value_ptr;
            for (pkg.capabilities) |*cap| {
                cap.deinit();
            }
        }
        self.packages.deinit();
    }
};

// Error types for parsing
pub const ManifestError = error{
    InvalidKDL,
    MissingRequiredField,
    InvalidCapability,
    InvalidSource,
    OutOfMemory,
};

pub const LockfileError = error{
    InvalidJSON,
    UnsupportedVersion,
    InvalidContentId,
    MissingRequiredField,
    OutOfMemory,
};
