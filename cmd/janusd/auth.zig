// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

pub const Principal = struct {
    id: []const u8,
    capabilities: []const []const u8,

    pub fn deinit(self: *Principal, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        for (self.capabilities) |c| allocator.free(c);
        allocator.free(self.capabilities);
    }
};

pub const ResolveError = error{ UnknownToken, InvalidToken } || std.mem.Allocator.Error;

pub const TokenResolver = struct {
    ctx: ?*anyopaque,
    resolveFn: *const fn (ctx: ?*anyopaque, token: []const u8, allocator: std.mem.Allocator) ResolveError!Principal,
};

/// Default resolver: checks env var JANUS_API_KEY for a single accepted token.
pub fn envResolver() TokenResolver {
    return TokenResolver{
        .ctx = null,
        .resolveFn = struct {
            fn resolve(_: ?*anyopaque, token: []const u8, allocator: std.mem.Allocator) ResolveError!Principal {
                const expect = std.process.getEnvVarOwned(allocator, "JANUS_API_KEY") catch |e| switch (e) {
                    error.EnvironmentVariableNotFound => return error.UnknownToken,
                    error.InvalidWtf8 => return error.InvalidToken,
                    else => return error.InvalidToken,
                };
                defer allocator.free(expect);
                if (!std.mem.eql(u8, expect, token)) return error.UnknownToken;

                const pid = try allocator.dupe(u8, "env:default");
                const caps = try allocator.alloc([]const u8, 0);
                return Principal{ .id = pid, .capabilities = caps };
            }
        }.resolve,
    };
}

/// In-memory resolver for tests or embedding.
pub const InMemoryResolver = struct {
    token: []const u8,
    principal_id: []const u8 = "test:principal",
    capabilities: []const []const u8 = &.{},

    pub fn asResolver(self: *InMemoryResolver) TokenResolver {
        return TokenResolver{
            .ctx = self,
            .resolveFn = struct {
                fn resolve(ctx: ?*anyopaque, token: []const u8, allocator: std.mem.Allocator) ResolveError!Principal {
                    const self_ref: *InMemoryResolver = @ptrCast(@alignCast(ctx.?));
                    if (!std.mem.eql(u8, self_ref.token, token)) return error.UnknownToken;
                    const pid = try allocator.dupe(u8, self_ref.principal_id);
                    var caps = try allocator.alloc([]const u8, self_ref.capabilities.len);
                    for (self_ref.capabilities, 0..) |c, i| caps[i] = try allocator.dupe(u8, c);
                    return Principal{ .id = pid, .capabilities = caps };
                }
            }.resolve,
        };
    }
};

pub fn parseBearerAuthorization(header_value: []const u8) ?[]const u8 {
    // Expect: "Bearer <token>" (case-insensitive scheme per RFC 6750)
    if (header_value.len < 7) return null;
    // Split by spaces
    var it = std.mem.tokenizeAny(u8, header_value, " \t");
    const scheme = it.next() orelse return null;
    if (!std.ascii.eqlIgnoreCase(scheme, "Bearer")) return null;
    const tok = it.next() orelse return null;
    if (tok.len == 0) return null;
    return tok;
}
