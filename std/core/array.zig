// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standard Library - :core Profile Array Module
//!
//! Simple, teaching-friendly array operations for the :core profile.
//! Works with both fixed-size arrays and dynamic ArrayLists.
//!
//! Functions:
//! - len(arr)              - Get array length
//! - append(arr, item)     - Add item to end (dynamic arrays only)
//! - get(arr, index)       - Get item at index
//! - set(arr, index, item) - Set item at index
//! - first(arr)            - Get first element
//! - last(arr)             - Get last element
//! - contains(arr, item)   - Check if array contains item
//! - indexOf(arr, item)    - Find index of item
//! - reverse(arr)          - Reverse array in place
//! - sort(arr)             - Sort array in place

const std = @import("std");

/// Array errors for :core profile
pub const ArrayError = error{
    OutOfBounds,
    EmptyArray,
    OutOfMemory,
    NotFound,
};

// =============================================================================
// CORE OPERATIONS
// =============================================================================

/// Get the length of an array or slice
///
/// Example:
/// ```janus
/// let arr = [1, 2, 3, 4, 5]
/// io.println(string(array.len(arr)))  // Output: 5
/// ```
pub fn len(arr: anytype) usize {
    const T = @TypeOf(arr);
    const info = @typeInfo(T);

    return switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => arr.len,
            .one => switch (@typeInfo(ptr.child)) {
                .array => |a| a.len,
                else => @compileError("Expected slice or array pointer"),
            },
            else => @compileError("Expected slice or array pointer"),
        },
        .array => |a| a.len,
        else => if (@hasField(T, "items")) arr.items.len else @compileError("Expected array, slice, or ArrayList"),
    };
}

/// Check if array is empty
pub fn isEmpty(arr: anytype) bool {
    return len(arr) == 0;
}

/// Get item at index (bounds-checked)
///
/// Example:
/// ```janus
/// let arr = [10, 20, 30]
/// let x = array.get(arr, 1)  // 20
/// ```
pub fn get(arr: anytype, index: usize) ArrayError!@TypeOf(arr[0]) {
    if (index >= len(arr)) return ArrayError.OutOfBounds;
    return arr[index];
}

/// Get first element
pub fn first(arr: anytype) ArrayError!@TypeOf(arr[0]) {
    if (len(arr) == 0) return ArrayError.EmptyArray;
    return arr[0];
}

/// Get last element
pub fn last(arr: anytype) ArrayError!@TypeOf(arr[0]) {
    const l = len(arr);
    if (l == 0) return ArrayError.EmptyArray;
    return arr[l - 1];
}

// =============================================================================
// SEARCH OPERATIONS
// =============================================================================

/// Check if array contains an item
///
/// Example:
/// ```janus
/// let arr = [1, 2, 3, 4, 5]
/// if array.contains(arr, 3) {
///     io.println("Found 3!")
/// }
/// ```
pub fn contains(arr: anytype, item: @TypeOf(arr[0])) bool {
    for (arr) |elem| {
        if (elem == item) return true;
    }
    return false;
}

/// Find the index of an item, returns null if not found
pub fn indexOf(arr: anytype, item: @TypeOf(arr[0])) ?usize {
    for (arr, 0..) |elem, i| {
        if (elem == item) return i;
    }
    return null;
}

/// Find the last index of an item
pub fn lastIndexOf(arr: anytype, item: @TypeOf(arr[0])) ?usize {
    var i = len(arr);
    while (i > 0) {
        i -= 1;
        if (arr[i] == item) return i;
    }
    return null;
}

/// Count occurrences of an item
pub fn count(arr: anytype, item: @TypeOf(arr[0])) usize {
    var c: usize = 0;
    for (arr) |elem| {
        if (elem == item) c += 1;
    }
    return c;
}

// =============================================================================
// TRANSFORMATION OPERATIONS
// =============================================================================

/// Reverse an array in place
///
/// Example:
/// ```janus
/// var arr = [1, 2, 3, 4, 5]
/// array.reverse(&arr)  // arr is now [5, 4, 3, 2, 1]
/// ```
pub fn reverse(arr: anytype) void {
    const T = @TypeOf(arr);
    const info = @typeInfo(T);

    const arr_slice = switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => arr,
            .one => switch (@typeInfo(ptr.child)) {
                .array => arr[0..],
                else => @compileError("Expected mutable slice or array pointer"),
            },
            else => @compileError("Expected mutable slice or array pointer"),
        },
        else => @compileError("Expected mutable slice or array pointer"),
    };

    std.mem.reverse(@TypeOf(arr_slice[0]), arr_slice);
}

