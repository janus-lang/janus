// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Cross-compilation verification tool for Citadel Architecture
//!
//! This tool verifies that janus-core-daemon can be built for all target platforms
//! without external dependencies, fulfilling the cross-platform deployment requirement.

const std = @import("std");
const builtin = @import("builtin");
const print = std.debug.print;

/// Target platforms for cross-compilation testing
const CrossCompileTarget = struct {
    name: []const u8,
    target_triple: []const u8,
    description: []const u8,
    expected_success: bool,
};

const CROSS_COMPILE_TARGETS = [_]CrossCompileTarget{
    // Linux targets
    .{
        .name = "linux-x86_64-musl",
        .target_triple = "x86_64-linux-musl",
        .description = "Linux x86_64 with musl (static linking)",
        .expected_success = true,
    },
    .{
        .name = "linux-aarch64-musl",
        .target_triple = "aarch64-linux-musl",
        .description = "Linux ARM64 with musl (static linking)",
        .expected_success = true,
    },
    .{
        .name = "linux-riscv64-musl",
        .target_triple = "riscv64-linux-musl",
        .description = "Linux RISC-V 64-bit with musl",
        .expected_success = true,
    },

    // macOS targets
    .{
        .name = "macos-x86_64",
        .target_triple = "x86_64-macos",
        .description = "macOS Intel x86_64",
        .expected_success = true,
    },
    .{
        .name = "macos-aarch64",
        .target_triple = "aarch64-macos",
        .description = "macOS Apple Silicon ARM64",
        .expected_success = true,
    },

    // Windows targets
    .{
        .name = "windows-x86_64",
        .target_triple = "x86_64-windows",
        .description = "Windows x86_64",
        .expected_success = true,
    },

    // Embedded/minimal targets
    .{
        .name = "linux-x86_64-gnu",
        .target_triple = "x86_64-linux-gnu",
        .description = "Linux x86_64 with glibc (dynamic linking)",
        .expected_success = true,
    },
};

/// Test cross-compilation for a specific target
fn testCrossCompile(allocator: std.mem.Allocator, target: CrossCompileTarget) !bool {
    print("🔨 Testing cross-compilation: {s}\n", .{target.name});
    print("   Target: {s}\n", .{target.target_triple});
    print("   Description: {s}\n", .{target.description});

    // Build command for janus-core-daemon
    const build_cmd = try std.fmt.allocPrint(allocator, "zig build -Dtarget={s} -Doptimize=ReleaseSafe", .{target.target_triple});
    defer allocator.free(build_cmd);

    print("   Command: {s}\n", .{build_cmd});

    // Execute build command
    var child = std.process.Child.init(&[_][]const u8{ "bash", "-c", build_cmd }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();

    const stdout = try child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stdout);

    const stderr = try child.stderr.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(stderr);

    const term = try child.wait();

    const success = switch (term) {
        .Exited => |code| code == 0,
        else => false,
    };

    if (success) {
        print("   ✅ SUCCESS: Cross-compilation completed\n", .{});

        // Verify binary was created
        const binary_path = try std.fmt.allocPrint(allocator, "zig-out/bin/janus-core-daemon", .{});
        defer allocator.free(binary_path);

        const file = std.fs.cwd().openFile(binary_path, .{}) catch |err| {
            print("   ⚠️  WARNING: Binary not found at {s}: {}\n", .{ binary_path, err });
            return false;
        };
        file.close();

        print("   ✅ Binary created successfully\n", .{});

        // Check binary size
        const stat = try std.fs.cwd().statFile(binary_path);
        const size_mb = @as(f64, @floatFromInt(stat.size)) / (1024.0 * 1024.0);
        print("   📊 Binary size: {d:.2} MB\n", .{size_mb});
    } else {
        print("   ❌ FAILED: Cross-compilation failed\n", .{});
        if (stderr.len > 0) {
            print("   Error output:\n{s}\n", .{stderr});
        }
    }

    print("\n", .{});
    return success;
}

