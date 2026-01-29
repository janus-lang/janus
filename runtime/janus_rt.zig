// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Pure Zig Runtime (v0.1.1)
// "Runtime Sovereignty" - Zig implementation using minimal libc
//
// This replaces the C shim with Zig, using std.c for libc functions
// to maintain compatibility while being written in Zig.

const std = @import("std");

// ============================================================================
// String API
// ============================================================================

export fn janus_string_len(str: [*:0]const u8) callconv(.c) i32 {
    if (@intFromPtr(str) == 0) return 0;
    return @intCast(std.mem.len(str));
}

export fn janus_string_concat_cstr(s1: [*:0]const u8, s2: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const str1 = if (@intFromPtr(s1) != 0) std.mem.span(s1) else "";
    const str2 = if (@intFromPtr(s2) != 0) std.mem.span(s2) else "";

    const len1 = str1.len;
    const len2 = str2.len;

    const result = std.c.malloc(len1 + len2 + 1) orelse return null;
    const result_slice: [*]u8 = @ptrCast(result);

    @memcpy(result_slice[0..len1], str1);
    @memcpy(result_slice[len1 .. len1 + len2], str2);
    result_slice[len1 + len2] = 0;

    return @ptrCast(result_slice);
}

// ============================================================================
// I/O API - Using C stdio for compatibility
// ============================================================================

export fn janus_print(str: [*:0]const u8) callconv(.c) void {
    if (@intFromPtr(str) != 0) {
        _ = std.c.printf("%s", str);
    } else {
        _ = std.c.printf("(null)");
    }
}

export fn janus_println(str: [*:0]const u8) callconv(.c) void {
    janus_print(str);
    _ = std.c.printf("\n");
}

export fn janus_print_int(value: i32) callconv(.c) void {
    _ = std.c.printf("%d\n", value);
}

export fn janus_print_float(value: f64) callconv(.c) void {
    _ = std.c.printf("%f\n", value);
}

export fn janus_print_bool(value: bool) callconv(.c) void {
    if (value) {
        _ = std.c.printf("true");
    } else {
        _ = std.c.printf("false");
    }
}

export fn janus_panic(msg: [*:0]const u8) callconv(.c) noreturn {
    const message = std.mem.span(msg);
    std.debug.print("PANIC: {s}\n", .{message});
    std.c.exit(1);
}

// ============================================================================
// Error Handling API - :core profile
// ============================================================================

/// Print error name to stderr
export fn janus_rt_print_error(error_name: [*:0]const u8) callconv(.c) void {
    if (@intFromPtr(error_name) != 0) {
        const name = std.mem.span(error_name);
        std.debug.print("Error: {s}\n", .{name});
    }
}

/// Panic on uncaught error with location information
export fn janus_rt_panic_uncaught_error(
    error_name: [*:0]const u8,
    file: [*:0]const u8,
    line: u32,
) callconv(.c) noreturn {
    const err_name = if (@intFromPtr(error_name) != 0) std.mem.span(error_name) else "(unknown)";
    const file_name = if (@intFromPtr(file) != 0) std.mem.span(file) else "(unknown)";

    std.debug.print("Uncaught error '{s}' at {s}:{d}\n", .{ err_name, file_name, line });
    std.c.exit(1);
}

export fn janus_pow(base: i32, exp: i32) callconv(.c) i32 {
    if (exp < 0) return 0; // Integer power with negative exponent returns 0
    if (exp == 0) return 1;
    var result: i32 = 1;
    var b = base;
    var e: u32 = @intCast(exp);
    // Fast exponentiation by squaring
    while (e > 0) {
        if (e & 1 == 1) {
            result *%= b;
        }
        b *%= b;
        e >>= 1;
    }
    return result;
}

// ============================================================================
// Math API (TODO: Requires -lm linkage in build.zig)
// ============================================================================

// export fn janus_sqrt(x: f64) callconv(.c) f64 {
//     return std.math.sqrt(x);
// }

