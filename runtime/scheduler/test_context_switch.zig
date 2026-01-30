// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Context Switch Integration Tests
//!
//! These tests verify the x86_64 assembly context switch implementation.
//! Must be linked with context_switch.s to run.

const std = @import("std");
const task_mod = @import("task.zig");
const SavedRegisters = task_mod.SavedRegisters;
const continuation = @import("continuation.zig");
const Context = continuation.Context;
const switchContext = continuation.switchContext;
const initFiberContext = continuation.initFiberContext;

// ============================================================================
// Test Fixtures
// ============================================================================

/// Global flag set by fiber to indicate it ran
var fiber_ran: bool = false;

/// Global value set by fiber to verify argument passing
var fiber_result: i64 = 0;

/// Test fiber entry function
fn testFiber(arg: ?*anyopaque) callconv(.c) i64 {
    fiber_ran = true;
    if (arg) |ptr| {
        const value = @as(*i64, @ptrCast(@alignCast(ptr))).*;
        fiber_result = value * 2;
        return value * 2;
    }
    return 42;
}

/// Cleanup function that switches back to caller
var caller_ctx: Context = undefined;
var fiber_ctx: Context = undefined;
var cleanup_called: bool = false;
var cleanup_result: i64 = 0;

fn testCleanup(result: i64) callconv(.c) void {
    cleanup_called = true;
    cleanup_result = result;
    // Switch back to caller (would normally spin in real implementation)
    switchContext(&fiber_ctx, &caller_ctx);
}

// ============================================================================
// Tests
// ============================================================================

test "Context switch: basic switch and return" {
    // Reset test state
    fiber_ran = false;
    fiber_result = 0;
    cleanup_called = false;
    cleanup_result = 0;

    // Allocate fiber stack
    var stack: [8192]u8 align(16) = undefined;

    // Initialize contexts
    caller_ctx = Context.init();
    fiber_ctx = Context.init();

    // Set up fiber context
    var arg: i64 = 21;
    initFiberContext(
        &fiber_ctx,
        &stack,
        &testFiber,
        @ptrCast(&arg),
        testCleanup,
    );

    // Switch to fiber
    switchContext(&caller_ctx, &fiber_ctx);

    // Verify fiber ran
    try std.testing.expect(fiber_ran);
    try std.testing.expectEqual(@as(i64, 42), fiber_result);
    try std.testing.expect(cleanup_called);
    // Verify cleanup received the return value from testFiber
    try std.testing.expectEqual(@as(i64, 42), cleanup_result);
}

test "Context switch: struct layout for register preservation" {
    // Verify the Context struct layout matches assembly expectations
    // This is critical for correct register save/restore
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(Context, "sp"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(Context, "regs"));
    try std.testing.expectEqual(@as(usize, 56), @sizeOf(Context));

    // Verify SavedRegisters layout
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(SavedRegisters));
    try std.testing.expectEqual(@as(usize, 0), @offsetOf(SavedRegisters, "rbx"));
    try std.testing.expectEqual(@as(usize, 8), @offsetOf(SavedRegisters, "rbp"));
    try std.testing.expectEqual(@as(usize, 16), @offsetOf(SavedRegisters, "r12"));
    try std.testing.expectEqual(@as(usize, 24), @offsetOf(SavedRegisters, "r13"));
    try std.testing.expectEqual(@as(usize, 32), @offsetOf(SavedRegisters, "r14"));
    try std.testing.expectEqual(@as(usize, 40), @offsetOf(SavedRegisters, "r15"));
}

test "Context switch: stack alignment" {
    var stack: [8192]u8 align(16) = undefined;
    var ctx = Context.init();

    const alignmentFiber = struct {
        fn entry(_: ?*anyopaque) callconv(.c) i64 {
            return 0;
        }
    }.entry;

    const noopCleanup = struct {
        fn cleanup(_: i64) callconv(.c) void {}
    }.cleanup;

    initFiberContext(&ctx, &stack, &alignmentFiber, null, noopCleanup);

    // Stack pointer must be 8 mod 16 (ABI: 16-aligned before call, 8 after return address push)
    // We pushed janus_fiber_entry address, so sp & 0xF == 8
    try std.testing.expectEqual(@as(usize, 8), ctx.sp & 0xF);

    // Stack pointer must be within bounds
    const stack_start = @intFromPtr(&stack);
    const stack_end = stack_start + stack.len;
    try std.testing.expect(ctx.sp >= stack_start);
    try std.testing.expect(ctx.sp < stack_end);
}

test "Context switch: fiber argument passing" {
    fiber_ran = false;
    fiber_result = 0;
    cleanup_called = false;
    cleanup_result = 0;

    var stack: [8192]u8 align(16) = undefined;
    caller_ctx = Context.init();
    fiber_ctx = Context.init();

    // Pass a specific argument
    var arg: i64 = 100;
    initFiberContext(
        &fiber_ctx,
        &stack,
        &testFiber,
        @ptrCast(&arg),
        testCleanup,
    );

    switchContext(&caller_ctx, &fiber_ctx);

    // testFiber multiplies arg by 2
    try std.testing.expectEqual(@as(i64, 200), fiber_result);
    // Cleanup should receive the return value (200)
    try std.testing.expectEqual(@as(i64, 200), cleanup_result);
}
