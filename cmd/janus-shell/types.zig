// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Core type definitions for the Janus Shell
//!
//! This module defines all the foundational types that embody our doctrines:
//! - Explicit process specifications (no shell magic)
//! - Capability-gated operations (security first)
//! - Profile-aware feature sets (progressive disclosure)

const std = @import("std");

/// Shell execution profiles providing progressive feature disclosure
pub const Profile = enum {
    /// Minimal profile - basic command execution, simple pipelines
    min,
    /// Go profile - adds job control, structured concurrency
    go,
    /// Full profile - complete capability security, advanced features
    full,
};

/// Shell configuration options
pub const ShellConfig = struct {
    profile: Profile = .min,
    deterministic: bool = false,
    script_file: ?[]const u8 = null,
};

/// Shell-specific error types with diagnostic context
pub const ShellError = error{
    CapabilityRequired,
    ExecutionFailed,
    ParseError,
    DeterministicViolation,
    JobControlDenied,
    TtyAccessDenied,
    ZombieDetected,
    RedirectionCapabilityMissing,
    CwdChangeFailed,
    DeterministicEnvDenied,
    GlobbingDenied,
    ScriptParseError,
    ProfileFeatureDisabled,
    ConfigInvalid,
    ResourceLimitExceeded,
};

/// Standard I/O specification for process execution
pub const StdioSpec = struct {
    stdin: StdioType = .inherit,
    stdout: StdioType = .inherit,
    stderr: StdioType = .inherit,

    pub const StdioType = union(enum) {
        inherit,
        null_device,
        pipe,
        file: FileSpec,
    };

    pub const FileSpec = struct {
        path: []const u8,
        append: bool = false,
    };
};

/// Complete process specification - no hidden behavior
pub const ProcessSpec = struct {
    /// Command line arguments (argv[0] may be relative or absolute)
    argv: []const []const u8,

    /// Environment variables (null = inherit, forbidden in deterministic mode)
    env: ?std.StringHashMap([]const u8) = null,

    /// Working directory (null = inherit)
    cwd: ?[]const u8 = null,

    /// Standard I/O configuration
    stdio: StdioSpec = .{},

    /// Execution timeout in milliseconds (required in deterministic mode)
    timeout_ms: ?u32 = null,

    /// Required capabilities for this process
    required_capabilities: []const Capability = &.{},

    pub fn deinit(self: *ProcessSpec, allocator: std.mem.Allocator) void {
        // Free argv
        for (self.argv) |arg| {
            allocator.free(arg);
        }
        allocator.free(self.argv);

        // Free environment if owned
        if (self.env) |*env_map| {
            var iter = env_map.iterator();
            while (iter.next()) |entry| {
                allocator.free(entry.key_ptr.*);
                allocator.free(entry.value_ptr.*);
            }
            env_map.deinit();
        }

        // Free cwd if owned
        if (self.cwd) |cwd| {
            allocator.free(cwd);
        }

        // Free capabilities
        allocator.free(self.required_capabilities);
    }
};

/// File redirection specification
pub const Redirection = union(enum) {
    input: []const u8, // < file (requires CapFsRead)
    output: OutputSpec, // > file or >> file (requires CapFsWrite)

    pub const OutputSpec = struct {
        path: []const u8,
        append: bool = false,
    };
};

/// Command AST representing parsed shell input
pub const Command = union(enum) {
    /// Simple command with optional redirections
    simple: SimpleCommand,
    /// Pipeline of commands (cmd1 | cmd2 | cmd3)
    pipeline: Pipeline,
    /// Built-in shell command
    builtin: BuiltinCommand,

    pub const SimpleCommand = struct {
        spec: ProcessSpec,
        redirections: []const Redirection = &.{},
    };

    pub const Pipeline = struct {
        stages: []const Command,
    };

    pub const BuiltinCommand = struct {
        name: []const u8,
        args: []const []const u8,
    };

    pub fn deinit(self: *Command, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .simple => |*simple| {
                simple.spec.deinit(allocator);
                for (simple.redirections) |redir| {
                    switch (redir) {
                        .input => |path| allocator.free(path),
                        .output => |output| allocator.free(output.path),
                    }
                }
                allocator.free(simple.redirections);
            },
            .pipeline => |*pipeline| {
                for (pipeline.stages) |stage| {
                    var mutable_stage = stage;
                    mutable_stage.deinit(allocator);
                }
                allocator.free(pipeline.stages);
            },
            .builtin => |*builtin| {
                allocator.free(builtin.name);
                for (builtin.args) |arg| {
                    allocator.free(arg);
                }
                allocator.free(builtin.args);
            },
        }
    }
};

