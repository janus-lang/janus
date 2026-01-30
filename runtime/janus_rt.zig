// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Pure Zig Runtime (v0.2.0)
// "Runtime Sovereignty" - Zig implementation using minimal libc
//
// This replaces the C shim with Zig, using std.c for libc functions
// to maintain compatibility while being written in Zig.
//
// v0.2.0: CBC-MN Scheduler integration (M:N fiber-based concurrency)

const std = @import("std");

// CBC-MN Scheduler (Capability-Budgeted Cooperative M:N)
const scheduler = @import("scheduler.zig");

// ============================================================================
// Runtime Root Architecture (SPEC-021 Section 2)
// ============================================================================
// The Runtime is the single global root. It owns the scheduler.
// No invisible authority - all handles are explicit.
// Subsystems MUST NOT access GLOBAL_RT directly.

/// Runtime configuration
pub const RuntimeConfig = extern struct {
    /// Number of worker threads (0 = auto-detect CPU count)
    worker_count: u32 = 0,
    /// Deterministic seed for reproducible tests (0 = non-deterministic)
    deterministic_seed: u64 = 0,
};

/// The Runtime - single root that owns all subsystems (SPEC-021 Section 2.2.1)
///
/// This is the only permitted global. Subsystems access it via explicit handles.
pub const Runtime = struct {
    const Self = @This();

    /// M:N task scheduler
    sched: *scheduler.Scheduler,
    /// Memory allocator
    allocator: std.mem.Allocator,
    /// Configuration used to create this runtime
    config: RuntimeConfig,

    /// Initialize a new runtime
    pub fn init(allocator: std.mem.Allocator, config: RuntimeConfig) !*Self {
        const self = try allocator.create(Self);
        errdefer allocator.destroy(self);

        const worker_count: usize = if (config.worker_count == 0)
            std.Thread.getCpuCount() catch 4
        else
            @intCast(config.worker_count);

        self.* = Self{
            .sched = try scheduler.Scheduler.init(allocator, worker_count),
            .allocator = allocator,
            .config = config,
        };

        return self;
    }

    /// Cleanup and deallocate runtime
    pub fn deinit(self: *Self) void {
        self.sched.deinit();
        self.allocator.destroy(self);
    }

    /// Start the runtime (spawn worker threads)
    pub fn start(self: *Self) !void {
        try self.sched.start();
    }

    /// Stop the runtime (signal shutdown, wait for workers)
    pub fn stop(self: *Self) void {
        self.sched.stop();
    }

    /// Create a nursery backed by this runtime's scheduler
    pub fn createNursery(self: *Self, budget: scheduler.Budget) scheduler.Nursery {
        return self.sched.createNursery(budget);
    }

    /// Check if runtime is running
    pub fn isRunning(self: *const Self) bool {
        return self.sched.isRunning();
    }
};

/// The ONLY global (SPEC-021 Section 2.2.2)
/// This is the runtime root, not a scheduler singleton.
var GLOBAL_RT: ?*Runtime = null;

/// Initialize the Janus runtime
///
/// Creates the Runtime root with the given configuration.
/// This MUST be called before any concurrency operations.
///
/// Returns: 0 on success, -1 on failure
export fn janus_rt_init(config: RuntimeConfig) callconv(.c) i32 {
    if (GLOBAL_RT != null) {
        // Already initialized
        return -1;
    }

    const allocator = gpa.allocator();
    GLOBAL_RT = Runtime.init(allocator, config) catch return -1;
    GLOBAL_RT.?.start() catch {
        GLOBAL_RT.?.deinit();
        GLOBAL_RT = null;
        return -1;
    };

    return 0;
}

/// Initialize runtime with defaults (auto-detect workers)
export fn janus_rt_init_default() callconv(.c) i32 {
    return janus_rt_init(RuntimeConfig{});
}

/// Shutdown the Janus runtime
///
/// Stops the scheduler and frees all resources.
/// After this call, no concurrency operations are valid.
export fn janus_rt_shutdown() callconv(.c) void {
    if (GLOBAL_RT) |rt| {
        rt.stop();
        rt.deinit();
        GLOBAL_RT = null;
    }
}