// export fn janus_pow(base: f64, exp: f64) callconv(.c) f64 {
//     return std.math.pow(f64, base, exp);
// }

// export fn janus_sin(x: f64) callconv(.c) f64 {
//     return std.math.sin(x);
// }

// export fn janus_cos(x: f64) callconv(.c) f64 {
//     return std.math.cos(x);
// }

export fn janus_abs_i32(x: i32) callconv(.c) i32 {
    return if (x < 0) -x else x;
}

export fn janus_abs_f64(x: f64) callconv(.c) f64 {
    return @abs(x);
}

// ============================================================================
// Allocator API
// ============================================================================

// Thread-local allocator using C malloc/free
export fn janus_alloc(size: usize) callconv(.c) ?*anyopaque {
    return std.c.malloc(size);
}

export fn janus_free(ptr: ?*anyopaque) callconv(.c) void {
    std.c.free(ptr);
}

export fn janus_realloc(ptr: ?*anyopaque, new_size: usize) callconv(.c) ?*anyopaque {
    return std.c.realloc(ptr, new_size);
}

// Compatibility Shims for Legacy Tests
export fn janus_default_allocator() callconv(.c) ?*anyopaque {
    return null;
}

export fn std_array_create(count: i64, allocator: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = allocator;
    // Shim: allocate enough for i64/pointer elements
    const size: usize = @intCast(count);
    return std.c.malloc(size * 8);
}

// ============================================================================
// Array/Slice API
// ============================================================================

export fn janus_array_alloc(element_size: usize, count: usize) callconv(.c) ?*anyopaque {
    const total_size = element_size * count;
    return std.c.malloc(total_size);
}

export fn janus_array_get_i32(array: [*]const i32, index: usize) callconv(.c) i32 {
    return array[index];
}

export fn janus_array_set_i32(array: [*]i32, index: usize, value: i32) callconv(.c) void {
    array[index] = value;
}

/// Create a slice of an i32 array from start to end (exclusive)
/// Returns a newly allocated array containing copied elements
export fn janus_array_slice_i32(array: [*]const i32, start: i32, end: i32) callconv(.c) ?[*]i32 {
    if (start < 0 or end < start) return null;

    const start_idx: usize = @intCast(start);
    const end_idx: usize = @intCast(end);
    const count = end_idx - start_idx;

    if (count == 0) {
        // Return empty array (still needs valid pointer for safety)
        const result = std.c.malloc(@sizeOf(i32)) orelse return null;
        return @ptrCast(@alignCast(result));
    }

    const result = std.c.malloc(count * @sizeOf(i32)) orelse return null;
    const result_slice: [*]i32 = @ptrCast(@alignCast(result));

    // Copy elements
    for (0..count) |i| {
        result_slice[i] = array[start_idx + i];
    }

    return result_slice;
}

/// Create an inclusive slice of an i32 array from start to end (inclusive)
export fn janus_array_slice_inclusive_i32(array: [*]const i32, start: i32, end: i32) callconv(.c) ?[*]i32 {
    return janus_array_slice_i32(array, start, end + 1);
}

// ============================================================================
// Slice Types - Fat Pointer Representation
// ============================================================================
// Slices are represented as { ptr, len } structs - NO data copying!
// This matches Zig's slice representation for interoperability.

/// Slice of i32 - fat pointer representation
pub const JanusSliceI32 = extern struct {
    ptr: [*]const i32,
    len: usize,
};

/// Create slice from array pointer and length (no copy)
export fn janus_slice_from_array_i32(array: [*]const i32, len: usize) callconv(.c) JanusSliceI32 {
    return JanusSliceI32{ .ptr = array, .len = len };
}

/// Create slice directly from array pointer + start + end (exclusive)
/// This is the primary function called by the LLVM emitter for arr[start..end]
export fn janus_make_slice_i32(array_ptr: [*]const i32, start: i32, end: i32) callconv(.c) JanusSliceI32 {
    const start_u: usize = if (start < 0) 0 else @intCast(start);
    const end_u: usize = if (end < start) start_u else @intCast(end);
    return JanusSliceI32{
        .ptr = array_ptr + start_u,
        .len = end_u - start_u,
    };
}

