// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Build configuration for Janus dispatch CLI tools

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Main CLI executable
    const cli_exe = b.addExecutable(.{
        .name = "janus-dispatch",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies to compiler modules
    const libjanus_path = "../../compiler/libjanus/";
    cli_exe.addIncludePath(b.path(libjanus_path));

    // Install the executable
    b.installArtifact(cli_exe);

    // Create run step
    const run_cmd = b.addRunArtifact(cli_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the CLI tool");
    run_step.dependOn(&run_cmd.step);

    // Tests
    const cli_tests = b.addTest(.{
        .root_source_file = b.path("test_cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const test_step = b.step("test", "Run CLI tests");
    test_step.dependOn(&b.addRunArtifact(cli_tests).step);

    // Individual tool executables for development
    const query_exe = b.addExecutable(.{
        .name = "janus-query",
        .root_source_file = b.path("dispatch_query.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(query_exe);

    const tracer_exe = b.addExecutable(.{
        .name = "janus-tracer",
        .root_source_file = b.path("dispatch_tracer.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(tracer_exe);

    // Documentation generation
    const docs_step = b.step("docs", "Generate documentation");
    const docs_cmd = b.addSystemCommand(&[_][]const u8{ "zig", "build-exe", "--emit", "docs", "main.zig" });
    docs_step.dependOn(&docs_cmd.step);
}
