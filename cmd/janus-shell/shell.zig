// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Core shell module implementing the Janus Shell architecture
//!
//! This module provides the main Shell struct and orchestrates all shell operations
//! according to our doctrines of capability-gated security and explicit execution.

const std = @import("std");
const types = @import("types.zig");
const parser = @import("parser.zig");
const executor = @import("executor.zig");
const capabilities = @import("capabilities.zig");
const diagnostics = @import("diagnostics.zig");

pub const Profile = types.Profile;
pub const ShellConfig = types.ShellConfig;
pub const ShellError = types.ShellError;

/// Main shell instance that orchestrates all operations
pub const Shell = struct {
    allocator: std.mem.Allocator,
    config: ShellConfig,
    parser: parser.Parser,
    executor: executor.Executor,
    capability_context: capabilities.CapabilityContext,
    capability_checker: capabilities.CapabilityChecker,

    /// Current working directory
    cwd: []u8,

    /// Environment variables (owned by shell)
    env: std.StringHashMap([]u8),

    /// Command history for interactive mode
    history: std.ArrayList([]u8),

    /// Job table for job control (profile-gated)
    jobs: ?types.JobTable,

    pub fn init(allocator: std.mem.Allocator, config: ShellConfig) !Shell {
        var capability_context = try capabilities.CapabilityContext.createDefault(allocator);

        var shell = Shell{
            .allocator = allocator,
            .config = config,
            .parser = try parser.Parser.init(allocator),
            .executor = try executor.Executor.init(allocator, config),
            .capability_context = capability_context,
            .capability_checker = capabilities.CapabilityChecker.init(&capability_context),
            .cwd = try std.process.getCwdAlloc(allocator),
            .env = std.StringHashMap([]u8).init(allocator),
            .history = .empty,
            .jobs = null,
        };

        // Initialize job control for appropriate profiles
        if (config.profile == .go or config.profile == .full) {
            shell.jobs = types.JobTable.init(allocator);
        }

        // Copy initial environment
        try shell.copyEnvironment();

        return shell;
    }

    pub fn deinit(self: *Shell) void {
        self.allocator.free(self.cwd);

        // Free environment variables
        var env_iter = self.env.iterator();
        while (env_iter.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.env.deinit();

        // Free history
        for (self.history.items) |cmd| {
            self.allocator.free(cmd);
        }
        self.history.deinit();

        // Clean up job table
        if (self.jobs) |*job_table| {
            job_table.deinit();
        }

        self.parser.deinit();
        self.executor.deinit();
    }

    /// Run shell in interactive REPL mode
    pub fn runInteractive(self: *Shell) !void {
        std.debug.print("Janus Shell v0.1.0 (profile: {})\n", .{self.config.profile});
        std.debug.print("Type 'help' for available commands or 'exit' to quit.\n\n", .{});

        while (true) {
            // Display prompt
            try self.displayPrompt();

            // Read input line
            const input = try self.readLine();
            defer self.allocator.free(input);

            // Skip empty lines
            if (std.mem.trim(u8, input, " \t\n").len == 0) continue;

            // Add to history
            try self.addToHistory(input);

            // Execute command
            self.executeCommand(input) catch |err| {
                try self.handleError(err, input);
            };
        }
    }

    /// Run shell in batch/script mode
    pub fn runScript(self: *Shell, script_path: []const u8) !void {
        const file = std.fs.cwd().openFile(script_path, .{}) catch |err| {
            return diagnostics.emitScriptError(.FileNotFound, script_path, 0, 0, err);
        };
        defer file.close();

        const content = try file.readToEndAlloc(self.allocator, 1024 * 1024); // 1MB limit
        defer self.allocator.free(content);

        var line_iter = std.mem.splitScalar(u8, content, '\n');
        var line_number: u32 = 1;

        while (line_iter.next()) |line| {
            defer line_number += 1;

            const trimmed = std.mem.trim(u8, line, " \t\r");
            if (trimmed.len == 0 or trimmed[0] == '#') continue; // Skip empty lines and comments

            self.executeCommand(trimmed) catch |err| {
                try diagnostics.emitScriptError(.ParseError, script_path, line_number, 0, err);
                return;
            };
        }
    }

    /// Execute a single command line
    fn executeCommand(self: *Shell, input: []const u8) !void {
        // Parse command into AST
        var command = try self.parser.parse(input);
        defer command.deinit(self.allocator);

        // Validate deterministic mode requirements
        if (self.config.deterministic) {
            try self.validateDeterministicMode(command);
        }

        // Check required capabilities
        const required_caps = try self.capability_checker.checkCommand(command);
        defer required_caps.deinit();

        // TODO: Validate capabilities against current context
        // For now, we assume all capabilities are available

        // Execute the command
        const result = try self.executor.execute(command, .{
            .cwd = self.cwd,
            .env = &self.env,
            .jobs = if (self.jobs) |*jobs| jobs else null,
        });

        // Handle execution result
        try self.handleExecutionResult(result);
    }

    fn displayPrompt(self: *Shell) !void {
        const prompt = switch (self.config.profile) {
            .min => "jsh> ",
            .go => "jsh:go> ",
            .full => "jsh:full> ",
        };
        try std.fs.File.stdout().writeAll(prompt);
    }

    fn readLine(self: *Shell) ![]u8 {
        var buffer: [1024]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(buffer[0..]);
        const reader_io = &stdin_reader.interface;

        if (try reader_io.readUntilDelimiterOrEof(&buffer, '\n')) |input| {
            return try self.allocator.dupe(u8, std.mem.trim(u8, input, "\r\n"));
        }

        std.process.exit(0);
    }

    fn addToHistory(self: *Shell, command: []const u8) !void {
        const owned_cmd = try self.allocator.dupe(u8, command);
        try self.history.append(owned_cmd);
    }

    fn copyEnvironment(self: *Shell) !void {
        // Copy environment variables from process
        var env_map = try std.process.getEnvMap(self.allocator);
        defer env_map.deinit();

        var iter = env_map.iterator();
        while (iter.next()) |entry| {
            const key = try self.allocator.dupe(u8, entry.key_ptr.*);
            const value = try self.allocator.dupe(u8, entry.value_ptr.*);
            try self.env.put(key, value);
        }
    }

    fn validateDeterministicMode(self: *Shell, command: types.Command) !void {
        // TODO: Implement deterministic mode validation
        // - Check for absolute paths
        // - Validate timeout requirements
        // - Ensure no ambient environment access
        _ = self;
        _ = command;
    }

    fn handleExecutionResult(self: *Shell, result: executor.ExecutionResult) !void {
        switch (result.status) {
            .success => {
                // Command succeeded - nothing to do
            },
            .failure => |exit_code| {
                std.debug.print("Command failed with exit code: {}\n", .{exit_code});
            },
            .signal => |signal| {
                std.debug.print("Command terminated by signal: {}\n", .{signal});
            },
        }

        // Update job table if applicable
        if (self.jobs) |*job_table| {
            if (result.job_id) |job_id| {
                try job_table.updateJob(job_id, .completed);
            }
        }
    }

    fn handleError(self: *Shell, err: anyerror, input: []const u8) !void {
        _ = self;
        switch (err) {
            ShellError.CapabilityRequired => {
                try diagnostics.emitCapabilityError(input);
            },
            ShellError.ExecutionFailed => {
                try diagnostics.emitExecutionError(input);
            },
            ShellError.ParseError => {
                try diagnostics.emitParseError(input);
            },
            else => {
                std.debug.print("Error: {}\n", .{err});
            },
        }
    }
};
