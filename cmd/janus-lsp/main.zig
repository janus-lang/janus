// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Standalone LSP Server
//!
//! "Thick Client" architecture:
//! - Direct ASTDB instantiation (no daemon dependency)
//! - Embedded Symbol Table
//! - Self-contained language intelligence
//!
//! Trade-off: Unsaved VS Code edits invisible to CLI `janus query`.
//! Bridge: Citadel Protocol (v0.3.0)

const std = @import("std");
const astdb = @import("astdb");
const lsp_server = @import("lsp_server");

/// Zig 0.16 compat: thin fd-based reader/writer replacing std.fs.File
const FdReader = struct {
    fd: std.posix.fd_t,
    pub fn read(self: FdReader, buf: []u8) !usize {
        const rc = std.os.linux.read(self.fd, buf.ptr, buf.len);
        const signed: isize = @bitCast(rc);
        if (signed < 0) return error.ReadFailed;
        if (rc == 0) return 0;
        return rc;
    }
};

const FdWriter = struct {
    fd: std.posix.fd_t,
    pub fn writeAll(self: FdWriter, data: []const u8) !void {
        var offset: usize = 0;
        while (offset < data.len) {
            const rc = std.os.linux.write(self.fd, data[offset..].ptr, data.len - offset);
            const signed: isize = @bitCast(rc);
            if (signed <= 0) return error.WriteFailed;
            offset += rc;
        }
    }
};

pub fn main(_: std.process.Init) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB (The Brain) - non-deterministic for LSP (timestamps vary)
    var db = try astdb.AstDB.init(allocator, false);
    defer db.deinit();

    std.log.info("Janus LSP Server v0.2.1 - Standalone Mode", .{});
    std.log.info("Listening on stdin/stdout (JSON-RPC)", .{});

    // Zig 0.16: std.fs.File removed — use raw fd adapters
    const stdin = FdReader{ .fd = 0 };
    const stdout = FdWriter{ .fd = 1 };

    var server = lsp_server.LspServer(
        FdReader,
        FdWriter,
    ).init(
        allocator,
        stdin,
        stdout,
        &db,
    );
    defer server.deinit();

    // Run event loop
    try server.run();
}
