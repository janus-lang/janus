// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const json_helpers = @import("json_helpers.zig");

pub const Options = struct {
    include_hinge_resolve: bool = false,
    compile_avg_response_size: ?usize = null,
    query_ast_avg_response_size: ?usize = null,
    diagnostics_avg_response_size: ?usize = null,
    hinge_resolve_avg_response_size: ?usize = null,
};

/// Render the UTCP manual JSON to the provided writer.
/// The manual follows the MVP design: HTTP POST tools, bearer auth, and capability declaration.
pub fn writeManualJSON(writer: anytype, opts: Options) !void {
    try writer.writeAll("{");
    try writer.writeAll("\"manual_version\":\"0.1.1\",");
    try writer.writeAll("\"utcp_version\":\"0.1\",");
    try writer.writeAll("\"auth\":{\"auth_type\":\"bearer\"},");
    try writer.writeAll("\"tools\":[");

    // Helper to emit optional average_response_size
    const emit_avg = struct {
        fn write(w: anytype, avg: ?usize) !void {
            if (avg) |v| {
                try w.print(",\"average_response_size\":{d}", .{v});
            }
        }
    }.write;

    // compile
    {
        try writer.writeAll("{");
        try writer.writeAll("\"name\":\"compile\",");
        try writer.writeAll("\"description\":\"Compile a Janus source file\",");
        try writer.writeAll("\"inputs\":{\"type\":\"object\",\"properties\":{\"source_file\":{\"type\":\"string\"},\"output_dir\":{\"type\":\"string\"}},\"required\":[\"source_file\"]},");
        try writer.writeAll("\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/tools/compile\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[\"fs.read:${WORKSPACE}\",\"fs.write:${WORKSPACE}/zig-out\"],\"optional\":[]}");
        try emit_avg(writer, opts.compile_avg_response_size);
        try writer.writeAll("}");
    }

    // query_ast
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"query_ast\",");
        try writer.writeAll("\"description\":\"Query the symbol index / AST\",");
        try writer.writeAll("\"inputs\":{\"type\":\"object\",\"properties\":{\"symbol\":{\"type\":\"string\"}},\"required\":[\"symbol\"]},");
        try writer.writeAll("\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/tools/query_ast\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[],\"optional\":[]}");
        try emit_avg(writer, opts.query_ast_avg_response_size);
        try writer.writeAll("}");
    }

    // diagnostics.list
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"diagnostics.list\",");
        try writer.writeAll("\"description\":\"List diagnostics for a project or current context\",");
        try writer.writeAll("\"inputs\":{\"type\":\"object\",\"properties\":{\"project\":{\"type\":\"string\"}},\"required\":[]},");
        try writer.writeAll("\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/tools/diagnostics.list\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[],\"optional\":[]}");
        try emit_avg(writer, opts.diagnostics_avg_response_size);
        try writer.writeAll("}");
    }

    // registry.lease.register (client-initiated lease registration)
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.lease.register\",");
        try writer.writeAll("\"description\":\"Register or renew a lease for a UTCP entry\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{\"group\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"ttl_seconds\":{\"type\":\"integer\"}},\"required\":[\"group\",\"name\",\"ttl_seconds\"]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/lease.register\",\"http_method\":\"POST\"},");
        // Capability placeholder: `<group>` denotes the lease namespace
        try writer.writeAll(
            "\"x-janus-capabilities\":{\"required\":[\"registry.lease.register:<group>\"],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // registry.lease.heartbeat (client-initiated lease extension)
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.lease.heartbeat\",");
        try writer.writeAll("\"description\":\"Extend a lease via heartbeat for a UTCP entry\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{\"group\":{\"type\":\"string\"},\"name\":{\"type\":\"string\"},\"ttl_seconds\":{\"type\":\"integer\"}},\"required\":[\"group\",\"name\",\"ttl_seconds\"]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/lease.heartbeat\",\"http_method\":\"POST\"},");
        try writer.writeAll(
            "\"x-janus-capabilities\":{\"required\":[\"registry.lease.heartbeat:<group>\"],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // registry.state (cluster-visible UTCP document)
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.state\",");
        try writer.writeAll("\"description\":\"Fetch the current UTCP registry document (read-only)\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{},\"required\":[]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/state\",\"http_method\":\"GET\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // admin: registry.quota.get
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.quota.get\",");
        try writer.writeAll("\"description\":\"Get namespace quota configuration (admin)\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{},\"required\":[]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/quota\",\"http_method\":\"GET\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[\"registry.admin:*\"],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // admin: registry.quota.set
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.quota.set\",");
        try writer.writeAll("\"description\":\"Set namespace quota (admin)\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{\"max_entries_per_group\":{\"type\":\"integer\"}},\"required\":[\"max_entries_per_group\"]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/quota.set\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[\"registry.admin:*\"],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // admin: registry.rotate
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.rotate\",");
        try writer.writeAll("\"description\":\"Rotate epoch key for RSP-1 (admin)\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{\"key_hex\":{\"type\":\"string\"}},\"required\":[\"key_hex\"]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/rotate\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[\"registry.admin:*\"],\"optional\":[]}");
        try writer.writeAll("}");
    }

    // public: registry.tokens (documentation of token model)
    {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"registry.tokens\",");
        try writer.writeAll("\"description\":\"Describe capability tokens for lease operations\",");
        try writer.writeAll(
            "\"inputs\":{\"type\":\"object\",\"properties\":{},\"required\":[]},");
        try writer.writeAll(
            "\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/registry/tokens\",\"http_method\":\"GET\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[],\"optional\":[]}");
        try writer.writeAll("}");
    }

    if (opts.include_hinge_resolve) {
        try writer.writeAll(",{");
        try writer.writeAll("\"name\":\"hinge.resolve\",");
        try writer.writeAll("\"description\":\"Resolve a package from configured registry\",");
        try writer.writeAll("\"inputs\":{\"type\":\"object\",\"properties\":{\"package\":{\"type\":\"string\"},\"version\":{\"type\":\"string\"}},\"required\":[\"package\"]},");
        try writer.writeAll("\"tool_call_template\":{\"call_template_type\":\"http\",\"url\":\"/tools/hinge.resolve\",\"http_method\":\"POST\"},");
        try writer.writeAll("\"x-janus-capabilities\":{\"required\":[\"net.http.POST:${REGISTRY_URL}\"],\"optional\":[]}");
        try emit_avg(writer, opts.hinge_resolve_avg_response_size);
        try writer.writeAll("}");
    }

    try writer.writeAll("]}");
}

