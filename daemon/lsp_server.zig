// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Language Server Protocol (LSP) Implementation
//!
//! This is the nervous system of the Janus toolchain.
//! It implements the Language Server Protocol 3.17 to provide:
//! - "Prophetic" features (completion, goto def) via ASTDB
//! - Hot-reloading coordination
//! - Live introspection
//!
//! Architecture:
//! - Transport: Stdin/Stdout (JSON-RPC)
//! - State: Holds the living AstDB graph
//! - Concurrency: Single-threaded event loop (Phase 1), Async/Fiber (Phase 3)

const std = @import("std");
const astdb = @import("astdb"); // ASTDB Core definitions
const parser = @import("janus_parser"); // Parser integration
const binder = @import("astdb_binder"); // Semantic binder (Phase 2)
const query = @import("astdb_query"); // ASTDB Query API
const semantic = @import("semantic"); // Semantic Analysis (Symbol Resolver)

pub const LspError = error{
    HeaderParseError,
    ContentLengthMissing,
    InvalidJson,
    MethodNotFound,
    Shutdown,
};

// ============================================================================
// SOVEREIGN I/O HELPERS
// We don't wait for library sugar. We pick up the saw.
// These work on ANY object with a basic .read(dest) -> usize method.
// ============================================================================

/// Read exactly dest.len bytes from reader, or return EndOfStream
fn readExact(reader: anytype, dest: []u8) !usize {
    var total: usize = 0;
    while (total < dest.len) {
        const amt = try reader.read(dest[total..]);
        if (amt == 0) return error.EndOfStream;
        total += amt;
    }
    return total;
}

/// Read a single byte from the reader
fn readByte(reader: anytype) !u8 {
    var buf: [1]u8 = undefined;
    _ = try readExact(reader, &buf);
    return buf[0];
}

// ============================================================================
// LSP PROTOCOL TYPES
// ============================================================================

pub const Position = struct {
    line: u32,
    character: u32,
};

pub const Range = struct {
    start: Position,
    end: Position,
};

pub const DiagnosticSeverity = enum(u8) {
    Error = 1,
    Warning = 2,
    Information = 3,
    Hint = 4,
};

pub const Diagnostic = struct {
    range: Range,
    severity: DiagnosticSeverity,
    message: []const u8,
    source: []const u8 = "janus",
};

pub const MarkupKind = enum {
    PlainText,
    Markdown,
};

pub const MarkupContent = struct {
    kind: []const u8 = "markdown", // "plaintext" | "markdown"
    value: []const u8,
};

pub const Hover = struct {
    contents: MarkupContent,
    range: ?Range = null,
};

pub const Location = struct {
    uri: []const u8,
    range: Range,
};

pub const CompletionItemKind = enum(u32) {
    Text = 1,
    Method = 2,
    Function = 3,
    Constructor = 4,
    Field = 5,
    Variable = 6,
    Class = 7,
    Interface = 8,
    Module = 9,
    Property = 10,
    Unit = 11,
    Value = 12,
    Enum = 13,
    Keyword = 14,
    Snippet = 15,
    Color = 16,
    File = 17,
    Reference = 18,
    Folder = 19,
    EnumMember = 20,
    Constant = 21,
    Struct = 22,
    Event = 23,
    Operator = 24,
    TypeParameter = 25,
};

pub const CompletionItem = struct {
    label: []const u8,
    kind: CompletionItemKind = .Text,
    detail: ?[]const u8 = null,
    documentation: ?MarkupContent = null,
    insertText: ?[]const u8 = null,
};

pub const CompletionList = struct {
    isIncomplete: bool = false,
    items: []const CompletionItem,
};

/// Helper to convert byte offsets to line/column positions
// Re-export or use query.LineIndex directly
pub const LineIndex = query.LineIndex;

