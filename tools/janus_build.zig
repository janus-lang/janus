// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Tokenizer = @import("../compiler/libjanus/tokenizer.zig");
const Parser = @import("../compiler/libjanus/parser.zig");
const Semantic = @import("../compiler/libjanus/semantic.zig");
const IR = @import("../compiler/libjanus/ir.zig");
const CodegenC = @import("../compiler/libjanus/codegen_c.zig");

pub fn main() !void {
    // Simple builder: default input/output (no complex arg parsing in this tool)
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

    // Tokenize
    const toks = try Tokenizer.tokenize(buf, allocator);
    // Parse
    var root = try Parser.parse(toks, allocator);
    // Semantic analyze
    const sem = try Semantic.analyze(root, allocator);

    // Generate IR
    var module = try IR.generateIR(root, &sem, allocator);

    // Emit C file
    try CodegenC.emit_c(&module, out_c, &allocator);

    // Note: We intentionally do not run module.deinit() here because generateIR may manage deinit internally.
    // Free parser AST
    root.deinit(allocator);
    allocator.destroy(root);

    std.debug.print("Wrote C output to {s}\n", .{out_c});
}