/// Convenience: render manual to an owned slice for testing or external use.
pub fn renderManualToOwnedSlice(allocator: std.mem.Allocator, opts: Options) ![]u8 {
    var buf = std.ArrayList(u8){};
    errdefer buf.deinit(allocator);
    try writeManualJSON(json_helpers.arrayListWriter(&buf, allocator), opts);
    return try buf.toOwnedSlice(allocator);
}

// -----------------------------
// Internal Manual Validator (1.1)
// -----------------------------

pub const ValidationIssue = struct {
    path: []u8,
    message: []u8,
};

fn addIssue(allocator: std.mem.Allocator, issues: *std.ArrayList(ValidationIssue), path: []const u8, message: []const u8) !void {
    const p = try allocator.dupe(u8, path);
    errdefer allocator.free(p);
    const m = try allocator.dupe(u8, message);
    errdefer allocator.free(m);
    try issues.append(allocator, .{ .path = p, .message = m });
}

/// Validate a UTCP manual JSON Value according to MVP rules.
/// Collects all issues (does not bail on first error). Returns success when no issues.
pub fn validateManualValue(allocator: std.mem.Allocator, root: std.json.Value, issues: *std.ArrayList(ValidationIssue)) !void {
    if (root != .object) {
        try addIssue(allocator, issues, "$", "root must be object");
        return;
    }
    const obj = root.object;

    // Top-level fields
    const manual_version = obj.get("manual_version");
    if (manual_version == null or manual_version.? != .string) try addIssue(allocator, issues, "$.manual_version", "missing or not string");
    const utcp_version = obj.get("utcp_version");
    if (utcp_version == null or utcp_version.? != .string) try addIssue(allocator, issues, "$.utcp_version", "missing or not string");

    const auth = obj.get("auth");
    if (auth == null or auth.? != .object) {
        try addIssue(allocator, issues, "$.auth", "missing or not object");
    } else {
        const auth_type = auth.?.object.get("auth_type");
        if (auth_type == null or auth_type.? != .string) {
            try addIssue(allocator, issues, "$.auth.auth_type", "missing or not string");
        } else if (!std.mem.eql(u8, auth_type.?.string, "bearer")) {
            try addIssue(allocator, issues, "$.auth.auth_type", "must be 'bearer' in MVP");
        }
    }

    const tools_val = obj.get("tools");
    if (tools_val == null or tools_val.? != .array) {
        try addIssue(allocator, issues, "$.tools", "missing or not array");
        return;
    }
    const tools = tools_val.?.array.items;
    if (tools.len == 0) try addIssue(allocator, issues, "$.tools", "must contain at least one tool");

    for (tools, 0..) |t, idx| {
        const base_path = try std.fmt.allocPrint(allocator, "$.tools[{d}]", .{idx});
        defer allocator.free(base_path);
        if (t != .object) {
            try addIssue(allocator, issues, base_path, "tool entry must be object");
            continue;
        }
        const to = t.object;
        const name = to.get("name");
        if (name == null or name.? != .string) try addIssue(allocator, issues, base_path, "missing field 'name' (string)");
        const descr = to.get("description");
        if (descr == null or descr.? != .string) try addIssue(allocator, issues, base_path, "missing field 'description' (string)");

        // inputs schema
        const inputs = to.get("inputs");
        if (inputs == null or inputs.? != .object) {
            try addIssue(allocator, issues, base_path, "missing field 'inputs' (object)");
        } else {
            const itype = inputs.?.object.get("type");
            if (itype == null or itype.? != .string or !std.mem.eql(u8, itype.?.string, "object")) {
                try addIssue(allocator, issues, base_path, "inputs.type must be 'object'");
            }
            const props = inputs.?.object.get("properties");
            if (props == null or props.? != .object) {
                try addIssue(allocator, issues, base_path, "inputs.properties missing or not object");
            } else {
                var it = props.?.object.iterator();
                while (it.next()) |entry| {
                    const pval = entry.value_ptr.*;
                    if (pval != .object) {
                        try addIssue(allocator, issues, base_path, "each property must be object");
                        continue;
                    }
                    const ptype = pval.object.get("type");
                    if (ptype == null or ptype.? != .string) {
                        try addIssue(allocator, issues, base_path, "property.type missing or not string");
                    }
                }
            }
            const req = inputs.?.object.get("required");
            if (req == null or req.? != .array) {
                try addIssue(allocator, issues, base_path, "inputs.required missing or not array");
            } else {
                for (req.?.array.items) |rv| {
                    if (rv != .string) try addIssue(allocator, issues, base_path, "inputs.required items must be string");
                }
            }
        }

        // call template
        const tmpl = to.get("tool_call_template");
        if (tmpl == null or tmpl.? != .object) {
            try addIssue(allocator, issues, base_path, "missing field 'tool_call_template' (object)");
        } else {
            const ctt = tmpl.?.object.get("call_template_type");
            const url = tmpl.?.object.get("url");
            const method = tmpl.?.object.get("http_method");
            if (ctt == null or ctt.? != .string) try addIssue(allocator, issues, base_path, "tool_call_template.call_template_type missing or not string");
            if (url == null or url.? != .string) try addIssue(allocator, issues, base_path, "tool_call_template.url missing or not string");
            if (method == null or method.? != .string) try addIssue(allocator, issues, base_path, "tool_call_template.http_method missing or not string");
        }

        // capabilities
        const caps = to.get("x-janus-capabilities");
        if (caps == null or caps.? != .object) {
            try addIssue(allocator, issues, base_path, "missing field 'x-janus-capabilities' (object)");
        } else {
            const req_caps = caps.?.object.get("required");
            if (req_caps == null or req_caps.? != .array) {
                try addIssue(allocator, issues, base_path, "x-janus-capabilities.required missing or not array");
            } else {
                for (req_caps.?.array.items) |rv| if (rv != .string) try addIssue(allocator, issues, base_path, "capability token must be string");
            }
            const opt_caps = caps.?.object.get("optional");
            if (opt_caps != null and opt_caps.? != .array) {
                try addIssue(allocator, issues, base_path, "x-janus-capabilities.optional must be array when present");
            } else if (opt_caps) |arr| {
                for (arr.array.items) |rv| if (rv != .string) try addIssue(allocator, issues, base_path, "optional capability token must be string");
            }
        }
    }
}

