// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus Shell (jsh) - Capability-gated, security-first shell
//!
//! The Janus Shell embodies our doctrines:
//! - Syntactic Honesty: No shell magic, everything explicit
//! - Mechanism over Policy: Provides tools without imposing rigid policies
//! - Revealed Complexity: Makes execution costs and security boundaries visible
//! - Honest Sugar: Convenient syntax that desugars to explicit operations
//!
//! Supports three profiles:
//! - :min - Basic functionality with simple command execution
//! - :go - Job control and structured concurrency
//! - :full - Advanced features with full capability security

const std = @import("std");
const shell = @import("shell/mod.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    // Initialize shell with appropriate profile
    var jsh = try shell.Shell.init(allocator, .{
        .profile = detectProfile(args),
        .deterministic = hasDeterministicFlag(args),
        .script_file = getScriptFile(args),
    });
    defer jsh.deinit();

    // Run shell in appropriate mode
    if (jsh.config.script_file) |script_path| {
        // Batch/script mode
        try jsh.runScript(script_path);
    } else {
        // Interactive REPL mode
        try jsh.runInteractive();
    }
}

fn detectProfile(args: []const []const u8) shell.Profile {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--profile=min")) return .min;
        if (std.mem.eql(u8, arg, "--profile=go")) return .go;
        if (std.mem.eql(u8, arg, "--profile=full")) return .full;
    }
    return .min; // Default to minimal profile
}

fn hasDeterministicFlag(args: []const []const u8) bool {
    for (args) |arg| {
        if (std.mem.eql(u8, arg, "--deterministic")) return true;
    }
    return false;
}

fn getScriptFile(args: []const []const u8) ?[]const u8 {
    var i: usize = 1; // Skip program name
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (!std.mem.startsWith(u8, arg, "--")) {
            return arg; // First non-flag argument is script file
        }
    }
    return null;
}
