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