pub fn validateManualBytes(allocator: std.mem.Allocator, json_bytes: []const u8, issues: *std.ArrayList(ValidationIssue)) !void {
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    try validateManualValue(allocator, parsed.value, issues);
}

test "UTCP ManualBuilder emits required top-level fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{});
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const root = parsed.value;

    try std.testing.expect(root == .object);
    try std.testing.expect(root.object.contains("manual_version"));
    try std.testing.expect(root.object.contains("utcp_version"));
    try std.testing.expect(root.object.contains("auth"));
    try std.testing.expect(root.object.contains("tools"));

    const auth = root.object.get("auth").?;
    try std.testing.expect(auth == .object);
    const auth_type = auth.object.get("auth_type").?;
    try std.testing.expect(auth_type == .string);
    try std.testing.expect(std.mem.eql(u8, auth_type.string, "bearer"));

    const manual_version = root.object.get("manual_version").?;
    try std.testing.expect(manual_version == .string);
    try std.testing.expect(std.mem.eql(u8, manual_version.string, "0.1.1"));

    const utcp_version = root.object.get("utcp_version").?;
    try std.testing.expect(utcp_version == .string);
    try std.testing.expect(std.mem.eql(u8, utcp_version.string, "0.1"));
}

test "UTCP ManualBuilder tools contain compile, query_ast, diagnostics.list" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{});
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();
    for (tools) |t| {
        const name = t.object.get("name").?.string;
        try seen.put(name, {});
    }
    try std.testing.expect(seen.contains("compile"));
    try std.testing.expect(seen.contains("query_ast"));
    try std.testing.expect(seen.contains("diagnostics.list"));
}

