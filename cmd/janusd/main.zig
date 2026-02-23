// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_time = @import("compat_time");
const manual = @import("utcp_manual.zig");
pub const auth = @import("auth.zig");
const caps = @import("capabilities.zig");
const validator = @import("validator.zig");
const adapters = @import("adapters.zig");
const errors = @import("errors.zig");
const metrics = @import("metrics.zig");
const json_helpers = @import("json_helpers.zig");
const utcp = @import("utcp_registry");
const lsp = @import("lsp_server");
const janus_lib = @import("janus_lib");
const cl = utcp.cluster;

// Re-export manual functions for testing
pub const writeManualJSON = manual.writeManualJSON;

/// Minimal writer over a raw fd (replaces std.fs.File.writer in Zig 0.16)
const SocketWriter = struct {
    fd: std.posix.fd_t,

    pub const Error = error{ WriteFailed, NoSpaceLeft };

    pub fn writeAll(self: SocketWriter, data: []const u8) Error!void {
        var offset: usize = 0;
        while (offset < data.len) {
            const rc = std.os.linux.write(self.fd, data[offset..].ptr, data.len - offset);
            const signed: isize = @bitCast(rc);
            if (signed <= 0) return error.WriteFailed;
            offset += rc;
        }
    }

    pub fn write(self: SocketWriter, data: []const u8) Error!usize {
        const rc = std.os.linux.write(self.fd, data.ptr, data.len);
        const signed: isize = @bitCast(rc);
        if (signed <= 0) return error.WriteFailed;
        return rc;
    }

    pub fn print(self: SocketWriter, comptime fmt: []const u8, args: anytype) Error!void {
        var buf: [4096]u8 = undefined;
        const result = std.fmt.bufPrint(&buf, fmt, args) catch return error.NoSpaceLeft;
        try self.writeAll(result);
    }

    pub fn writeByte(self: SocketWriter, byte: u8) Error!void {
        try self.writeAll(&[_]u8{byte});
    }
};
pub const Options = manual.Options;

const LeaseContainer = struct {
    name: []const u8,
    pub fn utcpManual(self: *const LeaseContainer, alloc: std.mem.Allocator) ![]const u8 {
        return std.fmt.allocPrint(alloc, "{{\"name\":\"{s}\"}}", .{self.name});
    }
};

// janusd — minimal UTCP bootstrap server
// Transport: line-delimited JSON over TCP (bootstrap only)

pub fn main(init: std.process.Init) !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Zig 0.16: args via Init, not std.process.argsWithAllocator
    var args = std.process.Args.iterate(init.minimal.args);
    _ = args.next(); // skip argv0
    var host: []const u8 = "127.0.0.1";
    var port: u16 = 7735;
    var cluster_mode: bool = false;
    var epoch_key: [32]u8 = undefined;
    var have_key: bool = false;

    // Mode selection: default line-delimited JSON; --http for HTTP routing
    var http_mode: bool = false;
    var lsp_mode: bool = false;

    // Parse all arguments, checking for flags first
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "--http")) {
            http_mode = true;
        } else if (std.mem.eql(u8, arg, "--lsp")) {
            lsp_mode = true;
        } else if (std.mem.eql(u8, arg, "--cluster")) {
            cluster_mode = true;
        } else if (std.mem.startsWith(u8, arg, "--key-hex=")) {
            const hex = arg["--key-hex=".len..];
            if (hexTo32(hex, &epoch_key)) have_key = true;
        } else if (std.fmt.parseInt(u16, arg, 10)) |parsed| {
            // Looks like a port number
            port = parsed;
        } else |_| {
            // Treat as host
            host = arg;
        }
    }

    if (lsp_mode) {
        std.log.info("janusd (LSP Mode) starting...", .{});
        // Zig 0.16: std.fs.File removed — use raw fd adapters
        const FdReader = struct {
            fd: std.posix.fd_t,
            pub fn read(self: @This(), buf: []u8) !usize {
                const rc = std.os.linux.read(self.fd, buf.ptr, buf.len);
                const signed: isize = @bitCast(rc);
                if (signed < 0) return error.ReadFailed;
                if (rc == 0) return 0;
                return rc;
            }
        };
        const FdWriter = struct {
            fd: std.posix.fd_t,
            pub fn writeAll(self: @This(), data: []const u8) !void {
                var offset: usize = 0;
                while (offset < data.len) {
                    const rc = std.os.linux.write(self.fd, data[offset..].ptr, data.len - offset);
                    const signed: isize = @bitCast(rc);
                    if (signed <= 0) return error.WriteFailed;
                    offset += rc;
                }
            }
        };
        const stdin = FdReader{ .fd = 0 };
        const stdout = FdWriter{ .fd = 1 };

        // Initialize ASTDB (The Brain)
        var db = try janus_lib.astdb.AstDB.init(allocator, false);
        defer db.deinit();

        var server = lsp.LspServer(FdReader, FdWriter).init(allocator, stdin, stdout, &db);
        defer server.deinit();
        try server.run();
        return;
    }

    // Resolve epoch key from env if not provided
    if (!have_key) {
        if (std.process.Environ.getAlloc(.empty, allocator, "JANUSD_EPOCH_KEY")) |hex| {
            defer allocator.free(hex);
            if (hexTo32(hex, &epoch_key)) have_key = true;
        } else |_| {}
    }
    if (!have_key) {
        // Zig 0.16: std.crypto.random removed — use Linux getrandom syscall
        _ = std.os.linux.getrandom(std.mem.asBytes(&epoch_key).ptr, @sizeOf(@TypeOf(epoch_key)), 0);
    }

    // Initialize UTCP Registry and optional cluster replicator
    var app = try App.init(allocator, epoch_key, cluster_mode);
    defer app.deinit();

    // Build sockaddr_in manually (std.net/std.posix.socket removed in Zig 0.16)
    const linux = std.os.linux;
    var addr: linux.sockaddr.in = .{
        .port = std.mem.nativeToBig(u16, port),
        .addr = 0, // INADDR_ANY
    };
    if (!std.mem.eql(u8, host, "0.0.0.0")) {
        var octets: [4]u8 = .{ 0, 0, 0, 0 };
        var it = std.mem.splitScalar(u8, host, '.');
        for (&octets) |*o| {
            const part = it.next() orelse break;
            o.* = std.fmt.parseInt(u8, part, 10) catch 0;
        }
        addr.addr = std.mem.readInt(u32, &octets, .big);
    }
    const SOCK_STREAM: u32 = 1;
    const SOCK_CLOEXEC: u32 = 0o2000000;
    const IPPROTO_TCP: u32 = 6;
    const SOL_SOCKET: u32 = 1;
    const SO_REUSEADDR: u32 = 2;

    const sock_rc = linux.socket(linux.AF.INET, SOCK_STREAM | SOCK_CLOEXEC, IPPROTO_TCP);
    if (@as(isize, @bitCast(sock_rc)) < 0) return error.SocketFailed;
    const sockfd: i32 = @intCast(sock_rc);
    defer _ = linux.close(sockfd);

    const reuse: i32 = 1;
    _ = linux.setsockopt(sockfd, SOL_SOCKET, SO_REUSEADDR, std.mem.asBytes(&reuse), @sizeOf(@TypeOf(reuse)));
    const bind_rc = linux.bind(sockfd, @ptrCast(&addr), @sizeOf(@TypeOf(addr)));
    if (@as(isize, @bitCast(bind_rc)) < 0) return error.BindFailed;
    const listen_rc = linux.listen(sockfd, 128);
    if (@as(isize, @bitCast(listen_rc)) < 0) return error.ListenFailed;

    if (http_mode) {
        std.log.info("janusd (HTTP UTCP) listening on {s}:{d}", .{ host, port });
        while (true) {
            var client_addr: linux.sockaddr.in = undefined;
            var addr_len: u32 = @sizeOf(linux.sockaddr.in);
            const accept_rc = linux.accept4(sockfd, @ptrCast(&client_addr), &addr_len, SOCK_CLOEXEC);
            const signed: isize = @bitCast(accept_rc);
            if (signed < 0) {
                std.log.err("accept failed", .{});
                continue;
            }
            const conn_fd: i32 = @intCast(accept_rc);
            handleHttpClientFd(&app, allocator, conn_fd) catch |e| {
                std.log.err("http client error: {s}", .{@errorName(e)});
            };
        }
    } else {
        std.log.info("janusd (UTCP bootstrap) listening on {s}:{d}", .{ host, port });
        while (true) {
            var client_addr: linux.sockaddr.in = undefined;
            var addr_len: u32 = @sizeOf(linux.sockaddr.in);
            const accept_rc = linux.accept4(sockfd, @ptrCast(&client_addr), &addr_len, SOCK_CLOEXEC);
            const signed: isize = @bitCast(accept_rc);
            if (signed < 0) {
                std.log.err("accept failed", .{});
                continue;
            }
            const conn_fd: i32 = @intCast(accept_rc);
            std.log.info("client connected", .{});
            handleClientFd(allocator, conn_fd) catch |e| {
                std.log.err("client error: {s}", .{@errorName(e)});
            };
        }
    }
}

