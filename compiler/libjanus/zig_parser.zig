// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Zig Signature Parser
//! Extracts pub fn declarations from Zig source files for native integration.
//!
//! This is NOT FFI - during bootstrap, Janus IS Zig. We parse Zig signatures
//! so the LLVM emitter knows how to emit correct calls. The build system
//! (build.zig) compiles both Janus and Zig files, linking them naturally.
//!
//! This is NOT a full Zig parser - just enough to extract function signatures.

const std = @import("std");

/// Represents a Zig function parameter
pub const ZigParam = struct {
    name: []const u8,
    type_str: []const u8,
    janus_type: JanusType,
};

/// Janus type mapping
pub const JanusType = enum {
    i32,
    i64,
    f32,
    f64,
    bool_,
    void_,
    ptr, // *anyopaque, [*]u8, etc.
    string, // [*:0]const u8
    unknown,

    pub fn toLLVMType(self: JanusType) []const u8 {
        return switch (self) {
            .i32 => "i32",
            .i64 => "i64",
            .f32 => "float",
            .f64 => "double",
            .bool_ => "i1",
            .void_ => "void",
            .ptr, .string => "ptr",
            .unknown => "i32", // fallback
        };
    }
};

/// Represents a parsed Zig function signature
pub const ZigFnSig = struct {
    name: []const u8,
    params: []ZigParam,
    return_type: JanusType,
    return_type_str: []const u8,
    is_export: bool,
    calling_convention: CallingConvention,

    pub const CallingConvention = enum {
        zig_default,
        c,
    };
};

/// Parse result containing all extracted function signatures
pub const ParseResult = struct {
    functions: std.ArrayListUnmanaged(ZigFnSig),
    allocator: std.mem.Allocator,

    pub fn deinit(self: *ParseResult) void {
        for (self.functions.items) |*func| {
            self.allocator.free(func.params);
        }
        self.functions.deinit(self.allocator);
    }
};

/// Parse a Zig source file and extract pub fn signatures
pub fn parseZigSource(allocator: std.mem.Allocator, source: []const u8) !ParseResult {
    var result = ParseResult{
        .functions = .{},
        .allocator = allocator,
    };
    errdefer result.deinit();

    var i: usize = 0;
    while (i < source.len) {
        // Skip whitespace
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
        if (i >= source.len) break;

        // Skip comments
        if (i + 1 < source.len and source[i] == '/' and source[i + 1] == '/') {
            while (i < source.len and source[i] != '\n') : (i += 1) {}
            continue;
        }

        // Look for 'pub' keyword
        if (startsWithWord(source[i..], "pub")) {
            i += 3;
            // Skip whitespace after pub
            while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

            // Check for 'export' (optional)
            var is_export = false;
            if (startsWithWord(source[i..], "export")) {
                is_export = true;
                i += 6;
                while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
            }

            // Look for 'fn' keyword
            if (startsWithWord(source[i..], "fn")) {
                i += 2;
                if (try parseFnSignature(allocator, source, &i, is_export)) |sig| {
                    try result.functions.append(allocator, sig);
                }
                continue;
            }
        }

        // Look for standalone 'export fn'
        if (startsWithWord(source[i..], "export")) {
            i += 6;
            while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
            if (startsWithWord(source[i..], "fn")) {
                i += 2;
                if (try parseFnSignature(allocator, source, &i, true)) |sig| {
                    try result.functions.append(allocator, sig);
                }
                continue;
            }
        }

        i += 1;
    }

    return result;
}

fn startsWithWord(haystack: []const u8, word: []const u8) bool {
    if (haystack.len < word.len) return false;
    if (!std.mem.eql(u8, haystack[0..word.len], word)) return false;
    // Make sure it's a word boundary
    if (haystack.len > word.len) {
        const next = haystack[word.len];
        if (std.ascii.isAlphanumeric(next) or next == '_') return false;
    }
    return true;
}