/// Create slice directly from array pointer + start + end (inclusive)
export fn janus_make_slice_inclusive_i32(array_ptr: [*]const i32, start: i32, end: i32) callconv(.c) JanusSliceI32 {
    return janus_make_slice_i32(array_ptr, start, end + 1);
}

/// Create subslice from slice (no copy) - exclusive end
export fn janus_slice_subslice_i32(slice: JanusSliceI32, start: usize, end: usize) callconv(.c) JanusSliceI32 {
    if (start > end or end > slice.len) {
        return JanusSliceI32{ .ptr = slice.ptr, .len = 0 };
    }
    return JanusSliceI32{
        .ptr = slice.ptr + start,
        .len = end - start,
    };
}

/// Create subslice - inclusive end
export fn janus_slice_subslice_inclusive_i32(slice: JanusSliceI32, start: usize, end: usize) callconv(.c) JanusSliceI32 {
    return janus_slice_subslice_i32(slice, start, end + 1);
}

/// Get slice length
export fn janus_slice_len_i32(slice: JanusSliceI32) callconv(.c) usize {
    return slice.len;
}

/// Get element from slice (bounds checked)
export fn janus_slice_get_i32(slice: JanusSliceI32, index: usize) callconv(.c) i32 {
    if (index >= slice.len) {
        janus_panic("slice index out of bounds");
        return 0;
    }
    return slice.ptr[index];
}

/// Generic slice for u8 (byte slices / strings)
pub const JanusSliceU8 = extern struct {
    ptr: [*]const u8,
    len: usize,
};

/// Create byte slice from pointer and length
export fn janus_slice_from_array_u8(array: [*]const u8, len: usize) callconv(.c) JanusSliceU8 {
    return JanusSliceU8{ .ptr = array, .len = len };
}

/// Get byte slice length
export fn janus_slice_len_u8(slice: JanusSliceU8) callconv(.c) usize {
    return slice.len;
}

/// Get byte from slice
export fn janus_slice_get_u8(slice: JanusSliceU8, index: usize) callconv(.c) u8 {
    if (index >= slice.len) {
        janus_panic("slice index out of bounds");
        return 0;
    }
    return slice.ptr[index];
}

// ============================================================================
// File I/O API - Using Zig std.fs
// ============================================================================

var gpa = std.heap.GeneralPurposeAllocator(.{}){};

export fn janus_readFile(path: [*:0]const u8) callconv(.c) ?[*:0]u8 {
    const allocator = gpa.allocator();
    const path_slice = std.mem.span(path);

    // Use std.fs.cwd() for blocking file read
    const content = std.fs.cwd().readFileAlloc(
        allocator,
        path_slice,
        std.math.maxInt(usize),
    ) catch {
        return null;
    };

    // Allocate with C allocator for lifetime management
    const c_buffer = std.c.malloc(content.len + 1) orelse {
        allocator.free(content);
        return null;
    };

    const result_slice: [*]u8 = @ptrCast(c_buffer);
    @memcpy(result_slice[0..content.len], content);
    result_slice[content.len] = 0;

    allocator.free(content);
    return @ptrCast(result_slice);
}

export fn janus_writeFile(path: [*:0]const u8, content: [*:0]const u8) callconv(.c) i32 {
    const path_slice = std.mem.span(path);
    const content_slice = std.mem.span(content);

    // Use std.fs.cwd() for blocking file write
    std.fs.cwd().writeFile(.{
        .sub_path = path_slice,
        .data = content_slice,
    }) catch {
        return -1;
    };

    return 0;
}

// ============================================================================
// VectorF64 API - Dynamic Array for f64
// ============================================================================

const VectorF64 = std.ArrayListUnmanaged(f64);