const App = struct {
    allocator: std.mem.Allocator,
    registry: utcp.Registry,
    epoch_id: u64,
    // cluster (optional)
    cluster_enabled: bool,
    leader: ?cl.RegistryNode = null,
    followers: std.ArrayList(cl.RegistryNode),
    follower_ptrs: ?[](*cl.RegistryNode) = null,
    repl_ctx: ?*anyopaque = null,
    replicator: ?cl.Replicator = null,
    lease_containers: std.ArrayList(*LeaseContainer),

    pub fn init(alloc: std.mem.Allocator, key: [32]u8, cluster_enabled: bool) !App {
        const reg = utcp.Registry.init(alloc, key);
        const followers = std.ArrayList(cl.RegistryNode){};
        var app = App{
            .allocator = alloc,
            .registry = reg,
            .epoch_id = 1,
            .cluster_enabled = cluster_enabled,
            .leader = null,
            .followers = followers,
            .repl_ctx = null,
            .replicator = null,
            .lease_containers = std.ArrayList(*LeaseContainer){},
        };
        if (cluster_enabled) try app.enableCluster();
        return app;
    }

    fn enableCluster(self: *App) !void {
        // 3-node in-process cluster (leader + 2 followers)
        const leader = try cl.RegistryNode.init(self.allocator, 1);
        self.leader = leader;
        const leader_ptr = if (self.leader) |*lp| lp else unreachable;
        try self.followers.append(self.allocator, try cl.RegistryNode.init(self.allocator, 2));
        try self.followers.append(self.allocator, try cl.RegistryNode.init(self.allocator, 3));

        // stash followers array pointer into a small context struct
        const Ctx = struct { leader: *cl.RegistryNode, followers: [](*cl.RegistryNode) };
        const ctx = try self.allocator.create(Ctx);
        // Build stable array of follower pointers for ctx
        const ptrs = try self.allocator.alloc(*cl.RegistryNode, self.followers.items.len);
        for (self.followers.items, 0..) |*node, i| ptrs[i] = node;
        self.follower_ptrs = ptrs;
        ctx.* = .{ .leader = leader_ptr, .followers = ptrs };
        self.repl_ctx = @ptrCast(ctx);
        self.replicator = cl.Replicator{
            .ctx = self.repl_ctx.?,
            .call = struct {
                fn call(ctx_any: *anyopaque, op: []const u8) anyerror!bool {
                    const c: *Ctx = @ptrCast(@alignCast(ctx_any));
                    return try cl.syncCluster(c.leader, c.followers, op);
                }
            }.call,
        };
        if (self.replicator) |rep| self.registry.attachReplicator(rep);
    }

    pub fn deinit(self: *App) void {
        if (self.leader) |*l| l.deinit();
        if (self.follower_ptrs) |p| self.allocator.free(p);
        for (self.followers.items) |*f| f.deinit();
        self.followers.deinit(self.allocator);
        for (self.lease_containers.items) |container| {
            self.allocator.free(container.name);
            self.allocator.destroy(container);
        }
        self.lease_containers.deinit(self.allocator);
        self.registry.deinit();
    }
};