/// Sort an array in place (ascending order for numeric types)
pub fn sort(arr: anytype) void {
    const T = @TypeOf(arr);
    const info = @typeInfo(T);

    const arr_slice = switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => arr,
            .one => switch (@typeInfo(ptr.child)) {
                .array => arr[0..],
                else => @compileError("Expected mutable slice or array pointer"),
            },
            else => @compileError("Expected mutable slice or array pointer"),
        },
        else => @compileError("Expected mutable slice or array pointer"),
    };

    std.mem.sort(@TypeOf(arr_slice[0]), arr_slice, {}, std.sort.asc(@TypeOf(arr_slice[0])));
}

/// Sort an array in descending order
pub fn sortDesc(arr: anytype) void {
    const T = @TypeOf(arr);
    const info = @typeInfo(T);

    const arr_slice = switch (info) {
        .pointer => |ptr| switch (ptr.size) {
            .slice => arr,
            .one => switch (@typeInfo(ptr.child)) {
                .array => arr[0..],
                else => @compileError("Expected mutable slice or array pointer"),
            },
            else => @compileError("Expected mutable slice or array pointer"),
        },
        else => @compileError("Expected mutable slice or array pointer"),
    };

    std.mem.sort(@TypeOf(arr_slice[0]), arr_slice, {}, std.sort.desc(@TypeOf(arr_slice[0])));
}

// =============================================================================
// COPY AND SLICE OPERATIONS
// =============================================================================

/// Create a copy of an array
/// Caller owns the returned memory.
pub fn clone(allocator: std.mem.Allocator, arr: anytype) ArrayError![]@TypeOf(arr[0]) {
    return allocator.dupe(@TypeOf(arr[0]), arr) catch return ArrayError.OutOfMemory;
}

/// Get a subslice of an array
/// Returns a view into the original array (no allocation).
pub fn subslice(arr: anytype, start: usize, end_arg: usize) ArrayError!@TypeOf(arr) {
    const l = len(arr);
    const end = @min(end_arg, l);
    if (start > l or start > end) return ArrayError.OutOfBounds;
    return arr[start..end];
}

/// Get the first n elements
pub fn take(arr: anytype, n: usize) @TypeOf(arr) {
    const l = len(arr);
    return arr[0..@min(n, l)];
}

/// Skip the first n elements
pub fn drop(arr: anytype, n: usize) @TypeOf(arr) {
    const l = len(arr);
    return arr[@min(n, l)..];
}

// =============================================================================
// AGGREGATION OPERATIONS
// =============================================================================

/// Sum all elements in a numeric array
pub fn sum(arr: anytype) @TypeOf(arr[0]) {
    var total: @TypeOf(arr[0]) = 0;
    for (arr) |elem| {
        total += elem;
    }
    return total;
}

/// Find the minimum element
pub fn min(arr: anytype) ArrayError!@TypeOf(arr[0]) {
    if (len(arr) == 0) return ArrayError.EmptyArray;
    return std.mem.min(@TypeOf(arr[0]), arr);
}

/// Find the maximum element
pub fn max(arr: anytype) ArrayError!@TypeOf(arr[0]) {
    if (len(arr) == 0) return ArrayError.EmptyArray;
    return std.mem.max(@TypeOf(arr[0]), arr);
}

// =============================================================================
// DYNAMIC ARRAY OPERATIONS (ArrayList)
// =============================================================================

/// Create a new ArrayList
/// Usage: var list = array.newList(i32);
pub fn newList(comptime T: type) std.ArrayListUnmanaged(T) {
    return std.ArrayListUnmanaged(T){};
}

/// Append an item to a dynamic array
/// Use std.ArrayListUnmanaged for dynamic arrays in :core profile.
///
/// Example (Zig interop):
/// ```zig
/// var list = std.ArrayListUnmanaged(i64){};
/// try array.append(allocator, &list, 42);
/// ```
pub fn append(allocator: std.mem.Allocator, list: anytype, item: anytype) ArrayError!void {
    list.append(allocator, item) catch return ArrayError.OutOfMemory;
}

/// Append multiple items to a dynamic array
pub fn appendSlice(allocator: std.mem.Allocator, list: anytype, items: anytype) ArrayError!void {
    list.appendSlice(allocator, items) catch return ArrayError.OutOfMemory;
}

/// Remove and return the last item
pub fn pop(list: anytype) ArrayError!@TypeOf(list.items[0]) {
    if (list.items.len == 0) return ArrayError.EmptyArray;
    return list.pop().?;
}

/// Insert an item at a specific index
pub fn insert(allocator: std.mem.Allocator, list: anytype, index: usize, item: anytype) ArrayError!void {
    if (index > list.items.len) return ArrayError.OutOfBounds;
    list.insert(allocator, index, item) catch return ArrayError.OutOfMemory;
}

/// Remove item at index (shifting remaining elements)
pub fn remove(list: anytype, index: usize) ArrayError!@TypeOf(list.items[0]) {
    if (index >= list.items.len) return ArrayError.OutOfBounds;
    return list.orderedRemove(index);
}

/// Remove item at index (swapping with last element - faster but unordered)
pub fn swapRemove(list: anytype, index: usize) ArrayError!@TypeOf(list.items[0]) {
    if (index >= list.items.len) return ArrayError.OutOfBounds;
    return list.swapRemove(index);
}

