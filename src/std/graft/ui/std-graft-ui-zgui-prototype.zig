// std/graft/ffi/zgui.zig - UI Grafting Prototype
// Copyright (c) 2025 Janus Project Authors
// SPDX-License-Identifier: Apache-2.0

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

// Forward declarations for zgui FFI bindings
extern fn zgui_begin(name: [*c]const u8, p_open: *bool, flags: u32) callconv(.C) bool;
extern fn zgui_end() callconv(.C) void;
extern fn zgui_button(label: [*c]const u8) callconv(.C) bool;
extern fn zgui_text(fmt: [*c]const u8, ...) callconv(.C) void;
extern fn zgui_input_text(label: [*c]const u8, buf: [*]u8, buf_size: usize, flags: u32) callconv(.C) bool;

// UI Effect types for capability tracking
pub const UiEffect = enum {
    Display,
    Interact,
    Window,
    Cleanup,
    Gpu,
};

// Capability token for UI operations
pub const UiCapabilityToken = struct {
    permissions: u32, // Bitfield of allowed operations
    allocator: Allocator,

    pub fn hasPermission(self: UiCapabilityToken, perm: UiEffect) bool {
        return (self.permissions & (@as(u32, 1) << @intFromEnum(perm))) != 0;
    }
};

// Main UI Context with arena-based resource management
pub const ZguiContext = struct {
    arena: std.heap.ArenaAllocator,
    cap_token: UiCapabilityToken,
    frame_count: u64 = 0,

    pub fn init(alloc: Allocator, cap_token: UiCapabilityToken) !ZguiContext {
        var arena = std.heap.ArenaAllocator.init(alloc);
        return ZguiContext{
            .arena = arena,
            .cap_token = cap_token,
        };
    }

    pub fn deinit(self: *ZguiContext) void {
        self.arena.deinit();
    }

    // Window management with capability checking
    pub fn beginWindow(self: *ZguiContext, name: []const u8) !bool {
        if (!self.cap_token.hasPermission(.Window)) {
            return error.CapabilityDenied;
        }

        var p_open: bool = true;
        const opened = zgui_begin(@ptrCast(name.ptr), &p_open, 0);
        self.frame_count += 1;
        return opened;
    }

    pub fn endWindow(self: *ZguiContext) !void {
        if (!self.cap_token.hasPermission(.Window)) {
            return error.CapabilityDenied;
        }

        zgui_end();
    }

    // Button widget with interaction capability checking
    pub fn button(self: *ZguiContext, label: []const u8) !bool {
        if (!self.cap_token.hasPermission(.Interact)) {
            return error.CapabilityDenied;
        }

        return zgui_button(@ptrCast(label.ptr));
    }

    // Text display with display capability checking
    pub fn text(self: *ZguiContext, fmt: []const u8, args: anytype) !void {
        if (!self.cap_token.hasPermission(.Display)) {
            return error.CapabilityDenied;
        }

        // Format the text into arena-allocated buffer
        const formatted = try std.fmt.allocPrint(self.arena.allocator(), fmt, args);
        zgui_text(@ptrCast(formatted.ptr));
    }

    // Input text with interaction capability checking
    pub fn inputText(self: *ZguiContext, label: []const u8, buffer: []u8) !bool {
        if (!self.cap_token.hasPermission(.Interact)) {
            return error.CapabilityDenied;
        }

        return zgui_input_text(@ptrCast(label.ptr), @ptrCast(buffer.ptr), buffer.len, 0);
    }

    // Frame budget tracking
    pub fn getFrameCount(self: ZguiContext) u64 {
        return self.frame_count;
    }
};

// Test suite for UI grafting functionality
test "ZguiContext: basic window management" {
    // Create test capability token
    var test_allocator = std.testing.allocator;
    const cap_token = UiCapabilityToken{
        .permissions = 0xFFFF, // All permissions for testing
        .allocator = test_allocator,
    };

    var ctx = try ZguiContext.init(test_allocator, cap_token);
    defer ctx.deinit();

    // Test window operations
    const window_opened = try ctx.beginWindow("Test Window");
    try testing.expect(window_opened);

    try ctx.text("Hello, {}", .{"World"});
    try ctx.endWindow();
}

test "ZguiContext: capability enforcement" {
    var test_allocator = std.testing.allocator;

    // Create restricted capability token (display only)
    const restricted_cap = UiCapabilityToken{
        .permissions = @as(u32, 1) << @intFromEnum(UiEffect.Display),
        .allocator = test_allocator,
    };

    var ctx = try ZguiContext.init(test_allocator, restricted_cap);
    defer ctx.deinit();

    // Display should work
    const window_opened = try ctx.beginWindow("Test Window");
    try testing.expect(window_opened);

    try ctx.text("Display works", .{});
    try ctx.endWindow();

    // Button should fail (no interact permission)
    const button_result = ctx.button("Click me");
    try testing.expectError(error.CapabilityDenied, button_result);
}

