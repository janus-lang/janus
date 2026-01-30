// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const libjanus = @import("libjanus");
const janus_parser = libjanus.parser;
const dumper = @import("dumper.zig");

pub const InspectFormat = enum {
    text,
    json,
};

pub const InspectOptions = struct {
    format: InspectFormat = .text,
    show_ast: bool = false,
    show_symbols: bool = false,
    show_types: bool = false,
};

pub const Inspector = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Inspector {
        return Inspector{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Inspector) void {
        _ = self;
    }

    /// Inspects a source string and returns the dump result.
    pub fn inspectSource(self: *Inspector, source: []const u8, options: InspectOptions) ![]const u8 {
        var astdb = try janus_parser.AstDB.init(self.allocator, true);
        defer astdb.deinit();

        var parser = janus_parser.Parser.init(self.allocator);
        defer parser.deinit();

        var error_name: ?[]const u8 = null;

        var snapshot = parser.parseIntoAstDB(&astdb, "inspect.jan", source) catch |err| blk: {
            error_name = @errorName(err);
            // Construct partial snapshot to inspect state despite error
            break :blk janus_parser.Snapshot{
                .core_snapshot = .{ .astdb = &astdb },
                .astdb_system = &astdb,
                .allocator = self.allocator,
                .owns_astdb = false,
            };
        };
        defer snapshot.deinit();

        const dump = if (options.format == .json)
            try dumper.dumpAstJson(&snapshot, self.allocator)
        else
            try dumper.dumpAstText(&snapshot, self.allocator);

        if (error_name) |ename| {
            const result = try std.fmt.allocPrint(self.allocator, "Parse Failed: {s}\n{s}", .{ ename, dump });
            self.allocator.free(dump);
            return result;
        }

        return dump;
    }
};
