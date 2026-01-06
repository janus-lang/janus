// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Capability checking system for the Janus Shell
//!
//! Implements capability-to-operation mapping as defined in the design document.
//! Ensures all operations are properly gated by required capabilities.
//! Provides introspection tools for security transparency.

const std = @import("std");
const types = @import("types.zig");

/// Capability grant with optional scope/path restrictions
pub const CapabilityGrant = struct {
    capability: types.Capability,
    scope: ?[]const u8 = null, // Optional path or scope restriction
    granted: bool = true,

    pub fn format(self: CapabilityGrant, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;

        const status = if (self.granted) "GRANTED" else "DENIED";
        if (self.scope) |scope| {
            try writer.print("{s}: {s} (scope: {s})", .{ @tagName(self.capability), status, scope });
        } else {
            try writer.print("{s}: {s}", .{ @tagName(self.capability), status });
        }
    }
};

/// Capability context that tracks granted and denied capabilities
pub const CapabilityContext = struct {
    allocator: std.mem.Allocator,
    grants: std.ArrayList(CapabilityGrant),

    pub fn init(allocator: std.mem.Allocator) CapabilityContext {
        return CapabilityContext{
            .allocator = allocator,
            .grants = std.ArrayList(CapabilityGrant).init(allocator),
        };
    }

    pub fn deinit(self: *CapabilityContext) void {
        for (self.grants.items) |capability_grant| {
            if (capability_grant.scope) |scope| {
                self.allocator.free(scope);
            }
        }
        self.grants.deinit();
    }

    /// Grant a capability with optional scope
    pub fn grant(self: *CapabilityContext, capability: types.Capability, scope: ?[]const u8) !void {
        const owned_scope = if (scope) |s| try self.allocator.dupe(u8, s) else null;
        try self.grants.append(CapabilityGrant{
            .capability = capability,
            .scope = owned_scope,
            .granted = true,
        });
    }

    /// Deny a capability with optional scope
    pub fn deny(self: *CapabilityContext, capability: types.Capability, scope: ?[]const u8) !void {
        const owned_scope = if (scope) |s| try self.allocator.dupe(u8, s) else null;
        try self.grants.append(CapabilityGrant{
            .capability = capability,
            .scope = owned_scope,
            .granted = false,
        });
    }

    /// Check if a capability is granted
    pub fn hasCapability(self: *CapabilityContext, capability: types.Capability, scope: ?[]const u8) bool {
        for (self.grants.items) |capability_grant| {
            if (capability_grant.capability == capability) {
                // If no scope specified, any grant works
                if (scope == null) return capability_grant.granted;

                // If grant has no scope, it applies to all
                if (capability_grant.scope == null) return capability_grant.granted;

                // Check scope match
                if (scope) |req_scope| {
                    if (capability_grant.scope) |grant_scope| {
                        if (std.mem.eql(u8, req_scope, grant_scope)) {
                            return capability_grant.granted;
                        }
                    }
                }
            }
        }
        return false; // Default deny
    }

    /// Get all grants for introspection
    pub fn getAllGrants(self: *CapabilityContext) []const CapabilityGrant {
        return self.grants.items;
    }

    /// Create a default capability context for the shell
    pub fn createDefault(allocator: std.mem.Allocator) !CapabilityContext {
        var ctx = CapabilityContext.init(allocator);

        // Grant basic capabilities for shell operation
        try ctx.grant(.proc_spawn, null);
        try ctx.grant(.fs_read, "/home"); // Allow reading from home directory
        try ctx.grant(.fs_write, "/tmp"); // Allow writing to tmp
        try ctx.grant(.env_read, null);
        try ctx.grant(.env_set, null);

        // Deny dangerous capabilities by default
        try ctx.deny(.fs_write, "/etc");
        try ctx.deny(.fs_write, "/usr");
        try ctx.deny(.fs_write, "/bin");

        return ctx;
    }
};

/// Capability checker that validates required capabilities for operations
pub const CapabilityChecker = struct {
    context: *CapabilityContext,

    pub fn init(context: *CapabilityContext) CapabilityChecker {
        return CapabilityChecker{
            .context = context,
        };
    }

    /// Check what capabilities are required for a command
    pub fn checkCommand(self: *CapabilityChecker, command: types.Command) !std.ArrayList(types.Capability) {
        var required_caps = std.ArrayList(types.Capability).init(std.heap.page_allocator);

        switch (command) {
            .simple => |simple| {
                try self.checkSimpleCommand(simple, &required_caps);
            },
            .pipeline => |pipeline| {
                for (pipeline.stages) |stage| {
                    const stage_caps = try self.checkCommand(stage);
                    defer stage_caps.deinit();

                    for (stage_caps.items) |cap| {
                        if (!self.containsCapability(required_caps.items, cap)) {
                            try required_caps.append(cap);
                        }
                    }
                }
            },
            .builtin => |builtin| {
                try self.checkBuiltinCommand(builtin, &required_caps);
            },
        }

        return required_caps;
    }

    fn checkSimpleCommand(self: *CapabilityChecker, simple: types.Command.SimpleCommand, caps: *std.ArrayList(types.Capability)) !void {
        _ = self;

        // Process spawning always requires CapProcSpawn
        try caps.append(.proc_spawn);

        // Check if executable is absolute path (requires CapFsExec)
        if (simple.spec.argv.len > 0) {
            const executable = simple.spec.argv[0];
            if (std.fs.path.isAbsolute(executable)) {
                try caps.append(.fs_exec);
            }
        }

        // Check redirections
        for (simple.redirections) |redir| {
            switch (redir) {
                .input => {
                    try caps.append(.fs_read);
                },
                .output => {
                    try caps.append(.fs_write);
                },
            }
        }
    }

    fn checkBuiltinCommand(self: *CapabilityChecker, builtin: types.Command.BuiltinCommand, caps: *std.ArrayList(types.Capability)) !void {
        _ = self;
        if (std.mem.eql(u8, builtin.name, "cd")) {
            try caps.append(.fs_read);
        } else if (std.mem.eql(u8, builtin.name, "export")) {
            try caps.append(.env_set);
        }
        // Other built-ins don't require special capabilities
    }

    fn containsCapability(self: *CapabilityChecker, caps: []const types.Capability, target: types.Capability) bool {
        _ = self;
        for (caps) |cap| {
            if (cap == target) return true;
        }
        return false;
    }

    /// Validate that required capabilities are available in context
    pub fn validateCapabilities(self: *CapabilityChecker, required: []const types.Capability, scope: ?[]const u8) !void {
        for (required) |req_cap| {
            if (!self.context.hasCapability(req_cap, scope)) {
                // Emit capability required error
                return types.ShellError.CapabilityRequired;
            }
        }
    }

    /// Validate a specific command against the capability context
    pub fn validateCommand(self: *CapabilityChecker, command: types.Command) !void {
        const required_caps = try self.checkCommand(command);
        defer required_caps.deinit();

        try self.validateCapabilities(required_caps.items, null);
    }

    /// Get capability context for introspection
    pub fn getContext(self: *CapabilityChecker) *CapabilityContext {
        return self.context;
    }
};