fn handleClientFd(allocator: std.mem.Allocator, fd: std.posix.fd_t) !void {
    defer _ = std.os.linux.close(fd);
    const writer = SocketWriter{ .fd = fd };

    while (true) {
        var line = std.ArrayList(u8){};
        defer line.deinit(allocator);
        readLine(fd, allocator, &line) catch |e| switch (e) {
            error.EndOfStream => break,
            else => return e,
        };

        const payload = std.mem.trim(u8, line.items, " \t\r\n");
        if (payload.len == 0) continue;

        // Parse JSON
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, payload, .{});
        defer parsed.deinit();
        const root = parsed.value;

        const op = root.object.get("op") orelse return sendError(writer, "E1400_BAD_REQUEST", "missing op", null, null, null);
        if (op != .string) return sendError(writer, "E1400_BAD_REQUEST", "op must be string", null, null, null);

        if (std.mem.eql(u8, op.string, "manual")) {
            try sendManual(writer, allocator);
            continue;
        }

        if (std.mem.eql(u8, op.string, "call")) {
            const tool_v = root.object.get("tool") orelse return sendError(writer, "E1400_BAD_REQUEST", "missing tool", null, null, null);
            if (tool_v != .string) return sendError(writer, "E1400_BAD_REQUEST", "tool must be string", null, null, null);
            const caps_v = root.object.get("caps") orelse return sendError(writer, "E1400_BAD_REQUEST", "missing caps", null, null, null);
            if (caps_v != .array) return sendError(writer, "E1400_BAD_REQUEST", "caps must be array", null, null, null);

            var presented = std.StringHashMap(void).init(allocator);
            defer presented.deinit();
            for (caps_v.array.items) |item| {
                if (item != .string) return sendError(writer, "E1400_BAD_REQUEST", "caps items must be string", null, null, null);
                try presented.put(item.string, {});
            }

            const tool_name = tool_v.string;
            var missing = std.ArrayList([]const u8){};
            defer missing.deinit(allocator);
            try computeMissingCaps(allocator, tool_name, &presented, &missing);
            if (missing.items.len > 0) {
                try sendCapMismatch(writer, tool_name, missing.items, presented.count());
                continue;
            }

            // TODO: Route to actual tool implementation via libjanus
            try sendOk(writer, .{ .message = "executed (stub)" });
            continue;
        }

        try sendError(writer, "E1400_BAD_REQUEST", "unknown op", null, null, null);
    }
}

fn sendManual(writer: anytype, allocator: std.mem.Allocator) !void {
    _ = allocator; // currently unused
    try writer.writeAll("{\"ok\":true,\"result\":");
    try manual.writeManualJSON(writer, .{ .include_hinge_resolve = false });
    try writer.writeAll("}\n");
}

// ================= HTTP server & router (MVP) =================

fn handleHttpClientFd(app: *App, allocator: std.mem.Allocator, fd: std.posix.fd_t) !void {
    defer _ = std.os.linux.close(fd);
    const writer = SocketWriter{ .fd = fd };

    // Read headers
    var header_buf = std.ArrayList(u8){};
    defer header_buf.deinit(allocator);
    try readUntilDoubleCrlf(fd, allocator, &header_buf);

    var method: []const u8 = undefined;
    var path: []const u8 = undefined;
    var version: []const u8 = undefined;
    var content_length: usize = 0;
    var content_type: []const u8 = "";
    var authorization: []const u8 = "";
    try parseRequestLineAndHeaders(header_buf.items, &method, &path, &version, &content_length, &content_type, &authorization);

    // Read body if any
    const body = try allocator.alloc(u8, content_length);
    defer allocator.free(body);
    if (content_length > 0) {
        try readExact(fd, body);
    }

    // Route
    try routeHttp(app, method, path, content_type, authorization, body, writer, allocator, auth.envResolver());
}

fn readUntilDoubleCrlf(fd: std.posix.fd_t, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    var matched: u8 = 0;
    var byte_buf: [1]u8 = undefined;
    while (true) {
        const len = try readInto(fd, byte_buf[0..1]);
        if (len == 0) return error.EndOfStream;
        const byte = byte_buf[0];
        try out.append(allocator, byte);
        // Track sequence: \r\n\r\n
        const expected: u8 = if (matched == 0)
            '\r'
        else if (matched == 1)
            '\n'
        else if (matched == 2)
            '\r'
        else if (matched == 3)
            '\n'
        else
            0;
        if (byte == expected) {
            matched += 1;
            if (matched == 4) return; // end of headers
        } else if (byte == '\r') {
            matched = 1;
        } else {
            matched = 0;
        }
    }
}

fn readLine(fd: std.posix.fd_t, allocator: std.mem.Allocator, out: *std.ArrayList(u8)) !void {
    var byte_buf: [1]u8 = undefined;
    while (true) {
        const len = try readInto(fd, byte_buf[0..1]);
        if (len == 0) return error.EndOfStream;
        const byte = byte_buf[0];
        try out.append(allocator, byte);
        if (byte == '\n') break;
    }
}

fn readExact(fd: std.posix.fd_t, buffer: []u8) !void {
    var offset: usize = 0;
    while (offset < buffer.len) {
        const read_len = try readInto(fd, buffer[offset..]);
        if (read_len == 0) return error.EndOfStream;
        offset += read_len;
    }
}

fn readInto(fd: std.posix.fd_t, buffer: []u8) !usize {
    // std.posix.read removed in Zig 0.16 — use linux syscall
    const rc = std.os.linux.read(fd, buffer.ptr, buffer.len);
    if (@as(isize, @bitCast(rc)) < 0) return error.ReadFailed;
    return rc;
}

fn parseRequestLineAndHeaders(
    header_bytes: []const u8,
    out_method: *[]const u8,
    out_path: *[]const u8,
    out_version: *[]const u8,
    out_content_length: *usize,
    out_content_type: *[]const u8,
    out_authorization: *[]const u8,
) !void {
    var it = std.mem.tokenizeScalar(u8, header_bytes, '\n');
    if (it.next()) |line0| {
        const line = std.mem.trim(u8, line0, " \t\r");
        var sp = std.mem.tokenizeAny(u8, line, " \t");
        out_method.* = sp.next() orelse return error.BadRequest;
        out_path.* = sp.next() orelse return error.BadRequest;
        out_version.* = sp.next() orelse return error.BadRequest;
    } else return error.BadRequest;

    var content_length: usize = 0;
    var content_type: []const u8 = "";
    var authorization: []const u8 = "";
    while (it.next()) |raw| {
        const l = std.mem.trim(u8, raw, " \t\r");
        if (l.len == 0) break;
        if (std.ascii.startsWithIgnoreCase(l, "Content-Length:")) {
            const v = std.mem.trim(u8, l["Content-Length:".len..], " \t");
            content_length = std.fmt.parseInt(usize, v, 10) catch 0;
        } else if (std.ascii.startsWithIgnoreCase(l, "Content-Type:")) {
            const v2 = std.mem.trim(u8, l["Content-Type:".len..], " \t");
            content_type = v2;
        } else if (std.ascii.startsWithIgnoreCase(l, "Authorization:")) {
            const v3 = std.mem.trim(u8, l["Authorization:".len..], " \t");
            authorization = v3;
        }
    }
    out_content_length.* = content_length;
    out_content_type.* = content_type;
    out_authorization.* = authorization;
}