test "UTCP ManualBuilder each tool has call template and capabilities" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{});
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;
    for (tools) |t| {
        try std.testing.expect(t.object.contains("tool_call_template"));
        try std.testing.expect(t.object.contains("x-janus-capabilities"));
        const tmpl = t.object.get("tool_call_template").?;
        try std.testing.expect(tmpl.object.get("call_template_type").?.string.len > 0);
        try std.testing.expect(tmpl.object.get("url").?.string.len > 0);
        try std.testing.expect(tmpl.object.get("http_method").?.string.len > 0);
        const caps = t.object.get("x-janus-capabilities").?;
        try std.testing.expect(caps.object.contains("required"));
    }
}

test "UTCP ManualBuilder optionally includes hinge.resolve when enabled" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{ .include_hinge_resolve = true });
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;

    var found = false;
    for (tools) |t| {
        if (std.mem.eql(u8, t.object.get("name").?.string, "hinge.resolve")) {
            found = true;
            break;
        }
    }
    try std.testing.expect(found);
}

test "UTCP ManualBuilder includes average_response_size when configured" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{
        .compile_avg_response_size = 1024,
        .query_ast_avg_response_size = 256,
        .diagnostics_avg_response_size = 128,
    });
    defer allocator.free(json_bytes);

    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, json_bytes, .{});
    defer parsed.deinit();
    const tools = parsed.value.object.get("tools").?.array.items;
    var found_any = false;
    for (tools) |t| {
        if (t.object.get("average_response_size")) |v| {
            _ = v; // numeric expected
            found_any = true;
        }
    }
    try std.testing.expect(found_any);
}

test "UTCP ManualBuilder validation passes for generated manual" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const json_bytes = try renderManualToOwnedSlice(allocator, .{});
    defer allocator.free(json_bytes);

    var issues = std.ArrayList(ValidationIssue){};
    defer {
        for (issues.items) |it| {
            allocator.free(it.path);
            allocator.free(it.message);
        }
        issues.deinit(allocator);
    }
    try validateManualBytes(allocator, json_bytes, &issues);
    try std.testing.expectEqual(@as(usize, 0), issues.items.len);
}

test "UTCP ManualBuilder validation detects missing fields" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Malformed manual: missing utcp_version and tool_call_template
    const bad =
        \\{
        \\  "manual_version": "0.1.1",
        \\  "auth": { "auth_type": "bearer" },
        \\  "tools": [ {
        \\    "name": "compile",
        \\    "description": "Compile a Janus source file",
        \\    "inputs": { "type": "object", "properties": { "source_file": { "type": "string" } }, "required": ["source_file"] },
        \\    "x-janus-capabilities": { "required": ["fs.read:${WORKSPACE}"] }
        \\  } ]
        \\}
    ;

    var issues = std.ArrayList(ValidationIssue){};
    defer {
        for (issues.items) |it| {
            allocator.free(it.path);
            allocator.free(it.message);
        }
        issues.deinit(allocator);
    }
    try validateManualBytes(allocator, bad, &issues);
    try std.testing.expect(issues.items.len > 0);
}
