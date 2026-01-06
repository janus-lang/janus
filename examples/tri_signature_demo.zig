// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Tri-Signature Pattern Demo
// Shows same function name, rising capability across profiles

const std = @import("std");
const http = @import("../std/net/http.zig");
const Context = @import("../std/context.zig").Context;
const Capability = @import("../std/capabilities.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    std.debug.print("🎯 Janus Tri-Signature Pattern Demo (M2)\n", .{});
    std.debug.print("Same name, rising capability across profiles...\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});

    // =================================================================
    // :min profile - Simple, synchronous
    // =================================================================
    std.debug.print("📋 :min Profile - Simple & Synchronous\n", .{});
    std.debug.print("Code: http_get(url, allocator)\n", .{});
    std.debug.print("Features: Basic functionality, no context, no capabilities\n\n", .{});

    {
        var response = try http.http_get_min("https://api.example.com/users", allocator);
        defer response.deinit();

        std.debug.print("Response Status: {}\n", .{response.status_code});
        std.debug.print("Response Body: {s}\n", .{response.body});

        if (response.headers.get("content-type")) |content_type| {
            std.debug.print("Content-Type: {s}\n", .{content_type});
        }
        std.debug.print("\n");
    }

    // =================================================================
    // :go profile - Context-aware with cancellation
    // =================================================================
    std.debug.print("📋 :go Profile - Context-Aware\n", .{});
    std.debug.print("Code: http_get(url, ctx, allocator)\n", .{});
    std.debug.print("Features: Timeout, cancellation, structured error handling\n\n", .{});

    {
        var ctx = Context.init(allocator);
        defer ctx.deinit();

        // Create context with 5 second timeout
        var timeout_ctx = Context.with_timeout(ctx, 5000, allocator);
        defer timeout_ctx.deinit();

        var response = try http.http_get_go("https://api.example.com/users", timeout_ctx, allocator);
        defer response.deinit();

        std.debug.print("Response Status: {}\n", .{response.status_code});
        std.debug.print("Response Body: {s}\n", .{response.body});

        if (response.headers.get("x-janus-profile")) |profile| {
            std.debug.print("Janus Profile: {s}\n", .{profile});
        }

        if (timeout_ctx.deadline_remaining_ms()) |remaining| {
            std.debug.print("Timeout Remaining: {}ms\n", .{remaining});
        }
        std.debug.print("\n");
    }

    // =================================================================
    // :full profile - Capability-gated with security
    // =================================================================
    std.debug.print("📋 :full Profile - Capability-Gated Security\n", .{});
    std.debug.print("Code: http_get(url, cap, allocator)\n", .{});
    std.debug.print("Features: Explicit permissions, audit trails, effect tracking\n\n", .{});

    {
        var cap = Capability.NetHttp.init("demo-http-capability", allocator);
        defer cap.deinit();

        // Configure capability permissions
        try cap.allow_host("api.example.com");
        try cap.allow_host("secure.api.com");

        var response = try http.http_get_full("https://api.example.com/users", cap, allocator);
        defer response.deinit();

        std.debug.print("Response Status: {}\n", .{response.status_code});
        std.debug.print("Response Body: {s}\n", .{response.body});

        if (response.headers.get("x-capability-id")) |cap_id| {
            std.debug.print("Capability ID: {s}\n", .{cap_id});
        }

        if (response.headers.get("x-janus-profile")) |profile| {
            std.debug.print("Janus Profile: {s}\n", .{profile});
        }
        std.debug.print("\n");
    }

    // =================================================================
    // Profile Comparison Summary
    // =================================================================
    std.debug.print("📊 Profile Comparison Summary\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});
    std.debug.print("| Profile | Signature                        | Features           |\n", .{});
    std.debug.print("|---------|----------------------------------|--------------------||\n", .{});
    std.debug.print("| :min    | http_get(url, allocator)         | Simple, sync       |\n", .{});
    std.debug.print("| :go     | http_get(url, ctx, allocator)    | Timeout, cancel    |\n", .{});
    std.debug.print("| :full   | http_get(url, cap, allocator)    | Security, audit    |\n", .{});
    std.debug.print("-" ** 60 ++ "\n", .{});

    std.debug.print("\n🎉 Tri-Signature Pattern Demo Complete!\n", .{});
    std.debug.print("=" ** 60 ++ "\n", .{});
    std.debug.print("Key Benefits Demonstrated:\n", .{});
    std.debug.print("✅ Same function name across all profiles\n", .{});
    std.debug.print("✅ Progressive capability without breaking changes\n", .{});
    std.debug.print("✅ Muscle memory preserved during profile upgrades\n", .{});
    std.debug.print("✅ Explicit honesty about costs and capabilities\n", .{});
    std.debug.print("✅ Type-safe capability enforcement\n", .{});

    std.debug.print("\nThis addresses the stdlib consistency requirement:\n", .{});
    std.debug.print("'Same name, rising honesty' - the secret to adoption success!\n", .{});
}
