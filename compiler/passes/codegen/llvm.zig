// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const IR = @import("../ir.zig");

pub const LLVMCodegen = struct {
    allocator: std.mem.Allocator,

    pub fn emit(module: *IR.Module, out_path: []const u8, allocator: std.mem.Allocator) !void {
        const cwd = std.fs.cwd();
        var file = try cwd.createFile(out_path, .{});
        defer file.close();
        const w = file.writer();

        var cg: LLVMCodegen = .{ .allocator = allocator };
        try cg.writeHeader(w);
        try cg.emitGlobals(w, module);
        try cg.emitFunctions(w, module);
    }

    fn writeHeader(self: *LLVMCodegen, w: anytype) !void {
        _ = self;
        _ = w;
        // Minimal module header
        // target triple can be omitted for textual IR; keep minimalism
    }

    fn valName(self: *LLVMCodegen, v: IR.Value, buf: *[64]u8) []const u8 {
        _ = self;
        return std.fmt.bufPrint(buf, "%v{d}", .{v.id}) catch "v0";
    }

    fn llvmTy(self: *LLVMCodegen, vt: IR.ValueType) []const u8 {
        _ = self;
        return switch (vt) {
            .Int => "i32",
            .Float => "double",
            .Bool => "i1",
            .String, .Function, .Capability, .Address => "ptr",
            .Void => "void",
        };
    }

    fn emitGlobals(self: *LLVMCodegen, w: anytype, module: *IR.Module) !void {
        // Emit string constants as private unnamed_addr globals
        for (module.instructions.items) |instr| {
            if (instr.kind == .StringConst) {
                if (instr.result) |v| {
                    const str = instr.metadata; // already literal content (maybe quoted)
                    // Create a simple cstring global
                    const esc = try self.escapeForLLVM(str);
                    defer self.allocator.free(esc);
                    try w.print("@s{d} = private unnamed_addr constant [{d} x i8] c{c}, align 1\n", .{ v.id, esc.len, esc });
                }
            }
        }
        try w.print("\n", .{});
    }

    fn escapeForLLVM(self: *LLVMCodegen, raw: []const u8) ![]u8 {
        // Convert a raw string to LLVM c"..." style bytes with \0 terminator
        var out: std.ArrayList(u8) = .empty;
        defer out.deinit();
        try out.append('"');
        // Strip quotes if present
        var src = raw;
        if (src.len >= 2 and src[0] == '"' and src[src.len - 1] == '"') src = src[1 .. src.len - 1];
        for (src) |b| {
            // basic escapes
            if (b == '\\' or b == '"') {
                try out.append('\\');
                try out.append(b);
            } else if (b == 0x0A) {
                try out.appendSlice("\\0A");
            } else if (b == 0x09) {
                try out.appendSlice("\\09");
            } else {
                if (b >= 0x20 and b <= 0x7E) {
                    try out.append(b);
                } else {
                    // hex escape
                    try out.append('\\');
                    const hi = (b >> 4) & 0xF;
                    const lo = b & 0xF;
                    const hch = if (hi < 10) (@as(u8, '0') + hi) else (@as(u8, 'A') + (hi - 10));
                    const lch = if (lo < 10) (@as(u8, '0') + lo) else (@as(u8, 'A') + (lo - 10));
                    try out.append(hch);
                    try out.append(lch);
                }
            }
        }
        // zero-terminate
        try out.appendSlice("\\00");
        try out.append('"');
        return try out.toOwnedSlice(alloc);
    }

    fn emitFunctions(self: *LLVMCodegen, w: anytype, module: *IR.Module) !void {
        var addr_types = std.AutoHashMap(u32, IR.ValueType).init(self.allocator);
        defer addr_types.deinit();

        var i: usize = 0;
        const instrs = module.instructions.items;
        while (i < instrs.len) : (i += 1) {
            const instr = instrs[i];
            if (instr.kind == .FunctionDef) {
                var fname: []const u8 = instr.metadata;
                if (instr.result) |r| fname = r.name;
                try w.print("define void @{s}() {{\n", .{fname});
                // Simple linear emission until next FunctionDef or EOF
                var j = i + 1;
                while (j < instrs.len) : (j += 1) {
                    const ni = instrs[j];
                    if (ni.kind == .FunctionDef) break;
                    try self.emitInstr(w, &addr_types, ni);
                    if (ni.kind == .Return) break;
                }
                try w.print("}}\n\n", .{});
                i = j;
            }
        }
    }

    fn emitInstr(self: *LLVMCodegen, w: anytype, addr_types: *std.AutoHashMap(u32, IR.ValueType), instr: IR.Instruction) !void {
        var buf: [64]u8 = undefined;
        switch (instr.kind) {
            .Label => {
                try w.print("{s}:\n", .{instr.metadata});
            },
            .Branch => {
                try w.print("  br label %{s}\n", .{instr.metadata});
            },
            .CondBranch => {
                // metadata "then:X else:Y" -> parse targets
                const then_pos = std.mem.indexOf(u8, instr.metadata, "then:") orelse 0;
                const else_pos = std.mem.indexOf(u8, instr.metadata, " else:") orelse instr.metadata.len;
                const then_name = std.mem.trim(u8, instr.metadata[then_pos + 5 .. else_pos], " ");
                const else_name = if (else_pos + 6 <= instr.metadata.len)
                    std.mem.trim(u8, instr.metadata[else_pos + 6 ..], " ")
                else
                    "";
                const cond = if (instr.operands.len > 0) blk: {
                    const v = instr.operands[0];
                    break :blk self.valName(v, &buf);
                } else "%c0";
                try w.print("  br i1 {s}, label %{s}, label %{s}\n", .{ cond, then_name, else_name });
            },
            .Return => {
                try w.print("  ret void\n", .{});
            },
            .VarDecl => {
                if (instr.result) |r| {
                    const n = self.valName(r, &buf);
                    try w.print("  {s} = alloca i8\n", .{n});
                }
            },
            .Store => {
                if (instr.dest) |d| {
                    const dst = self.valName(d, &buf);
                    if (instr.operands.len > 0) {
                        const sval = instr.operands[0];
                        _ = try addr_types.put(d.id, sval.type);
                        const ty = self.llvmTy(sval.type);
                        const src = self.valName(sval, &buf);
                        try w.print("  store {s} {s}, ptr {s}\n", .{ ty, src, dst });
                    } else {
                        try w.print("  ; store missing src\n", .{});
                    }
                } else {
                    try w.print("  ; store missing dest\n", .{});
                }
            },
            .Load => {
                if (instr.result) |r| {
                    const dst = self.valName(r, &buf);
                    if (instr.operands.len > 0) {
                        const addr = instr.operands[0];
                        const aname = self.valName(addr, &buf);
                        const elem_ty = addr_types.get(addr.id) orelse r.type;
                        const ty = self.llvmTy(elem_ty);
                        try w.print("  {s} = load {s}, ptr {s}\n", .{ dst, ty, aname });
                    }
                }
            },
            .BinaryOp => {
                if (instr.result) |r| {
                    const dst = self.valName(r, &buf);
                    const lhs = if (instr.operands.len > 0) self.valName(instr.operands[0], &buf) else "%x";
                    const rhs = if (instr.operands.len > 1) self.valName(instr.operands[1], &buf) else "%y";
                    const is_float = r.type == .Float;
                    const ty = self.llvmTy(r.type);
                    const op = switch (instr.binop orelse .Add) {
                        .Add => if (is_float) "fadd" else "add",
                        .Sub => if (is_float) "fsub" else "sub",
                        .Mul => if (is_float) "fmul" else "mul",
                        .Div => if (is_float) "fdiv" else "sdiv",
                    };
                    try w.print("  {s} = {s} {s} {s}, {s}\n", .{ dst, op, ty, lhs, rhs });
                }
            },
            .CompareOp => {
                if (instr.result) |r| {
                    const dst = self.valName(r, &buf);
                    const lhs = if (instr.operands.len > 0) self.valName(instr.operands[0], &buf) else "%x";
                    const rhs = if (instr.operands.len > 1) self.valName(instr.operands[1], &buf) else "%y";
                    const is_float = (instr.operands.len > 0 and instr.operands[0].type == .Float) or (instr.operands.len > 1 and instr.operands[1].type == .Float);
                    const ty = if (is_float) self.llvmTy(.Float) else self.llvmTy(.Int);
                    const cop = switch (instr.cmpop orelse .Eq) {
                        .Eq => if (is_float) "oeq" else "eq",
                        .Neq => if (is_float) "one" else "ne",
                        .Lt => if (is_float) "olt" else "slt",
                        .Le => if (is_float) "ole" else "sle",
                        .Gt => if (is_float) "ogt" else "sgt",
                        .Ge => if (is_float) "oge" else "sge",
                    };
                    if (is_float) {
                        try w.print("  {s} = fcmp {s} {s} {s}, {s}\n", .{ dst, cop, ty, lhs, rhs });
                    } else {
                        try w.print("  {s} = icmp {s} {s} {s}, {s}\n", .{ dst, cop, ty, lhs, rhs });
                    }
                }
            },
            .UnaryOp => {
                if (instr.result) |r| {
                    const dst = self.valName(r, &buf);
                    const op = instr.unop orelse .Plus;
                    const v = if (instr.operands.len > 0) self.valName(instr.operands[0], &buf) else "%x";
                    switch (op) {
                        .Not => try w.print("  {s} = xor i1 {s}, true\n", .{ dst, v }),
                        .Neg => if (r.type == .Float)
                            try w.print("  {s} = fneg double {s}\n", .{ dst, v })
                        else
                            try w.print("  {s} = sub i32 0, {s}\n", .{ dst, v }),
                        .Plus => try w.print("  {s} = add i32 0, {s}\n", .{ dst, v }),
                    }
                }
            },
            .AddressOf => {
                // Enforce typed GEP only: require layouts to be available
                return error.Unimplemented;
            },
            else => {
                // default: comment for now
                try w.print("  ; {s}\n", .{@tagName(instr.kind)});
            },
        }
    }
};