fn parseFnSignature(allocator: std.mem.Allocator, source: []const u8, pos: *usize, is_export: bool) !?ZigFnSig {
    var i = pos.*;

    // Skip whitespace
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

    // Parse function name
    const name_start = i;
    while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) : (i += 1) {}
    if (i == name_start) return null;
    const name = source[name_start..i];

    // Skip whitespace
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

    // Expect '('
    if (i >= source.len or source[i] != '(') return null;
    i += 1;

    // Parse parameters
    var params = std.ArrayListUnmanaged(ZigParam){};
    defer params.deinit(allocator);

    while (i < source.len and source[i] != ')') {
        // Skip whitespace
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
        if (i >= source.len or source[i] == ')') break;

        // Parse parameter name
        const param_name_start = i;
        while (i < source.len and (std.ascii.isAlphanumeric(source[i]) or source[i] == '_')) : (i += 1) {}
        const param_name = source[param_name_start..i];

        // Skip whitespace
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

        // Expect ':'
        if (i >= source.len or source[i] != ':') {
            // Skip to next param or end
            while (i < source.len and source[i] != ',' and source[i] != ')') : (i += 1) {}
            if (i < source.len and source[i] == ',') i += 1;
            continue;
        }
        i += 1;

        // Skip whitespace
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

        // Parse type (until ',' or ')')
        const type_start = i;
        var paren_depth: u32 = 0;
        while (i < source.len) {
            if (source[i] == '(') paren_depth += 1;
            if (source[i] == ')') {
                if (paren_depth == 0) break;
                paren_depth -= 1;
            }
            if (source[i] == ',' and paren_depth == 0) break;
            i += 1;
        }
        const type_str = std.mem.trim(u8, source[type_start..i], " \t\n\r");

        try params.append(allocator, .{
            .name = param_name,
            .type_str = type_str,
            .janus_type = mapZigTypeToJanus(type_str),
        });

        // Skip comma
        if (i < source.len and source[i] == ',') i += 1;
    }

    // Skip ')'
    if (i < source.len and source[i] == ')') i += 1;

    // Skip whitespace
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

    // Check for calling convention
    var calling_conv = ZigFnSig.CallingConvention.zig_default;
    if (startsWithWord(source[i..], "callconv")) {
        i += 8;
        // Skip to after the callconv(...)
        while (i < source.len and source[i] != ')') : (i += 1) {}
        if (i < source.len) i += 1;
        // Check if it was .c
        const start_check = if (i >= 20) i - 20 else 0;
        if (std.mem.indexOf(u8, source[start_check..i], ".c")) |_| {
            calling_conv = .c;
        }
        while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}
    }

    // Parse return type (after optional callconv)
    var return_type = JanusType.void_;
    var return_type_str: []const u8 = "void";

    // Look for return type or '{'
    while (i < source.len and std.ascii.isWhitespace(source[i])) : (i += 1) {}

    if (i < source.len and source[i] != '{') {
        const ret_start = i;
        while (i < source.len and source[i] != '{' and source[i] != ';') : (i += 1) {}
        return_type_str = std.mem.trim(u8, source[ret_start..i], " \t\n\r");
        return_type = mapZigTypeToJanus(return_type_str);
    }

    // Skip to end of function (find matching '{' '}' or ';')
    var brace_depth: u32 = 0;
    while (i < source.len) {
        if (source[i] == '{') brace_depth += 1;
        if (source[i] == '}') {
            if (brace_depth == 0) break;
            brace_depth -= 1;
            if (brace_depth == 0) {
                i += 1;
                break;
            }
        }
        if (source[i] == ';' and brace_depth == 0) {
            i += 1;
            break;
        }
        i += 1;
    }

    pos.* = i;

    // Allocate owned copy of params
    const owned_params = try allocator.alloc(ZigParam, params.items.len);
    @memcpy(owned_params, params.items);

    return ZigFnSig{
        .name = name,
        .params = owned_params,
        .return_type = return_type,
        .return_type_str = return_type_str,
        .is_export = is_export,
        .calling_convention = calling_conv,
    };
}

/// Map Zig type string to Janus type
fn mapZigTypeToJanus(zig_type: []const u8) JanusType {
    // Exact matches
    if (std.mem.eql(u8, zig_type, "i32")) return .i32;
    if (std.mem.eql(u8, zig_type, "i64")) return .i64;
    if (std.mem.eql(u8, zig_type, "u32")) return .i32; // unsigned -> signed for simplicity
    if (std.mem.eql(u8, zig_type, "u64")) return .i64;
    if (std.mem.eql(u8, zig_type, "f32")) return .f32;
    if (std.mem.eql(u8, zig_type, "f64")) return .f64;
    if (std.mem.eql(u8, zig_type, "bool")) return .bool_;
    if (std.mem.eql(u8, zig_type, "void")) return .void_;
    if (std.mem.eql(u8, zig_type, "usize")) return .i64;
    if (std.mem.eql(u8, zig_type, "isize")) return .i64;

    // Pointer types
    if (std.mem.indexOf(u8, zig_type, "*") != null) return .ptr;
    if (std.mem.indexOf(u8, zig_type, "[*]") != null) return .ptr;
    if (std.mem.indexOf(u8, zig_type, "[*:0]") != null) return .string;

    // Optional types (treat as pointer for now)
    if (std.mem.startsWith(u8, zig_type, "?")) return .ptr;

    return .unknown;
}

// Tests
test "parse simple pub fn" {
    const source =
        \\pub fn add(a: i32, b: i32) i32 {
        \\    return a + b;
        \\}
    ;

    var result = try parseZigSource(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.functions.items.len);
    const func = result.functions.items[0];
    try std.testing.expectEqualStrings("add", func.name);
    try std.testing.expectEqual(@as(usize, 2), func.params.len);
    try std.testing.expectEqual(JanusType.i32, func.return_type);
}

test "parse export fn with callconv" {
    const source =
        \\export fn janus_print_int(value: i32) callconv(.c) void {
        \\    // implementation
        \\}
    ;

    var result = try parseZigSource(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 1), result.functions.items.len);
    const func = result.functions.items[0];
    try std.testing.expectEqualStrings("janus_print_int", func.name);
    try std.testing.expect(func.is_export);
    try std.testing.expectEqual(ZigFnSig.CallingConvention.c, func.calling_convention);
}

test "parse multiple functions" {
    const source =
        \\const std = @import("std");
        \\
        \\pub fn foo() void {}
        \\
        \\fn private_fn() void {} // Should be ignored
        \\
        \\pub export fn bar(x: f64) callconv(.c) f64 {
        \\    return x * 2;
        \\}
    ;

    var result = try parseZigSource(std.testing.allocator, source);
    defer result.deinit();

    try std.testing.expectEqual(@as(usize, 2), result.functions.items.len);
    try std.testing.expectEqualStrings("foo", result.functions.items[0].name);
    try std.testing.expectEqualStrings("bar", result.functions.items[1].name);
}