/// Create a new VectorF64 with initial capacity
/// Returns opaque handle (pointer to ArrayList)
export fn janus_vector_create(capacity: i64) callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();

    const vec_ptr = allocator.create(VectorF64) catch return null;
    vec_ptr.* = VectorF64{};
    vec_ptr.ensureTotalCapacity(allocator, @intCast(capacity)) catch {
        allocator.destroy(vec_ptr);
        return null;
    };

    return @ptrCast(vec_ptr);
}

/// Push a value onto the vector
export fn janus_vector_push(handle: *anyopaque, value: f64) callconv(.c) i32 {
    const allocator = gpa.allocator();
    const vec: *VectorF64 = @ptrCast(@alignCast(handle));
    vec.append(allocator, value) catch return -1;
    return 0;
}

/// Get value at index
export fn janus_vector_get(handle: *anyopaque, index: i64) callconv(.c) f64 {
    const vec: *VectorF64 = @ptrCast(@alignCast(handle));
    const idx: usize = @intCast(index);

    if (idx >= vec.items.len) return 0.0; // Bounds check
    return vec.items[idx];
}

/// Set value at index
export fn janus_vector_set(handle: *anyopaque, index: i64, value: f64) callconv(.c) i32 {
    const vec: *VectorF64 = @ptrCast(@alignCast(handle));
    const idx: usize = @intCast(index);

    if (idx >= vec.items.len) return -1; // Bounds check
    vec.items[idx] = value;
    return 0;
}

/// Get current length
export fn janus_vector_len(handle: *anyopaque) callconv(.c) i64 {
    const vec: *VectorF64 = @ptrCast(@alignCast(handle));
    return @intCast(vec.items.len);
}

/// Free the vector
export fn janus_vector_free(handle: *anyopaque) callconv(.c) void {
    const allocator = gpa.allocator();
    const vec: *VectorF64 = @ptrCast(@alignCast(handle));

    vec.deinit(allocator);
    allocator.destroy(vec);
}

// ============================================================================
// StringHandle API - Dynamic String Manipulation
// ============================================================================

const StringHandle = std.ArrayListUnmanaged(u8);

/// Create a new StringHandle from a raw pointer and length
/// Copies the content to heap-managed storage
export fn janus_string_create(ptr: [*]const u8, len: i64, allocator_handle: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = allocator_handle; // Ignored for now, use global allocator
    const allocator = gpa.allocator();

    const str_ptr = allocator.create(StringHandle) catch return null;
    str_ptr.* = StringHandle{};

    const length: usize = @intCast(len);
    str_ptr.appendSlice(allocator, ptr[0..length]) catch {
        allocator.destroy(str_ptr);
        return null;
    };

    return @ptrCast(str_ptr);
}

/// Concatenate two StringHandles, returning a new StringHandle
export fn janus_string_concat(h1: *anyopaque, h2: *anyopaque, allocator_handle: ?*anyopaque) callconv(.c) ?*anyopaque {
    _ = allocator_handle; // Ignored for now, use global allocator
    const allocator = gpa.allocator();

    const s1: *StringHandle = @ptrCast(@alignCast(h1));
    const s2: *StringHandle = @ptrCast(@alignCast(h2));

    const result_ptr = allocator.create(StringHandle) catch return null;
    result_ptr.* = StringHandle{};

    result_ptr.appendSlice(allocator, s1.items) catch {
        allocator.destroy(result_ptr);
        return null;
    };
    result_ptr.appendSlice(allocator, s2.items) catch {
        allocator.destroy(result_ptr);
        return null;
    };

    return @ptrCast(result_ptr);
}

/// Get the length of a StringHandle
export fn janus_string_handle_len(handle: *anyopaque) callconv(.c) i64 {
    const str: *StringHandle = @ptrCast(@alignCast(handle));
    return @intCast(str.items.len);
}

/// Check equality of two StringHandles (content comparison)
export fn janus_string_eq(h1: *anyopaque, h2: *anyopaque) callconv(.c) bool {
    const s1: *StringHandle = @ptrCast(@alignCast(h1));
    const s2: *StringHandle = @ptrCast(@alignCast(h2));

    return std.mem.eql(u8, s1.items, s2.items);
}

