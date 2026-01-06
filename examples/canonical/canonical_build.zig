// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Oracle Demo executable
    const oracle_demo = b.addExecutable(.{
        .name = "oracle_demo",
        .root_source_file = b.path("oracle_demo.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Add compiler modules as dependencies
    const compiler_path = b.path("../../compiler");
    oracle_demo.addIncludePath(compiler_path);

    // Install the executable
    b.installArtifact(oracle_demo);

    // Create run step
    const run_cmd = b.addRunArtifact(oracle_demo);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the Oracle Proof Pack demo");
    run_step.dependOn(&run_cmd.step);

    // Test step
    const oracle_test = b.addTest(.{
        .root_source_file = b.path("oracle_proof_pack.zig"),
        .target = target,
        .optimize = optimize,
    });

    oracle_test.addIncludePath(compiler_path);

    const test_step = b.step("test", "Run Oracle Proof Pack tests");
    test_step.dependOn(&b.addRunArtifact(oracle_test).step);
}
