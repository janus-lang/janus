// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ============================================================================
// HINGE PACKAGE MANAGER BUILD CONFIGURATION
// ============================================================================
//
// This build file allows building the hinge package manager tools
// independently of the main Janus compiler project.
//
// Usage:
//   zig build demo         # Build and run the packer demonstration
//   zig build pack         # Build the packer tool
//   zig build main         # Build the main CLI
//

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const crypto_backend = b.option([]const u8, "crypto-backend", "Select crypto backend: test|pqclean") orelse "test";

    // Module dependencies
    const libjanus_module = b.createModule(.{
        .root_source_file = b.path("../../compiler/libjanus/libjanus.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Main hinge CLI
    const main_exe = b.addExecutable(.{
        .name = "hinge",
        .root_module = b.createModule(.{
            .root_source_file = b.path("main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    main_exe.root_module.addImport("libjanus", libjanus_module);
    var opts = b.addOptions();
    opts.addOption([]const u8, "crypto_backend", crypto_backend);
    main_exe.root_module.addOptions("build_options", opts);
    b.installArtifact(main_exe);

    // Packer demonstration
    const demo_exe = b.addExecutable(.{
        .name = "hinge-demo",
        .root_module = b.createModule(.{
            .root_source_file = b.path("demo_pack.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    demo_exe.root_module.addImport("libjanus", libjanus_module);
    demo_exe.root_module.addOptions("build_options", opts);
    b.installArtifact(demo_exe);

    // Run demo step
    const run_demo = b.addRunArtifact(demo_exe);
    run_demo.step.dependOn(b.getInstallStep());
    const demo_step = b.step("demo", "Run the package packer demonstration");
    demo_step.dependOn(&run_demo.step);

    // Default step
    const run_main = b.addRunArtifact(main_exe);
    run_main.step.dependOn(b.getInstallStep());
    const main_step = b.step("run", "Run the hinge package manager");
    main_step.dependOn(&run_main.step);
}