/// Clear all items from a dynamic array
pub fn clear(list: anytype) void {
    list.clearRetainingCapacity();
}

/// Resize a dynamic array to exactly n elements
pub fn resize(allocator: std.mem.Allocator, list: anytype, n: usize) ArrayError!void {
    list.resize(allocator, n) catch return ArrayError.OutOfMemory;
}

/// Free a dynamic array's memory
pub fn deinit(allocator: std.mem.Allocator, list: anytype) void {
    list.deinit(allocator);
}

// =============================================================================
// CREATION HELPERS
// =============================================================================

/// Create a new dynamic array with initial items
pub fn fromSlice(allocator: std.mem.Allocator, comptime T: type, items: []const T) ArrayError!std.ArrayListUnmanaged(T) {
    var list = std.ArrayListUnmanaged(T){};
    list.appendSlice(allocator, items) catch return ArrayError.OutOfMemory;
    return list;
}

/// Create a new array filled with a single value
pub fn filled(allocator: std.mem.Allocator, comptime T: type, value: T, n: usize) ArrayError![]T {
    const arr = allocator.alloc(T, n) catch return ArrayError.OutOfMemory;
    @memset(arr, value);
    return arr;
}

/// Create a range of integers [start, end)
pub fn range(allocator: std.mem.Allocator, start: i64, end: i64) ArrayError![]i64 {
    if (end <= start) {
        return allocator.alloc(i64, 0) catch return ArrayError.OutOfMemory;
    }

    const count_u: usize = @intCast(end - start);
    const arr = allocator.alloc(i64, count_u) catch return ArrayError.OutOfMemory;

    var val = start;
    for (arr) |*elem| {
        elem.* = val;
        val += 1;
    }

    return arr;
}

// =============================================================================
// TESTS
// =============================================================================

test "len and isEmpty" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(usize, 5), len(&arr));
    try std.testing.expect(!isEmpty(&arr));

    const empty: [0]i32 = .{};
    try std.testing.expectEqual(@as(usize, 0), len(&empty));
    try std.testing.expect(isEmpty(&empty));

    const slice_arr: []const i32 = &arr;
    try std.testing.expectEqual(@as(usize, 5), len(slice_arr));
}

test "get, first, last" {
    const arr = [_]i32{ 10, 20, 30 };
    try std.testing.expectEqual(@as(i32, 20), try get(&arr, 1));
    try std.testing.expectEqual(@as(i32, 10), try first(&arr));
    try std.testing.expectEqual(@as(i32, 30), try last(&arr));
    try std.testing.expectError(ArrayError.OutOfBounds, get(&arr, 10));
}

test "contains and indexOf" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expect(contains(&arr, 3));
    try std.testing.expect(!contains(&arr, 10));
    try std.testing.expectEqual(@as(?usize, 2), indexOf(&arr, 3));
    try std.testing.expectEqual(@as(?usize, null), indexOf(&arr, 10));
}

test "reverse and sort" {
    var arr = [_]i32{ 3, 1, 4, 1, 5, 9 };
    sort(&arr);
    try std.testing.expectEqual([_]i32{ 1, 1, 3, 4, 5, 9 }, arr);

    reverse(&arr);
    try std.testing.expectEqual([_]i32{ 9, 5, 4, 3, 1, 1 }, arr);
}

test "aggregation" {
    const arr = [_]i32{ 1, 2, 3, 4, 5 };
    try std.testing.expectEqual(@as(i32, 15), sum(&arr));
    try std.testing.expectEqual(@as(i32, 1), try min(&arr));
    try std.testing.expectEqual(@as(i32, 5), try max(&arr));
}

test "dynamic array operations" {
    const allocator = std.testing.allocator;

    var list = std.ArrayListUnmanaged(i32){};
    defer list.deinit(allocator);

    try append(allocator, &list, 1);
    try append(allocator, &list, 2);
    try append(allocator, &list, 3);

    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqual(@as(i32, 2), list.items[1]);

    const popped = try pop(&list);
    try std.testing.expectEqual(@as(i32, 3), popped);
    try std.testing.expectEqual(@as(usize, 2), list.items.len);
}

test "range" {
    const allocator = std.testing.allocator;
    const arr = try range(allocator, 0, 5);
    defer allocator.free(arr);

    try std.testing.expectEqual(@as(usize, 5), arr.len);
    try std.testing.expectEqual(@as(i64, 0), arr[0]);
    try std.testing.expectEqual(@as(i64, 4), arr[4]);
}

test "filled" {
    const allocator = std.testing.allocator;
    const arr = try filled(allocator, i32, 42, 5);
    defer allocator.free(arr);

    try std.testing.expectEqual(@as(usize, 5), arr.len);
    for (arr) |elem| {
        try std.testing.expectEqual(@as(i32, 42), elem);
    }
}