/// Check if runtime is initialized and running
export fn janus_rt_is_running() callconv(.c) bool {
    if (GLOBAL_RT) |rt| {
        return rt.isRunning();
    }
    return false;
}

/// Get current runtime (internal use only - not exported)
/// Subsystems should receive scheduler handles explicitly, not via this function.
fn getCurrentRuntime() ?*Runtime {
    return GLOBAL_RT;
}

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

// ============================================================================
// CBC-MN Scheduler API (Delegating to Runtime Root)
// ============================================================================
// These exports delegate to the Runtime Root. The global_scheduler singleton
// has been removed - all scheduler access goes through GLOBAL_RT.

/// Initialize the M:N scheduler with specified worker count
/// Call this at program start for :service profile
/// worker_count: 0 = auto-detect CPU cores
export fn janus_scheduler_init(worker_count: u32) callconv(.c) i32 {
    return janus_rt_init(RuntimeConfig{
        .worker_count = worker_count,
        .deterministic_seed = 0,
    });
}

/// Shutdown the scheduler and wait for all workers to stop
/// Call this at program exit
export fn janus_scheduler_shutdown() callconv(.c) void {
    janus_rt_shutdown();
}

/// Get scheduler statistics (for debugging/monitoring)
export fn janus_scheduler_stats() callconv(.c) u64 {
    if (GLOBAL_RT) |rt| {
        const stats = rt.sched.getStats();
        return stats.tasks_executed;
    }
    return 0;
}

/// Check if scheduler is running (internal)
fn ensureSchedulerRunning() bool {
    if (GLOBAL_RT == null) {
        // Auto-initialize with default config
        if (janus_rt_init_default() != 0) {
            return false;
        }
    }
    return GLOBAL_RT != null and GLOBAL_RT.?.isRunning();
}

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
// :service Profile - Structured Concurrency (CBC-MN Scheduler-Backed)
// ============================================================================
// Nursery exports backed by the CBC-MN scheduler via the Runtime Root.
// Tasks run as lightweight fibers in the M:N scheduler, not OS threads.
//
// MIGRATION: The thread-per-task JanusNursery has been replaced with
// scheduler.Nursery backed by GLOBAL_RT. Same C API, fiber implementation.

/// Task function signature: takes opaque argument, returns i64 result
pub const TaskFn = *const fn (?*anyopaque) callconv(.c) i64;

/// No-argument task function signature (common case)
/// Note: Returns i64 for compatibility with scheduler task system
pub const NoArgTaskFn = *const fn () callconv(.c) i64;

/// C ABI Adapter for scheduler.Nursery (SPEC-021 Section 3.2)
///
/// This is the boundary gasket that translates Janus runtime semantics
/// into the C ABI without leaking impurity inward.
///
/// IS: An opaque handle for C, an adapter, a lifetime owner
/// IS NOT: A scheduler, a policy object, part of Janus semantics
const RtNursery = struct {
    nursery: scheduler.Nursery,
    allocator: std.mem.Allocator, // For adapter lifecycle only
};

/// Thread-local nursery stack (SPEC-021 Section 3.3)
///
/// TLS is allowed ONLY to support the legacy C ABI illusion:
/// "There is a current nursery."
///
/// Containment rules:
/// - TLS lives ONLY in this file (janus_rt.zig)
/// - TLS is NEVER visible to scheduler code
/// - TLS stack stores RtNursery pointers only
///
/// This is ABI glue, not architecture.
threadlocal var rt_nursery_stack: std.ArrayListUnmanaged(*RtNursery) = .{};

/// Create a new nursery scope
/// Uses the Runtime Root's scheduler for M:N fiber scheduling
export fn janus_nursery_create() callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();

    // Ensure runtime is initialized
    if (!ensureSchedulerRunning()) {
        std.debug.print("ERROR: Runtime not initialized for nursery\n", .{});
        return null;
    }

    const rt = GLOBAL_RT.?;

    // Create nursery handle
    const handle = allocator.create(RtNursery) catch return null;
    handle.* = RtNursery{
        .nursery = rt.createNursery(scheduler.Budget.serviceDefault()),
        .allocator = allocator,
    };

    // Push onto nursery stack
    rt_nursery_stack.append(allocator, handle) catch {
        handle.nursery.deinit();
        allocator.destroy(handle);
        return null;
    };

    return @ptrCast(handle);
}

