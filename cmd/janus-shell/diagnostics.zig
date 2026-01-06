// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Diagnostic system for the Janus Shell
//!
//! Implements comprehensive error reporting with actionable fix-its as specified
//! in the requirements. All error codes follow the E25xx format.

const std = @import("std");
const types = @import("types.zig");

/// Emit capability required error (E2501_CAP_REQUIRED)
pub fn emitCapabilityError(input: []const u8) !void {
    std.debug.print("Error E2501_CAP_REQUIRED: Missing required capabilities\n", .{});
    std.debug.print("Command: {s}\n", .{input});
    std.debug.print("Fix-it: Grant required capabilities using 'with ctx' scope or update session policy\n", .{});
}

/// Emit execution failed error (E2502_EXEC_FAILED)
pub fn emitExecutionError(input: []const u8) !void {
    std.debug.print("Error E2502_EXEC_FAILED: Command execution failed\n", .{});
    std.debug.print("Command: {s}\n", .{input});
    std.debug.print("Fix-it: Check command syntax and file permissions\n", .{});
}

/// Emit parse error (E2513_SCRIPT_PARSE_ERROR)
pub fn emitParseError(input: []const u8) !void {
    std.debug.print("Error E2513_SCRIPT_PARSE_ERROR: Failed to parse command\n", .{});
    std.debug.print("Command: {s}\n", .{input});
    std.debug.print("Fix-it: Check command syntax and quoting\n", .{});
}

/// Emit script-specific errors with location information
pub fn emitScriptError(error_type: ScriptErrorType, script_path: []const u8, line: u32, column: u32, underlying_error: anyerror) !void {
    switch (error_type) {
        .FileNotFound => {
            std.debug.print("Error E2513_SCRIPT_PARSE_ERROR: Script file not found\n", .{});
            std.debug.print("File: {s}\n", .{script_path});
            std.debug.print("Underlying error: {}\n", .{underlying_error});
        },
        .ParseError => {
            std.debug.print("Error E2513_SCRIPT_PARSE_ERROR: Script parsing failed\n", .{});
            std.debug.print("File: {s}:{}:{}\n", .{ script_path, line, column });
            std.debug.print("Underlying error: {}\n", .{underlying_error});
        },
    }
}

const ScriptErrorType = enum {
    FileNotFound,
    ParseError,
};

/// Emit deterministic mode errors
pub fn emitDeterministicError(error_code: types.DiagnosticCode, context: []const u8) !void {
    switch (error_code) {
        .E2503_DET_ABS_PATH_REQUIRED => {
            std.debug.print("Error E2503_DET_ABS_PATH_REQUIRED: Absolute path required in deterministic mode\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Use absolute path or disable deterministic mode\n", .{});
        },
        .E2504_DET_TIMEOUT_REQUIRED => {
            std.debug.print("Error E2504_DET_TIMEOUT_REQUIRED: Timeout required in deterministic mode\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Add timeout_ms to ProcessSpec or disable deterministic mode\n", .{});
        },
        .E2505_DET_VIOLATION => {
            std.debug.print("Error E2505_DET_VIOLATION: Deterministic mode violation\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Follow deterministic mode requirements or disable deterministic mode\n", .{});
        },
        .E2511_DET_ENV_DENIED => {
            std.debug.print("Error E2511_DET_ENV_DENIED: Environment access denied in deterministic mode\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Provide explicit environment table or disable deterministic mode\n", .{});
        },
        else => {
            std.debug.print("Error {}: Deterministic mode error\n", .{error_code});
            std.debug.print("Context: {s}\n", .{context});
        },
    }
}

