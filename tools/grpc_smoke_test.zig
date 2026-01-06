// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const grpc = @import("grpc_bindings");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len < 3) {
        std.debug.print("usage: oracle-smoke <host> <port>\n", .{});
        std.process.exit(2);
    }
    const host = args[1];
    const port = try std.fmt.parseInt(u16, args[2], 10);

    if (!grpc.enabled) {
        std.debug.print("gRPC support not available in this build. Ensure stubs and system gRPC/protobuf are installed.\n", .{});
        std.process.exit(3);
    }

    // NUL-terminate host for C API
    var host_z = try allocator.alloc(u8, host.len + 1);
    defer allocator.free(host_z);
    @memcpy(host_z[0..host.len], host);
    host_z[host.len] = 0;

    const client = grpc.c.janus_oracle_client_connect(@ptrCast(host_z.ptr), port) orelse {
        std.debug.print("connect: unable to create client (is janusd running?)\n", .{});
        std.process.exit(5);
    };
    defer grpc.c.janus_oracle_client_disconnect(client);

    // DocUpdate
    var uri = try allocator.alloc(u8, "file:///tmp/demo.jan".len + 1);
    defer allocator.free(uri);
    @memcpy(uri[0.."file:///tmp/demo.jan".len], "file:///tmp/demo.jan");
    uri["file:///tmp/demo.jan".len] = 0;
    var content = try allocator.alloc(u8, "let x = 1\nlet y = x\n".len + 1);
    defer allocator.free(content);
    @memcpy(content[0.."let x = 1\nlet y = x\n".len], "let x = 1\nlet y = x\n");
    content["let x = 1\nlet y = x\n".len] = 0;
    var ok: bool = false;
    var rc = grpc.c.janus_oracle_doc_update(client, @ptrCast(uri.ptr), @ptrCast(content.ptr), &ok);
    std.debug.print("DocUpdate rc={} ok={}\n", .{ rc, ok });

    // HoverAt
    var md_ptr: ?[*:0]const u8 = null;
    rc = grpc.c.janus_oracle_hover_at(client, @ptrCast(uri.ptr), 0, 4, @ptrCast(&md_ptr));
    if (rc == 0) {
        if (md_ptr) |p| {
            const s = std.mem.span(p);
            std.debug.print("HoverAt rc=0 markdown='{s}'\n", .{s});
            grpc.c.janus_oracle_free_string(@ptrCast(p));
        } else {
            std.debug.print("HoverAt rc=0 markdown=null\n", .{});
        }
    } else {
        std.debug.print("HoverAt rc={} markdown=null\n", .{rc});
    }

    // DefinitionAt
    var found: bool = false;
    var def_uri_ptr: ?[*:0]const u8 = null;
    var def_line: u32 = 0;
    var def_char: u32 = 0;
    rc = grpc.c.janus_oracle_definition_at(client, @ptrCast(uri.ptr), 1, 4, &found, @ptrCast(&def_uri_ptr), &def_line, &def_char);
    if (rc == 0 and found) {
        const s = if (def_uri_ptr) |p| std.mem.span(p) else "";
        std.debug.print("DefinitionAt rc=0 found=true uri='{s}' line={} char={}\n", .{ s, def_line, def_char });
        if (def_uri_ptr) |p| grpc.c.janus_oracle_free_string(@ptrCast(p));
    } else {
        std.debug.print("DefinitionAt rc={} found=false\n", .{rc});
    }

    // ReferencesAt
    var arr_ptr: ?[*]grpc.c.JanusOracleLocation = null;
    var count: u32 = 0;
    rc = grpc.c.janus_oracle_references_at(client, @ptrCast(uri.ptr), 1, 4, true, @ptrCast(&arr_ptr), &count);
    std.debug.print("ReferencesAt rc={} count={}\n", .{ rc, count });
    if (rc == 0 and arr_ptr != null and count > 0) {
        var i: usize = 0;
        while (i < count) : (i += 1) {
            const loc = arr_ptr.?[i];
            const s = if (loc.uri) |p| std.mem.span(p) else "";
            std.debug.print("  - {s}@{}:{}\n", .{ s, loc.line, loc.character });
            if (loc.uri) |p| grpc.c.janus_oracle_free_string(@ptrCast(p));
        }
        std.c.free(@ptrCast(arr_ptr));
    }
}

// no local fallback; this client must hit the real gRPC server