/// Capability types for security enforcement
pub const Capability = enum {
    /// Process spawning capability
    proc_spawn,
    /// File system execution capability (for absolute paths)
    fs_exec,
    /// File system read capability
    fs_read,
    /// File system write capability
    fs_write,
    /// Environment variable read capability
    env_read,
    /// Environment variable set capability
    env_set,
    /// Process signal capability
    proc_signal,
    /// Job control capability
    proc_job_control,
    /// TTY access capability
    tty_access,
};

/// Job management types for job control
pub const JobId = u32;

pub const JobState = enum {
    running,
    stopped,
    completed,
    failed,
};

pub const Job = struct {
    id: JobId,
    command_text: []const u8,
    process_ids: []const std.posix.pid_t,
    state: JobState,
    started_at: i64, // Unix timestamp
    exit_codes: []const i32,

    pub fn deinit(self: *Job, allocator: std.mem.Allocator) void {
        allocator.free(self.command_text);
        allocator.free(self.process_ids);
        allocator.free(self.exit_codes);
    }
};

pub const JobTable = struct {
    allocator: std.mem.Allocator,
    foreground_job: ?JobId = null,
    next_job_id: JobId = 1,
    jobs: std.ArrayList(Job),

    pub fn init(allocator: std.mem.Allocator) JobTable {
        return JobTable{
            .allocator = allocator,
            .jobs = std.ArrayList(Job).init(allocator),
        };
    }

    pub fn deinit(self: *JobTable) void {
        for (self.jobs.items) |*job| {
            job.deinit(self.allocator);
        }
        self.jobs.deinit();
    }

    pub fn addJob(self: *JobTable, command_text: []const u8, process_ids: []const std.posix.pid_t) !JobId {
        const job_id = self.next_job_id;
        self.next_job_id += 1;

        const job = Job{
            .id = job_id,
            .command_text = try self.allocator.dupe(u8, command_text),
            .process_ids = try self.allocator.dupe(std.posix.pid_t, process_ids),
            .state = .running,
            .started_at = std.time.timestamp(),
            .exit_codes = try self.allocator.alloc(i32, process_ids.len),
        };

        try self.jobs.append(job);
        return job_id;
    }

    pub fn updateJob(self: *JobTable, job_id: JobId, new_state: JobState) !void {
        for (self.jobs.items) |*job| {
            if (job.id == job_id) {
                job.state = new_state;
                return;
            }
        }
    }

    pub fn getJob(self: *JobTable, job_id: JobId) ?*Job {
        for (self.jobs.items) |*job| {
            if (job.id == job_id) {
                return job;
            }
        }
        return null;
    }

    pub fn removeJob(self: *JobTable, job_id: JobId) void {
        for (self.jobs.items, 0..) |*job, i| {
            if (job.id == job_id) {
                job.deinit(self.allocator);
                _ = self.jobs.swapRemove(i);
                return;
            }
        }
    }
};

/// Execution context for command execution
pub const ExecutionContext = struct {
    cwd: []const u8,
    env: *std.StringHashMap([]u8),
    jobs: ?*JobTable = null,
};

/// Diagnostic error codes as defined in the specification
pub const DiagnosticCode = enum {
    E2501_CAP_REQUIRED,
    E2502_EXEC_FAILED,
    E2503_DET_ABS_PATH_REQUIRED,
    E2504_DET_TIMEOUT_REQUIRED,
    E2505_DET_VIOLATION,
    E2506_JOBCTL_DENIED,
    E2507_TTY_ACCESS_DENIED,
    E2508_ZOMBIE_DETECTED,
    E2509_REDIRECT_CAP_MISSING,
    E2510_CWD_CHANGE_FAILED,
    E2511_DET_ENV_DENIED,
    E2512_GLOB_DENIED,
    E2513_SCRIPT_PARSE_ERROR,
    E2514_PROFILE_FEATURE_DISABLED,
    E2515_CONFIG_INVALID,
    E2516_RESOURCE_LIMIT,
};
