// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Stackful Fiber Continuation for CBC-MN Scheduler
//!
//! x86_64 context switching using System V AMD64 ABI.
//! Saves/restores callee-saved registers and stack pointer.
//!
//! Callee-saved registers (must preserve across calls):
//!   rbx, rbp, r12, r13, r14, r15
//!
//! Implementation: External assembly (context_switch.s)
//! Invariants: See CONTEXT-SWITCH-INVARIANTS.md
//!
//! See: SPEC-021 Section 5.3 (Continuation)

const std = @import("std");
const builtin = @import("builtin");
const task_mod = @import("task.zig");
const Task = task_mod.Task;
const SavedRegisters = task_mod.SavedRegisters;

// ============================================================================
// External Assembly Functions (context_switch.s)
// ============================================================================

/// External context switch implemented in assembly.
/// See context_switch.s for implementation.
///
/// Context layout (must match):
///   offset 0:  sp   (stack pointer)
///   offset 8:  rbx
///   offset 16: rbp
///   offset 24: r12
///   offset 32: r13
///   offset 40: r14
///   offset 48: r15
extern fn janus_context_switch(from: *Context, to: *const Context) void;

/// External fiber entry trampoline.
/// Reads entry_fn from r12, arg from r13, calls entry_fn(arg).
extern fn janus_fiber_entry() void;

// ============================================================================
// Context Structure
// ============================================================================

/// Context switch state
///
/// Layout is critical - must match context_switch.s expectations.
/// sp at offset 0, then SavedRegisters (rbx, rbp, r12-r15) at offset 8.
pub const Context = struct {
    /// Stack pointer (offset 0)
    sp: usize,

    /// Saved callee-preserved registers (offset 8)
    regs: SavedRegisters,

    /// Initialize empty context
    pub fn init() Context {
        return .{
            .sp = 0,
            .regs = .{},
        };
    }
};

// Compile-time verification of layout
comptime {
    // Verify Context layout matches assembly expectations
    if (@offsetOf(Context, "sp") != 0) @compileError("Context.sp must be at offset 0");
    if (@offsetOf(Context, "regs") != 8) @compileError("Context.regs must be at offset 8");
    if (@sizeOf(Context) != 56) @compileError("Context must be 56 bytes (8 + 48)");
}

// ============================================================================
// Context Switch API
// ============================================================================

/// Switch from current context to target context
///
/// Saves current CPU state to `from`, restores state from `to`.
/// Returns when another fiber switches back to us.
///
/// This is the core primitive for cooperative multitasking.
/// Implemented in external assembly (context_switch.s).
///
/// SAFETY: Caller must ensure:
///   - from != to (no self-switch)
///   - to.sp is valid (points into target's stack)
///   - to.sp is 16-byte aligned
pub fn switchContext(from: *Context, to: *const Context) void {
    // Use assembly implementation on x86_64
    if (comptime builtin.cpu.arch == .x86_64) {
        janus_context_switch(from, to);
    } else {
        // Fallback stub for other architectures
        // TODO: Implement ARM64 context switch
        @compileError("Context switch not implemented for this architecture");
    }
}

/// Cleanup function signature (receives task result)
pub const CleanupFn = *const fn (i64) callconv(.c) void;

/// Initialize a new fiber context for first execution
///
/// Sets up the stack so that when switched to, execution begins
/// at the entry function with the given argument.
///
/// Stack layout after init:
/// ```
///                     ┌─────────────────┐ High address
///                     │   (red zone)    │
///                     ├─────────────────┤
///                     │  fiber_entry    │ ← Initial "return" target (janus_fiber_entry)
///                     ├─────────────────┤
///         sp ──────►  │  (16-aligned)   │
///                     └─────────────────┘ Low address
/// ```
///
/// Registers after init:
///   r12 = entry_fn (task entry point)
///   r13 = arg (task argument)
///   r14 = cleanup_fn (called with result after entry returns)
///   rbp = sp (frame pointer)
pub fn initFiberContext(
    ctx: *Context,
    stack: []align(16) u8,
    entry_fn: *const fn (?*anyopaque) callconv(.c) i64,
    arg: ?*anyopaque,
    cleanup_fn: CleanupFn,
) void {
    // Stack grows downward, start at the top
    var sp = @intFromPtr(stack.ptr) + stack.len;

    // Ensure 16-byte alignment (required by System V ABI)
    sp = sp & ~@as(usize, 0xF);

    // Reserve space for janus_fiber_entry (assembly trampoline)
    // First switch to this context will "ret" to janus_fiber_entry
    sp -= @sizeOf(usize);
    @as(*usize, @ptrFromInt(sp)).* = @intFromPtr(&janus_fiber_entry);

    // Store entry function, argument, and cleanup in callee-saved registers
    // janus_fiber_entry reads r12 (entry_fn), r13 (arg), r14 (cleanup_fn)
    ctx.regs.r12 = @intFromPtr(entry_fn); // Entry function
    ctx.regs.r13 = @intFromPtr(arg); // Argument
    ctx.regs.r14 = @intFromPtr(cleanup_fn); // Cleanup (receives result)
    ctx.regs.r15 = 0;
    ctx.regs.rbx = 0;
    ctx.regs.rbp = sp; // Frame pointer

    ctx.sp = sp;
}

