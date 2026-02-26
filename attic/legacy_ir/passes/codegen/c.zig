// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const IR = @import("../../ir.zig");

pub fn escape_c_string(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    // raw may include surrounding quotes. Strip if present.
    var src = raw;
    if (src.len >= 2 and src[0] == '"' and src[src.len - 1] == '"') {
        src = src[1 .. src.len - 1];
    }

    var out: std.ArrayList(u8) = .empty;
    // Surrounding quote
    try out.append('"');
    for (src) |b| {
        // Escape backslash and double-quote and non-printables minimally
        if (b == '\\') {
            try out.append('\\');
            try out.append('\\');
        } else if (b == '"') {
            try out.append('\\');
            try out.append('"');
        } else if (b == 0x0A) { // newline
            try out.append('\\');
            try out.append('n');
        } else if (b == 0x0D) { // carriage return
            try out.append('\\');
            try out.append('r');
        } else if (b == 0x09) { // tab
            try out.append('\\');
            try out.append('t');
        } else if (b < 0x20) {
            // use hex escape for other control chars: emit "\xHH"
            const hi = ((b >> 4) & 0xF);
            const lo = (b & 0xF);
            const hi_char = if (hi < 10) (@as(u8, '0') + hi) else (@as(u8, 'a') + (hi - 10));
            const lo_char = if (lo < 10) (@as(u8, '0') + lo) else (@as(u8, 'a') + (lo - 10));
            var esc: [4]u8 = undefined;
            esc[0] = '\\';
            esc[1] = 'x';
            esc[2] = hi_char;
            esc[3] = lo_char;
            try out.appendSlice(esc[0..4]);
        } else {
            try out.append(b);
        }
    }
    try out.append('"');

    return try out.toOwnedSlice(alloc);
}

pub fn emit_c(module: *IR.Module, out_path: []const u8, allocator: std.mem.Allocator) !void {
    const cwd = std.fs.cwd();
    var file = try cwd.createFile(out_path, .{});
    defer file.close();

    var w = file.writer();

    // header
    try w.print("#include <stdio.h>\n#include <stdlib.h>\n\n", .{});

    // Emit string constants mapping value id -> symbol name s{ID}
    // We need to inspect module.instructions to find StringConst instructions.
    const instrs = module.instructions.items;
    // Keep track of which ids we've emitted
    var emitted = std.AutoHashMap(u32, bool).init(allocator);
    defer emitted.deinit();

    for (instrs) |instr| {
        if (instr.kind == IR.InstructionKind.StringConst) {
            if (instr.result) |val| {
                const id = val.id;
                // Prevent double emit
                if (emitted.get(id) == null) {
                    try emitted.put(id, true);
                    // metadata contains the original literal (including quotes)
                    const meta = instr.metadata;
                    const esc = try escape_c_string(allocator, meta);
                    defer allocator.free(esc);

                    try w.print("static const char s{d}[] = {s};\n", .{ id, esc });
                }
            }
        }
    }

    try w.print("\n", .{});

    // Emit function definitions:
    // For each FunctionDef instruction, emit a void function with the function name.
    // The body contains calls found between FunctionDef and the following Return.
    var idx: usize = 0;
    while (idx < instrs.len) : (idx += 1) {
        const instr = instrs[idx];
        if (instr.kind == IR.InstructionKind.FunctionDef) {
            // get function name from result.name if present, otherwise metadata
            var fname: []const u8 = "";
            if (instr.result) |r| {
                fname = r.name;
            } else {
                fname = instr.metadata;
            }
            // sanitize function name: allow alnum and underscore, else replace with underscore
            var name_buf_list: std.ArrayList(u8) = .empty;
            defer name_buf_list.deinit();
            for (fname) |c| {
                if ((c >= '0' and c <= '9') or (c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z') or c == '_') {
                    try name_buf_list.append(c);
                } else {
                    try name_buf_list.append('_');
                }
            }
            const fname_s = name_buf_list.toOwnedSlice();
            defer allocator.free(fname_s);

            try w.print("void {s}() {{\n", .{fname_s});

            // scan forward for interesting instructions until Return or next FunctionDef
            var j = idx + 1;
            while (j < instrs.len) : (j += 1) {
                const ni = instrs[j];
                if (ni.kind == IR.InstructionKind.Call) {
                    // We assume first operand (if any) references a string constant value
                    if (ni.operands.len > 0) {
                        const op = ni.operands[0];
                        // Emit puts(sID);
                        try w.print("    puts(s{d});\n", .{op.id});
                    } else {
                        // no operands - emit a placeholder comment
                        try w.print("    /* call with no operands */\n", .{});
                    }
                } else if (ni.kind == IR.InstructionKind.UnaryOp) {
                    // Emit comment for unary op; real codegen can lower later
                    if (ni.result) |r| {
                        const op_name = if (ni.unop) |u| @tagName(u) else "?";
                        try w.print("    /* {s} -> v{d} */\n", .{ op_name, r.id });
                    } else {
                        try w.print("    /* unary */\n", .{});
                    }
                } else if (ni.kind == IR.InstructionKind.Store) {
                    // Store with explicit dest; show as comment for now
                    if (ni.dest) |d| {
                        if (ni.operands.len > 0) {
                            const src = ni.operands[0];
                            try w.print("    /* store v{d} := v{d} */\n", .{ d.id, src.id });
                        } else {
                            try w.print("    /* store v{d} */\n", .{d.id});
                        }
                    } else {
                        try w.print("    /* store (no dest) */\n", .{});
                    }
                } else if (ni.kind == IR.InstructionKind.Return) {
                    break;
                } else if (ni.kind == IR.InstructionKind.FunctionDef) {
                    // next function started; stop
                    break;
                }
            }

            try w.print("}\n\n", .{});

            idx = j; // advance index past handled instructions
        } else {
            // not a function def, continue
        }
    }

    // Emit main that calls function named "main" if present; otherwise call first function if any.
    // Find a value that is a Function with name "main"
    var main_found = false;
    for (module.values.items) |v| {
        if (v.type == IR.ValueType.Function) {
            if (std.mem.eql(u8, v.name, "main")) {
                try w.print("int main(void) {{\n    {s}();\n    return 0;\n}}\n", .{v.name});
                main_found = true;
                break;
            }
        }
    }
    if (!main_found) {
        // fallback: call first function value
        for (module.values.items) |v| {
            if (v.type == IR.ValueType.Function) {
                try w.print("int main(void) {{\n    {s}();\n    return 0;\n}}\n", .{v.name});
                main_found = true;
                break;
            }
        }
    }

    if (!main_found) {
        // no function found -> emit trivial main
        try w.print("int main(void) {{\n    return 0;\n}}\n", .{});
    }

    // file will be closed by defer; no explicit flush() on std.fs.File
}