/// Fixed-buffer writer providing print/writeAll for HTTP body construction.
const BufWriter = struct {
    buf: []u8,
    pos: usize = 0,

    pub fn print(self: *BufWriter, comptime fmt: []const u8, args: anytype) !void {
        const result = std.fmt.bufPrint(self.buf[self.pos..], fmt, args) catch return error.NoSpaceLeft;
        self.pos += result.len;
    }

    pub fn writeAll(self: *BufWriter, data: []const u8) !void {
        if (self.pos + data.len > self.buf.len) return error.NoSpaceLeft;
        @memcpy(self.buf[self.pos..][0..data.len], data);
        self.pos += data.len;
    }

    pub fn getWritten(self: *const BufWriter) []const u8 {
        return self.buf[0..self.pos];
    }
};

fn writeHttpJson(writer: anytype, status_code: u16, status_text: []const u8, body_writer_fn: anytype) !void {
    var body_buf_storage: [65536]u8 = undefined;
    var buf_writer = BufWriter{ .buf = &body_buf_storage };
    const Body = @TypeOf(body_writer_fn);
    const info = @typeInfo(Body);
    if (info == .@"fn") {
        try body_writer_fn(&buf_writer);
    } else if (info == .pointer and @hasDecl(info.pointer.child, "write")) {
        try body_writer_fn.*.write(&buf_writer);
    } else if (@hasDecl(Body, "write")) {
        try body_writer_fn.write(&buf_writer);
    } else {
        @compileError("body_writer_fn must be function or type with write method");
    }
    const body = buf_writer.getWritten();
    try writer.print("HTTP/1.1 {d} {s}\r\n", .{ status_code, status_text });
    try writer.print("Content-Type: application/json\r\n", .{});
    try writer.print("Content-Length: {d}\r\n", .{body.len});
    try writer.print("Connection: close\r\n\r\n", .{});
    try writer.writeAll(body);
}