/// The sovereign guardian of code intelligence
pub fn LspServer(comptime Reader: type, comptime Writer: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        input: Reader,
        output: Writer,
        db: *astdb.AstDB,

        // State
        initialized: bool,
        shutdown_requested: bool,

        // Document storage (in-memory, dirty buffers)
        documents: std.StringHashMap([]const u8), // URI -> source text

        // JSON Parser
        // arena: std.heap.ArenaAllocator,

        pub fn init(allocator: std.mem.Allocator, input: Reader, output: Writer, db: *astdb.AstDB) Self {
            return Self{
                .allocator = allocator,
                .input = input,
                .output = output,
                .db = db,
                .initialized = false,
                .shutdown_requested = false,
                .documents = std.StringHashMap([]const u8).init(allocator),
            };
        }

        pub fn deinit(self: *Self) void {
            // Free all stored documents
            var iter = self.documents.iterator();
            while (iter.next()) |entry| {
                self.allocator.free(entry.key_ptr.*);
                self.allocator.free(entry.value_ptr.*);
            }
            self.documents.deinit();
        }

        /// Main Event Loop
        pub fn run(self: *Self) !void {
            std.log.info("LSP Server starting event loop", .{});

            while (!self.shutdown_requested) {
                // 1. Read Message
                const message = self.readMessage() catch |err| {
                    if (err == error.EndOfStream) {
                        std.log.info("LSP input stream closed. Exiting.", .{});
                        return;
                    }
                    std.log.err("LSP read error: {s}", .{@errorName(err)});
                    continue; // Try to recover? Or crash?
                };
                defer self.allocator.free(message);

                // 2. Handle Message
                self.handleMessage(message) catch |err| {
                    if (err == LspError.Shutdown) return;
                    std.log.err("LSP handle error: {s}", .{@errorName(err)});
                    // Respond with error if possible
                };
            }
        }

        /// Read LSP message using Content-Length header
        fn readMessage(self: *Self) ![]u8 {
            // Read headers
            var content_length: usize = 0;

            while (true) {
                // Read line
                var line_buf: [1024]u8 = undefined;
                const line = try self.readLine(&line_buf);

                // Empty line (\r\n) marks end of headers
                if (line.len == 0) break;

                // Parse headers
                if (std.ascii.startsWithIgnoreCase(line, "Content-Length: ")) {
                    const value = std.mem.trim(u8, line["Content-Length: ".len..], " \r");
                    content_length = try std.fmt.parseInt(usize, value, 10);
                }
            }

            if (content_length == 0) return LspError.ContentLengthMissing;

            // Read body using sovereign helper
            const body = try self.allocator.alloc(u8, content_length);
            errdefer self.allocator.free(body);

            _ = try readExact(self.input, body);

            return body;
        }

        /// Read a single line (CRLF terminated) using sovereign I/O
        fn readLine(self: *Self, buffer: []u8) ![]u8 {
            var index: usize = 0;

            while (index < buffer.len) {
                const byte = readByte(self.input) catch |err| {
                    if (err == error.EndOfStream and index == 0) return err;
                    if (index > 0) break; // Partial line before EOF
                    return err;
                };

                buffer[index] = byte;
                index += 1;

                // Check for CRLF
                if (index >= 2 and buffer[index - 2] == '\r' and buffer[index - 1] == '\n') {
                    return buffer[0 .. index - 2]; // Return without CRLF
                }
            }

            // Return what we have (might not have CRLF at end)
            return buffer[0..index];
        }

        /// Handle JSON-RPC message
        fn handleMessage(self: *Self, message: []u8) !void {
            std.log.debug("LSP Recv: {s}", .{message});

            var parsed = try std.json.parseFromSlice(std.json.Value, self.allocator, message, .{});
            defer parsed.deinit();

            const root = parsed.value;
            if (root != .object) return LspError.InvalidJson;

            // Extract method name
            const method_val = root.object.get("method");
            if (method_val == null) {
                std.log.warn("LSP: Message missing 'method' field", .{});
                return;
            }
            const method = method_val.?.string;

            // TRACER ZERO: Prove message receipt

            // Extract ID (if request)
            const id_val = root.object.get("id");

            if (std.mem.eql(u8, method, "initialize")) {
                try self.handleInitialize(id_val);
            } else if (std.mem.eql(u8, method, "textDocument/didOpen")) {
                try self.handleDidOpen(root.object.get("params"));
            } else if (std.mem.eql(u8, method, "textDocument/didChange")) {
                try self.handleDidChange(root.object.get("params"));
            } else if (std.mem.eql(u8, method, "textDocument/hover")) {
                try self.handleHover(id_val, root.object.get("params"));
            } else if (std.mem.eql(u8, method, "textDocument/definition")) {
                try self.handleGotoDefinition(id_val, root.object.get("params"));
            } else if (std.mem.eql(u8, method, "textDocument/references")) {
                try self.handleReferences(id_val, root.object.get("params"));
            } else if (std.mem.eql(u8, method, "textDocument/completion")) {
                try self.handleCompletion(id_val, root.object.get("params"));
            } else if (std.mem.eql(u8, method, "shutdown")) {
                try self.handleShutdown(id_val);
            } else if (std.mem.eql(u8, method, "exit")) {
                self.shutdown_requested = true;
            } else {
                // Unknown method
                std.log.warn("Unknown LSP method: {s}", .{method});
            }
        }

        fn handleInitialize(self: *Self, id: ?std.json.Value) !void {
            self.initialized = true;

            const capabilities = .{
                .capabilities = .{
                    .textDocumentSync = 1, // Full
                    .hoverProvider = true,
                    .definitionProvider = true,
                    .referencesProvider = true,
                },
                .serverInfo = .{
                    .name = "janus-lsp",
                    .version = "0.2.2-0",
                },
            };

            try self.sendResponse(id, capabilities);
        }

        fn handleDidOpen(self: *Self, params: ?std.json.Value) !void {
            if (params == null) return;
            const root = params.?;
            const doc = root.object.get("textDocument") orelse return;
            const uri_val = doc.object.get("uri") orelse return;
            const text_val = doc.object.get("text") orelse return;

            if (uri_val != .string or text_val != .string) return;
            const uri = uri_val.string;
            const text = text_val.string;

            std.log.info("LSP: didOpen {s}", .{uri});

            // Store document in memory
            const uri_copy = try self.allocator.dupe(u8, uri);
            const text_copy = try self.allocator.dupe(u8, text);
            try self.documents.put(uri_copy, text_copy);

            // Compile and publish diagnostics
            try self.compileAndPublishDiagnostics(uri, text);
        }

        fn handleDidChange(self: *Self, params: ?std.json.Value) !void {
            if (params == null) {
                return;
            }
            const root = params.?;
            const doc = root.object.get("textDocument") orelse {
                return;
            };
            const uri_val = doc.object.get("uri") orelse {
                return;
            };
            const changes_val = root.object.get("contentChanges") orelse {
                return;
            };

            if (uri_val != .string or changes_val != .array) {
                return;
            }
            const uri = uri_val.string;
            const changes = changes_val.array;

            if (changes.items.len == 0) {
                return;
            }

            // For full sync, the last change is the full content
            const last_change = changes.items[changes.items.len - 1];
            const text_val = last_change.object.get("text") orelse {
                return;
            };
            if (text_val != .string) {
                return;
            }
            const text = text_val.string;

            // Update document cache: remove old, put new owned key/value
            if (self.documents.fetchRemove(uri)) |kv| {
                self.allocator.free(kv.key);
                self.allocator.free(kv.value);
            }

            const owned_uri = try self.allocator.dupe(u8, uri);
            const text_copy = try self.allocator.dupe(u8, text);
            try self.documents.put(owned_uri, text_copy);

            // Compile and publish diagnostics
            try self.compileAndPublishDiagnostics(uri, text);
        }

        fn handleHover(self: *Self, id: ?std.json.Value, params: ?std.json.Value) !void {
            if (id == null) return;
            if (params == null) return;

            const params_obj = params.?.object;
            const doc_obj = params_obj.get("textDocument").?.object;
            const uri = doc_obj.get("uri").?.string;
            const pos_obj = params_obj.get("position").?.object;
            const line = @as(u32, @intCast(pos_obj.get("line").?.integer));
            const char = @as(u32, @intCast(pos_obj.get("character").?.integer));

            // 1. Get Unit
            if (self.db.getUnitByPath(uri) == null) {
                return self.sendResponse(id, null);
            }
            const unit = self.db.getUnitByPath(uri).?;

            // 2. Query ASTDB for Node
            const node_id = query.findNodeAtPosition(self.db, unit.id, line, char, self.allocator) catch |err| {
                std.log.err("LSP Hover Query Failed: {s}", .{@errorName(err)});
                return self.sendResponse(id, null);
            } orelse return self.sendResponse(id, null);

            // 3. Run Semantic Analysis (Quick Pass)
            var resolver = try semantic.SymbolResolver.init(self.allocator, self.db);
            defer resolver.deinit();

            // Allow failure (best effort resolution)
            resolver.resolveUnit(unit.id) catch |err| {
                std.log.warn("Hover semantic resolution warning: {s}", .{@errorName(err)});
            };

            // 4. Get Node Data
            const node = self.db.getNode(unit.id, node_id) orelse return self.sendResponse(id, null);

            // 5. Determine context (Type Info)
            var type_info_str: []const u8 = "";
            var symbol_kind_str: []const u8 = "";

            if (resolver.node_to_symbol.get(node_id)) |symbol_id| {
                if (resolver.symbol_table.symbol_map.get(symbol_id)) |idx| {
                    const symbol = resolver.symbol_table.symbols.items[idx];
                    symbol_kind_str = @tagName(symbol.kind);

                    if (symbol.type_id) |tid| {
                        const info = resolver.type_system.getTypeInfo(tid);
                        type_info_str = switch (info.kind) {
                            .primitive => |p| @tagName(p),
                            .structure => |s| s.name,
                            .enumeration => |e| e.name,
                            else => "(complex type)", // TODO: Full type printing
                        };
                    }
                }
            }

            // 6. Build Response
            // Get node extent
            const first_tok_idx = @intFromEnum(node.first_token);
            const last_tok_idx = @intFromEnum(node.last_token);

            // Safety check
            if (first_tok_idx >= unit.tokens.len or last_tok_idx >= unit.tokens.len) {
                return self.sendResponse(id, null);
            }

            const first_tok = unit.tokens[first_tok_idx];
            const last_tok = unit.tokens[last_tok_idx];
            const start_byte = first_tok.span.start;
            const end_byte = last_tok.span.end;

            // Extract source snippet (limit to ~10 lines or 500 chars)
            var code_snippet: []const u8 = "";
            if (start_byte < unit.source.len and end_byte <= unit.source.len and start_byte <= end_byte) {
                const raw_snippet = unit.source[start_byte..end_byte];
                if (raw_snippet.len > 500) {
                    code_snippet = try std.fmt.allocPrint(self.allocator, "{s} ... (truncated)", .{raw_snippet[0..500]});
                } else {
                    code_snippet = raw_snippet;
                }
            }

            // Determine friendly title
            const kind_title = switch (node.kind) {
                .func_decl => "Function Declaration",
                .struct_decl => "Struct Declaration",
                .const_stmt => "Constant",
                .let_stmt => "Let Binding",
                .var_stmt => "Variable",
                .identifier => "Identifier",
                .string_literal => "String Literal",
                .integer_literal => "Integer Literal",
                else => @tagName(node.kind),
            };

            // Detailed info if it's an identifier
            var name_info: []const u8 = "";
            if (node.kind == .identifier) {
                if (first_tok.str) |str_id| {
                    if (self.db.str_interner.get(str_id)) |s| {
                        name_info = s;
                    }
                }
            }

            // Construct Markdown
            var md_text: []u8 = undefined;
            if (type_info_str.len > 0) {
                md_text = try std.fmt.allocPrint(self.allocator, "### {s}: `{s}`\n**Type**: `{s}`\n\n```janus\n{s}\n```", .{ kind_title, name_info, type_info_str, code_snippet });
            } else if (name_info.len > 0) {
                md_text = try std.fmt.allocPrint(self.allocator, "### {s}: `{s}`\n\n```janus\n{s}\n```", .{ kind_title, name_info, code_snippet });
            } else {
                md_text = try std.fmt.allocPrint(self.allocator, "### {s}\n\n```janus\n{s}\n```", .{ kind_title, code_snippet });
            }
            defer self.allocator.free(md_text);

            // Clean up allocated snippet if we duped it
            if (code_snippet.len > 0 and code_snippet.ptr != unit.source.ptr + start_byte) {
                self.allocator.free(code_snippet);
            }

            const result = Hover{
                .contents = .{
                    .kind = "markdown",
                    .value = md_text,
                },
            };
            try self.sendResponse(id, result);
        }

        /// Handle textDocument/definition - Goto Definition (F12)
        fn handleGotoDefinition(self: *Self, id: ?std.json.Value, params: ?std.json.Value) !void {
            if (id == null) return;
            if (params == null) return self.sendResponse(id, null);

            const params_obj = params.?.object;
            const doc_obj = params_obj.get("textDocument").?.object;
            const uri = doc_obj.get("uri").?.string;
            const pos_obj = params_obj.get("position").?.object;
            const line = @as(u32, @intCast(pos_obj.get("line").?.integer));
            const char = @as(u32, @intCast(pos_obj.get("character").?.integer));

            // 1. Get Unit
            const unit = self.db.getUnitByPath(uri) orelse return self.sendResponse(id, null);

            // 2. Resolve definition via Query API
            const node_id = query.findNodeAtPosition(self.db, unit.id, line, char, self.allocator) catch {
                return self.sendResponse(id, null);
            } orelse return self.sendResponse(id, null);

            const location = query.resolveDefinitionLocation(self.db, unit.id, node_id, self.allocator) catch {
                return self.sendResponse(id, null);
            };

            if (location) |loc| {
                const lsp_loc = Location{
                    .uri = loc.uri,
                    .range = .{
                        .start = .{ .line = loc.range.start.line, .character = loc.range.start.character },
                        .end = .{ .line = loc.range.end.line, .character = loc.range.end.character },
                    },
                };
                try self.sendResponse(id, lsp_loc);
            } else {
                try self.sendResponse(id, null);
            }
        }

        fn handleReferences(self: *Self, id: ?std.json.Value, params: ?std.json.Value) !void {
            if (id == null) return;
            if (params == null) return self.sendResponse(id, null);

            const params_obj = params.?.object;
            const doc_obj = params_obj.get("textDocument").?.object;
            const uri = doc_obj.get("uri").?.string;
            const pos_obj = params_obj.get("position").?.object;
            const line = @as(u32, @intCast(pos_obj.get("line").?.integer));
            const char = @as(u32, @intCast(pos_obj.get("character").?.integer));

            const unit = self.db.getUnitByPath(uri) orelse return self.sendResponse(id, null);

            const node_id = query.findNodeAtPosition(self.db, unit.id, line, char, self.allocator) catch {
                return self.sendResponse(id, null);
            } orelse return self.sendResponse(id, null);

            const locations = query.resolveReferences(self.db, unit.id, node_id, self.allocator) catch {
                return self.sendResponse(id, null);
            };
            defer self.allocator.free(locations);

            var lsp_locations = try std.ArrayList(Location).initCapacity(self.allocator, locations.len);
            defer lsp_locations.deinit(self.allocator);

            for (locations) |loc| {
                try lsp_locations.append(self.allocator, Location{
                    .uri = loc.uri,
                    .range = .{
                        .start = .{ .line = loc.range.start.line, .character = loc.range.start.character },
                        .end = .{ .line = loc.range.end.line, .character = loc.range.end.character },
                    },
                });
            }

            try self.sendResponse(id, lsp_locations.items);
        }

        fn handleCompletion(self: *Self, id: ?std.json.Value, params: ?std.json.Value) !void {
            if (params == null) return;
            const root = params.?.object;
            const text_document = root.get("textDocument") orelse return;
            const uri = text_document.object.get("uri").?.string;
            const position_json = root.get("position").?.object;
            const line = @as(u32, @intCast(position_json.get("line").?.integer));
            const character = @as(u32, @intCast(position_json.get("character").?.integer));

            const source = self.documents.get(uri) orelse return;
            var line_index = try LineIndex.init(self.allocator, source);
            defer line_index.deinit();

            // Perform a quick semantic pass to get symbols
            var resolver = try semantic.SymbolResolver.init(self.allocator, self.db);
            defer resolver.deinit();

            const unit = self.db.getUnitByPath(uri) orelse return;
            resolver.resolveUnit(unit.id) catch {};

            var type_checker = try semantic.TypeChecker.init(self.allocator, self.db, resolver.symbol_table, resolver.type_system);
            defer type_checker.deinit();
            type_checker.checkUnit(unit.id) catch {};

            var items = std.ArrayList(CompletionItem).initCapacity(self.allocator, 0) catch unreachable;
            defer {
                for (items.items) |item| {
                    self.allocator.free(item.label);
                    if (item.detail) |d| self.allocator.free(d);
                }
                items.deinit(self.allocator);
            }

            const cursor_pos = query.Position{ .line = line, .character = character };
            const cursor_offset = line_index.positionToByte(cursor_pos) orelse source.len;

            // Check if we are in a dot-completion context
            var is_dot_completion = false;
            var lhs_type_id: ?semantic.TypeId = null;

            if (cursor_offset > 0 and source[cursor_offset - 1] == '.') {
                is_dot_completion = true;
                const lhs_pos = Position{ .line = line, .character = if (character > 0) character - 1 else 0 };
                if (query.findNodeAtPosition(self.db, unit.id, lhs_pos.line, lhs_pos.character, self.allocator)) |maybe_node_id| {
                    if (maybe_node_id) |lhs_node_id| {
                        lhs_type_id = type_checker.inferExpressionType(lhs_node_id) catch null;
                    }
                } else |_| {}
            }

            for (resolver.symbol_table.symbols.items) |sym| {
                const name = resolver.symbol_table.symbol_interner.getString(sym.name);

                if (is_dot_completion) {
                    if (sym.kind == .function and lhs_type_id != null) {
                        const decl_node = unit.nodes[@intFromEnum(sym.declaration_node)];
                        const decl_children = unit.edges[decl_node.child_lo..decl_node.child_hi];

                        var first_param_type: ?semantic.TypeId = null;
                        for (decl_children) |child_id| {
                            const child = unit.nodes[@intFromEnum(child_id)];
                            if (child.kind == .parameter) {
                                const param_children = unit.edges[child.child_lo..child.child_hi];
                                if (param_children.len > 1) {
                                    first_param_type = resolver.resolveDeclarationType(param_children) catch null;
                                }
                                break;
                            }
                        }

                        if (first_param_type) |fp_type| {
                            if (fp_type.eql(lhs_type_id.?)) {
                                try items.append(self.allocator, .{
                                    .label = try self.allocator.dupe(u8, name),
                                    .kind = .Method,
                                    .detail = try std.fmt.allocPrint(self.allocator, "(self: {s})", .{type_checker.getTypeName(fp_type)}),
                                });
                            }
                        }
                    }
                } else {
                    const kind: CompletionItemKind = switch (sym.kind) {
                        .variable => .Variable,
                        .function => .Function,
                        .parameter => .Variable,
                        .type_alias => .Interface,
                        .struct_type => .Struct,
                        .enum_type => .Enum,
                    };
                    try items.append(self.allocator, .{
                        .label = try self.allocator.dupe(u8, name),
                        .kind = kind,
                    });
                }
            }

            const result = CompletionList{
                .isIncomplete = false,
                .items = items.items,
            };
            try self.sendResponse(id, result);
        }

        fn handleShutdown(self: *Self, id: ?std.json.Value) !void {
            try self.sendResponse(id, null);
        }

        fn sendResponse(self: *Self, id: ?std.json.Value, result: anytype) !void {
            if (id == null) return;

            const response = .{
                .jsonrpc = "2.0",
                .id = id.?,
                .result = result,
            };

            const body = try std.json.Stringify.valueAlloc(self.allocator, response, .{ .whitespace = .minified });
            defer self.allocator.free(body);

            const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
            defer self.allocator.free(header);
            try self.output.writeAll(header);
            try self.output.writeAll(body);
            try self.output.writeAll("");
        }

        /// Compile source and publish diagnostics
        fn compileAndPublishDiagnostics(self: *Self, uri: []const u8, source: []const u8) !void {
            // Create line index for byte offset -> line/column conversion
            var line_index = try LineIndex.init(self.allocator, source);
            defer line_index.deinit();

            // 1. PARSING PHASE
            var janus_parser = parser.Parser.init(self.allocator);
            defer janus_parser.deinit();

            // We'll collect all diagnostics here
            var all_diagnostics = try std.ArrayList(Diagnostic).initCapacity(self.allocator, 16);
            defer {
                for (all_diagnostics.items) |d| {
                    self.allocator.free(d.message);
                }
                all_diagnostics.deinit(self.allocator);
            }

            var parse_success = true;

            _ = janus_parser.parseIntoAstDB(self.db, uri, source) catch |err| {
                parse_success = false;

                // Extract error position
                var error_position = Position{ .line = 0, .character = 0 };
                var error_msg: []const u8 = undefined;

                if (self.db.getUnitByPath(uri)) |unit| {
                    if (unit.diags.len > 0) {
                        const first_diag = unit.diags[0];
                        const pos = line_index.byteToPosition(first_diag.span.start);
                        error_position = .{ .line = pos.line, .character = pos.character };
                    }
                }

                error_msg = try std.fmt.allocPrint(self.allocator, "Parse error: {s}", .{@errorName(err)});

                const diagnostic = Diagnostic{
                    .range = .{
                        .start = error_position,
                        .end = .{ .line = error_position.line, .character = error_position.character + 1 },
                    },
                    .severity = .Error,
                    .message = error_msg,
                };

                try all_diagnostics.append(self.allocator, diagnostic);
            };

            // 2. SEMANTIC PHASE (Only run if parsing succeeded)
            if (parse_success) {
                if (self.db.getUnitByPath(uri)) |unit| {
                    // A. Run Binder (for Go-To-Definition support)
                    // This populates unit.decls used by query.resolveDefinitionLocation
                    binder.bindUnit(self.db, unit.id) catch |err| {
                        std.log.warn("LSP: Binder failed: {s}", .{@errorName(err)});
                    };

                    // B. Run Symbol Resolver (for Semantic Diagnostics)
                    // This performs stricter checking and reports undeclared identifier
                    var resolver = try semantic.SymbolResolver.init(self.allocator, self.db);
                    defer resolver.deinit();

                    resolver.resolveUnit(unit.id) catch |err| {
                        std.log.warn("LSP: Symbol Resolver failed: {s}", .{@errorName(err)});
                    };

                    // Collect Semantic Diagnostics
                    const semantic_diags = resolver.getDiagnostics();
                    for (semantic_diags) |sd| {
                        const msg = try self.allocator.dupe(u8, sd.message);

                        // Convert SourceSpan (lines might be 1-based from tokenizer) to LSP Range (0-based)
                        // ASTDB SourceSpan: line, column, start, end (byte offsets)
                        // We assume single-line tokens for now
                        const start_line = sd.span.line;
                        const start_col = sd.span.column;
                        const len = sd.span.end - sd.span.start;

                        var range = Range{
                            .start = .{ .line = start_line, .character = start_col },
                            .end = .{ .line = start_line, .character = start_col + @as(u32, @intCast(len)) },
                        };

                        // Heuristic correction: if lines are 1-based, align to 0-based
                        if (range.start.line > 0) range.start.line -= 1;
                        if (range.end.line > 0) range.end.line -= 1;

                        const severity: DiagnosticSeverity = switch (sd.kind) {
                            .undefined_symbol => .Error,
                            .duplicate_declaration => .Error,
                            .inaccessible_symbol => .Error,
                            .shadowed_declaration => .Warning,
                        };

                        const diagnostic = Diagnostic{
                            .range = range,
                            .severity = severity,
                            .message = msg,
                            .source = "janus-semantic",
                        };

                        try all_diagnostics.append(self.allocator, diagnostic);
                    }

                    // C. Run Type Checker (for Type Mismatch Diagnostics)
                    var type_checker = try semantic.TypeChecker.init(self.allocator, self.db, resolver.symbol_table, resolver.type_system);
                    defer type_checker.deinit();

                    type_checker.checkUnit(unit.id) catch |err| {
                        std.log.warn("LSP: Type Checker failed: {s}", .{@errorName(err)});
                    };

                    // Collect Type Checker Diagnostics
                    const type_diags = type_checker.diagnostics.items;
                    for (type_diags) |td| {
                        const msg = try self.allocator.dupe(u8, td.message);

                        // Convert SourceSpan to LSP Range
                        // SourceSpan has: start, end (byte offsets), line, column
                        const start_line = td.span.line;
                        const start_col = td.span.column;
                        const len = td.span.end - td.span.start;

                        const range = Range{
                            .start = .{ .line = start_line, .character = start_col },
                            .end = .{ .line = start_line, .character = start_col + @as(u32, @intCast(len)) },
                        };

                        const severity: DiagnosticSeverity = switch (td.kind) {
                            .type_mismatch => .Error,
                            .invalid_call => .Error,
                            .unknown_type => .Warning,
                        };

                        const diagnostic = Diagnostic{
                            .range = range,
                            .severity = severity,
                            .message = msg,
                            .source = "janus-type-checker",
                        };

                        try all_diagnostics.append(self.allocator, diagnostic);
                    }
                }
            }

            // 3. PUBLISH
            try self.publishDiagnostics(uri, all_diagnostics.items);
        }

        fn publishDiagnostics(self: *Self, uri: []const u8, diagnostics: []const Diagnostic) !void {
            const notification = .{
                .jsonrpc = "2.0",
                .method = "textDocument/publishDiagnostics",
                .params = .{
                    .uri = uri,
                    .diagnostics = diagnostics,
                },
            };

            const body = try std.json.Stringify.valueAlloc(self.allocator, notification, .{ .whitespace = .minified });
            defer self.allocator.free(body);

            const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
            defer self.allocator.free(header);

            try self.output.writeAll(header);
            try self.output.writeAll(body);
        }
    };
}