test "ZguiContext: arena memory management" {
    var test_allocator = std.testing.allocator;
    const cap_token = UiCapabilityToken{
        .permissions = 0xFFFF,
        .allocator = test_allocator,
    };

    {
        var ctx = try ZguiContext.init(test_allocator, cap_token);

        // Allocate in arena
        const test_data = try ctx.arena.allocator().dupe(u8, "test data");
        try testing.expect(std.mem.eql(u8, test_data, "test data"));

        // Context deinit should clean up arena
    }

    // Test that arena was properly cleaned up
    // (In real implementation, would verify no memory leaks)
}

test "ZguiContext: frame counting" {
    var test_allocator = std.testing.allocator;
    const cap_token = UiCapabilityToken{
        .permissions = 0xFFFF,
        .allocator = test_allocator,
    };

    var ctx = try ZguiContext.init(test_allocator, cap_token);
    defer ctx.deinit();

    try testing.expectEqual(@as(u64, 0), ctx.getFrameCount());

    _ = try ctx.beginWindow("Frame 1");
    try ctx.endWindow();
    try testing.expectEqual(@as(u64, 1), ctx.getFrameCount());

    _ = try ctx.beginWindow("Frame 2");
    try ctx.endWindow();
    try testing.expectEqual(@as(u64, 2), ctx.getFrameCount());
}

// Integration test with Janus-style usage
test "ZguiContext: janus integration pattern" {
    var test_allocator = std.testing.allocator;

    // Simulate Janus context with UI capabilities
    const ui_caps = UiCapabilityToken{
        .permissions = 0xFFFF, // Full UI permissions
        .allocator = test_allocator,
    };

    var ctx = try ZguiContext.init(test_allocator, ui_caps);
    defer ctx.deinit();

    // Simulate Janus application pattern
    const window_open = try ctx.beginWindow("Janus Application");
    if (window_open) {
        try ctx.text("Frame: {}", .{ctx.getFrameCount()});

        const clicked = try ctx.button("Increment Counter");
        if (clicked) {
            // Handle button click
            try ctx.text("Button was clicked!", .{});
        }

        var input_buffer: [256]u8 = [_]u8{0} ** 256;
        _ = try ctx.inputText("Command", &input_buffer);

        try ctx.endWindow();
    }
}

// Performance benchmark stub
pub fn benchmarkZguiContext(iteration_count: usize) !u64 {
    var test_allocator = std.testing.allocator;
    const cap_token = UiCapabilityToken{
        .permissions = 0xFFFF,
        .allocator = test_allocator,
    };

    var ctx = try ZguiContext.init(test_allocator, cap_token);
    defer ctx.deinit();

    const start_time = std.time.nanoTimestamp();

    for (0..iteration_count) |_| {
        _ = try ctx.beginWindow("Benchmark Window");
        try ctx.text("Iteration", .{});
        try ctx.endWindow();
    }

    const end_time = std.time.nanoTimestamp();
    return @intCast(end_time - start_time);
}

test "ZguiContext: performance characteristics" {
    const iterations = 1000;
    const total_time_ns = try benchmarkZguiContext(iterations);

    const avg_time_ns = total_time_ns / iterations;
    std.debug.print("Average frame time: {}ns\n", .{avg_time_ns});

    // Should be well under 16ms (16,000,000ns) frame budget
    try testing.expect(avg_time_ns < 1_000_000); // Under 1ms per frame
}

// Error types for UI operations
pub const UiError = error{
    CapabilityDenied,
    WindowCreationFailed,
    WidgetRenderFailed,
    ContextNotInitialized,
    FrameBudgetExceeded,
};

// Utility functions for UI capability management
pub fn createDisplayOnlyToken(alloc: Allocator) !UiCapabilityToken {
    return UiCapabilityToken{
        .permissions = @as(u32, 1) << @intFromEnum(UiEffect.Display),
        .allocator = alloc,
    };
}

pub fn createFullUiToken(alloc: Allocator) !UiCapabilityToken {
    return UiCapabilityToken{
        .permissions = 0xFFFF, // All UI permissions
        .allocator = alloc,
    };
}

// Export for Janus FFI integration
pub const ZguiExports = struct {
    pub const Context = ZguiContext;
    pub const CapabilityToken = UiCapabilityToken;
    pub const Effect = UiEffect;
    pub const Error = UiError;

    pub fn createContext(alloc: Allocator, caps: UiCapabilityToken) !*ZguiContext {
        const ctx = try alloc.create(ZguiContext);
        ctx.* = try ZguiContext.init(alloc, caps);
        return ctx;
    }

    pub fn destroyContext(ctx: *ZguiContext) void {
        ctx.deinit();
        // Note: In real implementation, would need allocator reference for deallocation
    }
};
