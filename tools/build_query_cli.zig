// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Build script for Janus Query CLI - Real Implementation

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Real Query CLI executable
    const query_cli = b.addExecutable(.{
        .name = "janus-query",
        .root_source_file = b.path("janus_query_cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add dependencies to real ASTDB modules
    query_cli.root_module.addImport("astdb", b.createModule(.{
        .root_source_file = b.path("../compiler/libjanus/libjanus_astdb.zig"),
    }));

    query_cli.root_module.addImport("tokenizer", b.createModule(.{
        .root_source_file = b.path("../compiler/libjanus/janus_tokenizer.zig"),
    }));

    query_cli.root_module.addImport("parser", b.createModule(.{
        .root_source_file = b.path("../compiler/libjanus/janus_parser.zig"),
    }));

    b.installArtifact(query_cli);

    // Run command
    const run_cmd = b.addRunArtifact(query_cli);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Janus Query CLI");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const test_step = b.step("test", "Run query CLI tests");
    const tests = b.addTest(.{
        .root_source_file = b.path("janus_query_cli.zig"),
        .target = target,
        .optimize = optimize,
    });

    tests.root_module.addImport("astdb", b.createModule(.{
        .root_source_file = b.path("../compiler/libjanus/libjanus_astdb.zig"),
    }));

    const run_tests = b.addRunArtifact(tests);
    test_step.dependOn(&run_tests.step);
}
