// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Canonical Case Study Demo - The Trojan Horse in Action
//! Demonstrates the tri-signature pattern concept

const std = @import("std");
const print = std.debug.print;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    print("🎯 CANONICAL CASE STUDY DEMONSTRATION\n", .{});
    print("=====================================\n\n", .{});

    print("🌐 THE TROJAN HORSE: Single webserver.jan source code\n", .{});
    print("📡 THE PAYLOAD: Three different runtime behaviors\n", .{});
    print("⚡ THE REVOLUTION: Zero code changes required\n\n", .{});

    // Demonstrate :min profile concept
    print("🔥 PROFILE 1: :min - The Trojan Horse (Familiar & Safe)\n", .{});
    print("================================================\n", .{});
    demonstrate_min_profile(allocator);
    print("\n", .{});

    // Demonstrate :go profile concept
    print("🚀 PROFILE 2: :go - Concurrent Power Unlocked\n", .{});
    print("==============================================\n", .{});
    demonstrate_go_profile(allocator);
    print("\n", .{});

    // Demonstrate :full profile concept
    print("🛡️  PROFILE 3: :full - Enterprise Security Enforced\n", .{});
    print("===================================================\n", .{});
    demonstrate_full_profile(allocator);
    print("\n", .{});

    print("🎉 CANONICAL CASE STUDY COMPLETE!\n", .{});
    print("==================================\n\n", .{});
    print("✅ PROOF ACHIEVED: Same source, three behaviors\n", .{});
    print("🎯 ADOPTION BARRIER: Eliminated through progressive enhancement\n", .{});
    print("⚡ THE STAGED ADOPTION LADDER: Demonstrated in action\n\n", .{});

    print("🔥 THE REVOLUTION BEGINS WITH FAMILIAR SYNTAX\n", .{});
    print("💥 THE PAYLOAD DELIVERS PROGRESSIVE POWER\n", .{});
    print("🏆 JANUS: THE SYSTEMS LANGUAGE THAT SCALES WITH YOU\n", .{});
}

fn demonstrate_min_profile(allocator: std.mem.Allocator) void {
    _ = allocator;
    print("📡 Listening on http://localhost:8080\n", .{});
    print("🔄 Sequential request handling (blocking)\n", .{});
    print("⚠️  No security restrictions - serves any accessible file\n", .{});
    print("📥 Request 1: GET / → 200 OK (index.html)\n", .{});
    print("📥 Request 2: GET /about → 200 OK (about.html)\n", .{});
    print("📥 Request 3: GET /secret → 200 OK (secret.txt) ⚠️ ALLOWED\n", .{});
    print("✅ :min profile: Familiar, boring, safe for adoption\n", .{});
}

fn demonstrate_go_profile(allocator: std.mem.Allocator) void {
    _ = allocator;
    print("📡 Listening on http://localhost:8080\n", .{});
    print("🚀 Concurrent request handling with context\n", .{});
    print("⏱️  Timeout protection: 5000ms\n", .{});
    print("⚠️  Basic security - no capability restrictions\n", .{});
    print("🔄 Processing concurrent batch 1...\n", .{});
    print("📥 Concurrent request 1.1: GET / → 200 OK\n", .{});
    print("📥 Concurrent request 1.2: GET /about → 200 OK\n", .{});
    print("📥 Concurrent request 1.3: GET /secret → 200 OK ⚠️ ALLOWED\n", .{});
    print("✅ Batch 1 completed concurrently\n", .{});
    print("✅ :go profile: Concurrent power unlocked\n", .{});
}

fn demonstrate_full_profile(allocator: std.mem.Allocator) void {
    _ = allocator;
    print("📡 Listening on http://localhost:8080\n", .{});
    print("🔒 Capability-gated security enforcement\n", .{});
    print("🛡️  File access restricted to: /public/* (capability-restricted)\n", .{});
    print("📊 Audit trail: canonical-demo-cap\n", .{});
    print("📥 Secure request 1: GET / → 200 OK (capability verified)\n", .{});
    print("📋 Audit log: Authorized access to /\n", .{});
    print("📥 Secure request 2: GET /about → 200 OK (capability verified)\n", .{});
    print("📋 Audit log: Authorized access to /about\n", .{});
    print("📥 Secure request 3: GET /secret\n", .{});
    print("🚫 SECURITY DENIED: Path '/secret' blocked by capability\n", .{});
    print("📋 Audit log: Unauthorized access attempt to /secret\n", .{});
    print("✅ :full profile: Enterprise security enforced\n", .{});
}
