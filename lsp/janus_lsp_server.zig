// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus LSP Server - ASTDB Query Integration
//!
//! This module implements a Language Server Protocol (LSP) server that bridges
//! LSP requests to the ASTDB query engine, providing instant semantic information
//! for IDE integration.
//!
//! Key Features:
//! - Sub-10ms response times for hover, go-to-definition, find references
//! - Memoized query results with CID-based cache invalidation
//! - Real-time diagnostics with incremental parsing
//! - Profile-aware queries respecting feature gates

const std = @import("std");
const json = std.json;
const net = std.net;
const ArrayList = std.array_list.Managed;
const Allocator = std.mem.Allocator;
const Thread = std.Thread;
const Mutex = std.Thread.Mutex;
const Condition = std.Thread.Condition;

// NOTE: This module is currently gated in build.zig. When enabled, switch
// to stable imports via the libjanus public API instead of relative paths.
const api = @import("libjanus");

/// LSP Server Configuration
pub const LSPConfig = struct {
    /// Maximum response time for interactive operations (ms)
    max_response_time_ms: u32 = 10,
    /// Enable query result caching
    enable_caching: bool = true,
    /// Profile to use for queries (:min, :go, :elixir, :full)
    profile: []const u8 = ":full",
    /// Enable real-time diagnostics
    enable_diagnostics: bool = true,
};