/// Initialize context from an existing Task
pub fn initFromTask(ctx: *Context, task: *Task) void {
    if (task.stack) |stack| {
        const entry_fn = task.entry_fn orelse {
            // No-arg function variant
            if (task.entry_fn_noarg) |_| {
                // Wrap no-arg function
                // Note: In full implementation, we'd capture the actual function
                const wrapper = struct {
                    fn call(_: ?*anyopaque) callconv(.c) i64 {
                        // This is a simplified wrapper - in practice we'd need
                        // to store the actual function pointer somewhere accessible
                        return 0;
                    }
                };
                initFiberContext(
                    ctx,
                    stack,
                    &wrapper.call,
                    null,
                    defaultCleanup,
                );
                return;
            }
            return; // No entry function at all
        };

        initFiberContext(
            ctx,
            stack,
            entry_fn,
            task.entry_arg,
            defaultCleanup,
        );
    }
}

/// Default cleanup function for completed fibers
fn defaultCleanup(_: i64) callconv(.c) void {
    // Fiber completed - spin until scheduler notices
    // In full implementation, this would signal the scheduler
    // Note: Task.setupStack uses its own cleanup that calls worker_mod.yieldComplete
    while (true) {
        std.atomic.spinLoopHint();
    }
}

// ============================================================================
// Tests
// ============================================================================

test "Context: init creates zeroed context" {
    const ctx = Context.init();
    try std.testing.expectEqual(@as(usize, 0), ctx.sp);
    try std.testing.expectEqual(@as(u64, 0), ctx.regs.rbx);
    try std.testing.expectEqual(@as(u64, 0), ctx.regs.rbp);
}

test "Context: initFiberContext sets up stack" {
    var stack: [4096]u8 align(16) = undefined;
    var ctx = Context.init();

    const testEntry = struct {
        fn entry(_: ?*anyopaque) callconv(.c) i64 {
            return 42;
        }
    }.entry;

    const testCleanup = struct {
        fn cleanup(_: i64) callconv(.c) void {}
    }.cleanup;

    initFiberContext(&ctx, &stack, &testEntry, null, testCleanup);

    // Stack pointer should be within stack bounds
    const stack_start = @intFromPtr(&stack);
    const stack_end = stack_start + stack.len;
    try std.testing.expect(ctx.sp >= stack_start);
    try std.testing.expect(ctx.sp < stack_end);

    // Stack pointer should be 8 mod 16 (ABI: 16-aligned before call, 8 after return address push)
    // We pushed janus_fiber_entry address, so sp & 0xF == 8
    try std.testing.expectEqual(@as(usize, 8), ctx.sp & 0xF);
}

test "SavedRegisters: correct size and layout" {
    // Verify struct is packed correctly for assembly access
    try std.testing.expectEqual(@as(usize, 48), @sizeOf(SavedRegisters));

    const regs = SavedRegisters{
        .rbx = 1,
        .rbp = 2,
        .r12 = 3,
        .r13 = 4,
        .r14 = 5,
        .r15 = 6,
    };

    // Verify field offsets match assembly expectations
    const base = @intFromPtr(&regs);
    try std.testing.expectEqual(@as(usize, 0), @intFromPtr(&regs.rbx) - base);
    try std.testing.expectEqual(@as(usize, 8), @intFromPtr(&regs.rbp) - base);
    try std.testing.expectEqual(@as(usize, 16), @intFromPtr(&regs.r12) - base);
    try std.testing.expectEqual(@as(usize, 24), @intFromPtr(&regs.r13) - base);
    try std.testing.expectEqual(@as(usize, 32), @intFromPtr(&regs.r14) - base);
    try std.testing.expectEqual(@as(usize, 40), @intFromPtr(&regs.r15) - base);
}
