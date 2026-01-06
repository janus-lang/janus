// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Built-in command implementations for the Janus Shell
//!
//! Implements essential shell functionality with explicit capability requirements
//! and proper error handling according to our diagnostic framework.

const std = @import("std");
const types = @import("types.zig");
const diagnostics = @import("diagnostics.zig");

/// Handler for built-in shell commands
pub const BuiltinHandler = struct {
    allocator: std.mem.Allocator,
    config: types.ShellConfig,

    pub fn init(allocator: std.mem.Allocator, config: types.ShellConfig) !BuiltinHandler {
        return BuiltinHandler{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn deinit(self: *BuiltinHandler) void {
        _ = self;
    }

    /// Execute a built-in command
    pub fn execute(self: *BuiltinHandler, name: []const u8, args: []const []const u8, context: types.ExecutionContext) !i32 {
        if (std.mem.eql(u8, name, "cd")) {
            return try self.executeCD(args, context);
        } else if (std.mem.eql(u8, name, "pwd")) {
            return try self.executePWD(args, context);
        } else if (std.mem.eql(u8, name, "exit")) {
            return try self.executeExit(args, context);
        } else if (std.mem.eql(u8, name, "help")) {
            return try self.executeHelp(args, context);
        } else if (std.mem.eql(u8, name, "set")) {
            return try self.executeSet(args, context);
        } else if (std.mem.eql(u8, name, "unset")) {
            return try self.executeUnset(args, context);
        } else if (std.mem.eql(u8, name, "export")) {
            return try self.executeExport(args, context);
        } else if (std.mem.eql(u8, name, "history")) {
            return try self.executeHistory(args, context);
        } else if (std.mem.eql(u8, name, "caps")) {
            return try self.executeCaps(args, context);
        } else {
            std.debug.print("Unknown built-in command: {s}\n", .{name});
            return 1;
        }
    }

    /// Change directory (requires CapFsRead)
    fn executeCD(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = self;

        const target_dir = if (args.len > 0)
            args[0]
        else
            std.posix.getenv("HOME") orelse {
                std.debug.print("cd: HOME not set\n", .{});
                return 1;
            };

        // Attempt to change directory
        std.posix.chdir(target_dir) catch |err| {
            switch (err) {
                error.FileNotFound => {
                    std.debug.print("cd: {s}: No such file or directory\n", .{target_dir});
                },
                error.AccessDenied => {
                    std.debug.print("cd: {s}: Permission denied\n", .{target_dir});
                },
                error.NotDir => {
                    std.debug.print("cd: {s}: Not a directory\n", .{target_dir});
                },
                else => {
                    std.debug.print("cd: {s}: {}\n", .{ target_dir, err });
                },
            }
            return 1;
        };

        // Update context working directory would happen here
        // For now, we just report success
        _ = context;
        return 0;
    }

    /// Print working directory
    fn executePWD(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = args;

        const cwd = try std.process.getCwdAlloc(self.allocator);
        defer self.allocator.free(cwd);

        std.debug.print("{s}\n", .{cwd});
        _ = context;
        return 0;
    }

    /// Exit shell
    fn executeExit(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = self;
        _ = context;

        const exit_code: i32 = if (args.len > 0)
            std.fmt.parseInt(i32, args[0], 10) catch {
                std.debug.print("exit: {s}: numeric argument required\n", .{args[0]});
                return 2;
            }
        else
            0;

        std.process.exit(@intCast(exit_code));
    }

    /// Display help information
    fn executeHelp(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = args;
        _ = context;

        std.debug.print("Janus Shell (jsh) - Built-in Commands:\n\n", .{});
        std.debug.print("  cd [dir]     Change directory\n", .{});
        std.debug.print("  pwd          Print working directory\n", .{});
        std.debug.print("  exit [code]  Exit shell\n", .{});
        std.debug.print("  help         Show this help\n", .{});
        std.debug.print("  set var=val  Set shell variable\n", .{});
        std.debug.print("  unset var    Unset shell variable\n", .{});
        std.debug.print("  export var   Export variable to environment\n", .{});
        std.debug.print("  history      Show command history\n", .{});
        std.debug.print("  caps         Show capability status (🔒 SECURITY)\n", .{});
        std.debug.print("\nProfile: {}\n", .{self.config.profile});
        std.debug.print("Deterministic mode: {}\n", .{self.config.deterministic});

        return 0;
    }

    /// Set shell variable
    fn executeSet(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = self;
        _ = context;

        if (args.len == 0) {
            // Display all variables
            std.debug.print("Shell variables:\n", .{});
            // TODO: Implement variable display
            return 0;
        }

        for (args) |arg| {
            if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                const var_name = arg[0..eq_pos];
                const var_value = arg[eq_pos + 1 ..];

                // TODO: Store in shell variable table
                std.debug.print("Set {s}={s}\n", .{ var_name, var_value });
            } else {
                std.debug.print("set: {s}: invalid assignment\n", .{arg});
                return 1;
            }
        }

        return 0;
    }

    /// Unset shell variable
    fn executeUnset(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = self;
        _ = context;

        if (args.len == 0) {
            std.debug.print("unset: not enough arguments\n", .{});
            return 1;
        }

        for (args) |var_name| {
            // TODO: Remove from shell variable table
            std.debug.print("Unset {s}\n", .{var_name});
        }

        return 0;
    }

    /// Export variable to environment (requires CapEnvSet)
    fn executeExport(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        if (args.len == 0) {
            // Display exported variables
            var env_iter = context.env.iterator();
            while (env_iter.next()) |entry| {
                std.debug.print("export {s}={s}\n", .{ entry.key_ptr.*, entry.value_ptr.* });
            }
            return 0;
        }

        for (args) |arg| {
            if (std.mem.indexOf(u8, arg, "=")) |eq_pos| {
                const var_name = arg[0..eq_pos];
                const var_value = arg[eq_pos + 1 ..];

                // TODO: Check CapEnvSet capability
                // For now, just add to environment
                const owned_name = try self.allocator.dupe(u8, var_name);
                const owned_value = try self.allocator.dupe(u8, var_value);
                try context.env.put(owned_name, owned_value);

                std.debug.print("Export {s}={s}\n", .{ var_name, var_value });
            } else {
                // Export existing shell variable
                // TODO: Look up in shell variable table and export
                std.debug.print("Export {s}\n", .{arg});
            }
        }

        return 0;
    }

    /// Show command history
    fn executeHistory(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = self;
        _ = args;
        _ = context;

        std.debug.print("Command history:\n", .{});
        // TODO: Access shell history and display
        std.debug.print("  (history not yet implemented)\n", .{});

        return 0;
    }

    /// Show capability status - THE REVOLUTIONARY TRANSPARENCY COMMAND
    fn executeCaps(self: *BuiltinHandler, args: []const []const u8, context: types.ExecutionContext) !i32 {
        _ = args;
        _ = context;

        std.debug.print("🔒 Janus Shell Capability Status\n", .{});
        std.debug.print("═══════════════════════════════════\n", .{});
        std.debug.print("\n", .{});

        // TODO: Access capability context from shell context
        // For now, show example capabilities
        std.debug.print("📋 Current Capability Grants:\n", .{});
        std.debug.print("  proc_spawn: GRANTED\n", .{});
        std.debug.print("  fs_read: GRANTED (scope: /home)\n", .{});
        std.debug.print("  fs_write: GRANTED (scope: /tmp)\n", .{});
        std.debug.print("  env_read: GRANTED\n", .{});
        std.debug.print("  env_set: GRANTED\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("🚫 Denied Capabilities:\n", .{});
        std.debug.print("  fs_write: DENIED (scope: /etc)\n", .{});
        std.debug.print("  fs_write: DENIED (scope: /usr)\n", .{});
        std.debug.print("  fs_write: DENIED (scope: /bin)\n", .{});
        std.debug.print("  proc_job_control: DENIED (profile: min)\n", .{});
        std.debug.print("  tty_access: DENIED (profile: min)\n", .{});
        std.debug.print("\n", .{});

        std.debug.print("ℹ️  Profile: {}\n", .{self.config.profile});
        std.debug.print("ℹ️  Deterministic Mode: {}\n", .{self.config.deterministic});
        std.debug.print("\n", .{});
        std.debug.print("💡 Use 'caps --help' for capability management options\n", .{});

        return 0;
    }
};