/// Spawn a task in the current nursery
/// func: function pointer (TaskFn signature)
/// arg: opaque argument to pass to function
export fn janus_nursery_spawn(func: TaskFn, arg: ?*anyopaque) callconv(.c) i32 {
    // Get current nursery from stack
    if (rt_nursery_stack.items.len == 0) {
        std.debug.print("ERROR: spawn called outside of nursery\n", .{});
        return -1;
    }

    const handle = rt_nursery_stack.items[rt_nursery_stack.items.len - 1];

    // Spawn task via scheduler nursery
    const task = handle.nursery.spawn(func, arg);
    if (task == null) {
        std.debug.print("ERROR: failed to spawn task (budget exhausted?)\n", .{});
        return -1;
    }

    return 0;
}

/// Spawn a no-argument function in the current nursery
/// func: function pointer returning i32 (common Janus function signature)
export fn janus_nursery_spawn_noarg(func: NoArgTaskFn) callconv(.c) i32 {
    // Get current nursery from stack
    if (rt_nursery_stack.items.len == 0) {
        std.debug.print("ERROR: spawn called outside of nursery\n", .{});
        return -1;
    }

    const handle = rt_nursery_stack.items[rt_nursery_stack.items.len - 1];

    // Spawn no-arg task via scheduler nursery
    const task = handle.nursery.spawnNoArg(func);
    if (task == null) {
        std.debug.print("ERROR: failed to spawn task (budget exhausted?)\n", .{});
        return -1;
    }

    return 0;
}

/// Wait for all tasks in nursery to complete and cleanup
/// Returns 0 on success, error code on failure
export fn janus_nursery_await_all() callconv(.c) i64 {
    const allocator = gpa.allocator();

    // Pop nursery from stack
    if (rt_nursery_stack.items.len == 0) {
        std.debug.print("ERROR: nursery_await_all called without active nursery\n", .{});
        return -1;
    }

    // Manual pop: get last item and shrink
    const idx = rt_nursery_stack.items.len - 1;
    const handle = rt_nursery_stack.items[idx];
    rt_nursery_stack.items.len = idx;

    // Wait for all tasks via scheduler nursery
    const result = handle.nursery.awaitAll();

    // Convert NurseryResult to i64
    const error_code: i64 = switch (result) {
        .success => 0,
        .child_failed => |err| err.error_code,
        .cancelled => -2,
        .pending => -3, // Should not happen after awaitAll
    };

    // Cleanup
    handle.nursery.deinit();
    allocator.destroy(handle);

    return error_code;
}

/// Get the number of active tasks in current nursery (for debugging)
export fn janus_nursery_task_count() callconv(.c) i32 {
    if (rt_nursery_stack.items.len == 0) return 0;

    const handle = rt_nursery_stack.items[rt_nursery_stack.items.len - 1];
    return @intCast(handle.nursery.activeChildCount());
}

// ============================================================================
// Channel API - Phase 3: CSP-style Message Passing
// ============================================================================
//
// Channels provide type-safe, thread-safe communication between tasks.
// Design: Zig generic internally, C-compatible exports for LLVM interop.
//
// Key properties:
// - Non-nullable (no nil channel trap like Go)
// - Buffered or unbuffered
// - Close semantics: recv drains buffer, then returns error
// - Thread-safe via mutex + condition variables

