// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ============================================================================
// JANUS PACKAGE PACKER DEMONSTRATION
// ============================================================================
//
// This demonstrates the .jpk packer functionality without requiring
// the full project build. Shows SBOM generation, BLAKE3 hashing,
// and package structure creation.
//
// Run with: zig run demo_pack.zig
//

const std = @import("std");
const packer = @import("packer.zig");

// Simple demo to show .jpk packer functionality
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🎯 Janus Package Packer Demonstration\n", .{});
    std.debug.print("====================================\n", .{});
    std.debug.print("\n📦 Creating a sample .jpk package...\n", .{});

    // Create a simple test directory structure
    try createDemoStructure(allocator);

    // Configure the packer
    const config = packer.PackerConfig{
        .output_dir = "demo_output/",
        .package_format = .jpk,
        .compression = .zstd,
        .include_sbom = true,
        .sbom_format = .cyclonedx_json,
        .generate_manifest = true,
        .sign_package = false, // No signing for demo
        .verify_integrity = true,
        .parallel_workers = 2,
        .chunk_size = 64 * 1024,
        .buffer_size = 1024 * 1024,
    };

    std.debug.print("⚙️  Packer Configuration:\n", .{});
    std.debug.print("   • Output format: .jpk\n", .{});
    std.debug.print("   • SBOM generation: enabled (CycloneDX JSON)\n", .{});
    std.debug.print("   • Manifest generation: enabled\n", .{});
    std.debug.print("   • Integrity verification: enabled\n", .{});
    std.debug.print("   • Compression: Zstandard\n", .{});
    std.debug.print("   • Workers: 2 parallel\n", .{});

    // Create the packer
    var package_packer = try packer.PackagePacker.init(allocator, config, "demo_cas/");
    defer package_packer.deinit();

    // Pack the demo project
    var package = try package_packer.pack("demo_project/", "janus-demo", "1.0.0");
    defer package.deinit();

    std.debug.print("\n📋 Package Analysis Results:\n", .{});
    std.debug.print("   • Package name: {s}\n", .{package.programs.items[0].name});
    std.debug.print("   • Version: {s}\n", .{package.programs.items[0].version});
    std.debug.print("   • Binaries found: {d}\n", .{package.programs.items[0].binaries.items.len});
    std.debug.print("   • Libraries found: {d}\n", .{package.programs.items[0].libraries.items.len});
    std.debug.print("   • Data files found: {d}\n", .{package.programs.items[0].data_files.items.len});

    if (package.hash_b3) |hash| {
        const hash_hex = try packer.hexSlice(allocator, &hash);
        defer allocator.free(hash_hex);
        std.debug.print("\n🔐 BLAKE3 Merkle Root: {s}\n", .{hash_hex});
    }

    if (package.sbom_content) |sbom| {
        std.debug.print("\n📄 SBOM Generated: {d} bytes\n", .{sbom.len});
        const preview_len: usize = @min(200, sbom.len);
        std.debug.print("   SBOM preview: {s}...\n", .{sbom[0..preview_len]});
    }

    // Write the package
    const output_path = try std.fmt.allocPrint(allocator, "{s}janus-demo-1.0.0.jpk", .{config.output_dir});
    defer allocator.free(output_path);

    try package_packer.writePackage(&package, output_path);

    std.debug.print("🎉 Demo package created!\n", .{});
    std.debug.print("   Output: {s}\n", .{output_path});
    const hash_hex2 = try packer.hexSlice(allocator, &package.hash_b3.?);
    defer allocator.free(hash_hex2);
    std.debug.print("   Hash:   {s}\n", .{hash_hex2});
    std.debug.print("   Integrity: BLAKE3 content-addressed\n", .{});

    // Cleanup
    try std.fs.cwd().deleteTree("demo_project/");
    try std.fs.cwd().deleteTree("demo_cas/");
    try std.fs.cwd().deleteTree("demo_output/");

    std.debug.print("\n✅ Demo completed successfully!\n", .{});
    std.debug.print("\n🚀 Key Features Demonstrated:\n", .{});
    std.debug.print("   • Content-addressed package creation\n", .{});
    std.debug.print("   • BLAKE3 Merkle tree hashing\n", .{});
    std.debug.print("   • CycloneDX SBOM generation\n", .{});
    std.debug.print("   • Deterministic package structure\n", .{});
    std.debug.print("   • Capability-based security model\n", .{});
    std.debug.print("   • High-performance serde integration\n", .{});
}

fn createDemoStructure(_: std.mem.Allocator) !void {
    // Create a demo project structure
    try std.fs.cwd().makePath("demo_project/Programs/janus-demo/1.0.0/bin/");
    try std.fs.cwd().makePath("demo_project/Programs/janus-demo/1.0.0/lib/");
    try std.fs.cwd().makePath("demo_project/Programs/janus-demo/1.0.0/include/");

    // Create some demo files
    const demo_files = [_]struct { path: []const u8, content: []const u8 }{
        .{
            .path = "demo_project/Programs/janus-demo/1.0.0/bin/janus-demo",
            .content = "#!/bin/bash\necho 'Janus Demo Package'\n",
        },
        .{
            .path = "demo_project/Programs/janus-demo/1.0.0/lib/libdemo.so",
            .content = "# Demo shared library\n",
        },
        .{
            .path = "demo_project/Programs/janus-demo/1.0.0/include/demo.h",
            .content = "// Demo header file\n#pragma once\nvoid demo_function(void);\n",
        },
        .{
            .path = "demo_project/Programs/janus-demo/1.0.0/README.md",
            .content = "# Janus Demo Package\n\nThis is a demonstration package for the Janus Package Manager.\n",
        },
    };

    for (demo_files) |file| {
        try std.fs.cwd().writeFile(.{ .sub_path = file.path, .data = file.content });
        // Make executable
        if (std.mem.containsAtLeast(u8, file.path, 1, "bin/")) {
            const stat = try std.fs.cwd().statFile(file.path);
            var f = try std.fs.cwd().openFile(file.path, .{ .mode = .read_write });
            defer f.close();
            try std.posix.fchmod(f.handle, stat.mode | 0o111);
        }
    }

    std.debug.print("📁 Created demo project structure\n", .{});
}
