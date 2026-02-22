// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus LSP Server - Task 4: LSP Shim Implementation
//!
//! Minimal LSP server that translates LSP protocol messages to CLI queries.
//! Enables immediate VSCode integration before full daemon is ready.

const std = @import("std");
const json = std.json;
const Allocator = std.mem.Allocator;

/// Simple LSP Server for Janus
const JanusLSPServer = struct {
    allocator: Allocator,
    stdin_file: std.fs.File,
    stdin_buffer: [4096]u8,
    stdin_reader: std.fs.File.Reader,
    stdout_file: std.fs.File,
    stdout_buffer: [4096]u8,
    stdout_writer: std.fs.File.Writer,
    daemon_connection: ?std.net.Stream = null,
    daemon_host: []const u8 = "127.0.0.1",
    daemon_port: u16 = 7777,

    const Self = @This();

    pub fn init(allocator: Allocator) Self {
        var self = Self{
            .allocator = allocator,
            .stdin_file = std.fs.File.stdin(),
            .stdin_buffer = undefined,
            .stdin_reader = undefined,
            .stdout_file = std.fs.File.stdout(),
            .stdout_buffer = undefined,
            .stdout_writer = undefined,
        };
        self.setupStreams();
        return self;
    }

    pub fn setupStreams(self: *Self) void {
        self.stdin_reader = self.stdin_file.reader(&self.stdin_buffer);
        self.stdout_writer = self.stdout_file.writer(&self.stdout_buffer);
    }

    /// Main server loop
    pub fn run(self: *Self) !void {
        std.log.info("Janus LSP Server starting...", .{});

        // Connect to janusd daemon
        try self.connectToDaemon();
        defer self.disconnectFromDaemon();

        while (true) {
            // Read LSP message
            const message = self.readLSPMessage() catch |err| switch (err) {
                error.EndOfStream => {
                    std.log.info("Client disconnected", .{});
                    break;
                },
                else => return err,
            };
            defer self.allocator.free(message);

            // Process message
            try self.processMessage(message);
        }
    }

    /// Read a complete LSP message
    fn readLSPMessage(self: *Self) ![]u8 {
        var content_length: ?usize = null;
        var line_buffer: [1024]u8 = undefined;
        var header_io = &self.stdin_reader.interface;

        // Read headers
        while (true) {
            if (try header_io.readUntilDelimiterOrEof(&line_buffer, '\n')) |line| {
                const trimmed = std.mem.trim(u8, line, " \r\n");

                if (trimmed.len == 0) break; // End of headers

                if (std.mem.startsWith(u8, trimmed, "Content-Length: ")) {
                    const length_str = trimmed[16..];
                    content_length = try std.fmt.parseInt(usize, length_str, 10);
                }
            } else {
                return error.EndOfStream;
            }
        }

        const length = content_length orelse return error.InvalidMessage;

        // Read content
        const content = try self.allocator.alloc(u8, length);
        _ = try header_io.readAll(content);
        return content;
    }

    /// Process an LSP message
    fn processMessage(self: *Self, message: []const u8) !void {
        var parsed = json.parseFromSlice(json.Value, self.allocator, message, .{}) catch |err| {
            std.log.err("Failed to parse JSON: {}", .{err});
            return;
        };
        defer parsed.deinit();

        const root = parsed.value;
        const method = if (root.object.get("method")) |m| m.string else return;

        std.log.debug("Processing: {s}", .{method});

        if (std.mem.eql(u8, method, "initialize")) {
            try self.handleInitialize(root);
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            try self.handleHover(root);
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            try self.handleDefinition(root);
        } else if (std.mem.eql(u8, method, "textDocument/references")) {
            try self.handleReferences(root);
        } else {
            std.log.debug("Unhandled method: {s}", .{method});
        }
    }

    /// Handle initialize
    fn handleInitialize(self: *Self, request: json.Value) !void {
        const id = request.object.get("id").?.integer;

        const response = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": {d},
            \\  "result": {{
            \\    "capabilities": {{
            \\      "textDocumentSync": 1,
            \\      "hoverProvider": true,
            \\      "definitionProvider": true,
            \\      "referencesProvider": true
            \\    }},
            \\    "serverInfo": {{
            \\      "name": "janus-lsp",
            \\      "version": "0.1.0"
            \\    }}
            \\  }}
            \\}}
        , .{id});
        defer self.allocator.free(response);

        try self.sendResponse(response);
        std.log.info("LSP initialized", .{});
    }

    /// Handle hover
    fn handleHover(self: *Self, request: json.Value) !void {
        const id = request.object.get("id").?.integer;
        const params = request.object.get("params").?.object;
        const text_document = params.get("textDocument").?.object;
        const position = params.get("position").?.object;

        const uri = text_document.get("uri").?.string;
        const line = @as(u32, @intCast(position.get("line").?.integer));
        const character = @as(u32, @intCast(position.get("character").?.integer));

        // Convert URI to file path
        const file_path = try self.uriToFilePath(uri);
        defer self.allocator.free(file_path);

        // Execute CLI query
        const query_result = try self.executeQuery("--node-at", file_path, line + 1, character + 1);
        defer self.allocator.free(query_result);

        // Create hover response
        const hover_content = try self.createHoverContent(query_result);
        defer self.allocator.free(hover_content);

        const response = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": {d},
            \\  "result": {s}
            \\}}
        , .{ id, hover_content });
        defer self.allocator.free(response);

        try self.sendResponse(response);
    }

    /// Handle definition
    fn handleDefinition(self: *Self, request: json.Value) !void {
        const id = request.object.get("id").?.integer;
        const params = request.object.get("params").?.object;
        const text_document = params.get("textDocument").?.object;
        const position = params.get("position").?.object;

        const uri = text_document.get("uri").?.string;
        const line = @as(u32, @intCast(position.get("line").?.integer));
        const character = @as(u32, @intCast(position.get("character").?.integer));

        const file_path = try self.uriToFilePath(uri);
        defer self.allocator.free(file_path);

        const query_result = try self.executeQuery("--def-of", file_path, line + 1, character + 1);
        defer self.allocator.free(query_result);

        const definition_content = try self.createDefinitionContent(query_result);
        defer self.allocator.free(definition_content);

        const response = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": {d},
            \\  "result": {s}
            \\}}
        , .{ id, definition_content });
        defer self.allocator.free(response);

        try self.sendResponse(response);
    }

    /// Handle references
    fn handleReferences(self: *Self, request: json.Value) !void {
        const id = request.object.get("id").?.integer;

        // For now, return empty array
        const response = try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "jsonrpc": "2.0",
            \\  "id": {d},
            \\  "result": []
            \\}}
        , .{id});
        defer self.allocator.free(response);

        try self.sendResponse(response);
    }

    /// Execute REAL ASTDB Query - NO DAEMON, NO MOCKS
    fn executeQuery(self: *Self, query_type: []const u8, file_path: []const u8, line: u32, column: u32) ![]u8 {
        // Import real ASTDB query command
        const query_command = @import("../../src/query_command.zig");

        // Create query command instance
        var cmd = query_command.QueryCommand.init(self.allocator);

        // Map LSP query types to internal query types
        const lsp_query_type = if (std.mem.eql(u8, query_type, "--node-at"))
            query_command.LSPQueryType.node_at
        else if (std.mem.eql(u8, query_type, "--def-of"))
            query_command.LSPQueryType.definition_of
        else if (std.mem.eql(u8, query_type, "--type-of"))
            query_command.LSPQueryType.type_of
        else if (std.mem.eql(u8, query_type, "--refs-of"))
            query_command.LSPQueryType.references_of
        else
            query_command.LSPQueryType.node_at;

        // Create position
        const position = query_command.SourcePosition{
            .line = line,
            .column = column,
        };

        // Execute real query using the real executeQueryEngine function
        const result = query_command.executeQueryEngine(lsp_query_type, file_path, position, null, self.allocator) catch |err| {
            std.log.err("Real query execution failed: {}", .{err});
            return try std.fmt.allocPrint(self.allocator, "{{\"error\": \"Query failed: {}\"}}", .{err});
        };

        // Convert result to JSON for LSP response
        return try self.formatQueryResultAsJSON(result);
    }

    /// Format query result as JSON for LSP
    fn formatQueryResultAsJSON(self: *Self, result: anytype) ![]u8 {
        return switch (result) {
            .node_at => |node_result| try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "node_id": "{s}",
                \\  "node_type": "{s}",
                \\  "text": "{s}",
                \\  "start_line": {},
                \\  "start_column": {},
                \\  "end_line": {},
                \\  "end_column": {}
                \\}}
            , .{
                node_result.node_id,
                node_result.node_type,
                node_result.text,
                node_result.start_line,
                node_result.start_column,
                node_result.end_line,
                node_result.end_column,
            }),
            .definition_of => |def_result| try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "definition_file": "{s}",
                \\  "definition_line": {},
                \\  "definition_column": {},
                \\  "symbol_name": "{s}",
                \\  "symbol_type": "{s}"
                \\}}
            , .{
                def_result.definition_file,
                def_result.definition_line,
                def_result.definition_column,
                def_result.symbol_name,
                def_result.symbol_type,
            }),
            .references_of => |refs_result| blk: {
                var json_buffer = std.ArrayList(u8).init(self.allocator);
                defer json_buffer.deinit();

                try json_buffer.appendSlice("{\"references\": [");
                for (refs_result.references, 0..) |ref, i| {
                    if (i > 0) try json_buffer.appendSlice(", ");
                    const ref_json = try std.fmt.allocPrint(self.allocator,
                        \\{{"file": "{s}", "line": {}, "column": {}, "context": "{s}"}}
                    , .{ ref.file, ref.line, ref.column, ref.context });
                    defer self.allocator.free(ref_json);
                    try json_buffer.appendSlice(ref_json);
                }
                try json_buffer.appendSlice("]}");
                break :blk try json_buffer.toOwnedSlice();
            },
            .type_of => |type_result| try std.fmt.allocPrint(self.allocator,
                \\{{
                \\  "type_name": "{s}",
                \\  "is_mutable": {},
                \\  "is_optional": {},
                \\  "signature": "{s}"
                \\}}
            , .{
                type_result.type_name,
                type_result.is_mutable,
                type_result.is_optional,
                type_result.signature,
            }),
            .diagnostics => |diag_result| blk: {
                var json_buffer = std.ArrayList(u8).init(self.allocator);
                defer json_buffer.deinit();

                try json_buffer.appendSlice("{\"diagnostics\": [");
                for (diag_result.diagnostics, 0..) |diag, i| {
                    if (i > 0) try json_buffer.appendSlice(", ");
                    const diag_json = try std.fmt.allocPrint(self.allocator,
                        \\{{"severity": "{s}", "message": "{s}", "file": "{s}", "line": {}, "column": {}, "code": "{s}"}}
                    , .{ diag.severity, diag.message, diag.file, diag.line, diag.column, diag.code });
                    defer self.allocator.free(diag_json);
                    try json_buffer.appendSlice(diag_json);
                }
                try json_buffer.appendSlice("]}");
                break :blk try json_buffer.toOwnedSlice();
            },
        };
    }

    /// Convert URI to file path
    fn uriToFilePath(self: *Self, uri: []const u8) ![]u8 {
        if (std.mem.startsWith(u8, uri, "file://")) {
            return try self.allocator.dupe(u8, uri[7..]);
        }
        return try self.allocator.dupe(u8, uri);
    }

    /// Create hover content from query result
    fn createHoverContent(self: *Self, query_result: []const u8) ![]u8 {
        // Parse the JSON result
        var parsed = json.parseFromSlice(json.Value, self.allocator, query_result, .{}) catch {
            return try self.allocator.dupe(u8, "null");
        };
        defer parsed.deinit();

        const result = parsed.value.object.get("result") orelse {
            return try self.allocator.dupe(u8, "null");
        };

        const node_type = if (result.object.get("node_type")) |nt| nt.string else "unknown";
        const text = if (result.object.get("text")) |t| t.string else "unknown";

        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "contents": {{
            \\    "kind": "markdown",
            \\    "value": "**{s}**\\n\\n```janus\\n{s}\\n```"
            \\  }}
            \\}}
        , .{ node_type, text });
    }

    /// Create definition content from query result
    fn createDefinitionContent(self: *Self, query_result: []const u8) ![]u8 {
        // Parse the JSON result
        var parsed = json.parseFromSlice(json.Value, self.allocator, query_result, .{}) catch {
            return try self.allocator.dupe(u8, "null");
        };
        defer parsed.deinit();

        const result = parsed.value.object.get("result") orelse {
            return try self.allocator.dupe(u8, "null");
        };

        const file = if (result.object.get("definition_file")) |f| f.string else "unknown";
        const line = if (result.object.get("definition_line")) |l| l.integer else 1;
        const column = if (result.object.get("definition_column")) |c| c.integer else 1;

        const file_uri = try std.fmt.allocPrint(self.allocator, "file://{s}", .{file});
        defer self.allocator.free(file_uri);

        return try std.fmt.allocPrint(self.allocator,
            \\{{
            \\  "uri": "{s}",
            \\  "range": {{
            \\    "start": {{"line": {d}, "character": {d}}},
            \\    "end": {{"line": {d}, "character": {d}}}
            \\  }}
            \\}}
        , .{ file_uri, line - 1, column - 1, line - 1, column + 10 });
    }

    /// Send LSP response
    fn sendResponse(self: *Self, content: []const u8) !void {
        const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{content.len});
        defer self.allocator.free(header);

        var stdout_writer = &self.stdout_writer.interface;
        try stdout_writer.writeAll(header);
        try stdout_writer.writeAll(content);
    }

    /// Connect to janusd daemon
    fn connectToDaemon(self: *Self) !void {
        const address = try std.net.Address.parseIp(self.daemon_host, self.daemon_port);
        self.daemon_connection = try std.net.tcpConnectToAddress(address);
        std.log.info("Connected to janusd at {s}:{}", .{ self.daemon_host, self.daemon_port });
    }

    /// Disconnect from daemon
    fn disconnectFromDaemon(self: *Self) void {
        if (self.daemon_connection) |connection| {
            connection.close();
            self.daemon_connection = null;
            std.log.info("Disconnected from janusd", .{});
        }
    }

    /// Send RPC request to daemon and get response
    fn queryDaemon(self: *Self, method: []const u8, params: std.json.Value) ![]u8 {
        const connection = self.daemon_connection orelse return error.NotConnected;

        // Serialize params to JSON string
        var params_string = std.ArrayList(u8).init(self.allocator);
        defer params_string.deinit();
        try std.json.stringify(params, .{}, params_string.writer());

        // Create RPC request
        const request = try std.fmt.allocPrint(self.allocator,
            \\{{"method": "{s}", "params": {s}}}
            \\
        , .{ method, params_string.items });
        defer self.allocator.free(request);

        // Send request
        _ = try connection.write(request);

        // Read response
        var response_buffer: [8192]u8 = undefined;
        const bytes_read = try connection.read(response_buffer[0..]);

        return try self.allocator.dupe(u8, response_buffer[0..bytes_read]);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var server = JanusLSPServer.init(allocator);
    try server.run();
}