/// Generic Channel implementation
/// T must be a simple type that can be copied (no pointers for now)
pub fn Channel(comptime T: type) type {
    return struct {
        const Self = @This();

        // Ring buffer for buffered channels (capacity 0 = unbuffered)
        buffer: []T,
        head: usize, // Read position
        tail: usize, // Write position
        count: usize, // Current items in buffer
        capacity: usize,

        // Synchronization
        mutex: std.Thread.Mutex,
        not_empty: std.Thread.Condition, // Signaled when data available
        not_full: std.Thread.Condition, // Signaled when space available

        // State
        closed: std.atomic.Value(bool),
        allocator: std.mem.Allocator,

        /// Create unbuffered channel (synchronous rendezvous)
        pub fn init(allocator: std.mem.Allocator) !*Self {
            return try initBuffered(allocator, 0);
        }

        /// Create buffered channel with given capacity
        pub fn initBuffered(allocator: std.mem.Allocator, capacity: usize) !*Self {
            const self = try allocator.create(Self);
            errdefer allocator.destroy(self);

            // For unbuffered (capacity=0), we still need 1 slot for handoff
            const actual_capacity = if (capacity == 0) 1 else capacity;
            const buffer = try allocator.alloc(T, actual_capacity);

            self.* = Self{
                .buffer = buffer,
                .head = 0,
                .tail = 0,
                .count = 0,
                .capacity = capacity, // Store original (0 = unbuffered)
                .mutex = .{},
                .not_empty = .{},
                .not_full = .{},
                .closed = std.atomic.Value(bool).init(false),
                .allocator = allocator,
            };

            return self;
        }

        pub fn deinit(self: *Self) void {
            self.allocator.free(self.buffer);
            self.allocator.destroy(self);
        }

        /// Send value to channel (blocks until receiver ready or buffer has space)
        /// Returns error.ChannelClosed if channel is closed
        pub fn send(self: *Self, value: T) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for space (or unbuffered handoff)
            while (self.isFull() and !self.closed.load(.acquire)) {
                self.not_full.wait(&self.mutex);
            }

            if (self.closed.load(.acquire)) {
                return error.ChannelClosed;
            }

            // Write to buffer
            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;

            // Signal waiting receivers
            self.not_empty.signal();

            // For unbuffered: wait for receiver to take value
            if (self.capacity == 0) {
                while (self.count > 0 and !self.closed.load(.acquire)) {
                    self.not_full.wait(&self.mutex);
                }
            }
        }

        /// Receive value from channel (blocks until value available)
        /// Returns error.ChannelClosed if channel is closed AND empty
        pub fn recv(self: *Self) !T {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Wait for data
            while (self.count == 0 and !self.closed.load(.acquire)) {
                self.not_empty.wait(&self.mutex);
            }

            // If empty and closed, return error
            if (self.count == 0) {
                return error.ChannelClosed;
            }

            // Read from buffer
            const value = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;

            // Signal waiting senders
            self.not_full.signal();

            return value;
        }

        /// Non-blocking send
        /// Returns true if sent, false if would block
        pub fn trySend(self: *Self, value: T) !bool {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.closed.load(.acquire)) {
                return error.ChannelClosed;
            }

            if (self.isFull()) {
                return false; // Would block
            }

            self.buffer[self.tail] = value;
            self.tail = (self.tail + 1) % self.buffer.len;
            self.count += 1;

            self.not_empty.signal();
            return true;
        }

        /// Non-blocking receive
        /// Returns null if would block, value if available
        pub fn tryRecv(self: *Self) !?T {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.count == 0) {
                if (self.closed.load(.acquire)) {
                    return error.ChannelClosed;
                }
                return null; // Would block
            }

            const value = self.buffer[self.head];
            self.head = (self.head + 1) % self.buffer.len;
            self.count -= 1;

            self.not_full.signal();
            return value;
        }

        /// Close the channel
        /// Idempotent: multiple closes are no-op
        pub fn close(self: *Self) void {
            self.closed.store(true, .release);

            // Wake all waiters
            self.mutex.lock();
            self.not_empty.broadcast();
            self.not_full.broadcast();
            self.mutex.unlock();
        }

        /// Check if channel is closed
        pub fn isClosed(self: *Self) bool {
            return self.closed.load(.acquire);
        }

        /// Check if buffer is full (internal)
        fn isFull(self: *Self) bool {
            if (self.capacity == 0) {
                // Unbuffered: full if any item waiting
                return self.count > 0;
            }
            return self.count >= self.capacity;
        }

        /// Get current count of items in buffer
        pub fn len(self: *Self) usize {
            self.mutex.lock();
            defer self.mutex.unlock();
            return self.count;
        }
    };
}

// ============================================================================
// C-Compatible Channel Exports (for LLVM interop)
// ============================================================================
// We export typed channels for common types: i64, f64, ptr
// The opaque handle is a pointer to the channel struct

/// i64 Channel - most common case for integer values
const ChannelI64 = Channel(i64);