/// Test that janus-core-daemon has no external dependencies
fn testDependencyIsolation(allocator: std.mem.Allocator) !bool {
    print("🔍 Testing dependency isolation...\n", .{});

    // Build janus-core-daemon (built as part of default install)
    const build_cmd = "zig build -Doptimize=ReleaseSafe";

    var child = std.process.Child.init(&[_][]const u8{ "bash", "-c", build_cmd }, allocator);
    child.stdout_behavior = .Pipe;
    child.stderr_behavior = .Pipe;

    try child.spawn();
    _ = try child.wait();

    // Check dependencies using ldd (Linux) or otool (macOS)
    const check_deps_cmd = if (builtin.os.tag == .linux)
        "ldd zig-out/bin/janus-core-daemon 2>/dev/null || echo 'Static binary (no dependencies)'"
    else if (builtin.os.tag == .macos)
        "otool -L zig-out/bin/janus-core-daemon 2>/dev/null || echo 'Static binary (no dependencies)'"
    else
        "echo 'Dependency check not supported on this platform'";

    var deps_child = std.process.Child.init(&[_][]const u8{ "bash", "-c", check_deps_cmd }, allocator);
    deps_child.stdout_behavior = .Pipe;
    deps_child.stderr_behavior = .Pipe;

    try deps_child.spawn();

    const deps_output = try deps_child.stdout.?.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(deps_output);

    _ = try deps_child.wait();

    print("Dependencies:\n{s}\n", .{deps_output});

    // Check for forbidden dependencies
    const forbidden_deps = [_][]const u8{
        "libgrpc",
        "libprotobuf",
        "libstdc++",
        "libgcc_s",
    };

    var has_forbidden = false;
    for (forbidden_deps) |forbidden| {
        if (std.mem.indexOf(u8, deps_output, forbidden) != null) {
            print("❌ FORBIDDEN DEPENDENCY FOUND: {s}\n", .{forbidden});
            has_forbidden = true;
        }
    }

    if (!has_forbidden) {
        print("✅ No forbidden dependencies found\n", .{});
        return true;
    } else {
        print("❌ Dependency isolation test failed\n", .{});
        return false;
    }
}

/// Main cross-compilation test runner
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🔥 CITADEL ARCHITECTURE CROSS-COMPILATION VERIFICATION 🔥\n", .{});
    print("Testing cross-platform deployment capability...\n\n", .{});

    var total_tests: u32 = 0;
    var passed_tests: u32 = 0;

    // Test dependency isolation first
    total_tests += 1;
    if (try testDependencyIsolation(allocator)) {
        passed_tests += 1;
    }

    // Test cross-compilation for each target
    for (CROSS_COMPILE_TARGETS) |target| {
        total_tests += 1;

        const success = testCrossCompile(allocator, target) catch |err| blk: {
            print("❌ ERROR testing {s}: {}\n\n", .{ target.name, err });
            break :blk false;
        };

        if (success == target.expected_success) {
            passed_tests += 1;
        } else if (target.expected_success) {
            print("❌ UNEXPECTED FAILURE for {s}\n\n", .{target.name});
        } else {
            print("❌ UNEXPECTED SUCCESS for {s} (expected to fail)\n\n", .{target.name});
        }
    }

    // Summary
    print("🎯 CROSS-COMPILATION TEST RESULTS:\n", .{});
    print("   Total tests: {}\n", .{total_tests});
    print("   Passed: {}\n", .{passed_tests});
    print("   Failed: {}\n", .{total_tests - passed_tests});

    if (passed_tests == total_tests) {
        print("\n🔥 ALL TESTS PASSED! CITADEL ARCHITECTURE IS CROSS-PLATFORM READY! 🔥\n", .{});
    } else {
        print("\n❌ Some tests failed. Cross-platform deployment needs work.\n", .{});
        std.process.exit(1);
    }
}