/// Emit job control errors
pub fn emitJobControlError(error_code: types.DiagnosticCode, context: []const u8) !void {
    switch (error_code) {
        .E2506_JOBCTL_DENIED => {
            std.debug.print("Error E2506_JOBCTL_DENIED: Job control capability denied\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Grant CapProcJobCtl and CapProcSignal capabilities\n", .{});
        },
        .E2507_TTY_ACCESS_DENIED => {
            std.debug.print("Error E2507_TTY_ACCESS_DENIED: TTY access capability denied\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Grant CapTtyAccess capability\n", .{});
        },
        .E2508_ZOMBIE_DETECTED => {
            std.debug.print("Error E2508_ZOMBIE_DETECTED: Unreaped child process detected\n", .{});
            std.debug.print("Context: {s}\n", .{context});
            std.debug.print("Fix-it: Ensure proper process cleanup in pipeline execution\n", .{});
        },
        else => {
            std.debug.print("Error {}: Job control error\n", .{error_code});
            std.debug.print("Context: {s}\n", .{context});
        },
    }
}

/// Emit file system errors
pub fn emitFileSystemError(error_code: types.DiagnosticCode, path: []const u8, operation: []const u8) !void {
    switch (error_code) {
        .E2509_REDIRECT_CAP_MISSING => {
            std.debug.print("Error E2509_REDIRECT_CAP_MISSING: File redirection capability missing\n", .{});
            std.debug.print("Operation: {s}\n", .{operation});
            std.debug.print("Path: {s}\n", .{path});
            std.debug.print("Fix-it: Grant CapFsRead for input redirection or CapFsWrite for output redirection\n", .{});
        },
        .E2510_CWD_CHANGE_FAILED => {
            std.debug.print("Error E2510_CWD_CHANGE_FAILED: Directory change failed\n", .{});
            std.debug.print("Path: {s}\n", .{path});
            std.debug.print("Fix-it: Check directory exists and has proper permissions\n", .{});
        },
        .E2512_GLOB_DENIED => {
            std.debug.print("Error E2512_GLOB_DENIED: Globbing capability denied\n", .{});
            std.debug.print("Path: {s}\n", .{path});
            std.debug.print("Fix-it: Grant CapFsRead capability for target directories\n", .{});
        },
        else => {
            std.debug.print("Error {}: File system error\n", .{error_code});
            std.debug.print("Path: {s}\n", .{path});
        },
    }
}

/// Emit profile-related errors
pub fn emitProfileError(error_code: types.DiagnosticCode, feature: []const u8, current_profile: types.Profile) !void {
    switch (error_code) {
        .E2514_PROFILE_FEATURE_DISABLED => {
            std.debug.print("Error E2514_PROFILE_FEATURE_DISABLED: Feature disabled in current profile\n", .{});
            std.debug.print("Feature: {s}\n", .{feature});
            std.debug.print("Current profile: {}\n", .{current_profile});
            std.debug.print("Fix-it: Use appropriate profile (--profile=go or --profile=full) or use alternative approach\n", .{});
        },
        else => {
            std.debug.print("Error {}: Profile error\n", .{error_code});
            std.debug.print("Feature: {s}\n", .{feature});
        },
    }
}

/// Emit resource limit errors
pub fn emitResourceError(error_code: types.DiagnosticCode, resource: []const u8, limit: []const u8) !void {
    switch (error_code) {
        .E2516_RESOURCE_LIMIT => {
            std.debug.print("Error E2516_RESOURCE_LIMIT: Resource limit exceeded\n", .{});
            std.debug.print("Resource: {s}\n", .{resource});
            std.debug.print("Limit: {s}\n", .{limit});
            std.debug.print("Fix-it: Reduce resource usage or increase limits\n", .{});
        },
        else => {
            std.debug.print("Error {}: Resource error\n", .{error_code});
            std.debug.print("Resource: {s}\n", .{resource});
        },
    }
}

/// Emit configuration errors
pub fn emitConfigError(error_code: types.DiagnosticCode, config_path: []const u8, issue: []const u8) !void {
    switch (error_code) {
        .E2515_CONFIG_INVALID => {
            std.debug.print("Error E2515_CONFIG_INVALID: Configuration file invalid\n", .{});
            std.debug.print("File: {s}\n", .{config_path});
            std.debug.print("Issue: {s}\n", .{issue});
            std.debug.print("Fix-it: Correct configuration syntax or remove invalid entries\n", .{});
        },
        else => {
            std.debug.print("Error {}: Configuration error\n", .{error_code});
            std.debug.print("File: {s}\n", .{config_path});
        },
    }
}