/// Print a StringHandle to stdout
export fn janus_string_print(handle: *anyopaque) callconv(.c) void {
    const str: *StringHandle = @ptrCast(@alignCast(handle));

    // Print as raw bytes (not null-terminated)
    _ = std.c.printf("%.*s\n", @as(c_int, @intCast(str.items.len)), str.items.ptr);
}

/// Free a StringHandle
export fn janus_string_free(handle: ?*anyopaque, allocator_handle: ?*anyopaque) callconv(.c) void {
    if (handle == null) return;
    _ = allocator_handle; // Ignored for now, use global allocator
    const allocator = gpa.allocator();
    const str: *StringHandle = @ptrCast(@alignCast(handle));

    str.deinit(allocator);
    allocator.destroy(str);
}

// ============================================================================
// :service Profile - Structured Concurrency (Phase 2)
// ============================================================================
// Thread-based implementation of nursery/spawn for concurrent task execution.
// Each spawned task runs in a separate OS thread, managed by the nursery.

/// Task function signature: takes opaque argument, returns i64 result
pub const TaskFn = *const fn (?*anyopaque) callconv(.c) i64;

/// No-argument task function signature (Phase 2.3 - common case)
pub const NoArgTaskFn = *const fn () callconv(.c) i32;

/// Task context for thread execution
const TaskContext = struct {
    func: TaskFn,
    arg: ?*anyopaque,
    result: i64,
    has_error: bool,
};

/// No-argument task context (Phase 2.3)
const NoArgTaskContext = struct {
    func: NoArgTaskFn,
    result: i64,
    has_error: bool,
};

/// Nursery - manages structured concurrency scope
/// All spawned tasks MUST complete before nursery exits
const JanusNursery = struct {
    threads: std.ArrayListUnmanaged(std.Thread),
    contexts: std.ArrayListUnmanaged(*TaskContext),
    noarg_contexts: std.ArrayListUnmanaged(*NoArgTaskContext), // Phase 2.3
    allocator: std.mem.Allocator,
    has_error: bool,

    fn init(allocator: std.mem.Allocator) JanusNursery {
        return JanusNursery{
            .threads = .{},
            .contexts = .{},
            .noarg_contexts = .{},
            .allocator = allocator,
            .has_error = false,
        };
    }

    fn deinit(self: *JanusNursery) void {
        // Free all task contexts
        for (self.contexts.items) |ctx| {
            self.allocator.destroy(ctx);
        }
        self.contexts.deinit(self.allocator);
        // Free no-arg task contexts (Phase 2.3)
        for (self.noarg_contexts.items) |ctx| {
            self.allocator.destroy(ctx);
        }
        self.noarg_contexts.deinit(self.allocator);
        self.threads.deinit(self.allocator);
    }

    fn spawn(self: *JanusNursery, func: TaskFn, arg: ?*anyopaque) !void {
        // Create task context
        const ctx = try self.allocator.create(TaskContext);
        ctx.* = TaskContext{
            .func = func,
            .arg = arg,
            .result = 0,
            .has_error = false,
        };
        try self.contexts.append(self.allocator, ctx);

        // Spawn thread
        const thread = try std.Thread.spawn(.{}, taskRunner, .{ctx});
        try self.threads.append(self.allocator, thread);
    }

    /// Spawn a no-argument function (Phase 2.3 - common case)
    fn spawnNoArg(self: *JanusNursery, func: NoArgTaskFn) !void {
        // Create task context
        const ctx = try self.allocator.create(NoArgTaskContext);
        ctx.* = NoArgTaskContext{
            .func = func,
            .result = 0,
            .has_error = false,
        };
        try self.noarg_contexts.append(self.allocator, ctx);

        // Spawn thread
        const thread = try std.Thread.spawn(.{}, noArgTaskRunner, .{ctx});
        try self.threads.append(self.allocator, thread);
    }

    fn awaitAll(self: *JanusNursery) i64 {
        // Join all threads (wait for completion)
        for (self.threads.items) |thread| {
            thread.join();
        }

        // Check for errors and collect results from regular contexts
        var first_error: i64 = 0;
        for (self.contexts.items) |ctx| {
            if (ctx.has_error and first_error == 0) {
                first_error = ctx.result;
                self.has_error = true;
            }
        }

        // Check for errors from no-arg contexts (Phase 2.3)
        for (self.noarg_contexts.items) |ctx| {
            if (ctx.has_error and first_error == 0) {
                first_error = ctx.result;
                self.has_error = true;
            }
        }

        return first_error;
    }
};