/// Create a new i64 channel
/// capacity = 0 for unbuffered (synchronous)
/// capacity > 0 for buffered (async up to capacity)
/// Returns opaque handle, or null on allocation failure
pub export fn janus_channel_create_i64(capacity: i32) callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();
    const cap: usize = if (capacity < 0) 0 else @intCast(capacity);

    const ch = ChannelI64.initBuffered(allocator, cap) catch return null;
    return @ptrCast(ch);
}

/// Destroy an i64 channel
pub export fn janus_channel_destroy_i64(handle: ?*anyopaque) callconv(.c) void {
    if (handle) |h| {
        const ch: *ChannelI64 = @ptrCast(@alignCast(h));
        ch.deinit();
    }
}

/// Send i64 value to channel (blocking)
/// Returns 0 on success, -1 if channel closed
pub export fn janus_channel_send_i64(handle: ?*anyopaque, value: i64) callconv(.c) i32 {
    if (handle == null) return -1;

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    ch.send(value) catch return -1;
    return 0;
}

/// Receive i64 value from channel (blocking)
/// Returns value on success
/// On error (closed channel), returns min_i64 and sets *error_out to -1
pub export fn janus_channel_recv_i64(handle: ?*anyopaque, error_out: ?*i32) callconv(.c) i64 {
    if (handle == null) {
        if (error_out) |e| e.* = -1;
        return std.math.minInt(i64);
    }

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    const value = ch.recv() catch {
        if (error_out) |e| e.* = -1;
        return std.math.minInt(i64);
    };

    if (error_out) |e| e.* = 0;
    return value;
}

/// Non-blocking send
/// Returns 1 if sent, 0 if would block, -1 if closed
pub export fn janus_channel_try_send_i64(handle: ?*anyopaque, value: i64) callconv(.c) i32 {
    if (handle == null) return -1;

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    const sent = ch.trySend(value) catch return -1;
    return if (sent) 1 else 0;
}

/// Non-blocking receive
/// Returns 1 if received (value in *value_out), 0 if would block, -1 if closed
pub export fn janus_channel_try_recv_i64(handle: ?*anyopaque, value_out: ?*i64) callconv(.c) i32 {
    if (handle == null) return -1;
    if (value_out == null) return -1;

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    const maybe_value = ch.tryRecv() catch return -1;

    if (maybe_value) |v| {
        value_out.?.* = v;
        return 1;
    }
    return 0; // Would block
}

/// Close a channel
pub export fn janus_channel_close_i64(handle: ?*anyopaque) callconv(.c) void {
    if (handle) |h| {
        const ch: *ChannelI64 = @ptrCast(@alignCast(h));
        ch.close();
    }
}

/// Check if channel is closed
pub export fn janus_channel_is_closed_i64(handle: ?*anyopaque) callconv(.c) i32 {
    if (handle == null) return 1; // Null is considered closed

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    return if (ch.isClosed()) 1 else 0;
}

/// Get number of items currently in channel buffer
pub export fn janus_channel_len_i64(handle: ?*anyopaque) callconv(.c) i32 {
    if (handle == null) return 0;

    const ch: *ChannelI64 = @ptrCast(@alignCast(handle.?));
    return @intCast(ch.len());
}

// ============================================================================
// Select API - Phase 4: CSP-style Multi-Channel Wait
// ============================================================================
//
// Select enables waiting on multiple channel operations simultaneously.
// Semantics match Go's select:
// - Multiple cases: first ready case is chosen
// - Default case: non-blocking, chosen if no other case ready
// - Timeout case: chosen after specified duration
//
// Implementation: Polling with exponential backoff
// Future optimization: Use proper condition variable waiting

/// Maximum number of cases in a select statement
const MAX_SELECT_CASES = 16;

/// Select case types
pub const SelectCaseType = enum(i32) {
    recv = 0,
    send = 1,
    timeout = 2,
    default = 3,
};

/// Select case descriptor
pub const SelectCase = struct {
    case_type: SelectCaseType,
    channel: ?*ChannelI64, // null for timeout/default
    value: i64, // value to send, or storage for received value
    timeout_ns: u64, // timeout in nanoseconds (for timeout case)
    ready: bool, // set to true when case completes
};