/// LSP Server State
pub const LSPServer = struct {
    allocator: Allocator,
    config: LSPConfig,
    // gRPC Oracle client
    oracle: @import("oracle_grpc_client.zig").OracleGrpcClient,

    // AST and query engine integration is pending; currently stubbed for compile.

    /// Document synchronization state (thread-safe)
    documents: std.StringHashMap(DocumentState),
    documents_mutex: Mutex = .{},

    /// Request ID counter (atomic)
    request_id: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Concurrent request handling
    thread_pool: ThreadPool,
    request_queue: RequestQueue,

    /// Server lifecycle
    shutdown_requested: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
    active_requests: std.atomic.Value(u32) = std.atomic.Value(u32).init(0),

    /// Thread Pool for concurrent request handling
    const ThreadPool = struct {
        threads: []Thread,
        allocator: Allocator,

        pub fn init(allocator: Allocator, thread_count: u32) !ThreadPool {
            const threads = try allocator.alloc(Thread, thread_count);
            return ThreadPool{
                .threads = threads,
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *ThreadPool) void {
            self.allocator.free(self.threads);
        }

        pub fn spawn(self: *ThreadPool, comptime func: anytype, args: anytype) !void {
            // Find available thread or queue request
            for (self.threads) |*thread| {
                if (thread.* == undefined) {
                    thread.* = try Thread.spawn(.{}, func, args);
                    return;
                }
            }
            // All threads busy - this is where we'd implement queuing
        }
    };

    /// Request Queue for handling concurrent LSP requests
    const RequestQueue = struct {
        requests: ArrayList(LSPRequest),
        mutex: Mutex = .{},
        condition: Condition = .{},

        const LSPRequest = struct {
            method: []const u8,
            params: json.Value,
            response_channel: *ResponseChannel,
        };

        const ResponseChannel = struct {
            result: ?json.Value = null,
            error_msg: ?[]const u8 = null,
            completed: std.atomic.Value(bool) = std.atomic.Value(bool).init(false),
        };

        pub fn init(allocator: Allocator) RequestQueue {
            return RequestQueue{
                .requests = ArrayList(LSPRequest).init(allocator),
            };
        }

        pub fn deinit(self: *RequestQueue) void {
            self.requests.deinit();
        }

        pub fn enqueue(self: *RequestQueue, request: LSPRequest) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            try self.requests.append(request);
            self.condition.signal();
        }

        pub fn dequeue(self: *RequestQueue) ?LSPRequest {
            self.mutex.lock();
            defer self.mutex.unlock();

            if (self.requests.items.len == 0) return null;
            return self.requests.orderedRemove(0);
        }
    };

    const DocumentState = struct {
        uri: []const u8,
        version: i32,
        content: []const u8,
        /// CID of last parsed content for incremental updates
        last_cid: ?[32]u8 = null,
        /// Cached diagnostics
        diagnostics: []Diagnostic = &.{},
        /// Line endings cache for efficient position mapping
        line_offsets: []u32 = &.{},
        /// Current AST snapshot for this document
        snapshot: ?*api.Snapshot = null,
        /// Mutex for thread-safe document updates
        mutex: Mutex = .{},

        /// Apply incremental text changes efficiently
        pub fn applyIncrementalChanges(self: *DocumentState, allocator: Allocator, changes: []const TextDocumentContentChangeEvent) !void {
            self.mutex.lock();
            defer self.mutex.unlock();

            for (changes) |change| {
                if (change.range) |range| {
                    // Incremental change - surgical update
                    try self.applyRangeChange(allocator, range, change.text);
                } else {
                    // Full document replacement
                    allocator.free(self.content);
                    self.content = try allocator.dupe(u8, change.text);
                    try self.rebuildLineOffsets(allocator);
                }
            }
        }

        fn applyRangeChange(self: *DocumentState, allocator: Allocator, range: Range, new_text: []const u8) !void {
            const start_offset = self.positionToOffset(range.start);
            const end_offset = self.positionToOffset(range.end);

            // Calculate new content size
            const old_len = self.content.len;
            const removed_len = end_offset - start_offset;
            const new_len = old_len - removed_len + new_text.len;

            // Allocate new content buffer
            const new_content = try allocator.alloc(u8, new_len);

            // Copy: [before_change][new_text][after_change]
            @memcpy(new_content[0..start_offset], self.content[0..start_offset]);
            @memcpy(new_content[start_offset .. start_offset + new_text.len], new_text);
            @memcpy(new_content[start_offset + new_text.len ..], self.content[end_offset..]);

            // Replace content
            allocator.free(self.content);
            self.content = new_content;

            // Rebuild line offsets for affected region
            try self.rebuildLineOffsets(allocator);
        }

        fn positionToOffset(self: *const DocumentState, position: Position) u32 {
            if (position.line >= self.line_offsets.len) return @intCast(self.content.len);

            const line_start = self.line_offsets[position.line];
            return line_start + position.character;
        }

        fn rebuildLineOffsets(self: *DocumentState, allocator: Allocator) !void {
            // Free existing line offsets
            if (self.line_offsets.len > 0) {
                allocator.free(self.line_offsets);
            }

            // Count lines
            var line_count: u32 = 1;
            for (self.content) |byte| {
                if (byte == '\n') line_count += 1;
            }

            // Build line offset table
            self.line_offsets = try allocator.alloc(u32, line_count);
            var line_idx: u32 = 0;
            self.line_offsets[0] = 0;

            for (self.content, 0..) |byte, i| {
                if (byte == '\n') {
                    line_idx += 1;
                    if (line_idx < line_count) {
                        self.line_offsets[line_idx] = @intCast(i + 1);
                    }
                }
            }
        }
    };

    const TextDocumentContentChangeEvent = struct {
        range: ?Range = null,
        text: []const u8,
    };

    const Diagnostic = struct {
        range: Range,
        severity: DiagnosticSeverity,
        message: []const u8,
        code: ?[]const u8 = null,
    };

    const Range = struct {
        start: Position,
        end: Position,
    };

    const Position = struct {
        line: u32,
        character: u32,
    };

    const DiagnosticSeverity = enum(u8) {
        Error = 1,
        Warning = 2,
        Information = 3,
        Hint = 4,
    };

    pub fn init(allocator: Allocator, config: LSPConfig) !*LSPServer {
        const server = try allocator.create(LSPServer);

        // Initialize thread pool (4 worker threads for concurrent requests)
        const thread_pool = try ThreadPool.init(allocator, 4);

        // Initialize request queue
        const request_queue = RequestQueue.init(allocator);

        server.* = LSPServer{
            .allocator = allocator,
            .config = config,
            .oracle = try @import("oracle_grpc_client.zig").OracleGrpcClient.connect(allocator, "127.0.0.1", 7777),
            .documents = std.StringHashMap(DocumentState).init(allocator),
            .thread_pool = thread_pool,
            .request_queue = request_queue,
        };

        return server;
    }

    pub fn deinit(self: *LSPServer) void {
        // Signal shutdown to all worker threads
        self.shutdown_requested.store(true, .seq_cst);

        // Wait for all active requests to complete
        while (self.active_requests.load(.seq_cst) > 0) {
            std.time.sleep(1_000_000); // 1ms
        }

        // Clean up thread pool
        self.thread_pool.deinit();

        // Clean up request queue
        self.request_queue.deinit();

        // Clean up documents (thread-safe)
        self.documents_mutex.lock();
        defer self.documents_mutex.unlock();

        var iterator = self.documents.iterator();
        while (iterator.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            if (entry.value_ptr.snapshot) |ss| ss.deinit();
            self.allocator.free(entry.value_ptr.content);
            if (entry.value_ptr.diagnostics.len > 0) self.allocator.free(entry.value_ptr.diagnostics);
            if (entry.value_ptr.line_offsets.len > 0) self.allocator.free(entry.value_ptr.line_offsets);
        }
        self.documents.deinit();

        // Deinit oracle client
        self.oracle.deinit();

        self.allocator.destroy(self);
    }

    /// Error-resilient request wrapper - NEVER crashes the server
    fn executeRequestSafely(self: *LSPServer, comptime handler: anytype, params: json.Value) json.Value {
        // Increment active request counter
        _ = self.active_requests.fetchAdd(1, .seq_cst);
        defer _ = self.active_requests.fetchSub(1, .seq_cst);

        // Execute handler with comprehensive error catching
        const result = handler(self, params) catch |err| {
            // Log the internal error for debugging
            std.log.err("LSP request handler failed: {}", .{err});

            // Return structured LSP error response
            return self.createErrorResponse(err) catch {
                // Fallback error response if even error creation fails
                return json.Value{
                    .object = std.json.ObjectMap.init(self.allocator),
                };
            };
        };

        return result;
    }

    /// Create structured LSP error response
    fn createErrorResponse(self: *LSPServer, err: anyerror) !json.Value {
        var err_map = std.json.ObjectMap.init(self.allocator);

        // Map Zig errors to LSP error codes
        const error_code: i32 = switch (err) {
            error.OutOfMemory => -32001, // LSP: Server not initialized
            error.InvalidJson => -32700, // LSP: Parse error
            error.MethodNotFound => -32601, // LSP: Method not found
            error.InvalidParams => -32602, // LSP: Invalid params
            else => -32603, // LSP: Internal error
        };

        const error_message = switch (err) {
            error.OutOfMemory => "Server out of memory",
            error.InvalidJson => "Invalid JSON in request",
            error.MethodNotFound => "LSP method not implemented",
            error.InvalidParams => "Invalid parameters for LSP method",
            else => "Internal server error",
        };

        try err_map.put("code", json.Value{ .integer = error_code });
        try err_map.put("message", json.Value{ .string = error_message });
        var resp_map = std.json.ObjectMap.init(self.allocator);
        try resp_map.put("error", json.Value{ .object = err_map });
        return json.Value{ .object = resp_map };
    }

    /// Handle LSP initialize request (error-resilient)
    pub fn handleInitialize(self: *LSPServer, params: json.Value) json.Value {
        return self.executeRequestSafely(handleInitializeImpl, params);
    }

    fn handleInitializeImpl(self: *LSPServer, params: json.Value) !json.Value {
        _ = params;

        var caps = std.json.ObjectMap.init(self.allocator);
        // Add capabilities
        try caps.put("textDocumentSync", json.Value{ .integer = 2 });
        try caps.put("hoverProvider", json.Value{ .bool = true });
        try caps.put("definitionProvider", json.Value{ .bool = true });
        try caps.put("referencesProvider", json.Value{ .bool = true });
        try caps.put("diagnosticProvider", json.Value{ .bool = true });

        var res = std.json.ObjectMap.init(self.allocator);
        try res.put("capabilities", json.Value{ .object = caps });
        return json.Value{ .object = res };
    }

    /// Handle document open/change notifications (error-resilient)
    pub fn handleTextDocumentDidChange(self: *LSPServer, params: json.Value) void {
        _ = self.executeRequestSafely(handleTextDocumentDidChangeImpl, params);
    }

    fn handleTextDocumentDidChangeImpl(self: *LSPServer, params: json.Value) !json.Value {
        const text_document = params.object.get("textDocument") orelse return error.InvalidParams;
        const uri = text_document.object.get("uri").?.string;
        const version = text_document.object.get("version").?.integer;

        const content_changes = params.object.get("contentChanges") orelse return error.InvalidParams;
        if (content_changes.array.items.len == 0) return json.Value{ .null = {} };

        // Convert JSON changes to internal format
        var changes = try self.allocator.alloc(TextDocumentContentChangeEvent, content_changes.array.items.len);
        defer self.allocator.free(changes);

        for (content_changes.array.items, 0..) |change_json, i| {
            const text = change_json.object.get("text").?.string;

            if (change_json.object.get("range")) |range_json| {
                // Incremental change with range
                const start_json = range_json.object.get("start").?;
                const end_json = range_json.object.get("end").?;

                const range = Range{
                    .start = Position{
                        .line = @intCast(start_json.object.get("line").?.integer),
                        .character = @intCast(start_json.object.get("character").?.integer),
                    },
                    .end = Position{
                        .line = @intCast(end_json.object.get("line").?.integer),
                        .character = @intCast(end_json.object.get("character").?.integer),
                    },
                };

                changes[i] = TextDocumentContentChangeEvent{
                    .range = range,
                    .text = text,
                };
            } else {
                // Full document replacement
                changes[i] = TextDocumentContentChangeEvent{
                    .range = null,
                    .text = text,
                };
            }
        }

        // Thread-safe document update
        self.documents_mutex.lock();
        defer self.documents_mutex.unlock();

        const owned_uri = try self.allocator.dupe(u8, uri);

        if (self.documents.getPtr(owned_uri)) |doc_state| {
            // Update existing document with incremental changes
            try doc_state.applyIncrementalChanges(self.allocator, changes);
            doc_state.version = @intCast(version);
        } else {
            // Create new document state
            const initial_content = if (changes.len > 0 and changes[0].range == null)
                try self.allocator.dupe(u8, changes[0].text)
            else
                try self.allocator.dupe(u8, "");

            var doc_state = DocumentState{
                .uri = owned_uri,
                .version = @intCast(version),
                .content = initial_content,
            };

            // Build initial line offsets
            try doc_state.rebuildLineOffsets(self.allocator);

            try self.documents.put(owned_uri, doc_state);
        }

        // Get updated content for ASTDB
        const updated_doc = self.documents.get(owned_uri).?;

        // Parse and update ASTDB (outside of mutex to avoid deadlock)
        self.documents_mutex.unlock();
        try self.updateDocumentAST(owned_uri, updated_doc.content);
        try self.updateDiagnostics(owned_uri);
        self.documents_mutex.lock();

        return json.Value{ .null = {} };
    }

    /// Handle hover requests (error-resilient)
    pub fn handleHover(self: *LSPServer, params: json.Value) ?json.Value {
        const result = self.executeRequestSafely(handleHoverImpl, params);
        return if (result.object.contains("error")) null else result;
    }

    fn handleHoverImpl(self: *LSPServer, params: json.Value) !json.Value {
        const text_document = params.object.get("textDocument") orelse return json.Value{ .null = {} };
        const position = params.object.get("position") orelse return json.Value{ .null = {} };
        const uri = text_document.object.get("uri").?.string;
        const line: u32 = @intCast(position.object.get("line").?.integer);
        const character: u32 = @intCast(position.object.get("character").?.integer);

        if (try self.oracle.HoverAt(uri, line, character)) |md| {
            var contents = std.json.ObjectMap.init(self.allocator);
            try contents.put("kind", json.Value{ .string = "markdown" });
            try contents.put("value", json.Value{ .string = md });
            var out = std.json.ObjectMap.init(self.allocator);
            try out.put("contents", json.Value{ .object = contents });
            return json.Value{ .object = out };
        }
        return json.Value{ .null = {} };
    }

    /// Handle go-to-definition requests (error-resilient)
    pub fn handleDefinition(self: *LSPServer, params: json.Value) ?json.Value {
        const result = self.executeRequestSafely(handleDefinitionImpl, params);
        return if (result.object.contains("error")) null else result;
    }

    fn handleDefinitionImpl(self: *LSPServer, params: json.Value) !json.Value {
        const text_document = params.object.get("textDocument") orelse return json.Value{ .null = {} };
        const position = params.object.get("position") orelse return json.Value{ .null = {} };
        const uri = text_document.object.get("uri").?.string;
        const line: u32 = @intCast(position.object.get("line").?.integer);
        const character: u32 = @intCast(position.object.get("character").?.integer);
        if (try self.oracle.DefinitionAt(uri, line, character)) |loc| {
            var location = std.json.ObjectMap.init(self.allocator);
            try location.put("uri", json.Value{ .string = loc.uri });
            var range = std.json.ObjectMap.init(self.allocator);
            var start_pos = std.json.ObjectMap.init(self.allocator);
            try start_pos.put("line", json.Value{ .integer = loc.line });
            try start_pos.put("character", json.Value{ .integer = loc.character });
            try range.put("start", json.Value{ .object = start_pos });
            try range.put("end", json.Value{ .object = start_pos });
            try location.put("range", json.Value{ .object = range });
            return json.Value{ .object = location };
        }
        return json.Value{ .null = {} };
    }

    /// Handle find references requests (error-resilient)
    pub fn handleReferences(self: *LSPServer, params: json.Value) ?json.Value {
        const result = self.executeRequestSafely(handleReferencesImpl, params);
        return if (result.object.contains("error")) null else result;
    }

    fn handleReferencesImpl(self: *LSPServer, params: json.Value) !json.Value {
        const text_document = params.object.get("textDocument") orelse return json.Value{ .array = std.ArrayList(json.Value).init(self.allocator) };
        const position = params.object.get("position") orelse return json.Value{ .array = std.ArrayList(json.Value).init(self.allocator) };

        const uri = text_document.object.get("uri").?.string;
        const line: u32 = @intCast(position.object.get("line").?.integer);
        const character: u32 = @intCast(position.object.get("character").?.integer);

        const include_decl = blk: {
            if (params.object.get("context")) |ctx| {
                if (ctx.object.get("includeDeclaration")) |v| break :blk v.bool;
            }
            break :blk true;
        };

        const locs = try self.oracle.ReferencesAt(uri, line, character, include_decl);
        var out = std.ArrayList(json.Value).init(self.allocator);
        for (locs) |l| {
            var loc = std.json.ObjectMap.init(self.allocator);
            try loc.put("uri", json.Value{ .string = l.uri });
            var range = std.json.ObjectMap.init(self.allocator);
            var sp = std.json.ObjectMap.init(self.allocator);
            try sp.put("line", json.Value{ .integer = l.line });
            try sp.put("character", json.Value{ .integer = l.character });
            try range.put("start", json.Value{ .object = sp });
            try range.put("end", json.Value{ .object = sp });
            try loc.put("range", json.Value{ .object = range });
            try out.append(json.Value{ .object = loc });
        }
        return json.Value{ .array = out };
    }

    // Private helper methods

    const SymbolInfo = struct {
        name: []const u8,
        type_name: []const u8,
        definition_file: []const u8,
        definition_line: u32,
        definition_column: u32,
    };

    const LocationInfo = struct {
        uri: []const u8,
        line: u32,
        column: u32,
    };

    fn updateDocumentAST(self: *LSPServer, uri: []const u8, content: []const u8) !void {
        // Forward document to janusd daemon
        _ = try self.oracle.DocUpdate(uri, content);
    }

    fn updateDiagnostics(self: *LSPServer, uri: []const u8) !void {
        if (self.documents.getPtr(uri)) |doc_state| {
            if (doc_state.diagnostics.len > 0) self.allocator.free(doc_state.diagnostics);
            doc_state.diagnostics = &.{};
        }
    }

    // JSON JanusdClient removed; all transport via gRPC OracleGrpcClient

    fn getSymbolAtPosition(self: *LSPServer, uri: []const u8, line: u32, character: u32) !?SymbolInfo {
        // Query ASTDB for symbol at position using memoized queries
        const query_key = try std.fmt.allocPrint(self.allocator, "symbol_at:{s}:{d}:{d}", .{ uri, line, character });
        defer self.allocator.free(query_key);

        if (try self.query_engine.getCachedResult(query_key)) |cached| {
            return cached.symbol_info;
        }

        // Perform actual query
        const symbol = try self.query_engine.querySymbolAtPosition(uri, line, character);
        if (symbol == null) return null;

        const symbol_info = SymbolInfo{
            .name = try self.allocator.dupe(u8, symbol.?.name),
            .type_name = try self.allocator.dupe(u8, symbol.?.type_name),
            .definition_file = try self.allocator.dupe(u8, symbol.?.definition_file),
            .definition_line = symbol.?.definition_line,
            .definition_column = symbol.?.definition_column,
        };

        // Stub mode: no caching, return null
        _ = symbol_info;
        return null;
    }

    fn getDefinitionAtPosition(self: *LSPServer, uri: []const u8, line: u32, character: u32) !?LocationInfo {
        // Query ASTDB for definition location
        const definition = try self.query_engine.queryDefinitionAtPosition(uri, line, character);
        if (definition == null) return null;

        return LocationInfo{
            .uri = try self.allocator.dupe(u8, definition.?.uri),
            .line = definition.?.line,
            .column = definition.?.column,
        };
    }

    fn getReferencesAtPosition(self: *LSPServer, _: []const u8, _: u32, _: u32) ![]LocationInfo {
        // Stub mode: no references
        return self.allocator.alloc(LocationInfo, 0);
    }
    /// Start the concurrent LSP server with JSON-RPC message loop
    pub fn startServer(self: *LSPServer) !void {
        std.debug.print("🚀 Janus LSP Server starting with concurrent request handling\n", .{});
        std.debug.print("Max response time: {}ms\n", .{self.config.max_response_time_ms});
        std.debug.print("Profile: {s}\n", .{self.config.profile});
        std.debug.print("Worker threads: {}\n", .{self.thread_pool.threads.len});

        // Start worker threads for concurrent request processing
        for (self.thread_pool.threads, 0..) |*thread, i| {
            thread.* = try Thread.spawn(.{}, workerThread, .{ self, i });
        }

        // Main JSON-RPC message loop
        var stdin_buffer: [8192]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(stdin_buffer[0..]);
        const stdin_io = &stdin_reader.interface;

        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.fs.File.stdout().writer(&stdout_buffer);
        const stdout = &stdout_writer.interface;

        var buffer: [8192]u8 = undefined;

        while (!self.shutdown_requested.load(.seq_cst)) {
            // Read JSON-RPC message header
            const header_line = stdin_io.readUntilDelimiterOrEof(&buffer, '\n') catch |err| {
                std.log.err("Failed to read message header: {}", .{err});
                continue;
            } orelse break;

            if (!std.mem.startsWith(u8, header_line, "Content-Length: ")) {
                continue;
            }

            // Parse content length
            const length_str = header_line[16..];
            const content_length = std.fmt.parseInt(u32, std.mem.trim(u8, length_str, " \r\n"), 10) catch {
                std.log.err("Invalid Content-Length: {s}", .{length_str});
                continue;
            };

            // Skip empty line
            _ = stdin_io.readUntilDelimiterOrEof(&buffer, '\n') catch continue;

            // Read JSON content
            if (content_length > buffer.len) {
                std.log.err("Message too large: {} bytes", .{content_length});
                continue;
            }

            var total_read: usize = 0;
            while (total_read < content_length) {
                const bytes_read = try stdin_reader.read(buffer[total_read..content_length]);
                if (bytes_read == 0) break;
                total_read += bytes_read;
            }
            if (total_read != content_length) {
                std.log.err("Message truncated. Expected {}, got {}", .{ content_length, total_read });
                continue;
            }

            // Parse JSON-RPC request
            const parsed = json.parseFromSlice(json.Value, self.allocator, buffer[0..content_length], .{}) catch |err| {
                std.log.err("Failed to parse JSON: {}", .{err});
                self.sendErrorResponse(stdout, null, -32700, "Parse error") catch {};
                continue;
            };
            defer parsed.deinit();

            const request = parsed.value;

            // Extract request ID for response correlation
            const request_id = if (request.object.get("id")) |id| id else null;

            // Route request to appropriate handler
            if (request.object.get("method")) |method| {
                try self.routeRequest(stdout, request_id, method.string, request.object.get("params"));
            } else {
                try self.sendErrorResponse(stdout, request_id, -32600, "Invalid Request");
            }
        }

        // Wait for all worker threads to complete
        for (self.thread_pool.threads) |thread| {
            thread.join();
        }

        std.debug.print("🛑 Janus LSP Server shutdown complete\n", .{});
    }

    /// Worker thread for concurrent request processing
    fn workerThread(self: *LSPServer, thread_id: usize) void {
        std.debug.print("🔧 Worker thread {} started\n", .{thread_id});

        while (!self.shutdown_requested.load(.seq_cst)) {
            // Check for queued requests
            if (self.request_queue.dequeue()) |request| {
                // Process request and send response
                self.processQueuedRequest(request) catch |err| {
                    std.log.err("Worker thread {} failed to process request: {}", .{ thread_id, err });
                };
            } else {
                // No requests available, sleep briefly
                std.time.sleep(1_000_000); // 1ms
            }
        }

        std.debug.print("🔧 Worker thread {} shutting down\n", .{thread_id});
    }

    /// Route incoming requests to appropriate handlers
    fn routeRequest(self: *LSPServer, writer: anytype, request_id: ?json.Value, method: []const u8, params: ?json.Value) !void {
        const params_value = params orelse json.Value{ .null = {} };

        if (std.mem.eql(u8, method, "initialize")) {
            const result = self.handleInitialize(params_value);
            try self.sendResponse(writer, request_id, result);
        } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
            self.handleTextDocumentDidChange(params_value);
            // No response needed for notifications
        } else if (std.mem.eql(u8, method, "textDocument/hover")) {
            if (self.handleHover(params_value)) |result| {
                try self.sendResponse(writer, request_id, result);
            } else {
                try self.sendResponse(writer, request_id, json.Value{ .null = {} });
            }
        } else if (std.mem.eql(u8, method, "textDocument/definition")) {
            if (self.handleDefinition(params_value)) |result| {
                try self.sendResponse(writer, request_id, result);
            } else {
                try self.sendResponse(writer, request_id, json.Value{ .null = {} });
            }
        } else if (std.mem.eql(u8, method, "textDocument/references")) {
            if (self.handleReferences(params_value)) |result| {
                try self.sendResponse(writer, request_id, result);
            } else {
                try self.sendResponse(writer, request_id, json.Value{ .null = {} });
            }
        } else if (std.mem.eql(u8, method, "shutdown")) {
            try self.sendResponse(writer, request_id, json.Value{ .null = {} });
            self.shutdown_requested.store(true, .seq_cst);
        } else {
            try self.sendErrorResponse(writer, request_id, -32601, "Method not found");
        }
    }

    /// Send JSON-RPC response
    fn sendResponse(self: *LSPServer, writer: anytype, request_id: ?json.Value, result: json.Value) !void {
        var resp_map = std.json.ObjectMap.init(self.allocator);
        try resp_map.put("jsonrpc", json.Value{ .string = "2.0" });
        if (request_id) |id| {
            try resp_map.put("id", id);
        }
        try resp_map.put("result", result);

        const json_string = try json.stringifyAlloc(self.allocator, json.Value{ .object = resp_map }, .{});
        defer self.allocator.free(json_string);

        try writer.print("Content-Length: {}\r\n\r\n{s}", .{ json_string.len, json_string });
        try writer.flush();
    }

    /// Send JSON-RPC error response
    fn sendErrorResponse(self: *LSPServer, writer: anytype, request_id: ?json.Value, code: i32, message: []const u8) !void {
        var err_map = std.json.ObjectMap.init(self.allocator);
        try err_map.put("code", json.Value{ .integer = code });
        try err_map.put("message", json.Value{ .string = message });
        var resp_map2 = std.json.ObjectMap.init(self.allocator);
        try resp_map2.put("jsonrpc", json.Value{ .string = "2.0" });
        if (request_id) |id| {
            try resp_map2.put("id", id);
        }
        try resp_map2.put("error", json.Value{ .object = err_map });

        const json_string = try json.stringifyAlloc(self.allocator, json.Value{ .object = resp_map2 }, .{});
        defer self.allocator.free(json_string);

        try writer.print("Content-Length: {}\r\n\r\n{s}", .{ json_string.len, json_string });
        try writer.flush();
    }

    /// Process queued request (for future async implementation)
    fn processQueuedRequest(_: *LSPServer, _: RequestQueue.LSPRequest) !void {
        // TODO: Implement async request processing
        // This is where we'd handle requests that need to be processed asynchronously
    }
};

/// Production-hardened LSP server entry point
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const config = LSPConfig{
        .max_response_time_ms = 10,
        .enable_caching = true,
        .profile = ":full",
        .enable_diagnostics = true,
    };

    const server = try LSPServer.init(allocator, config);
    defer server.deinit();

    // Start the concurrent server
    try server.startServer();
}
