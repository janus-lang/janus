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

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB (The Brain) - non-deterministic for LSP (timestamps vary)
    var db = try astdb.AstDB.init(allocator, false);
    defer db.deinit();

    std.log.info("🧠 Janus LSP Server v0.2.1 - Standalone Mode", .{});
    std.log.info("📡 Listening on stdin/stdout (JSON-RPC)", .{});

    // Zig 0.15.2: Pass File directly, not File.Reader (Reader lacks methods)
    const stdin = std.fs.File.stdin();
    const stdout = std.fs.File.stdout();

    // Create LSP server with direct File access (bypasses broken Reader abstraction)
    var server = lsp_server.LspServer(
        std.fs.File,
        std.fs.File,
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