fn routeHttp(
    app: *App,
    method: []const u8,
    path: []const u8,
    content_type: []const u8,
    authorization: []const u8,
    body: []const u8,
    writer: anytype,
    allocator: std.mem.Allocator,
    resolver: auth.TokenResolver,
) !void {
    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/utcp")) {
        try writeHttpJson(writer, 200, "OK", struct {
            fn write(w: anytype) !void {
                try manual.writeManualJSON(w, .{ .include_hinge_resolve = false });
            }
        }.write);
        return;
    }

    // Registry endpoints (MVP)
    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/registry/state")) {
        const doc = try app.registry.buildManual(app.allocator);
        defer app.allocator.free(doc);
        try writer.print("HTTP/1.1 {d} {s}\r\n", .{ 200, "OK" });
        try writer.print("Content-Type: application/json\r\n", .{});
        try writer.print("Content-Length: {d}\r\n", .{doc.len});
        try writer.print("Connection: close\r\n\r\n", .{});
        try writer.writeAll(doc);
        return;
    }

    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/registry/tokens")) {
        try writeHttpJson(writer, 200, "OK", struct {
            fn write(w: anytype) !void {
                try w.writeAll("{\"lease_tokens\":{");
                try w.writeAll("\"register\":\"registry.lease.register:<group>\",");
                try w.writeAll("\"heartbeat\":\"registry.lease.heartbeat:<group>\"}");
                try w.writeAll("}");
            }
        }.write);
        return;
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/registry/lease.register")) {
        if (content_type.len == 0 or std.mem.indexOf(u8, content_type, "application/json") == null) {
            try writeHttpJson(writer, 415, "Unsupported Media Type", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Content-Type must be application/json");
                }
            }.write);
            return;
        }
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        const root = parsed.value;
        const group = root.object.get("group") orelse return writeBadReq(writer, "missing group");
        const name = root.object.get("name") orelse return writeBadReq(writer, "missing name");
        const ttlv = root.object.get("ttl_seconds") orelse return writeBadReq(writer, "missing ttl_seconds");
        if (group != .string or name != .string or ttlv != .integer) return writeBadReq(writer, "invalid fields");

        // Client gating: require lease.register:<group>
        const tok_reg = auth.parseBearerAuthorization(authorization);
        if (tok_reg == null) {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            return;
        }
        var principal_reg = resolver.resolveFn(resolver.ctx, tok_reg.?, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            return;
        };
        defer principal_reg.deinit(allocator);
        const req_reg = try std.fmt.allocPrint(allocator, "registry.lease.register:{s}", .{group.string});
        defer allocator.free(req_reg);
        const miss_reg = caps.computeMissing(allocator, principal_reg.capabilities, &.{req_reg}) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Capability evaluation failed");
                }
            }.write);
            return;
        };
        defer allocator.free(miss_reg);
        if (miss_reg.len != 0) {
            const st = errors.statusFor(.AuthorizationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Missing capability: registry.lease.register:<group>");
                }
            }.write);
            return;
        }

        const container = try allocator.create(LeaseContainer);
        var container_guard = true;
        defer if (container_guard) allocator.destroy(container);
        container.name = try allocator.dupe(u8, name.string);
        var name_guard = true;
        defer if (name_guard) allocator.free(container.name);
        app.lease_containers.append(allocator, container) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Lease allocation failed");
                }
            }.write);
            return;
        };
        var appended_guard = true;
        defer if (appended_guard) {
            _ = app.lease_containers.pop();
        };
        try app.registry.registerLease(group.string, name.string, container, utcp.makeManualAdapter(LeaseContainer), @intCast(ttlv.integer), .{});
        container_guard = false;
        name_guard = false;
        appended_guard = false;
        try writeHttpJson(writer, 200, "OK", struct {
            fn write(w: anytype) !void {
                try w.writeAll("{\"ok\":true}");
            }
        }.write);
        return;
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/registry/lease.heartbeat")) {
        if (content_type.len == 0 or std.mem.indexOf(u8, content_type, "application/json") == null) {
            try writeHttpJson(writer, 415, "Unsupported Media Type", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Content-Type must be application/json");
                }
            }.write);
            return;
        }
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        const root = parsed.value;
        const group = root.object.get("group") orelse return writeBadReq(writer, "missing group");
        const name = root.object.get("name") orelse return writeBadReq(writer, "missing name");
        const ttlv = root.object.get("ttl_seconds") orelse return writeBadReq(writer, "missing ttl_seconds");
        if (group != .string or name != .string or ttlv != .integer) return writeBadReq(writer, "invalid fields");
        // Client gating: require lease.heartbeat:<group>
        const tok_hb = auth.parseBearerAuthorization(authorization);
        if (tok_hb == null) {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            return;
        }
        var principal_hb = resolver.resolveFn(resolver.ctx, tok_hb.?, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            return;
        };
        defer principal_hb.deinit(allocator);
        const req_hb = try std.fmt.allocPrint(allocator, "registry.lease.heartbeat:{s}", .{group.string});
        defer allocator.free(req_hb);
        const miss_hb = caps.computeMissing(allocator, principal_hb.capabilities, &.{req_hb}) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Capability evaluation failed");
                }
            }.write);
            return;
        };
        defer allocator.free(miss_hb);
        if (miss_hb.len != 0) {
            const st = errors.statusFor(.AuthorizationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Missing capability: registry.lease.heartbeat:<group>");
                }
            }.write);
            return;
        }

        const ok = try app.registry.heartbeat(group.string, name.string, @intCast(ttlv.integer), .{});
        if (!ok) {
            try writeHttpJson(writer, 409, "Conflict", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Lease signature invalid");
                }
            }.write);
        } else {
            try writeHttpJson(writer, 200, "OK", struct {
                fn write(w: anytype) !void {
                    try w.writeAll("{\"ok\":true}");
                }
            }.write);
        }
        return;
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/registry/rotate")) {
        if (content_type.len == 0 or std.mem.indexOf(u8, content_type, "application/json") == null) {
            try writeHttpJson(writer, 415, "Unsupported Media Type", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Content-Type must be application/json");
                }
            }.write);
            return;
        }
        // Admin auth: require registry.admin:*
        const token_opt = auth.parseBearerAuthorization(authorization);
        if (token_opt == null) {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            return;
        }
        var principal = resolver.resolveFn(resolver.ctx, token_opt.?, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            return;
        };
        defer principal.deinit(allocator);
        const missing = caps.computeMissing(allocator, principal.capabilities, &.{"registry.admin:*"}) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Capability evaluation failed");
                }
            }.write);
            return;
        };
        defer allocator.free(missing);
        if (missing.len != 0) {
            const st = errors.statusFor(.AuthorizationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Missing capability: registry.admin:*");
                }
            }.write);
            return;
        }
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        const root = parsed.value;
        const key_hex = root.object.get("key_hex") orelse return writeBadReq(writer, "missing key_hex");
        if (key_hex != .string) return writeBadReq(writer, "key_hex must be string");
        var key: [32]u8 = undefined;
        if (hexTo32(key_hex.string, &key)) {
            app.epoch_id += 1;
            app.registry.rotateKey(.{ .key = key, .id = app.epoch_id });
            try writeHttpJson(writer, 200, "OK", struct {
                fn write(w: anytype) !void {
                    try w.writeAll("{\"ok\":true}");
                }
            }.write);
        } else {
            try writeHttpJson(writer, 400, "Bad Request", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "invalid key_hex");
                }
            }.write);
        }
        return;
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.eql(u8, path, "/registry/quota.set")) {
        if (content_type.len == 0 or std.mem.indexOf(u8, content_type, "application/json") == null) {
            try writeHttpJson(writer, 415, "Unsupported Media Type", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Content-Type must be application/json");
                }
            }.write);
            return;
        }
        // Admin auth: require registry.admin:*
        const token_opt2 = auth.parseBearerAuthorization(authorization);
        if (token_opt2 == null) {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            return;
        }
        var principal2 = resolver.resolveFn(resolver.ctx, token_opt2.?, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            return;
        };
        defer principal2.deinit(allocator);
        const missing2 = caps.computeMissing(allocator, principal2.capabilities, &.{"registry.admin:*"}) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Capability evaluation failed");
                }
            }.write);
            return;
        };
        defer allocator.free(missing2);
        if (missing2.len != 0) {
            const st = errors.statusFor(.AuthorizationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Missing capability: registry.admin:*");
                }
            }.write);
            return;
        }
        var parsed = try std.json.parseFromSlice(std.json.Value, allocator, body, .{});
        defer parsed.deinit();
        const root = parsed.value;
        const maxv = root.object.get("max_entries_per_group") orelse return writeBadReq(writer, "missing max_entries_per_group");
        if (maxv != .integer or maxv.integer < 0) return writeBadReq(writer, "max_entries_per_group must be non-negative integer");
        app.registry.setNamespaceQuota(@intCast(maxv.integer));
        try writeHttpJson(writer, 200, "OK", struct {
            fn write(w: anytype) !void {
                try w.writeAll("{\"ok\":true}");
            }
        }.write);
        return;
    }

    if (std.mem.eql(u8, method, "GET") and std.mem.eql(u8, path, "/registry/quota")) {
        // Admin auth: require registry.admin:*
        const token_opt3 = auth.parseBearerAuthorization(authorization);
        if (token_opt3 == null) {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            return;
        }
        var principal3 = resolver.resolveFn(resolver.ctx, token_opt3.?, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            return;
        };
        defer principal3.deinit(allocator);
        const missing3 = caps.computeMissing(allocator, principal3.capabilities, &.{"registry.admin:*"}) catch {
            const st = errors.statusFor(.ToolCallError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ToolCallError, "Capability evaluation failed");
                }
            }.write);
            return;
        };
        defer allocator.free(missing3);
        if (missing3.len != 0) {
            const st = errors.statusFor(.AuthorizationError);
            try writeHttpJson(writer, st.code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthorizationError, "Missing capability: registry.admin:*");
                }
            }.write);
            return;
        }
        try writeHttpJson(writer, 200, "OK", struct {
            app: *App,
            fn write(self: @This(), w: anytype) !void {
                try json_helpers.writeMinified(w, .{ .max_entries_per_group = self.app.registry.max_entries_per_group });
            }
        }{ .app = app });
        return;
    }

    if (std.mem.eql(u8, method, "POST") and std.mem.startsWith(u8, path, "/tools/")) {
        const start_ns = compat_time.nanoTimestamp();
        var status_code: u16 = 200;
        const tool_name: []const u8 = path["/tools/".len..];
        const finalize = struct {
            fn done(tool: []const u8, code: u16, start: i128) void {
                const now = compat_time.nanoTimestamp();
                const dur = now - start;
                const dur_ns = if (dur <= 0)
                    0
                else
                    @as(u64, @intCast(dur));
                metrics.record(metrics.toolFromName(tool), code, dur_ns);
                const ms: f64 = @as(f64, @floatFromInt(dur_ns)) / @as(f64, std.time.ns_per_ms);
                std.log.info("tool_call tool={s} status={d} dur_ms={d:.2} principal=redacted", .{ tool, code, ms });
            }
        }.done;
        // content type check
        if (content_type.len == 0 or std.mem.indexOf(u8, content_type, "application/json") == null) {
            status_code = 415;
            try writeHttpJson(writer, status_code, "Unsupported Media Type", struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Content-Type must be application/json");
                }
            }.write);
            finalize(tool_name, status_code, start_ns);
            return;
        }

        // Bearer auth
        const token_opt = auth.parseBearerAuthorization(authorization);
        if (token_opt == null) {
            const st = errors.statusFor(.AuthenticationError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Missing or invalid bearer token");
                }
            }.write);
            finalize(tool_name, status_code, start_ns);
            return;
        }
        const token = token_opt.?;
        var principal = resolver.resolveFn(resolver.ctx, token, allocator) catch {
            const st = errors.statusFor(.AuthenticationError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .AuthenticationError, "Unknown or invalid token");
                }
            }.write);
            finalize(tool_name, status_code, start_ns);
            return;
        };
        defer principal.deinit(allocator);

        const tool = path["/tools/".len..];
        if (!isKnownTool(tool)) {
            const st = errors.statusFor(.ToolNotFoundError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                tool: []const u8,
                fn write(self: @This(), w: anytype) !void {
                    try errors.writeErrorWithDetails(w, .ToolNotFoundError, "Unknown tool", .{ .tool = self.tool });
                }
            }{ .tool = tool });
            finalize(tool, status_code, start_ns);
            return;
        }

        // Capability enforcement (exact match MVP)
        const required = requiredCapsForTool(tool);
        const missing_caps = try caps.computeMissing(allocator, principal.capabilities, required);
        defer allocator.free(missing_caps);
        if (missing_caps.len > 0) {
            const st = errors.statusFor(.AuthorizationError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                missing: []const []const u8,
                fn write(self: @This(), w: anytype) !void {
                    try errors.writeErrorWithDetails(w, .AuthorizationError, "UTCP capability mismatch", .{ .missing = self.missing });
                }
            }{ .missing = missing_caps });
            finalize(tool, status_code, start_ns);
            return;
        }

        // Parse JSON body and validate against schema
        var parsed = std.json.parseFromSlice(std.json.Value, allocator, body, .{}) catch {
            const st = errors.statusFor(.ValidationError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                fn write(w: anytype) !void {
                    try errors.writeError(w, .ValidationError, "Invalid JSON");
                }
            }.write);
            finalize(tool, status_code, start_ns);
            return;
        };
        defer parsed.deinit();

        var issues = std.ArrayList(validator.Issue){};
        defer {
            for (issues.items) |it| {
                allocator.free(it.path);
                allocator.free(it.message);
            }
            issues.deinit(allocator);
        }
        try validator.validateToolInput(allocator, tool, parsed.value, &issues);
        if (issues.items.len > 0) {
            const st = errors.statusFor(.ValidationError);
            status_code = st.code;
            try writeHttpJson(writer, status_code, st.text, struct {
                issues: []const validator.Issue,
                fn write(self: @This(), w: anytype) !void {
                    try errors.writeErrorWithDetails(w, .ValidationError, "Input schema mismatch", .{ .issues = self.issues });
                }
            }{ .issues = issues.items });
            finalize(tool, status_code, start_ns);
            return;
        }

        // Dispatch to tool adapters
        status_code = 200;
        try writeHttpJson(writer, status_code, "OK", struct {
            tool: []const u8,
            parsed: std.json.Value,
            allocator: std.mem.Allocator,
            fn write(self: @This(), w: anytype) !void {
                try w.writeAll("{\"ok\":true,\"result\":");
                if (std.mem.eql(u8, self.tool, "compile")) {
                    try adapters.compileAdapter(self.parsed, self.allocator, w);
                } else if (std.mem.eql(u8, self.tool, "query_ast")) {
                    try adapters.queryAstAdapter(self.parsed, self.allocator, w);
                } else if (std.mem.eql(u8, self.tool, "diagnostics.list")) {
                    try adapters.diagnosticsListAdapter(self.parsed, self.allocator, w);
                } else {
                    try json_helpers.writeMinified(w, .{ .tool = self.tool, .status = "ok" });
                }
                try w.writeAll("}");
            }
        }{ .tool = tool, .parsed = parsed.value, .allocator = allocator });
        finalize(tool, status_code, start_ns);
        return;
    }

    const st = errors.statusFor(.ToolNotFoundError);
    try writeHttpJson(writer, st.code, st.text, struct {
        fn write(w: anytype) !void {
            try errors.writeError(w, .ToolNotFoundError, "Unknown path");
        }
    }.write);
}