/// Select context - manages multiple cases
pub const SelectContext = struct {
    cases: [MAX_SELECT_CASES]SelectCase,
    case_count: usize,
    has_default: bool,
    has_timeout: bool,
    timeout_deadline: u64, // absolute deadline in nanoseconds
    allocator: std.mem.Allocator,

    fn init(allocator: std.mem.Allocator) SelectContext {
        return SelectContext{
            .cases = undefined,
            .case_count = 0,
            .has_default = false,
            .has_timeout = false,
            .timeout_deadline = 0,
            .allocator = allocator,
        };
    }

    /// Add a receive case
    fn addRecv(self: *SelectContext, channel: ?*anyopaque) i32 {
        if (self.case_count >= MAX_SELECT_CASES) return -1;
        if (channel == null) return -1;

        self.cases[self.case_count] = SelectCase{
            .case_type = .recv,
            .channel = @ptrCast(@alignCast(channel.?)),
            .value = 0,
            .timeout_ns = 0,
            .ready = false,
        };
        const idx: i32 = @intCast(self.case_count);
        self.case_count += 1;
        return idx;
    }

    /// Add a send case
    fn addSend(self: *SelectContext, channel: ?*anyopaque, value: i64) i32 {
        if (self.case_count >= MAX_SELECT_CASES) return -1;
        if (channel == null) return -1;

        self.cases[self.case_count] = SelectCase{
            .case_type = .send,
            .channel = @ptrCast(@alignCast(channel.?)),
            .value = value,
            .timeout_ns = 0,
            .ready = false,
        };
        const idx: i32 = @intCast(self.case_count);
        self.case_count += 1;
        return idx;
    }

    /// Add a timeout case
    fn addTimeout(self: *SelectContext, timeout_ms: i64) i32 {
        if (self.case_count >= MAX_SELECT_CASES) return -1;

        const timeout_ns: u64 = if (timeout_ms < 0) 0 else @as(u64, @intCast(timeout_ms)) * 1_000_000;

        self.cases[self.case_count] = SelectCase{
            .case_type = .timeout,
            .channel = null,
            .value = 0,
            .timeout_ns = timeout_ns,
            .ready = false,
        };
        const idx: i32 = @intCast(self.case_count);
        self.case_count += 1;
        self.has_timeout = true;
        return idx;
    }

    /// Add a default case
    fn addDefault(self: *SelectContext) i32 {
        if (self.case_count >= MAX_SELECT_CASES) return -1;

        self.cases[self.case_count] = SelectCase{
            .case_type = .default,
            .channel = null,
            .value = 0,
            .timeout_ns = 0,
            .ready = false,
        };
        const idx: i32 = @intCast(self.case_count);
        self.case_count += 1;
        self.has_default = true;
        return idx;
    }

    /// Wait for one case to become ready
    /// Returns the index of the ready case, or -1 on error
    fn wait(self: *SelectContext) i32 {
        // Record start time for timeout handling
        const start_time = std.time.nanoTimestamp();

        // Find maximum timeout and set deadline
        var max_timeout_ns: u64 = 0;
        for (self.cases[0..self.case_count]) |c| {
            if (c.case_type == .timeout and c.timeout_ns > max_timeout_ns) {
                max_timeout_ns = c.timeout_ns;
            }
        }
        if (self.has_timeout) {
            self.timeout_deadline = @as(u64, @intCast(start_time)) + max_timeout_ns;
        }

        // Polling loop with exponential backoff
        var sleep_ns: u64 = 1000; // Start at 1 microsecond
        const max_sleep_ns: u64 = 10_000_000; // Cap at 10ms

        while (true) {
            // Check each case
            for (self.cases[0..self.case_count], 0..) |*c, i| {
                switch (c.case_type) {
                    .recv => {
                        if (c.channel) |ch| {
                            const maybe_value = ch.tryRecv() catch {
                                // Channel closed - mark ready with error indication
                                c.ready = true;
                                c.value = std.math.minInt(i64);
                                return @intCast(i);
                            };
                            if (maybe_value) |v| {
                                c.ready = true;
                                c.value = v;
                                return @intCast(i);
                            }
                        }
                    },
                    .send => {
                        if (c.channel) |ch| {
                            const sent = ch.trySend(c.value) catch {
                                // Channel closed - mark as error
                                c.ready = true;
                                return @intCast(i);
                            };
                            if (sent) {
                                c.ready = true;
                                return @intCast(i);
                            }
                        }
                    },
                    .timeout => {
                        const now: u64 = @intCast(std.time.nanoTimestamp());
                        const elapsed = now -| @as(u64, @intCast(start_time));
                        if (elapsed >= c.timeout_ns) {
                            c.ready = true;
                            return @intCast(i);
                        }
                    },
                    .default => {
                        // Default is only taken if no other case is immediately ready
                        // We do one pass first, then take default
                    },
                }
            }

            // If we have a default case and no other case was ready, take default
            if (self.has_default) {
                for (self.cases[0..self.case_count], 0..) |*c, i| {
                    if (c.case_type == .default) {
                        c.ready = true;
                        return @intCast(i);
                    }
                }
            }

            // Check timeout deadline
            if (self.has_timeout) {
                const now: u64 = @intCast(std.time.nanoTimestamp());
                if (now >= self.timeout_deadline) {
                    // Find and return timeout case
                    for (self.cases[0..self.case_count], 0..) |*c, i| {
                        if (c.case_type == .timeout) {
                            c.ready = true;
                            return @intCast(i);
                        }
                    }
                }
            }

            // Sleep with exponential backoff
            std.Thread.sleep(sleep_ns);
            sleep_ns = @min(sleep_ns * 2, max_sleep_ns);
        }
    }

    /// Get received value from a completed recv case
    fn getRecvValue(self: *SelectContext, case_index: i32) i64 {
        if (case_index < 0 or @as(usize, @intCast(case_index)) >= self.case_count) {
            return 0;
        }
        return self.cases[@intCast(case_index)].value;
    }
};

