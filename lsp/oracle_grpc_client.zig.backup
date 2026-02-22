// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const grpc = @import("grpc_bindings");

pub const OracleGrpcClient = struct {
    allocator: std.mem.Allocator,
    c_handle: *anyopaque,

    pub fn connect(allocator: std.mem.Allocator, host: []const u8, port: u16) !OracleGrpcClient {
        var host_buf = try allocator.alloc(u8, host.len + 1);
        defer allocator.free(host_buf);
        @memcpy(host_buf[0..host.len], host);
        host_buf[host.len] = 0;
        const handle = grpc.c.janus_oracle_client_connect(@ptrCast(host_buf.ptr), port) orelse return error.Unavailable;
        // Harden with sensible defaults: 1500ms connect (already enforced in shim) and 1000ms per-RPC
        _ = grpc.c.janus_oracle_client_set_timeouts(@ptrCast(handle), 0, 1000);
        return .{ .allocator = allocator, .c_handle = handle };
    }

    pub fn deinit(self: *OracleGrpcClient) void {
        grpc.c.janus_oracle_client_disconnect(@ptrCast(self.c_handle));
    }

    pub fn DocUpdate(self: *OracleGrpcClient, uri: []const u8, content: []const u8) !bool {
        var ok: bool = false;
        var uri_z = try self.allocator.alloc(u8, uri.len + 1);
        defer self.allocator.free(uri_z);
        @memcpy(uri_z[0..uri.len], uri);
        uri_z[uri.len] = 0;
        var content_z = try self.allocator.alloc(u8, content.len + 1);
        defer self.allocator.free(content_z);
        @memcpy(content_z[0..content.len], content);
        content_z[content.len] = 0;
        const rc = grpc.c.janus_oracle_doc_update(@ptrCast(self.c_handle), @ptrCast(uri_z.ptr), @ptrCast(content_z.ptr), &ok);
        if (rc != 0) return error.Transport;
        return ok;
    }

    pub fn HoverAt(self: *OracleGrpcClient, uri: []const u8, line: u32, character: u32) !?[]const u8 {
        var md_ptr: ?[*:0]const u8 = null;
        var uri_z = try self.allocator.alloc(u8, uri.len + 1);
        defer self.allocator.free(uri_z);
        @memcpy(uri_z[0..uri.len], uri);
        uri_z[uri.len] = 0;
        const rc = grpc.c.janus_oracle_hover_at(@ptrCast(self.c_handle), @ptrCast(uri_z.ptr), line, character, @ptrCast(&md_ptr));
        if (rc != 0) return error.Transport;
        if (md_ptr) |p| {
            const s = std.mem.span(p);
            const out = try self.allocator.dupe(u8, s);
            grpc.c.janus_oracle_free_string(@ptrCast(p));
            return out;
        }
        return null;
    }

    pub const Location = struct { uri: []const u8, line: u32, character: u32 };

    pub fn DefinitionAt(self: *OracleGrpcClient, uri: []const u8, line: u32, character: u32) !?Location {
        var found: bool = false;
        var uri_ptr: ?[*:0]const u8 = null;
        var out_line: u32 = 0;
        var out_char: u32 = 0;
        var uri_z = try self.allocator.alloc(u8, uri.len + 1);
        defer self.allocator.free(uri_z);
        @memcpy(uri_z[0..uri.len], uri);
        uri_z[uri.len] = 0;
        const rc = grpc.c.janus_oracle_definition_at(@ptrCast(self.c_handle), @ptrCast(uri_z.ptr), line, character, &found, @ptrCast(&uri_ptr), &out_line, &out_char);
        if (rc != 0) return error.Transport;
        if (!found) return null;
        const def_uri = if (uri_ptr) |p| blk: {
            const s = std.mem.span(p);
            const out = try self.allocator.dupe(u8, s);
            grpc.c.janus_oracle_free_string(@ptrCast(p));
            break :blk out;
        } else uri;
        return Location{ .uri = def_uri, .line = out_line, .character = out_char };
    }

    pub fn ReferencesAt(self: *OracleGrpcClient, uri: []const u8, line: u32, character: u32, include_decl: bool) ![]Location {
        var arr_ptr: ?[*]grpc.c.JanusOracleLocation = null;
        var count: u32 = 0;
        var uri_z = try self.allocator.alloc(u8, uri.len + 1);
        defer self.allocator.free(uri_z);
        @memcpy(uri_z[0..uri.len], uri);
        uri_z[uri.len] = 0;
        const rc = grpc.c.janus_oracle_references_at(@ptrCast(self.c_handle), @ptrCast(uri_z.ptr), line, character, include_decl, @ptrCast(&arr_ptr), &count);
        if (rc != 0) return error.Transport;
        if (count == 0 or arr_ptr == null) return &[_]Location{};
        var list = std.ArrayList(Location).init(self.allocator);
        defer list.deinit();
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const loc = arr_ptr.?[i];
            const u = if (loc.uri) |p| blk: {
                const s = std.mem.span(p);
                const out = try self.allocator.dupe(u8, s);
                grpc.c.janus_oracle_free_string(@ptrCast(p));
                break :blk out;
            } else uri;
            try list.append(Location{ .uri = u, .line = loc.line, .character = loc.character });
        }
        std.c.free(@ptrCast(arr_ptr));
        return try list.toOwnedSlice();
    }
};