fn isKnownTool(name: []const u8) bool {
    return std.mem.eql(u8, name, "compile") or std.mem.eql(u8, name, "query_ast") or std.mem.eql(u8, name, "diagnostics.list");
}

fn requiredCapsForTool(name: []const u8) []const []const u8 {
    if (std.mem.eql(u8, name, "compile")) {
        return &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" };
    }
    // query_ast, diagnostics.list require no capabilities for MVP
    return &.{};
}

// Test-only helper to route without network
fn test_route_with_app(
    app: *App,
    method: []const u8,
    path: []const u8,
    content_type: []const u8,
    authorization: []const u8,
    body: []const u8,
    allocator: std.mem.Allocator,
    resolver: auth.TokenResolver,
) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try routeHttp(app, method, path, content_type, authorization, body, buf.writer(allocator), allocator, resolver);
    return try buf.toOwnedSlice(allocator);
}

pub fn test_route_response(method: []const u8, path: []const u8, content_type: ?[]const u8, body: []const u8, allocator: std.mem.Allocator) ![]u8 {
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);
    var app = try App.init(allocator, key, false);
    defer app.deinit();
    return try test_route_with_app(&app, method, path, content_type orelse "", "", body, allocator, auth.envResolver());
}

pub fn test_route_response_with_resolver(method: []const u8, path: []const u8, content_type: ?[]const u8, authorization: ?[]const u8, body: []const u8, resolver: auth.TokenResolver, allocator: std.mem.Allocator) ![]u8 {
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);
    var app = try App.init(allocator, key, false);
    defer app.deinit();
    return try test_route_with_app(&app, method, path, content_type orelse "", authorization orelse "", body, allocator, resolver);
}

