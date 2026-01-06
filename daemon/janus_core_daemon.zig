// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Janus Core Daemon - The Keep
//!
//! A lightweight, dependency-free daemon that exposes libjanus functionality
//! over the Citadel Protocol. This daemon forms the core of the Citadel
//! Architecture, providing cross-platform compiler services without any
//! transport protocol dependencies.

const std = @import("std");
const protocol = @import("citadel_protocol.zig");
const libjanus = @import("libjanus");


// Inline hex formatting helper
inline fn hexFmt(hash: []const u8, buf: []u8) void {
    const hex_chars = "0123456789abcdef";
    for (hash, 0..) |byte, i| {
        buf[i * 2] = hex_chars[byte >> 4];
        buf[i * 2 + 1] = hex_chars[byte & 0x0f];
    }
}

const print = std.debug.print;

const DaemonConfig = struct {
    use_stdio: bool = true,
    socket_path: ?[]const u8 = null,
    log_level: LogLevel = .info,
    max_concurrent_requests: u32 = 100,

    const LogLevel = enum {
        debug,
        info,
        warn,
        @"error",
    };
};

const DocumentSession = struct {
    uri: []const u8,
    content: []const u8,
    snapshot: ?libjanus.Snapshot = null,
    last_modified: i64,
    token_count: u32 = 0,
    node_count: u32 = 0,
    parse_time_ns: u64 = 0,

    pub fn deinit(self: *DocumentSession, allocator: std.mem.Allocator) void {
        allocator.free(self.uri);
        allocator.free(self.content);
        if (self.snapshot) |*snapshot| {
            snapshot.deinit();
        }
    }

    pub fn updateContent(self: *DocumentSession, allocator: std.mem.Allocator, new_content: []const u8) !void {
        // Free old content (snapshot cleanup handled by ASTDB system)
        if (self.content.len > 0) {
            allocator.free(self.content);
        }

        // Store new content
        self.content = try allocator.dupe(u8, new_content);
        self.last_modified = std.time.timestamp();

        // Parse content and create new snapshot
        const start_time = std.time.nanoTimestamp();

        var system = try libjanus.astdb.ASTDBSystem.init(allocator, true);
        defer system.deinit();

        self.snapshot = try system.createSnapshot();

        var tokenizer = libjanus.tokenizer.Tokenizer.init(allocator, self.content);
        defer tokenizer.deinit();
        const tokens = try tokenizer.tokenize();
        defer allocator.free(tokens);
        self.token_count = @as(u32, @intCast(tokens.len));

        var parser = libjanus.parser.Parser.init(allocator, tokens);
        defer parser.deinit();
        _ = try parser.parseIntoSnapshot(self.snapshot.?);
        self.node_count = self.snapshot.?.nodeCount();

        const end_time = std.time.nanoTimestamp();
        self.parse_time_ns = @as(u64, @intCast(end_time - start_time));
    }
};