// ============================================================================
// C-Compatible Select Exports (for LLVM interop)
// ============================================================================

/// Create a new select context
/// Returns opaque handle, or null on allocation failure
pub export fn janus_select_create() callconv(.c) ?*anyopaque {
    const allocator = gpa.allocator();
    const ctx = allocator.create(SelectContext) catch return null;
    ctx.* = SelectContext.init(allocator);
    return @ptrCast(ctx);
}

/// Destroy a select context
pub export fn janus_select_destroy(handle: ?*anyopaque) callconv(.c) void {
    if (handle) |h| {
        const ctx: *SelectContext = @ptrCast(@alignCast(h));
        ctx.allocator.destroy(ctx);
    }
}

/// Add a receive case to select
/// Returns case index (0-based), or -1 on error
pub export fn janus_select_add_recv(handle: ?*anyopaque, channel: ?*anyopaque) callconv(.c) i32 {
    if (handle == null) return -1;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.addRecv(channel);
}

/// Add a send case to select
/// Returns case index (0-based), or -1 on error
pub export fn janus_select_add_send(handle: ?*anyopaque, channel: ?*anyopaque, value: i64) callconv(.c) i32 {
    if (handle == null) return -1;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.addSend(channel, value);
}

/// Add a timeout case to select (in milliseconds)
/// Returns case index (0-based), or -1 on error
pub export fn janus_select_add_timeout(handle: ?*anyopaque, timeout_ms: i64) callconv(.c) i32 {
    if (handle == null) return -1;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.addTimeout(timeout_ms);
}

/// Add a default case to select
/// Returns case index (0-based), or -1 on error
pub export fn janus_select_add_default(handle: ?*anyopaque) callconv(.c) i32 {
    if (handle == null) return -1;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.addDefault();
}

/// Wait for one case to become ready
/// Returns the index of the ready case (0-based), or -1 on error
pub export fn janus_select_wait(handle: ?*anyopaque) callconv(.c) i32 {
    if (handle == null) return -1;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.wait();
}

/// Get the received value from a completed recv case
/// Only valid after janus_select_wait returns the recv case index
pub export fn janus_select_get_recv_value(handle: ?*anyopaque, case_index: i32) callconv(.c) i64 {
    if (handle == null) return 0;
    const ctx: *SelectContext = @ptrCast(@alignCast(handle.?));
    return ctx.getRecvValue(case_index);
}
