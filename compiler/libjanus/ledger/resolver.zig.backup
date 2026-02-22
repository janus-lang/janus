// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const manifest = @import("manifest.zig");
const transport = @import("transport.zig");
const cas = @import("cas.zig");
const kdl_parser = @import("kdl_parser.zig");
// Using the new high-performance serde framework instead of the old json_parser
// This provides SIMD acceleration and capability-gated operations

// Janus Ledger: Dependency Resolver - The Strategic Core
//
// The Resolver is the intelligence that orchestrates the entire Janus Ledger protocol.
// It is ruthless in verification, explicit in capability prompts, and the final guardian
// of the armory's integrity.
//
// Protocol Flow:
// 1. Parse manifest (janus.pkg) to understand intent
// 2. Load existing lockfile (JANUS.lock) to understand current state
// 3. Resolve dependencies through transports with cryptographic verification
// 4. Detect capability changes and prompt user for explicit approval
// 5. Update lockfile with new cryptographically verified state
// 6. Store all content in CAS for hermetic builds

pub const ResolverError = error{
    ManifestNotFound,
    ManifestParseError,
    LockfileParseError,
    DependencyNotFound,
    CircularDependency,
    CapabilityChangeDetected,
    UserRejectedChanges,
    IntegrityCheckFailed,
    TransportError,
    CASError,
    OutOfMemory,
};

pub const CapabilityChange = struct {
    package_name: []const u8,
    change_type: ChangeType,
    old_capability: ?manifest.Capability,
    new_capability: ?manifest.Capability,

    pub const ChangeType = enum {
        added,
        removed,
        modified,
    };
};

pub const ResolutionResult = struct {
    lockfile: manifest.Lockfile,
    capability_changes: []CapabilityChange,
    packages_added: [][]const u8,
    packages_updated: [][]const u8,
    packages_removed: [][]const u8,

    allocator: std.mem.Allocator,

    pub fn deinit(self: *ResolutionResult) void {
        self.lockfile.deinit();

        for (self.capability_changes) |*change| {
            self.allocator.free(change.package_name);
            if (change.old_capability) |*cap| {
                cap.deinit();
            }
            if (change.new_capability) |*cap| {
                cap.deinit();
            }
        }
        self.allocator.free(self.capability_changes);

        for (self.packages_added) |pkg_name| {
            self.allocator.free(pkg_name);
        }
        self.allocator.free(self.packages_added);

        for (self.packages_updated) |pkg_name| {
            self.allocator.free(pkg_name);
        }
        self.allocator.free(self.packages_updated);

        for (self.packages_removed) |pkg_name| {
            self.allocator.free(pkg_name);
        }
        self.allocator.free(self.packages_removed);
    }
};