const CoreDaemon = struct {
    allocator: std.mem.Allocator,
    config: DaemonConfig,
    running: bool = false,
    request_counter: u32 = 0,
    document_sessions: std.StringHashMap(DocumentSession),

    pub fn init(allocator: std.mem.Allocator, config: DaemonConfig) CoreDaemon {
        return .{
            .allocator = allocator,
            .config = config,
            .document_sessions = std.StringHashMap(DocumentSession).init(allocator),
        };
    }

    pub fn deinit(self: *CoreDaemon) void {
        var iterator = self.document_sessions.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.document_sessions.deinit();
    }

    pub fn run(self: *CoreDaemon) !void {
        self.running = true;

        if (self.config.log_level == .info or self.config.log_level == .debug) {
            print("🏰 Janus Core Daemon starting (Citadel Protocol v{}.{}.{})\n", .{
                protocol.PROTOCOL_VERSION_MAJOR,
                protocol.PROTOCOL_VERSION_MINOR,
                protocol.PROTOCOL_VERSION_PATCH,
            });
        }

        if (self.config.use_stdio) {
            try self.runStdioLoop();
        } else {
            return error.UnixSocketNotImplemented; // TODO: Implement Unix socket support
        }
    }

    fn runStdioLoop(self: *CoreDaemon) !void {
        var stdin_buffer: [4096]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(stdin_buffer[0..]);
        var frame_reader = protocol.FrameReader.init(self.allocator, stdin_reader.any());

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        var frame_writer = protocol.FrameWriter.init(stdout_writer.any());

        while (self.running) {
            // Read incoming message frame
            const message_data = frame_reader.readFrame() catch |err| switch (err) {
                error.EndOfStream => {
                    if (self.config.log_level == .debug) {
                        print("📡 Client disconnected, shutting down\n", .{});
                    }
                    break;
                },
                else => {
                    if (self.config.log_level == .@"error") {
                        print("❌ Error reading frame: {}\n", .{err});
                    }
                    continue;
                },
            };
            defer self.allocator.free(message_data);

            // Process the message
            self.processMessage(message_data, &frame_writer) catch |err| {
                if (self.config.log_level == .@"error") {
                    print("❌ Error processing message: {}\n", .{err});
                }
                continue;
            };

            stdout_writer.flush() catch {};
        }
    }

    fn processMessage(self: *CoreDaemon, message_data: []const u8, frame_writer: *protocol.FrameWriter) !void {
        // Parse MessagePack request
        const request = protocol.parseRequest(self.allocator, message_data) catch {
            try self.sendErrorResponse(frame_writer, 0, "error_response", protocol.ProtocolError{
                .code = protocol.ProtocolError.INVALID_REQUEST,
                .message = "Failed to parse MessagePack request",
            });
            return;
        };
        defer request.deinit(self.allocator);

        // Dispatch to appropriate handler based on request type
        switch (request.request_type) {
            .version_request => try self.handleVersionRequest(frame_writer, request),
            .ping => try self.handlePing(frame_writer, request),
            .doc_update => try self.handleDocUpdate(frame_writer, request),
            .hover_at => try self.handleHoverAt(frame_writer, request),
            .definition_at => try self.handleDefinitionAt(frame_writer, request),
            .references_at => try self.handleReferencesAt(frame_writer, request),
            .shutdown => try self.handleShutdown(frame_writer, request),
        }
    }

    fn handleVersionRequest(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const response_payload = protocol.ResponsePayload{
            .version_response = protocol.VersionResponsePayload{
                .server_version = protocol.ProtocolVersion.current(),
                .negotiated_version = protocol.ProtocolVersion.current(),
                .enabled_features = &[_][]const u8{"stdio"},
                .status = "success",
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "version_response", response_payload);

        if (self.config.log_level == .debug) {
            print("🤝 Version negotiation completed\n", .{});
        }
    }

    fn handlePing(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const echo_data = request.payload.ping.echo_data;

        const response_payload = protocol.ResponsePayload{
            .ping_response = protocol.PingResponsePayload{
                .echo_data = echo_data,
                .server_timestamp = protocol.Request.getTimestamp(),
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "ping_response", response_payload);

        if (self.config.log_level == .debug) {
            print("🏓 Ping handled: {s}\n", .{echo_data});
        }
    }

    fn handleShutdown(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const response_payload = protocol.ResponsePayload{
            .shutdown_response = protocol.ShutdownResponsePayload{
                .message = "Daemon shutting down gracefully",
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "shutdown_response", response_payload);

        if (self.config.log_level == .info) {
            print("🛑 Shutdown requested, terminating\n", .{});
        }

        self.running = false;
    }

    fn handleDocUpdate(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const uri = request.payload.doc_update.uri;
        const content = request.payload.doc_update.content;

        if (self.config.log_level == .debug) {
            print("📄 DocUpdate for URI: {s} ({} bytes)\n", .{ uri, content.len });
        }

        // Get or create document session
        var session_result = self.document_sessions.getOrPut(uri) catch {
            try self.sendErrorResponse(frame_writer, request.id, "doc_update_response", protocol.ProtocolError{
                .code = protocol.ProtocolError.OUT_OF_MEMORY,
                .message = "Failed to allocate document session",
            });
            return;
        };

        if (!session_result.found_existing) {
            // Create new session
            session_result.value_ptr.* = DocumentSession{
                .uri = try self.allocator.dupe(u8, uri),
                .content = &[_]u8{}, // Will be set by updateContent
                .last_modified = 0,
            };
        }

        // Update document content and parse
        session_result.value_ptr.updateContent(self.allocator, content) catch |err| {
            const error_message = switch (err) {
                error.OutOfMemory => "Out of memory during parsing",
            };

            try self.sendErrorResponse(frame_writer, request.id, "doc_update_response", protocol.ProtocolError{
                .code = switch (err) {
                    error.OutOfMemory => protocol.ProtocolError.OUT_OF_MEMORY,
                },
                .message = error_message,
            });
            return;
        };

        // Generate snapshot ID (SHA256 hash of content)
        var hasher = std.crypto.hash.sha2.Sha256.init(.{});
        hasher.update(content);
        const hash_bytes = hasher.finalResult();

        var snapshot_id_buf: [64 + 7]u8 = undefined; // "sha256:" + 64 hex chars
        const snapshot_id = try (blk: {
        const hex_chars = "0123456789abcdef";
        var hex_buf: [&hash_bytes.len * 2]u8 = undefined;
        for (&hash_bytes, 0..) |byte, i| {
            hex_buf[i * 2] = hex_chars[byte >> 4];
            hex_buf[i * 2 + 1] = hex_chars[byte & 0x0f];
        }
        break :blk try std.fmt.bufPrint(&snapshot_id_buf, "sha256:{s}", .{hex_buf});
    });

        // Create successful response
        const response_payload = protocol.ResponsePayload{
            .doc_update_response = protocol.DocUpdateResponsePayload{
                .success = true,
                .snapshot_id = snapshot_id,
                .parse_time_ns = session_result.value_ptr.parse_time_ns,
                .token_count = session_result.value_ptr.token_count,
                .node_count = session_result.value_ptr.node_count,
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "doc_update_response", response_payload);

        if (self.config.log_level == .debug) {
            print("✅ DocUpdate complete: {} tokens, {} nodes, {}ns parse time\n", .{
                session_result.value_ptr.token_count,
                session_result.value_ptr.node_count,
                session_result.value_ptr.parse_time_ns,
            });
        }
    }

    fn sendSuccessResponse(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request_id: u32, response_type: []const u8, payload: anytype) !void {
        const response = protocol.MessagePackResponse{
            .id = request_id,
            .response_type = response_type,
            .timestamp = protocol.Request.getTimestamp(),
            .status = "success",
            .payload = payload,
            .error_info = null,
        };

        const serialized = try protocol.serializeMessagePackResponse(self.allocator, response);
        defer self.allocator.free(serialized);

        try frame_writer.writeFrame(serialized);
    }

    fn sendErrorResponse(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request_id: u32, response_type: []const u8, err: protocol.ProtocolError) !void {
        const response = protocol.MessagePackResponse{
            .id = request_id,
            .response_type = response_type,
            .timestamp = protocol.Request.getTimestamp(),
            .status = "error",
            .payload = null,
            .error_info = err,
        };

        const serialized = try protocol.serializeMessagePackResponse(self.allocator, response);
        defer self.allocator.free(serialized);

        try frame_writer.writeFrame(serialized);
    }

    fn handleHoverAt(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const uri = request.payload.hover_at.uri;
        const position = request.payload.hover_at.position;

        if (self.config.log_level == .debug) {
            print("🔍 HoverAt for URI: {s} at {}:{}\n", .{ uri, position.line, position.character });
        }

        // Get document session
        const session = self.document_sessions.get(uri);
        if (session == null or session.?.snapshot == null) {
            // No document or snapshot available - return empty hover
            const response_payload = protocol.ResponsePayload{
                .hover_at_response = protocol.HoverAtResponsePayload{
                    .hover_info = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
            return;
        }

        var snapshot = session.?.snapshot.?;
        var engine = libjanus.QueryEngine.init(self.allocator, &snapshot);
        defer engine.deinit();

        // Convert line/character to byte position
        var byte_pos: u32 = 0;
        for (0..snapshot.tokenCount()) |i| {
            const tid: libjanus.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const token = snapshot.getToken(tid) orelse continue;
            if (token.span.line == position.line + 1 and token.span.column >= position.character + 1) {
                byte_pos = token.span.start;
                break;
            }
        }

        // Find node at position
        const node_result = engine.nodeAt(byte_pos);
        if (node_result.result == null) {
            // No node at position
            const response_payload = protocol.ResponsePayload{
                .hover_at_response = protocol.HoverAtResponsePayload{
                    .hover_info = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
            return;
        }

        var target_node = node_result.result.?;
        const node_row = snapshot.getNode(target_node) orelse {
            const response_payload = protocol.ResponsePayload{
                .hover_at_response = protocol.HoverAtResponsePayload{
                    .hover_info = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
            return;
        };

        // If hovering an identifier, resolve its declaration and report its type
        if (node_row.kind == .identifier) {
            const token = snapshot.getToken(node_row.first_token) orelse {
                const response_payload = protocol.ResponsePayload{
                    .hover_at_response = protocol.HoverAtResponsePayload{
                        .hover_info = null,
                    },
                };
                try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
                return;
            };
            const scope = snapshot.getNodeScope(target_node) orelse {
                const response_payload = protocol.ResponsePayload{
                    .hover_at_response = protocol.HoverAtResponsePayload{
                        .hover_info = null,
                    },
                };
                try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
                return;
            };
            const decl_result = engine.lookup(scope, token.str orelse {
                const response_payload = protocol.ResponsePayload{
                    .hover_at_response = protocol.HoverAtResponsePayload{
                        .hover_info = null,
                    },
                };
                try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
                return;
            });
            if (decl_result.result) |decl| {
                const decl_row = snapshot.getDeclCompat(decl) orelse {
                    const response_payload = protocol.ResponsePayload{
                        .hover_at_response = protocol.HoverAtResponsePayload{
                            .hover_info = null,
                        },
                    };
                    try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);
                    return;
                };
                target_node = decl_row.node;
            }
        }

        // Get type information
        const type_result = engine.typeOf(target_node);
        const type_id = type_result.result;

        // Map builtin type ids to human-readable names
        const type_name = switch (@intFromEnum(type_id)) {
            1 => "i32",
            2 => "f64",
            3 => "bool",
            4 => "string",
            else => "unknown",
        };

        // Create hover info
        var content_buf: [256]u8 = undefined;
        const content = try std.fmt.bufPrint(&content_buf, "type: {s}", .{type_name});
        const owned_content = try self.allocator.dupe(u8, content);

        const hover_info = protocol.HoverInfo{
            .markdown = owned_content,
            .range = protocol.Range{
                .start = protocol.Position{ .line = position.line, .character = position.character },
                .end = protocol.Position{ .line = position.line, .character = position.character + 1 },
            },
        };

        const response_payload = protocol.ResponsePayload{
            .hover_at_response = protocol.HoverAtResponsePayload{
                .hover_info = hover_info,
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "hover_at_response", response_payload);

        if (self.config.log_level == .debug) {
            print("✅ HoverAt complete: {s}\n", .{type_name});
        }
    }

    fn handleDefinitionAt(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const uri = request.payload.definition_at.uri;
        const position = request.payload.definition_at.position;

        if (self.config.log_level == .debug) {
            print("📍 DefinitionAt for URI: {s} at {}:{}\n", .{ uri, position.line, position.character });
        }

        // Get document session
        const session = self.document_sessions.get(uri);
        if (session == null or session.?.snapshot == null) {
            // No document or snapshot available
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        }

        var snapshot = session.?.snapshot.?;
        var engine = libjanus.QueryEngine.init(self.allocator, &snapshot);
        defer engine.deinit();

        // Convert line/character to byte position
        var byte_pos: u32 = 0;
        for (0..snapshot.tokenCount()) |i| {
            const tid: libjanus.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const token = snapshot.getToken(tid) orelse continue;
            if (token.span.line == position.line + 1 and token.span.column >= position.character + 1) {
                byte_pos = token.span.start;
                break;
            }
        }

        // Find node at position
        const node_result = engine.nodeAt(byte_pos);
        const node = node_result.result orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const node_row = snapshot.getNode(node) orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const token = snapshot.getToken(node_row.first_token) orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const scope = snapshot.getNodeScope(node) orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const decl_result = engine.lookup(scope, token.str orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        });

        const decl = decl_result.result orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const decl_row = snapshot.getDeclCompat(decl) orelse {
            const response_payload = protocol.ResponsePayload{
                .definition_at_response = protocol.DefinitionAtResponsePayload{
                    .definition = null,
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);
            return;
        };

        const first_token = snapshot.getToken(snapshot.getNode(decl_row.node).?.first_token).?;
        const owned_uri = try self.allocator.dupe(u8, uri);

        const location = protocol.Location{
            .uri = owned_uri,
            .range = protocol.Range{
                .start = protocol.Position{
                    .line = first_token.span.line - 1,
                    .character = first_token.span.column,
                },
                .end = protocol.Position{
                    .line = first_token.span.line - 1,
                    .character = first_token.span.column + 1, // Use fixed width for now
                },
            },
        };

        const response_payload = protocol.ResponsePayload{
            .definition_at_response = protocol.DefinitionAtResponsePayload{
                .definition = location,
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "definition_at_response", response_payload);

        if (self.config.log_level == .debug) {
            print("✅ DefinitionAt complete: {}:{}\n", .{ first_token.span.line - 1, first_token.span.column });
        }
    }

    fn handleReferencesAt(self: *CoreDaemon, frame_writer: *protocol.FrameWriter, request: protocol.ParsedRequest) !void {
        const uri = request.payload.references_at.uri;
        const position = request.payload.references_at.position;
        const include_declaration = request.payload.references_at.include_declaration;

        if (self.config.log_level == .debug) {
            print("🔗 ReferencesAt for URI: {s} at {}:{} (include_decl: {})\n", .{ uri, position.line, position.character, include_declaration });
        }

        // Get document session
        const session = self.document_sessions.get(uri);
        if (session == null or session.?.snapshot == null) {
            // No document or snapshot available
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        }

        var snapshot = session.?.snapshot.?;
        var engine = libjanus.QueryEngine.init(self.allocator, &snapshot);
        defer engine.deinit();

        // Convert line/character to byte position
        var byte_pos: u32 = 0;
        for (0..snapshot.tokenCount()) |i| {
            const tid: libjanus.TokenId = @enumFromInt(@as(u32, @intCast(i)));
            const token = snapshot.getToken(tid) orelse continue;
            if (token.span.line == position.line + 1 and token.span.column >= position.character + 1) {
                byte_pos = token.span.start;
                break;
            }
        }

        // Find node at position
        const node_result = engine.nodeAt(byte_pos);
        const node = node_result.result orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        };

        const node_row = snapshot.getNode(node) orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        };

        const token = snapshot.getToken(node_row.first_token) orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        };

        const scope = snapshot.getNodeScope(node) orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        };

        const decl_result = engine.lookup(scope, token.str orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        });

        const decl = decl_result.result orelse {
            const response_payload = protocol.ResponsePayload{
                .references_at_response = protocol.ReferencesAtResponsePayload{
                    .references = &[_]protocol.Reference{},
                },
            };
            try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);
            return;
        };

        // Collect references
        var references = std.ArrayList(protocol.Reference).init(self.allocator);
        defer references.deinit();

        // Optionally include the declaration itself
        if (include_declaration) {
            const decl_row = snapshot.getDeclCompat(decl);
            if (decl_row) |drow| {
                const decl_token = snapshot.getToken(snapshot.getNode(drow.node).?.first_token).?;
                const owned_uri = try self.allocator.dupe(u8, uri);
                const reference = protocol.Reference{
                    .uri = owned_uri,
                    .range = protocol.Range{
                        .start = protocol.Position{
                            .line = decl_token.span.line - 1,
                            .character = decl_token.span.column,
                        },
                        .end = protocol.Position{
                            .line = decl_token.span.line - 1,
                            .character = decl_token.span.column + 1, // Use fixed width for now
                        },
                    },
                    .is_declaration = true,
                };
                try references.append(reference);
            }
        }

        // Stream all references pointing to the declaration
        for (0..snapshot.refCount()) |ri| {
            const rid: libjanus.RefId = @enumFromInt(@as(u32, @intCast(ri)));
            const ref = snapshot.getRef(rid) orelse continue;
            if (std.meta.eql(ref.decl, decl)) {
                const ref_token = snapshot.getToken(snapshot.getNode(ref.at_node).?.first_token).?;
                const owned_uri = try self.allocator.dupe(u8, uri);
                const reference = protocol.Reference{
                    .uri = owned_uri,
                    .range = protocol.Range{
                        .start = protocol.Position{
                            .line = ref_token.span.line - 1,
                            .character = ref_token.span.column,
                        },
                        .end = protocol.Position{
                            .line = ref_token.span.line - 1,
                            .character = ref_token.span.column + 1, // Use fixed width for now
                        },
                    },
                    .is_declaration = false,
                };
                try references.append(reference);
            }
        }

        const owned_references = try self.allocator.dupe(protocol.Reference, references.items);

        const response_payload = protocol.ResponsePayload{
            .references_at_response = protocol.ReferencesAtResponsePayload{
                .references = owned_references,
            },
        };

        try self.sendSuccessResponse(frame_writer, request.id, "references_at_response", response_payload);

        if (self.config.log_level == .debug) {
            print("✅ ReferencesAt complete: {} references found\n", .{references.items.len});
        }
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = DaemonConfig{};

    // Parse command line arguments
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--socket") and i + 1 < args.len) {
            config.use_stdio = false;
            config.socket_path = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--log-level") and i + 1 < args.len) {
            if (std.mem.eql(u8, args[i + 1], "debug")) {
                config.log_level = .debug;
            } else if (std.mem.eql(u8, args[i + 1], "info")) {
                config.log_level = .info;
            } else if (std.mem.eql(u8, args[i + 1], "warn")) {
                config.log_level = .warn;
            } else if (std.mem.eql(u8, args[i + 1], "error")) {
                config.log_level = .@"error";
            } else {
                print("❌ Invalid log level: {s}\n", .{args[i + 1]});
                return;
            }
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            print("Janus Core Daemon - The Keep\n\n", .{});
            print("Usage: janus-core-daemon [OPTIONS]\n\n", .{});
            print("Options:\n", .{});
            print("  --socket PATH     Use Unix socket instead of stdio\n", .{});
            print("  --log-level LEVEL Set log level (debug|info|warn|error)\n", .{});
            print("  --help, -h        Show this help message\n\n", .{});
            print("The daemon implements the Citadel Protocol v{}.{}.{}\n", .{
                protocol.PROTOCOL_VERSION_MAJOR,
                protocol.PROTOCOL_VERSION_MINOR,
                protocol.PROTOCOL_VERSION_PATCH,
            });
            return;
        } else {
            print("❌ Unknown argument: {s}\n", .{args[i]});
            print("Use --help for usage information\n", .{});
            return;
        }
    }

    var daemon = CoreDaemon.init(allocator, config);
    defer daemon.deinit();
    try daemon.run();
}
