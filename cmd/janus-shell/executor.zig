// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Command executor for the Janus Shell
//!
//! Implements honest command execution with no shell magic - everything desugars
//! to explicit std.process operations with capability checking.

const std = @import("std");
const types = @import("types.zig");
const builtins = @import("builtins.zig");

/// Execution result status
pub const ExecutionStatus = union(enum) {
    success,
    failure: i32, // exit code
    signal: i32, // signal number
};

/// Result of command execution
pub const ExecutionResult = struct {
    status: ExecutionStatus,
    job_id: ?types.JobId = null,
    stdout: ?[]u8 = null,
    stderr: ?[]u8 = null,

    pub fn deinit(self: *ExecutionResult, allocator: std.mem.Allocator) void {
        if (self.stdout) |stdout| allocator.free(stdout);
        if (self.stderr) |stderr| allocator.free(stderr);
    }
};

/// Command executor implementing honest execution semantics
pub const Executor = struct {
    allocator: std.mem.Allocator,
    config: types.ShellConfig,
    builtin_handler: builtins.BuiltinHandler,

    pub fn init(allocator: std.mem.Allocator, config: types.ShellConfig) !Executor {
        return Executor{
            .allocator = allocator,
            .config = config,
            .builtin_handler = try builtins.BuiltinHandler.init(allocator, config),
        };
    }

    pub fn deinit(self: *Executor) void {
        self.builtin_handler.deinit();
    }

    /// Execute a command with explicit context
    pub fn execute(self: *Executor, command: types.Command, context: types.ExecutionContext) anyerror!ExecutionResult {
        switch (command) {
            .simple => |simple| {
                return try self.executeSimple(simple, context);
            },
            .pipeline => |pipeline| {
                return try self.executePipeline(pipeline, context);
            },
            .builtin => |builtin| {
                return try self.executeBuiltin(builtin, context);
            },
        }
    }

    fn executeSimple(self: *Executor, simple: types.Command.SimpleCommand, context: types.ExecutionContext) anyerror!ExecutionResult {
        // Apply redirections to create stdio spec
        var stdio_spec = simple.spec.stdio;
        try self.applyRedirections(simple.redirections, &stdio_spec);

        // Create process specification
        var process_spec = simple.spec;
        process_spec.stdio = stdio_spec;

        // Set working directory and environment
        if (process_spec.cwd == null) {
            process_spec.cwd = context.cwd;
        }

        if (process_spec.env == null and !self.config.deterministic) {
            // In non-deterministic mode, inherit environment
            // TODO: Convert context.env to the format expected by std.process
        }

        // Spawn process
        var result = try self.spawnProcess(process_spec);

        // Add to job table if available
        var job_id: ?types.JobId = null;
        if (context.jobs) |job_table| {
            job_id = try job_table.addJob("command", &.{result.id});
        }

        // Wait for completion
        const term = try result.wait();

        return ExecutionResult{
            .status = switch (term) {
                .Exited => |code| if (code == 0) .success else ExecutionStatus{ .failure = code },
                .Signal => |sig| ExecutionStatus{ .signal = @intCast(sig) },
                .Stopped => |sig| ExecutionStatus{ .signal = @intCast(sig) },
                .Unknown => |code| ExecutionStatus{ .failure = @intCast(code) },
            },
            .job_id = job_id,
        };
    }

    fn executePipeline(self: *Executor, pipeline: types.Command.Pipeline, context: types.ExecutionContext) anyerror!ExecutionResult {
        if (pipeline.stages.len == 0) {
            return ExecutionResult{ .status = .success };
        }

        if (pipeline.stages.len == 1) {
            return try self.execute(pipeline.stages[0], context);
        }

        // Create pipes for pipeline stages
        var pipes = std.ArrayList(std.posix.fd_t).init(self.allocator);
        defer pipes.deinit();

        var processes = std.ArrayList(std.process.Child).init(self.allocator);
        defer processes.deinit();

        // Create n-1 pipes for n stages
        for (0..pipeline.stages.len - 1) |_| {
            const pipe_fds = try std.posix.pipe();
            try pipes.append(pipe_fds[0]); // read end
            try pipes.append(pipe_fds[1]); // write end
        }

        // Spawn all stages
        for (pipeline.stages, 0..) |stage, i| {
            // TODO: Implement full pipeline execution
            _ = stage;
            _ = i;
            // _ = pipes;
            // This is a simplified version - full implementation would handle
            // the complexity of pipe wiring and process management
        }

        // Wait for all processes and collect results
        var last_exit_code: i32 = 0;
        for (processes.items) |*process| {
            const term = try process.wait();
            switch (term) {
                .Exited => |code| last_exit_code = code,
                .Signal => |sig| return ExecutionResult{ .status = ExecutionStatus{ .signal = @intCast(sig) } },
                else => last_exit_code = 1,
            }
        }

        return ExecutionResult{
            .status = if (last_exit_code == 0) .success else ExecutionStatus{ .failure = last_exit_code },
        };
    }

    fn executeBuiltin(self: *Executor, builtin: types.Command.BuiltinCommand, context: types.ExecutionContext) anyerror!ExecutionResult {
        const exit_code = try self.builtin_handler.execute(builtin.name, builtin.args, context);

        return ExecutionResult{
            .status = if (exit_code == 0) .success else ExecutionStatus{ .failure = exit_code },
        };
    }

    fn applyRedirections(self: *Executor, redirections: []const types.Redirection, stdio_spec: *types.StdioSpec) !void {
        _ = self;

        for (redirections) |redir| {
            switch (redir) {
                .input => |path| {
                    stdio_spec.stdin = .{ .file = .{ .path = path, .append = false } };
                },
                .output => |output| {
                    stdio_spec.stdout = .{ .file = .{ .path = output.path, .append = output.append } };
                },
            }
        }
    }

    fn spawnProcess(self: *Executor, spec: types.ProcessSpec) !std.process.Child {
        var process = std.process.Child.init(spec.argv, self.allocator);

        // Set working directory
        if (spec.cwd) |cwd| {
            process.cwd = cwd;
        }

        // Set environment
        if (spec.env) |env_map| {
            // Convert StringHashMap to format expected by ChildProcess
            // TODO: Implement environment conversion
            _ = env_map;
        }

        // Configure stdio
        switch (spec.stdio.stdin) {
            .inherit => process.stdin_behavior = .Inherit,
            .null_device => process.stdin_behavior = .Ignore,
            .pipe => process.stdin_behavior = .Pipe,
            .file => |file_spec| {
                // TODO: Open file and set as stdin
                _ = file_spec;
                process.stdin_behavior = .Ignore; // Placeholder
            },
        }

        switch (spec.stdio.stdout) {
            .inherit => process.stdout_behavior = .Inherit,
            .null_device => process.stdout_behavior = .Ignore,
            .pipe => process.stdout_behavior = .Pipe,
            .file => |file_spec| {
                // TODO: Open file and set as stdout
                _ = file_spec;
                process.stdout_behavior = .Ignore; // Placeholder
            },
        }

        switch (spec.stdio.stderr) {
            .inherit => process.stderr_behavior = .Inherit,
            .null_device => process.stderr_behavior = .Ignore,
            .pipe => process.stderr_behavior = .Pipe,
            .file => |file_spec| {
                // TODO: Open file and set as stderr
                _ = file_spec;
                process.stderr_behavior = .Ignore; // Placeholder
            },
        }

        try process.spawn();
        return process;
    }
};
