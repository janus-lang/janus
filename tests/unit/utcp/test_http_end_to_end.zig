// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

const main = @import("janusd_main");
const auth = main.auth;

fn headerContains(resp: []const u8, s: []const u8) bool {
    return std.mem.indexOf(u8, resp, s) != null;
}

test "e2e: GET /utcp returns manual JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    const resp = try main.test_route_response("GET", "/utcp", null, "", a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    try std.testing.expect(headerContains(resp, "Content-Type: application/json"));
    try std.testing.expect(headerContains(resp, "\"manual_version\""));
}

test "e2e: compile happy path (auth, caps, valid input)" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "tok", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try main.test_route_response_with_resolver(
        "POST", "/tools/compile", "application/json", "Bearer tok",
        "{\"source_file\":\"main.jan\"}", mem.asResolver(), a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 200 OK"));
    try std.testing.expect(headerContains(resp, "\"result\":{"));
    try std.testing.expect(headerContains(resp, "\"tool\":\"compile\""));
}

test "e2e: compile missing capability returns 403" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "tok" }; // no caps
    const resp = try main.test_route_response_with_resolver(
        "POST", "/tools/compile", "application/json", "Bearer tok",
        "{\"source_file\":\"main.jan\"}", mem.asResolver(), a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 403 Forbidden"));
}

test "e2e: wrong content type returns 415" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "tok" };
    const resp = try main.test_route_response_with_resolver(
        "POST", "/tools/compile", "text/plain", "Bearer tok",
        "{\"source_file\":\"main.jan\"}", mem.asResolver(), a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 415 Unsupported Media Type"));
}

test "e2e: invalid json returns 400" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "tok", .capabilities = &.{ "fs.read:${WORKSPACE}", "fs.write:${WORKSPACE}/zig-out" } };
    const resp = try main.test_route_response_with_resolver(
        "POST", "/tools/compile", "application/json", "Bearer tok",
        "{\"source_file\":", mem.asResolver(), a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 400 Bad Request"));
}

test "e2e: unknown tool returns 404" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; defer _ = gpa.deinit();
    const a = gpa.allocator();
    var mem = auth.InMemoryResolver{ .token = "tok" };
    const resp = try main.test_route_response_with_resolver(
        "POST", "/tools/unknown", "application/json", "Bearer tok",
        "{}", mem.asResolver(), a);
    defer a.free(resp);
    try std.testing.expect(std.mem.startsWith(u8, resp, "HTTP/1.1 404 Not Found"));
}
