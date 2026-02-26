// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Shared Runtime Compilation Utility for E2E Tests
//!
//! This module provides common functions for compiling the Janus runtime
//! in integration tests. It handles:
//! - Runtime compilation (janus_rt.zig → janus_rt.o)
//! - Context switch assembly (context_switch.s → context_switch.o)
//! - Linking with proper object file ordering

const std = @import("std");
const testing = std.testing;
const io = testing.io;

/// Compile the Janus runtime and context switch assembly to a temp directory.
/// Returns paths to the object files that must be linked.
pub const RuntimeObjects = struct {
    runtime_obj: []const u8,
    asm_obj: []const u8,
    allocator: std.mem.Allocator,

    pub fn deinit(self: *RuntimeObjects) void {
        self.allocator.free(self.runtime_obj);
        self.allocator.free(self.asm_obj);
    }
};

/// Compile the runtime and assembly files to the given output directory.
/// Assumes CWD is the project root.
pub fn compileRuntime(allocator: std.mem.Allocator, output_dir: []const u8) !RuntimeObjects {
    // Paths for output object files
    const rt_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ output_dir, "janus_rt.o" });
    errdefer allocator.free(rt_obj_path);

    const asm_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ output_dir, "context_switch.o" });
    errdefer allocator.free(asm_obj_path);

    // Compile runtime
    const rt_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{rt_obj_path});
    defer allocator.free(rt_emit_arg);

    const zig_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "zig",
            "build-obj",
            "runtime/janus_rt.zig",
            rt_emit_arg,
            "-lc",
        },
    });
    defer allocator.free(zig_build_result.stdout);
    defer allocator.free(zig_build_result.stderr);

    if (zig_build_result.term.exited != 0) {
        return error.RuntimeCompilationFailed;
    }

    // Compile context switch assembly
    const asm_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{asm_obj_path});
    defer allocator.free(asm_emit_arg);

    const asm_build_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "zig",
            "build-obj",
            "runtime/scheduler/context_switch.s",
            asm_emit_arg,
        },
    });
    defer allocator.free(asm_build_result.stdout);
    defer allocator.free(asm_build_result.stderr);

    if (asm_build_result.term.exited != 0) {
        return error.AssemblyCompilationFailed;
    }

    return RuntimeObjects{
        .runtime_obj = rt_obj_path,
        .asm_obj = asm_obj_path,
        .allocator = allocator,
    };
}

/// Link an object file with the runtime to produce an executable.
pub fn linkWithRuntime(
    allocator: std.mem.Allocator,
    main_obj: []const u8,
    runtime_objs: RuntimeObjects,
    output_exe: []const u8,
) !void {
    const link_result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{
            "cc",
            main_obj,
            runtime_objs.runtime_obj,
            runtime_objs.asm_obj,
            "-o",
            output_exe,
        },
    });
    defer allocator.free(link_result.stdout);
    defer allocator.free(link_result.stderr);

    if (link_result.term.exited != 0) {
        return error.LinkFailed;
    }
}

/// Execute a compiled program and return its output.
pub fn executeProgram(allocator: std.mem.Allocator, exe_path: []const u8) !struct {
    stdout: []const u8,
    stderr: []const u8,
    exit_code: u8,
} {
    const result = try std.process.run(allocator, io, .{
        .argv = &[_][]const u8{exe_path},
    });

    return .{
        .stdout = result.stdout,
        .stderr = result.stderr,
        .exit_code = if (result.term == .exited) result.term.exited else 255,
    };
}