/// Thread entry point - executes task and stores result
fn taskRunner(ctx: *TaskContext) void {
    ctx.result = ctx.func(ctx.arg);
    // Result < 0 indicates error in Janus convention
    ctx.has_error = (ctx.result < 0);
}

/// Thread entry point for no-argument tasks (Phase 2.3)
fn noArgTaskRunner(ctx: *NoArgTaskContext) void {
    const result_i32 = ctx.func();
    ctx.result = @intCast(result_i32);
    // Result < 0 indicates error in Janus convention
    ctx.has_error = (ctx.result < 0);
}

/// Thread-local nursery stack for nested nurseries
threadlocal var nursery_stack: std.ArrayListUnmanaged(*JanusNursery) = .{};

/// Create a new nursery scope
export fn janus_nursery_create() callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();

    const nursery = allocator.create(JanusNursery) catch return null;
    nursery.* = JanusNursery.init(allocator);

    // Push onto nursery stack
    nursery_stack.append(allocator, nursery) catch {
        allocator.destroy(nursery);
        return null;
    };

    return @ptrCast(nursery);
}

/// Spawn a task in the current nursery
/// func: function pointer (TaskFn signature)
/// arg: opaque argument to pass to function
export fn janus_nursery_spawn(func: TaskFn, arg: ?*anyopaque) callconv(.c) i32 {
    // Get current nursery from stack
    if (nursery_stack.items.len == 0) {
        std.debug.print("ERROR: spawn called outside of nursery\n", .{});
        return -1;
    }

    const nursery = nursery_stack.items[nursery_stack.items.len - 1];
    nursery.spawn(func, arg) catch {
        std.debug.print("ERROR: failed to spawn task\n", .{});
        return -1;
    };

    return 0;
}

/// Spawn a no-argument function in the current nursery (Phase 2.3)
/// func: function pointer returning i32 (common Janus function signature)
/// Runtime handles thread spawning and result collection
export fn janus_nursery_spawn_noarg(func: NoArgTaskFn) callconv(.c) i32 {
    // Get current nursery from stack
    if (nursery_stack.items.len == 0) {
        std.debug.print("ERROR: spawn called outside of nursery\n", .{});
        return -1;
    }

    const nursery = nursery_stack.items[nursery_stack.items.len - 1];
    nursery.spawnNoArg(func) catch {
        std.debug.print("ERROR: failed to spawn task\n", .{});
        return -1;
    };

    return 0;
}

/// Wait for all tasks in nursery to complete and cleanup
/// Returns 0 on success, error code on failure
export fn janus_nursery_await_all() callconv(.c) i64 {
    const allocator = gpa.allocator();

    // Pop nursery from stack manually
    if (nursery_stack.items.len == 0) {
        std.debug.print("ERROR: nursery_await_all called without active nursery\n", .{});
        return -1;
    }

    // Manual pop: get last item and shrink
    const idx = nursery_stack.items.len - 1;
    const nursery = nursery_stack.items[idx];
    nursery_stack.items.len = idx;

    // Wait for all tasks
    const result = nursery.awaitAll();

    // Cleanup
    nursery.deinit();
    allocator.destroy(nursery);

    return result;
}

/// Get the number of active tasks in current nursery (for debugging)
export fn janus_nursery_task_count() callconv(.c) i32 {
    if (nursery_stack.items.len == 0) return 0;

    const nursery = nursery_stack.items[nursery_stack.items.len - 1];
    return @intCast(nursery.threads.items.len);
}
