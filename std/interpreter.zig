// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// std/interpreter.zig - Simple Janus interpreter for :min profile
// Executes basic Janus programs directly without LLVM compilation

const std = @import("std");

// Simple Janus interpreter for basic programs
pub const JanusInterpreter = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) JanusInterpreter {
        return JanusInterpreter{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *JanusInterpreter) void {
        _ = self;
    }

    // Execute a simple Janus program
    pub fn execute(self: *JanusInterpreter, source: []const u8) !void {

        // For now, implement a very basic interpreter that recognizes
        // simple print statements and executes them

        // Look for print statements in the source
        var lines = std.mem.split(u8, source, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            // Skip empty lines and comments
            if (trimmed.len == 0 or std.mem.startsWith(u8, trimmed, "//")) {
                continue;
            }

            // Look for print statements
            if (std.mem.startsWith(u8, trimmed, "print(")) {
                try executePrint(self, trimmed);
            }
        }
    }

    fn executePrint(_: *JanusInterpreter, line: []const u8) !void {

        // Extract the string from print("...")
        const start_quote = std.mem.indexOf(u8, line, "\"");
        if (start_quote == null) return;

        const start = start_quote.? + 1;
        const end_quote = std.mem.lastIndexOf(u8, line, "\"");
        if (end_quote == null or end_quote.? <= start) return;

        const message = line[start..end_quote.?];

        // Print to stdout
        var stdout_buffer: [256]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        try stdout_writer.print("{s}\n", .{message});
        try stdout_writer.flush();
    }
};

// Export functions for the Janus runtime
export fn executeJanusProgram(source_ptr: [*]const u8, source_len: usize) i32 {
    const source = source_ptr[0..source_len];

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var interpreter = JanusInterpreter.init(allocator);
    defer interpreter.deinit();

    interpreter.execute(source) catch |err| switch (err) {
        error.OutOfMemory => return 1,
        else => return 2,
    };

    return 0;
}