test "HTTP GET /utcp returns JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const resp = try test_route_response("GET", "/utcp", null, "", allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "Content-Type: application/json") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"manual_version\"") != null);
    // New registry tools are exposed in the manual
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.lease.register") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.lease.heartbeat") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.state") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.tokens") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.quota.get") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.quota.set") != null);
    try std.testing.expect(std.mem.indexOf(u8, resp, "registry.rotate") != null);
}

// ---- Helpers ----
fn writeBadReq(writer: anytype, msg: []const u8) !void {
    try writeHttpJson(writer, 400, "Bad Request", struct {
        message: []const u8,
        fn write(self: @This(), w: anytype) !void {
            try errors.writeError(w, .ValidationError, self.message);
        }
    }{ .message = msg });
}

fn hexTo32(hex: []const u8, out: *[32]u8) bool {
    if (hex.len != 64) return false;
    var i: usize = 0;
    while (i < 32) : (i += 1) {
        const hi = std.fmt.charToDigit(hex[i * 2], 16) catch return false;
        const lo = std.fmt.charToDigit(hex[i * 2 + 1], 16) catch return false;
        out.*[i] = @as(u8, @intCast(hi * 16 + lo));
    }
    return true;
}

test "HTTP POST /tools/unknown returns 404 ToolNotFoundError" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token" };
    const resp = try test_route_response_with_resolver("POST", "/tools/unknown", "application/json", "Bearer secret-token", "{}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 404 Not Found"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"ToolNotFoundError\"") != null);
}

test "HTTP POST /tools/compile wrong content type returns 415" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    const resp = try test_route_response("POST", "/tools/compile", "text/plain", "{}", allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 415 Unsupported Media Type"));
}

test "HTTP POST /tools/compile missing auth returns 401" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var resolver = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{} };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", null, "{}", resolver.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 401 Unauthorized"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"AuthenticationError\"") != null);
}

test "HTTP POST /tools/compile invalid token returns 401" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var resolver = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{} };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", null, "{}", resolver.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 401 Unauthorized"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"AuthenticationError\"") != null);
}

test "HTTP POST /tools/compile valid token returns 200" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", "Bearer secret-token", "{\"source_file\":\"main.jan\"}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
}

test "HTTP POST /tools/compile insufficient capabilities returns 403" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{} };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", "Bearer secret-token", "{\"source_file\":\"a\"}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 403 Forbidden"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"AuthorizationError\"") != null);
}

test "HTTP POST /tools/compile with required capabilities returns 200" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", "Bearer secret-token", "{\"source_file\":\"a\"}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
}

test "HTTP GET /registry/quota missing auth returns 401" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    const resp = try test_route_response("GET", "/registry/quota", null, "", A);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 401 Unauthorized"));
}

test "HTTP GET /registry/quota insufficient caps returns 403" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{} };
    const resp = try test_route_response_with_resolver("GET", "/registry/quota", null, "Bearer t", "", mem.asResolver(), A);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 403 Forbidden"));
}

test "HTTP GET /registry/quota with admin caps returns 200" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.admin:*"} };
    const resp = try test_route_response_with_resolver("GET", "/registry/quota", null, "Bearer t", "", mem.asResolver(), A);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    // Parse JSON body
    const split = std.mem.indexOf(u8, resp, "\r\n\r\n").? + 4;
    const body = resp[split..];
    var parsed = try std.json.parseFromSlice(std.json.Value, A, body, .{});
    defer parsed.deinit();
    const root = parsed.value;
    try std.testing.expect(root == .object);
    const mev = root.object.get("max_entries_per_group");
    try std.testing.expect(mev != null);
}

test "HTTP POST /registry/quota.set updates quota (admin)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);
    var app = try App.init(A, key, false);
    defer app.deinit();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.admin:*"} };
    const resolver = mem.asResolver();
    const body = "{\"max_entries_per_group\":2}";
    const resp = try test_route_with_app(&app, "POST", "/registry/quota.set", "application/json", "Bearer t", body, A, resolver);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    const resp2 = try test_route_with_app(&app, "GET", "/registry/quota", "", "Bearer t", "", A, resolver);
    defer A.free(resp2);
    try std.testing.expect(std.mem.startsWith(u8, resp2, "HTTP/1.1 200 OK"));
    const split2 = std.mem.indexOf(u8, resp2, "\r\n\r\n").? + 4;
    const body2 = resp2[split2..];
    var parsed2 = try std.json.parseFromSlice(std.json.Value, A, body2, .{});
    defer parsed2.deinit();
    const root2 = parsed2.value;
    const mev2 = root2.object.get("max_entries_per_group").?.integer;
    try std.testing.expectEqual(@as(i128, 2), mev2);
}

test "lease.register requires capability per-group" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    // Missing auth
    const body = "{\"group\":\"G\",\"name\":\"N\",\"ttl_seconds\":5}";
    const no_auth = try test_route_response("POST", "/registry/lease.register", "application/json", body, A);
    defer A.free(no_auth);
    try std.testing.expect(std.mem.startsWith(u8, no_auth, "HTTP/1.1 401 Unauthorized"));
    // Wrong caps
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{} };
    const bad = try test_route_response_with_resolver("POST", "/registry/lease.register", "application/json", "Bearer t", body, mem.asResolver(), A);
    defer A.free(bad);
    try std.testing.expect(std.mem.startsWith(u8, bad, "HTTP/1.1 403 Forbidden"));
    // Correct cap
    var mem_ok = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.lease.register:G"} };
    const ok = try test_route_response_with_resolver("POST", "/registry/lease.register", "application/json", "Bearer t", body, mem_ok.asResolver(), A);
    defer A.free(ok);
    try std.testing.expect(std.mem.startsWith(u8, ok, "HTTP/1.1 200 OK"));
}

