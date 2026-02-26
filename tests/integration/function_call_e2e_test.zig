// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Integration Test: User-Defined Function Calls End-to-End
//
// This test validates that user-defined functions can call other user-defined
// functions through the complete pipeline:
// Source → Parser → ASTDB → Lowerer → QTJIR → LLVM → Object → Executable → Execution

const std = @import("std");
const testing = std.testing;
const e2e = @import("e2e_helper");

test "Epic 2.1: Simple function call - add function" {
    const allocator = testing.allocator;

    const source =
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func main() {
        \\    let result = add(3, 4)
        \\    print_int(result)
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "func_add");
    defer allocator.free(output);


    // 3 + 4 = 7
    try testing.expectEqualStrings("7\n", output);

}

test "Epic 2.1: Chained function calls - double then add" {
    const allocator = testing.allocator;

    const source =
        \\func double(x: i32) -> i32 {
        \\    return x + x
        \\}
        \\
        \\func add(a: i32, b: i32) -> i32 {
        \\    return a + b
        \\}
        \\
        \\func main() {
        \\    let a = double(5)
        \\    let b = double(3)
        \\    let result = add(a, b)
        \\    print_int(result)
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "func_chain");
    defer allocator.free(output);


    // double(5) = 10, double(3) = 6, add(10, 6) = 16
    try testing.expectEqualStrings("16\n", output);

}

test "Epic 2.1: Function calling function - nested calls" {
    const allocator = testing.allocator;

    const source =
        \\func increment(x: i32) -> i32 {
        \\    return x + 1
        \\}
        \\
        \\func add_three(x: i32) -> i32 {
        \\    let step1 = increment(x)
        \\    let step2 = increment(step1)
        \\    let step3 = increment(step2)
        \\    return step3
        \\}
        \\
        \\func main() {
        \\    let result = add_three(10)
        \\    print_int(result)
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "func_nested");
    defer allocator.free(output);


    // 10 + 1 + 1 + 1 = 13
    try testing.expectEqualStrings("13\n", output);

}

test "Epic 2.1: Function with loop - print sequence" {
    const allocator = testing.allocator;

    const source =
        \\func print_range(n: i32) {
        \\    for i in 1..n do
        \\        print_int(i)
        \\    end
        \\}
        \\
        \\func main() {
        \\    print_range(3)
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "func_loop");
    defer allocator.free(output);


    // Print 1, 2, 3 (inclusive range)
    try testing.expectEqualStrings("1\n2\n3\n", output);

}

test "Epic 2.1: Function with conditional - absolute value" {
    const allocator = testing.allocator;

    const source =
        \\func abs(x: i32) -> i32 {
        \\    if x < 0 do
        \\        return 0 - x
        \\    else do
        \\        return x
        \\    end
        \\}
        \\
        \\func main() {
        \\    print_int(abs(5))
        \\    print_int(abs(0 - 7))
        \\}
    ;

    const output = try e2e.compileAndRun(allocator, source, "func_abs");
    defer allocator.free(output);


    // abs(5) = 5, abs(-7) = 7
    try testing.expectEqualStrings("5\n7\n", output);

}
