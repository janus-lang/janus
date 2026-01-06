// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const grpc = @import("grpc_bindings");
const api = @import("libjanus");

const DocumentState = struct { uri: []const u8, content: []const u8, snapshot: ?api.Snapshot = null };

// gRPC server backed by pure-Zig janusd logic. Bridges via C shim.
pub const OracleGrpcServer = if (grpc.enabled) struct {
    allocator: std.mem.Allocator,
    c_server: ?*grpc.c.JanusOracleServer = null,

    // Minimal daemon state (mirrors janusd JSON path but without JSON)
    docs: std.StringHashMap(DocumentState),

    pub fn init(allocator: std.mem.Allocator) OracleGrpcServer {
        return .{ .allocator = allocator, .docs = std.StringHashMap(DocumentState).init(allocator) };
    }

    pub fn deinit(self: *OracleGrpcServer) void {
        if (self.c_server) |s| {
            _ = grpc.c.janus_oracle_server_stop(s);
            grpc.c.janus_oracle_server_destroy(s);
            self.c_server = null;
        }
        var it = self.docs.iterator();
        while (it.next()) |entry| {
            const ds = entry.value_ptr.*;
            if (ds.snapshot) |ss| ss.deinit();
            self.allocator.free(ds.uri);
            self.allocator.free(ds.content);
        }
        self.docs.deinit();
    }

    pub fn start(self: *OracleGrpcServer, host: []const u8, port: u16) !void {
        if (!grpc.enabled) return error.Unavailable;

        var host_buf = try self.allocator.alloc(u8, host.len + 1);
        defer self.allocator.free(host_buf);
        @memcpy(host_buf[0..host.len], host);
        host_buf[host.len] = 0;
        const srv = grpc.c.janus_oracle_server_create(@ptrCast(host_buf.ptr), port) orelse return error.Unavailable;
        self.c_server = srv;
        // Register handlers with `self` as user pointer
        const rc = grpc.c.janus_oracle_server_set_handlers(
            srv,
            onDocUpdate,
            onHoverAt,
            onDefinitionAt,
            onReferencesAt,
            self,
        );
        if (rc != 0) return error.Unavailable;
        if (grpc.c.janus_oracle_server_start(srv) != 0) return error.Unavailable;
    }

    fn requireSnapshot(self: *OracleGrpcServer, uri: []const u8, content: []const u8) !api.Snapshot {
        const owned_uri = try self.allocator.dupe(u8, uri);
        errdefer self.allocator.free(owned_uri);
        const owned_content = try self.allocator.dupe(u8, content);
        errdefer self.allocator.free(owned_content);

        var system = try api.ASTDBSystem.init(self.allocator, true);
        const ss = system.createSnapshot() catch return error.OutOfMemory;
        var tok = api.tokenizer.Tokenizer.init(self.allocator, owned_content);
        defer tok.deinit();
        const tokens = try tok.tokenize();
        defer self.allocator.free(tokens);
        var parser = api.parser.Parser.init(self.allocator, tokens);
        defer parser.deinit();
        _ = try parser.parseIntoSnapshot(ss);

        if (self.docs.getPtr(owned_uri)) |ds| {
            if (ds.snapshot) |*old| old.deinit();
            self.allocator.free(ds.content);
            ds.content = owned_content;
            ds.snapshot = ss;
        } else {
            try self.docs.put(owned_uri, .{ .uri = owned_uri, .content = owned_content, .snapshot = ss });
        }
        return ss;
    }

    fn getSnapshot(self: *OracleGrpcServer, uri: []const u8) ?*api.Snapshot {
        if (self.docs.getPtr(uri)) |ds| {
            if (ds.snapshot) |*snapshot| return snapshot;
        }
        return null;
    }

    // ---------- C handler bridges ----------
    fn onDocUpdate(uri_c: [*c]const u8, content_c: [*c]const u8, ok_out: [*c]bool, user: ?*anyopaque) callconv(.C) c_int {
        const self: *OracleGrpcServer = @ptrCast(@alignCast(user.?));
        const uri = std.mem.span(uri_c);
        const content = std.mem.span(content_c);
        ok_out.* = false;
        _ = self.requireSnapshot(uri, content) catch return 2;
        ok_out.* = true;
        return 0;
    }

    fn onHoverAt(uri_c: [*c]const u8, line: u32, character: u32, markdown_out: [*c][*c]const u8, user: ?*anyopaque) callconv(.C) c_int {
        const self: *OracleGrpcServer = @ptrCast(@alignCast(user.?));
        markdown_out.* = null;
        const uri = std.mem.span(uri_c);
        const ss = self.getSnapshot(uri) orelse return 0; // no hover
        var engine = api.QueryEngine.init(self.allocator, ss);
        defer engine.deinit();
        var byte_pos: u32 = 0;
        for (0..ss.tokenCount()) |i| {
            const tid: api.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const t = ss.getToken(tid) orelse continue;
            if (t.span.line == line + 1 and t.span.column >= character + 1) {
                byte_pos = t.span.start;
                break;
            }
        }
        const node_res = engine.nodeAt(byte_pos);
        if (node_res.result == null) return 0;
        var target_node = node_res.result.?;
        const nrow = ss.getNode(target_node) orelse return 0;

        // If we're hovering an identifier, resolve its declaration and report its type
        if (nrow.kind == .identifier) {
            const tok = ss.getToken(nrow.first_token) orelse return 0;
            const scope = ss.getNodeScope(target_node) orelse return 0;
            const decl_opt = engine.lookup(scope, tok.str orelse return 0).result;
            if (decl_opt) |decl| {
                const drow = ss.getDeclCompat(decl) orelse return 0;
                target_node = drow.node;
            }
        }

        const type_res = engine.typeOf(target_node);
        const ty = type_res.result;

        // Map builtin type ids (1..4) to human-readable names
        const name = switch (@intFromEnum(ty)) {
            1 => "i32",
            2 => "f64",
            3 => "bool",
            4 => "string",
            else => "unknown",
        };

        var buf: [128]u8 = undefined;
        const s = std.fmt.bufPrintZ(&buf, "type: {s}", .{name}) catch null;
        if (s) |z| {
            markdown_out.* = @ptrCast(z.ptr);
        }
        return 0;
    }

    fn onDefinitionAt(uri_c: [*c]const u8, line: u32, character: u32, found_out: [*c]bool, def_uri_out: [*c][*c]const u8, def_line_out: [*c]u32, def_character_out: [*c]u32, user: ?*anyopaque) callconv(.C) c_int {
        const self: *OracleGrpcServer = @ptrCast(@alignCast(user.?));
        found_out.* = false;
        def_uri_out.* = null;
        def_line_out.* = 0;
        def_character_out.* = 0;
        const uri = std.mem.span(uri_c);
        const ss = self.getSnapshot(uri) orelse return 0;
        var engine = api.QueryEngine.init(self.allocator, ss);
        defer engine.deinit();
        var byte_pos: u32 = 0;
        for (0..ss.tokenCount()) |i| {
            const tid: api.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const t = ss.getToken(tid) orelse continue;
            if (t.span.line == line + 1 and t.span.column >= character + 1) {
                byte_pos = t.span.start;
                break;
            }
        }
        const node_opt = engine.nodeAt(byte_pos).result;
        if (node_opt == null) return 0;
        const node = node_opt.?;
        const nrow = ss.getNode(node) orelse return 0;
        const tok = ss.getToken(nrow.first_token) orelse return 0;
        const scope = ss.getNodeScope(node) orelse return 0;
        const decl_opt = engine.lookup(scope, tok.str orelse return 0).result;
        if (decl_opt == null) return 0;
        const decl = decl_opt.?;
        const drow = ss.getDeclCompat(decl) orelse return 0;
        const first_tok = ss.getToken(ss.getNode(drow.node).?.first_token).?;
        found_out.* = true;
        def_uri_out.* = uri_c; // same file
        def_line_out.* = first_tok.span.line - 1;
        def_character_out.* = first_tok.span.column;
        return 0;
    }

    fn onReferencesAt(uri_c: [*c]const u8, line: u32, character: u32, include_decl: bool, sink: grpc.c.JanusLocationSinkFn, sink_user: ?*anyopaque, user: ?*anyopaque) callconv(.C) c_int {
        // include_decl honored below
        const self: *OracleGrpcServer = @ptrCast(@alignCast(user.?));
        const uri = std.mem.span(uri_c);
        const ss = self.getSnapshot(uri) orelse return 0;
        var engine = api.QueryEngine.init(self.allocator, ss);
        defer engine.deinit();
        var byte_pos: u32 = 0;
        for (0..ss.tokenCount()) |i| {
            const tid: api.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const t = ss.getToken(tid) orelse continue;
            if (t.span.line == line + 1 and t.span.column >= character + 1) {
                byte_pos = t.span.start;
                break;
            }
        }
        const node_opt = engine.nodeAt(byte_pos).result;
        if (node_opt == null) return 0;
        const node = node_opt.?;
        // Resolve declaration then stream references to it
        const nrow = ss.getNode(node) orelse return 0;
        const tok = ss.getToken(nrow.first_token) orelse return 0;
        const scope = ss.getNodeScope(node) orelse return 0;
        const decl_opt = engine.lookup(scope, tok.str orelse return 0).result;
        if (decl_opt) |decl| {
            // Optionally include the declaration itself
            if (include_decl) {
                const drow = ss.getDeclCompat(decl) orelse return 0;
                const dtok = ss.getToken(ss.getNode(drow.node).?.first_token).?;
                const s = sink.?;
                s(sink_user, uri_c, dtok.span.line - 1, dtok.span.column);
            }
            // Stream all refs pointing to decl
            for (0..ss.refCount()) |ri| {
                const rid: api.RefId = @enumFromInt(@as(u32, @intCast(ri)));
                const r = ss.getRef(rid) orelse continue;
                if (std.meta.eql(r.decl, decl)) {
                    const rtok = ss.getToken(ss.getNode(r.at_node).?.first_token).?;
                    const s = sink.?;
                    s(sink_user, uri_c, rtok.span.line - 1, rtok.span.column);
                }
            }
        }
        return 0;
    }
} else struct {
    pub fn init(allocator: std.mem.Allocator) OracleGrpcServer {
        _ = allocator;
        return .{};
    }
    pub fn deinit(self: *OracleGrpcServer) void {
        _ = self;
    }
    pub fn start(self: *OracleGrpcServer, host: []const u8, port: u16) !void {
        _ = self;
        _ = host;
        _ = port;
        return error.Unavailable;
    }
};

pub const Location = struct { uri: []const u8, line: u32, character: u32 };