test "lease.heartbeat requires capability per-group" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var key: [32]u8 = undefined;
    std.crypto.random.bytes(&key);
    var app = try App.init(A, key, false);
    defer app.deinit();
    // Prepare: register with admin-like resolver that has both register + heartbeat caps
    var mem_ok = auth.InMemoryResolver{ .token = "t", .capabilities = &.{ "registry.lease.register:G", "registry.lease.heartbeat:G" } };
    const resolver_ok = mem_ok.asResolver();
    const body_reg = "{\"group\":\"G\",\"name\":\"N\",\"ttl_seconds\":1}";
    const r = try test_route_with_app(&app, "POST", "/registry/lease.register", "application/json", "Bearer t", body_reg, A, resolver_ok);
    defer A.free(r);
    try std.testing.expect(std.mem.startsWith(u8, r, "HTTP/1.1 200 OK"));
    const body_hb = "{\"group\":\"G\",\"name\":\"N\",\"ttl_seconds\":2}";
    // Missing auth
    const no_auth = try test_route_with_app(&app, "POST", "/registry/lease.heartbeat", "application/json", "", body_hb, A, resolver_ok);
    defer A.free(no_auth);
    try std.testing.expect(std.mem.startsWith(u8, no_auth, "HTTP/1.1 401 Unauthorized"));
    // Wrong caps
    var mem_bad = auth.InMemoryResolver{ .token = "t2", .capabilities = &.{} };
    const bad = try test_route_with_app(&app, "POST", "/registry/lease.heartbeat", "application/json", "Bearer t2", body_hb, A, mem_bad.asResolver());
    defer A.free(bad);
    try std.testing.expect(std.mem.startsWith(u8, bad, "HTTP/1.1 403 Forbidden"));
    // Correct cap
    const ok = try test_route_with_app(&app, "POST", "/registry/lease.heartbeat", "application/json", "Bearer t", body_hb, A, resolver_ok);
    defer A.free(ok);
    try std.testing.expect(std.mem.startsWith(u8, ok, "HTTP/1.1 200 OK"));
}

test "HTTP POST /registry/rotate with admin returns 200" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.admin:*"} };
    // 64-hex bytes of zeros
    const body = "{\"key_hex\":\"0000000000000000000000000000000000000000000000000000000000000000\"}";
    const resp = try test_route_response_with_resolver("POST", "/registry/rotate", "application/json", "Bearer t", body, mem.asResolver(), A);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
}

test "HTTP POST /registry/rotate invalid key returns 400" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.admin:*"} };
    // invalid hex (not 64 chars)
    const body = "{\"key_hex\":\"abcd\"}";
    const resp = try test_route_response_with_resolver("POST", "/registry/rotate", "application/json", "Bearer t", body, mem.asResolver(), A);
    defer A.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 400 Bad Request"));
}

test "HTTP POST /registry/quota.set invalid payload returns 400" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const A = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{"registry.admin:*"} };
    // missing field
    const resp1 = try test_route_response_with_resolver("POST", "/registry/quota.set", "application/json", "Bearer t", "{}", mem.asResolver(), A);
    defer A.free(resp1);
    try std.testing.expect(std.mem.startsWith(u8, resp1, "HTTP/1.1 400 Bad Request"));
    // wrong type
    const resp2 = try test_route_response_with_resolver("POST", "/registry/quota.set", "application/json", "Bearer t", "{\"max_entries_per_group\":\"oops\"}", mem.asResolver(), A);
    defer A.free(resp2);
    try std.testing.expect(std.mem.startsWith(u8, resp2, "HTTP/1.1 400 Bad Request"));
    // negative value
    const resp3 = try test_route_response_with_resolver("POST", "/registry/quota.set", "application/json", "Bearer t", "{\"max_entries_per_group\":-1}", mem.asResolver(), A);
    defer A.free(resp3);
    try std.testing.expect(std.mem.startsWith(u8, resp3, "HTTP/1.1 400 Bad Request"));
}

test "HTTP POST /tools/query_ast requires no caps and returns 200 with auth" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token" }; // no caps
    const resp = try test_route_response_with_resolver("POST", "/tools/query_ast", "application/json", "Bearer secret-token", "{\"symbol\":\"X\"}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
}

test "HTTP POST /tools/compile missing required field returns 400" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", "Bearer secret-token", "{}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 400 Bad Request"));
    try std.testing.expect(std.mem.indexOf(u8, resp, "\"ValidationError\"") != null);
}

test "HTTP POST /tools/diagnostics.list wrong type returns 400" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "secret-token" };
    const resp = try test_route_response_with_resolver("POST", "/tools/diagnostics.list", "application/json", "Bearer secret-token", "{\"project\":5}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 400 Bad Request"));
}

test "metrics: successful compile increments counters" {
    metrics.reset();
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "t", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try test_route_response_with_resolver("POST", "/tools/compile", "application/json", "Bearer t", "{\"source_file\":\"a\"}", mem.asResolver(), allocator);
    defer allocator.free(resp);
    const snap = metrics.snapshot();
    try std.testing.expect(snap.compile_calls >= 1);
    try std.testing.expect(snap.status_2xx >= 1);
}

fn computeMissingCaps(
    allocator: std.mem.Allocator,
    tool: []const u8,
    presented: *const std.StringHashMap(void),
    out_missing: *std.ArrayList([]const u8),
) !void {
    const req = requiredCapsForTool(tool);
    for (req) |cap| {
        if (!presented.contains(cap)) {
            try out_missing.append(allocator, try allocator.dupe(u8, cap));
        }
    }
}

fn sendCapMismatch(writer: anytype, tool: []const u8, missing: []const []const u8, presented_count: usize) !void {
    const resp = .{
        .ok = false,
        .err = .{
            .code = "E1403_CAP_MISMATCH",
            .message = "UTCP capability mismatch",
            .tool = tool,
            .missing = missing,
            .presented_count = presented_count,
        },
    };
    try json_helpers.writeMinified(writer, resp);
    try writer.writeByte('\n');
}

fn sendError(
    writer: anytype,
    code: []const u8,
    message: []const u8,
    tool_opt: ?[]const u8,
    missing_opt: ?[]const []const u8,
    presented_count_opt: ?usize,
) !void {
    const resp = .{
        .ok = false,
        .err = .{
            .code = code,
            .message = message,
            .tool = tool_opt,
            .missing = missing_opt,
            .presented_count = presented_count_opt,
        },
    };
    try json_helpers.writeMinified(writer, resp);
    try writer.writeByte('\n');
}

fn sendOk(writer: anytype, result: anytype) !void {
    const resp = .{ .ok = true, .result = result };
    try json_helpers.writeMinified(writer, resp);
    try writer.writeByte('\n');
}
