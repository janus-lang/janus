// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("tokenizer.zig");
const Parser = @import("parser.zig");
const Semantic = @import("semantic.zig");
const IR = @import("ir.zig");
const CodegenC = @import("codegen_c.zig");

pub fn main() !void {
    // Use fixed test input/output to avoid ArgIterator differences across Zig std versions
    const input_path = "tests/hello.jan";
    const out_c = "out.c";

    const allocator = std.heap.page_allocator;

    const cwd = std.fs.cwd();
    var in_file = try cwd.openFile(input_path, .{});
    defer in_file.close();

    const file_size = try in_file.getEndPos();
    var reader = in_file.reader();
    const buf = try allocator.alloc(u8, file_size);
    defer allocator.free(buf);
    _ = try reader.readAll(buf);

    const toks = try Tokenizer.tokenize(buf, allocator);
    var root = try Parser.parse(toks, allocator);
    const sem = try Semantic.analyze(root, allocator);

    var module = try IR.generateIR(root, &sem, allocator);

    try CodegenC.emit_c(&module, out_c, allocator);

    // cleanup AST
    root.deinit(allocator);
    allocator.destroy(root);

    std.debug.print("Wrote C output to {s}\n", .{out_c});
}