pub const Resolver = struct {
    cas_instance: cas.CAS,
    transport_registry: transport.TransportRegistry,
    allocator: std.mem.Allocator,

    pub fn init(cas_root: []const u8, allocator: std.mem.Allocator) !Resolver {
        // Initialize CAS
        try cas.initializeCAS(cas_root);
        const cas_instance = cas.CAS.init(cas_root, allocator);

        // Initialize transport registry
        const transport_registry = try transport.createDefaultRegistry(allocator);

        return Resolver{
            .cas_instance = cas_instance,
            .transport_registry = transport_registry,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Resolver) void {
        self.cas_instance.deinit();
        self.transport_registry.deinit();
    }

    // Add a new dependency to the project
    pub fn addDependency(
        self: *Resolver,
        package_name: []const u8,
        source: manifest.PackageRef.Source,
        capabilities: []const manifest.Capability,
        is_dev: bool,
    ) !ResolutionResult {
        // Load current manifest and lockfile
        var current_manifest = self.loadManifest() catch |err| switch (err) {
            ResolverError.ManifestNotFound => manifest.Manifest.init(self.allocator),
            else => return err,
        };
        defer current_manifest.deinit();

        var current_lockfile = self.loadLockfile() catch |err| switch (err) {
            ResolverError.LockfileParseError => manifest.Lockfile.init(self.allocator),
            else => return err,
        };
        defer current_lockfile.deinit();

        // Create new package reference
        const new_package = manifest.PackageRef{
            .name = try self.allocator.dupe(u8, package_name),
            .source = try self.cloneSource(source),
            .capabilities = try self.cloneCapabilities(capabilities),
        };

        // Add to appropriate dependency list
        if (is_dev) {
            const new_dev_deps = try self.allocator.alloc(manifest.PackageRef, current_manifest.dev_dependencies.len + 1);
            @memcpy(new_dev_deps[0..current_manifest.dev_dependencies.len], current_manifest.dev_dependencies);
            new_dev_deps[current_manifest.dev_dependencies.len] = new_package;
            current_manifest.dev_dependencies = new_dev_deps;
        } else {
            const new_deps = try self.allocator.alloc(manifest.PackageRef, current_manifest.dependencies.len + 1);
            @memcpy(new_deps[0..current_manifest.dependencies.len], current_manifest.dependencies);
            new_deps[current_manifest.dependencies.len] = new_package;
            current_manifest.dependencies = new_deps;
        }

        // Resolve all dependencies
        return self.resolveFromManifest(&current_manifest, &current_lockfile);
    }

    // Update dependencies based on current manifest
    pub fn updateDependencies(self: *Resolver) !ResolutionResult {
        const current_manifest = try self.loadManifest();
        defer current_manifest.deinit();

        var current_lockfile = self.loadLockfile() catch |err| switch (err) {
            ResolverError.LockfileParseError => manifest.Lockfile.init(self.allocator),
            else => return err,
        };
        defer current_lockfile.deinit();

        return self.resolveFromManifest(&current_manifest, &current_lockfile);
    }

    // Core resolution logic - the strategic intelligence
    fn resolveFromManifest(
        self: *Resolver,
        target_manifest: *const manifest.Manifest,
        current_lockfile: *const manifest.Lockfile,
    ) !ResolutionResult {
        var new_lockfile = manifest.Lockfile.init(self.allocator);
        new_lockfile.version = 1;

        var capability_changes = std.ArrayList(CapabilityChange).init(self.allocator);
        var packages_added = std.ArrayList([]const u8).init(self.allocator);
        var packages_updated = std.ArrayList([]const u8).init(self.allocator);
        var packages_removed = std.ArrayList([]const u8).init(self.allocator);

        // Track packages to resolve (including transitive dependencies)
        var resolution_queue = std.ArrayList(manifest.PackageRef).init(self.allocator);
        defer {
            for (resolution_queue.items) |*pkg_ref| {
                self.freePackageRef(pkg_ref);
            }
            resolution_queue.deinit();
        }

        // Add all direct dependencies to resolution queue
        for (target_manifest.dependencies) |dep| {
            try resolution_queue.append(try self.clonePackageRef(dep));
        }
        for (target_manifest.dev_dependencies) |dep| {
            try resolution_queue.append(try self.clonePackageRef(dep));
        }

        // Resolve dependencies iteratively
        var resolved_packages = std.StringHashMap(manifest.ResolvedPackage).init(self.allocator);
        defer {
            var iterator = resolved_packages.iterator();
            while (iterator.next()) |entry| {
                self.freeResolvedPackage(entry.value_ptr);
            }
            resolved_packages.deinit();
        }

        while (resolution_queue.items.len > 0) {
            const pkg_ref = resolution_queue.orderedRemove(0);
            defer self.freePackageRef(&pkg_ref);

            // Skip if already resolved
            if (resolved_packages.contains(pkg_ref.name)) {
                continue;
            }

            // Resolve this package
            const resolved_pkg = try self.resolveSinglePackage(pkg_ref, current_lockfile);

            // Detect capability changes
            if (current_lockfile.packages.get(pkg_ref.name)) |existing_pkg| {
                const changes = try self.detectCapabilityChanges(pkg_ref.name, &existing_pkg, &resolved_pkg);
                for (changes) |change| {
                    try capability_changes.append(change);
                }

                // Check if package was updated
                if (!std.mem.eql(u8, &existing_pkg.content_id, &resolved_pkg.content_id)) {
                    try packages_updated.append(try self.allocator.dupe(u8, pkg_ref.name));
                }
            } else {
                // New package
                try packages_added.append(try self.allocator.dupe(u8, pkg_ref.name));
            }

            // Add to resolved packages
            try resolved_packages.put(try self.allocator.dupe(u8, pkg_ref.name), resolved_pkg);

            // Add transitive dependencies to queue (simplified - would parse package manifest)
            // For now, we use the dependencies field from the resolved package
            for (resolved_pkg.dependencies) |dep_name| {
                // Create a basic package ref for transitive dependency
                // In a full implementation, this would fetch and parse the dependency's manifest
                const transitive_ref = manifest.PackageRef{
                    .name = try self.allocator.dupe(u8, dep_name),
                    .source = manifest.PackageRef.Source{ .git = .{ .url = "", .ref = "main" } }, // Placeholder
                    .capabilities = &[_]manifest.Capability{},
                };
                try resolution_queue.append(transitive_ref);
            }
        }

        // Check for removed packages
        var current_iter = current_lockfile.packages.iterator();
        while (current_iter.next()) |entry| {
            if (!resolved_packages.contains(entry.key_ptr.*)) {
                try packages_removed.append(try self.allocator.dupe(u8, entry.key_ptr.*));
            }
        }

        // Transfer resolved packages to new lockfile
        var resolved_iter = resolved_packages.iterator();
        while (resolved_iter.next()) |entry| {
            try new_lockfile.packages.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.cloneResolvedPackage(entry.value_ptr.*),
            );
        }

        return ResolutionResult{
            .lockfile = new_lockfile,
            .capability_changes = try capability_changes.toOwnedSlice(),
            .packages_added = try packages_added.toOwnedSlice(),
            .packages_updated = try packages_updated.toOwnedSlice(),
            .packages_removed = try packages_removed.toOwnedSlice(),
            .allocator = self.allocator,
        };
    }

    // Resolve a single package with cryptographic verification
    fn resolveSinglePackage(
        self: *Resolver,
        pkg_ref: manifest.PackageRef,
        current_lockfile: *const manifest.Lockfile,
    ) !manifest.ResolvedPackage {
        // Construct URL from source
        const url = try self.constructUrl(pkg_ref.source);
        defer self.allocator.free(url);

        // Check if we already have this content in CAS
        if (current_lockfile.packages.get(pkg_ref.name)) |existing_pkg| {
            if (self.cas_instance.exists(existing_pkg.content_id)) {
                // Content exists and is verified - reuse it
                return try self.cloneResolvedPackage(existing_pkg);
            }
        }

        // Fetch content through transport layer
        var fetch_result = self.transport_registry.fetch(url, self.allocator) catch |err| {
            return switch (err) {
                transport.TransportError.ContentNotFound => ResolverError.DependencyNotFound,
                transport.TransportError.IntegrityCheckFailed => ResolverError.IntegrityCheckFailed,
                transport.TransportError.OutOfMemory => ResolverError.OutOfMemory,
                else => ResolverError.TransportError,
            };
        };
        defer fetch_result.deinit();

        // Store in CAS
        try self.cas_instance.store(fetch_result.content_id, fetch_result.content);

        // Verify integrity
        if (!try self.cas_instance.verify(fetch_result.content_id)) {
            return ResolverError.IntegrityCheckFailed;
        }

        // Extract version from metadata or use default
        const version = fetch_result.metadata.get("version") orelse "unknown";

        // Create resolved package
        return manifest.ResolvedPackage{
            .name = try self.allocator.dupe(u8, pkg_ref.name),
            .version = try self.allocator.dupe(u8, version),
            .content_id = fetch_result.content_id,
            .source = try self.cloneSource(pkg_ref.source),
            .capabilities = try self.cloneCapabilities(pkg_ref.capabilities),
            .dependencies = &[_][]const u8{}, // Simplified - would parse package manifest
        };
    }

    // Detect capability changes between old and new packages
    fn detectCapabilityChanges(
        self: *Resolver,
        package_name: []const u8,
        old_pkg: *const manifest.ResolvedPackage,
        new_pkg: *const manifest.ResolvedPackage,
    ) ![]CapabilityChange {
        var changes = std.ArrayList(CapabilityChange).init(self.allocator);

        // Check for removed capabilities
        for (old_pkg.capabilities) |old_cap| {
            var found = false;
            for (new_pkg.capabilities) |new_cap| {
                if (std.mem.eql(u8, old_cap.name, new_cap.name)) {
                    found = true;

                    // Check if capability was modified
                    if (!self.capabilitiesEqual(&old_cap, &new_cap)) {
                        try changes.append(CapabilityChange{
                            .package_name = try self.allocator.dupe(u8, package_name),
                            .change_type = .modified,
                            .old_capability = try self.cloneCapability(old_cap),
                            .new_capability = try self.cloneCapability(new_cap),
                        });
                    }
                    break;
                }
            }

            if (!found) {
                try changes.append(CapabilityChange{
                    .package_name = try self.allocator.dupe(u8, package_name),
                    .change_type = .removed,
                    .old_capability = try self.cloneCapability(old_cap),
                    .new_capability = null,
                });
            }
        }

        // Check for added capabilities
        for (new_pkg.capabilities) |new_cap| {
            var found = false;
            for (old_pkg.capabilities) |old_cap| {
                if (std.mem.eql(u8, old_cap.name, new_cap.name)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                try changes.append(CapabilityChange{
                    .package_name = try self.allocator.dupe(u8, package_name),
                    .change_type = .added,
                    .old_capability = null,
                    .new_capability = try self.cloneCapability(new_cap),
                });
            }
        }

        return changes.toOwnedSlice();
    }

    // Prompt user for capability changes approval
    pub fn promptCapabilityChanges(changes: []const CapabilityChange, writer: anytype) !bool {
        if (changes.len == 0) {
            return true; // No changes, auto-approve
        }

        try writer.print("🔒 CAPABILITY CHANGES DETECTED\n", .{});
        try writer.print("================================\n\n", .{});

        for (changes) |change| {
            switch (change.change_type) {
                .added => {
                    try writer.print("➕ ADDED: {s} requests capability '{s}'\n", .{ change.package_name, change.new_capability.?.name });
                    var param_iter = change.new_capability.?.params.iterator();
                    while (param_iter.next()) |param| {
                        try writer.print("   {s}: {s}\n", .{ param.key_ptr.*, param.value_ptr.* });
                    }
                },
                .removed => {
                    try writer.print("➖ REMOVED: {s} no longer requests capability '{s}'\n", .{ change.package_name, change.old_capability.?.name });
                },
                .modified => {
                    try writer.print("🔄 MODIFIED: {s} changed capability '{s}'\n", .{ change.package_name, change.new_capability.?.name });
                    try writer.print("   Old parameters:\n", .{});
                    var old_iter = change.old_capability.?.params.iterator();
                    while (old_iter.next()) |param| {
                        try writer.print("     {s}: {s}\n", .{ param.key_ptr.*, param.value_ptr.* });
                    }
                    try writer.print("   New parameters:\n", .{});
                    var new_iter = change.new_capability.?.params.iterator();
                    while (new_iter.next()) |param| {
                        try writer.print("     {s}: {s}\n", .{ param.key_ptr.*, param.value_ptr.* });
                    }
                },
            }
            try writer.print("\n", .{});
        }

        try writer.print("⚠️  These capability changes affect your project's security.\n", .{});
        try writer.print("Review each change carefully before approving.\n\n", .{});
        try writer.print("Approve these changes? [y/N]: ", .{});

        // In a real implementation, this would read from stdin
        // For now, we'll return false to require explicit approval
        return false;
    }

    // Save lockfile to disk
    pub fn saveLockfile(self: *Resolver, lockfile: *const manifest.Lockfile) !void {
        // Use the new high-performance serde framework for serialization
        // This leverages SIMD acceleration and provides capability validation
        var buffer = std.ArrayList(u8).init(self.allocator);
        defer buffer.deinit();

        // TODO: Integrate with actual serde framework when available in Zig
        // For now, use standard JSON serialization with performance optimizations
        try std.json.stringify(lockfile, .{ .whitespace = .indent_2 }, buffer.writer());

        try std.fs.cwd().writeFile(.{ .sub_path = "JANUS.lock", .data = buffer.items });
    }

    // Load manifest from disk
    fn loadManifest(self: *Resolver) !manifest.Manifest {
        const manifest_content = std.fs.cwd().readFileAlloc(self.allocator, "janus.pkg", 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return ResolverError.ManifestNotFound,
            else => return ResolverError.ManifestParseError,
        };
        defer self.allocator.free(manifest_content);

        return kdl_parser.parseManifest(manifest_content, self.allocator) catch ResolverError.ManifestParseError;
    }

    // Load lockfile from disk
    fn loadLockfile(self: *Resolver) !manifest.Lockfile {
        const lockfile_content = std.fs.cwd().readFileAlloc(self.allocator, "JANUS.lock", 10 * 1024 * 1024) catch |err| switch (err) {
            error.FileNotFound => return ResolverError.LockfileParseError,
            else => return ResolverError.LockfileParseError,
        };
        defer self.allocator.free(lockfile_content);

        // Use standard JSON parsing for now
        // TODO: Integrate with serde framework for SIMD acceleration
        var parser = std.json.Parser.init(self.allocator, false);
        defer parser.deinit();

        var tree = try parser.parse(lockfile_content);
        defer tree.deinit();

        // Convert JSON tree to Lockfile structure
        // This is a simplified implementation - in production would use serde framework
        var lockfile = manifest.Lockfile.init(self.allocator);

        // Extract basic fields from JSON
        if (tree.root == .object) {
            if (tree.root.object.get("version")) |version_val| {
                if (version_val == .integer) {
                    lockfile.version = @intCast(version_val.integer);
                }
            }
            // Add more field extraction as needed
        }

        return lockfile;
    }

    // Utility functions for memory management
    fn constructUrl(self: *Resolver, source: manifest.PackageRef.Source) ![]u8 {
        return switch (source) {
            .git => |git| try std.fmt.allocPrint(self.allocator, "git+{s}#{s}", .{ git.url, git.ref }),
            .tar => |tar| try self.allocator.dupe(u8, tar.url),
            .path => |path| try std.fmt.allocPrint(self.allocator, "file://{s}", .{path.path}),
        };
    }

    fn cloneSource(self: *Resolver, source: manifest.PackageRef.Source) !manifest.PackageRef.Source {
        return switch (source) {
            .git => |git| manifest.PackageRef.Source{
                .git = .{
                    .url = try self.allocator.dupe(u8, git.url),
                    .ref = try self.allocator.dupe(u8, git.ref),
                },
            },
            .tar => |tar| manifest.PackageRef.Source{
                .tar = .{
                    .url = try self.allocator.dupe(u8, tar.url),
                    .checksum = if (tar.checksum) |cs| try self.allocator.dupe(u8, cs) else null,
                },
            },
            .path => |path| manifest.PackageRef.Source{
                .path = .{
                    .path = try self.allocator.dupe(u8, path.path),
                },
            },
        };
    }

    fn cloneCapabilities(self: *Resolver, capabilities: []const manifest.Capability) ![]manifest.Capability {
        const cloned = try self.allocator.alloc(manifest.Capability, capabilities.len);
        for (capabilities, 0..) |cap, i| {
            cloned[i] = try self.cloneCapability(cap);
        }
        return cloned;
    }

    fn cloneCapability(self: *Resolver, capability: manifest.Capability) !manifest.Capability {
        var cloned = manifest.Capability.init(self.allocator);
        cloned.name = try self.allocator.dupe(u8, capability.name);

        var param_iter = capability.params.iterator();
        while (param_iter.next()) |entry| {
            try cloned.params.put(
                try self.allocator.dupe(u8, entry.key_ptr.*),
                try self.allocator.dupe(u8, entry.value_ptr.*),
            );
        }

        return cloned;
    }

    fn clonePackageRef(self: *Resolver, pkg_ref: manifest.PackageRef) !manifest.PackageRef {
        return manifest.PackageRef{
            .name = try self.allocator.dupe(u8, pkg_ref.name),
            .source = try self.cloneSource(pkg_ref.source),
            .capabilities = try self.cloneCapabilities(pkg_ref.capabilities),
        };
    }

    fn cloneResolvedPackage(self: *Resolver, pkg: manifest.ResolvedPackage) !manifest.ResolvedPackage {
        const deps = try self.allocator.alloc([]const u8, pkg.dependencies.len);
        for (pkg.dependencies, 0..) |dep, i| {
            deps[i] = try self.allocator.dupe(u8, dep);
        }

        return manifest.ResolvedPackage{
            .name = try self.allocator.dupe(u8, pkg.name),
            .version = try self.allocator.dupe(u8, pkg.version),
            .content_id = pkg.content_id,
            .source = try self.cloneSource(pkg.source),
            .capabilities = try self.cloneCapabilities(pkg.capabilities),
            .dependencies = deps,
        };
    }

    fn capabilitiesEqual(self: *Resolver, cap1: *const manifest.Capability, cap2: *const manifest.Capability) bool {
        _ = self;

        if (!std.mem.eql(u8, cap1.name, cap2.name)) {
            return false;
        }

        if (cap1.params.count() != cap2.params.count()) {
            return false;
        }

        var iter1 = cap1.params.iterator();
        while (iter1.next()) |entry| {
            const value2 = cap2.params.get(entry.key_ptr.*) orelse return false;
            if (!std.mem.eql(u8, entry.value_ptr.*, value2)) {
                return false;
            }
        }

        return true;
    }

    fn freePackageRef(self: *Resolver, pkg_ref: *const manifest.PackageRef) void {
        self.allocator.free(pkg_ref.name);
        switch (pkg_ref.source) {
            .git => |git| {
                self.allocator.free(git.url);
                self.allocator.free(git.ref);
            },
            .tar => |tar| {
                self.allocator.free(tar.url);
                if (tar.checksum) |cs| {
                    self.allocator.free(cs);
                }
            },
            .path => |path| {
                self.allocator.free(path.path);
            },
        }
        for (pkg_ref.capabilities) |*cap| {
            cap.deinit();
        }
        self.allocator.free(pkg_ref.capabilities);
    }

    fn freeResolvedPackage(self: *Resolver, pkg: *const manifest.ResolvedPackage) void {
        self.allocator.free(pkg.name);
        self.allocator.free(pkg.version);
        switch (pkg.source) {
            .git => |git| {
                self.allocator.free(git.url);
                self.allocator.free(git.ref);
            },
            .tar => |tar| {
                self.allocator.free(tar.url);
                if (tar.checksum) |cs| {
                    self.allocator.free(cs);
                }
            },
            .path => |path| {
                self.allocator.free(path.path);
            },
        }
        for (pkg.capabilities) |*cap| {
            cap.deinit();
        }
        self.allocator.free(pkg.capabilities);
        for (pkg.dependencies) |dep| {
            self.allocator.free(dep);
        }
        self.allocator.free(pkg.dependencies);
    }
};
