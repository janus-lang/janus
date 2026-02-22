// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Production-Grade HTTP Protocol Implementation
//! Zero-copy HTTP/1.1 parser and serializer with performance optimization

const std = @import("std");

/// HTTP parsing errors with detailed context
pub const HttpError = error{
    /// Protocol-level errors
    InvalidMethod,
    InvalidUri,
    InvalidVersion,
    InvalidHeader,
    InvalidChunkSize,

    /// Content-level errors
    ContentTooLarge,
    HeadersTooLarge,
    TooManyHeaders,

    /// State-level errors
    IncompleteRequest,
    MalformedRequest,
    UnsupportedVersion,

    /// Resource-level errors
    OutOfMemory,
    BufferTooSmall,
};

/// HTTP methods enumeration
pub const HttpMethod = enum {
    GET,
    POST,
    PUT,
    DELETE,
    HEAD,
    OPTIONS,
    PATCH,
    TRACE,
    CONNECT,

    /// Parse method from string slice
    pub fn parse(method_str: []const u8) HttpError!HttpMethod {
        const method_map = std.ComptimeStringMap(HttpMethod, .{
            .{ "GET", .GET },
            .{ "POST", .POST },
            .{ "PUT", .PUT },
            .{ "DELETE", .DELETE },
            .{ "HEAD", .HEAD },
            .{ "OPTIONS", .OPTIONS },
            .{ "PATCH", .PATCH },
            .{, .TRACE },
            .{ "CONNECT", .CONNECT },
        });

        return method_map.get(method_str) orelse HttpError.InvalidMethod;
    }

    /// Convert to string representation
    pub fn to_string(self: HttpMethod) []const u8 {
        return switch (self) {
            .GET => "GET",
            .POST => "POST",
            .PUT => "PUT",
            .DELETE => "DELETE",
            .HEAD => "HEAD",
            .OPTIONS => "OPTIONS",
            .PATCH => "PATCH",
            .TRACE => "TRACE",
            .CONNECT => "CONNECT",
        };
    }
};

/// HTTP version enumeration
pub const HttpVersion = enum {
    http_1_0,
    http_1_1,
    http_2_0,

    /// Parse version from string slice
    pub fn parse(version_str: []const u8) HttpError!HttpVersion {
        if (std.mem.eql(u8, version_str, "HTTP/1.0")) return .http_1_0;
        if (std.mem.eql(u8, version_str, "HTTP/1.1")) return .http_1_1;
        if (std.mem.eql(u8, version_str, "HTTP/2.0")) return .http_2_0;
        return HttpError.InvalidVersion;
    }

    /// Convert to string representation
    pub fn to_string(self: HttpVersion) []const u8 {
        return switch (self) {
            .http_1_0 => "HTTP/1.0",
            .http_1_1 => "HTTP/1.1",
            .http_2_0 => "HTTP/2.0",
        };
    }
};

/// HTTP status codes
pub const HttpStatus = enum(u16) {
    // 1xx Informational
    continue_status = 100,
    switching_protocols = 101,

    // 2xx Success
    ok = 200,
    created = 201,
    accepted = 202,
    no_content = 204,

    // 3xx Redirection
    moved_permanently = 301,
    found = 302,
    not_modified = 304,

    // 4xx Client Error
    bad_request = 400,
    unauthorized = 401,
    forbidden = 403,
    not_found = 404,
    method_not_allowed = 405,

    // 5xx Server Error
    internal_server_error = 500,
    not_implemented = 501,
    bad_gateway = 502,
    service_unavailable = 503,

    /// Get reason phrase for status code
    pub fn reason_phrase(self: HttpStatus) []const u8 {
        return switch (self) {
            .continue_status => "Continue",
            .switching_protocols => "Switching Protocols",
            .ok => "OK",
            .created => "Created",
            .accepted => "Accepted",
            .no_content => "No Content",
            .moved_permanently => "Moved Permanently",
            .found => "Found",
            .not_modified => "Not Modified",
            .bad_request => "Bad Request",
            .unauthorized => "Unauthorized",
            .forbidden => "Forbidden",
            .not_found => "Not Found",
            .method_not_allowed => "Method Not Allowed",
            .internal_server_error => "Internal Server Error",
            .not_implemented => "Not Implemented",
            .bad_gateway => "Bad Gateway",
            .service_unavailable => "Service Unavailable",
        };
    }
};

/// HTTP header structure with zero-copy design
pub const HttpHeader = struct {
    name: []const u8,
    value: []const u8,

    /// Common header names as constants
    pub const CONTENT_TYPE = "Content-Type";
    pub const CONTENT_LENGTH = "Content-Length";
    pub const CONNECTION = "Connection";
    pub const HOST = "Host";
    pub const USER_AGENT = "User-Agent";
    pub const ACCEPT = "Accept";
    pub const AUTHORIZATION = "Authorization";
    pub const CACHE_CONTROL = "Cache-Control";
};

/// HTTP request structure with zero-copy parsing
pub const HttpRequest = struct {
    method: HttpMethod,
    uri: []const u8,
    version: HttpVersion,
    headers: []HttpHeader,
    body: []const u8,

    // Internal parsing state
    allocator: std.mem.Allocator,
    raw_data: []const u8, // Reference to original buffer

    const Self = @This();

    /// Initialize empty request
    pub fn init(allocator: std.mem.Allocator) Self {
        return Self{
            .method = .GET,
            .uri = "",
            .version = .http_1_1,
            .headers = &[_]HttpHeader{},
            .body = "",
            .allocator = allocator,
            .raw_data = "",
        };
    }

    /// Get header value by name (case-insensitive)
    pub fn get_header(self: Self, name: []const u8) ?[]const u8 {
        for (self.headers) |header| {
            if (std.ascii.eqlIgnoreCase(header.name, name)) {
                return header.value;
            }
        }
        return null;
    }

    /// Check if connection should be kept alive
    pub fn keep_alive(self: Self) bool {
        if (self.version == .http_1_0) {
            // HTTP/1.0 requires explicit Connection: keep-alive
            if (self.get_header(HttpHeader.CONNECTION)) |conn| {
                return std.ascii.eqlIgnoreCase(conn, "keep-alive");
            }
            return false;
        } else {
            // HTTP/1.1 defaults to keep-alive unless Connection: close
            if (self.get_header(HttpHeader.CONNECTION)) |conn| {
                return !std.ascii.eqlIgnoreCase(conn, "close");
            }
            return true;
        }
    }

    /// Get content length from headers
    pub fn content_length(self: Self) ?usize {
        if (self.get_header(HttpHeader.CONTENT_LENGTH)) |length_str| {
            return std.fmt.parseInt(usize, length_str, 10) catch null;
        }
        return null;
    }

    /// Cleanup request resources
    pub fn deinit(self: *Self) void {
        if (self.headers.len > 0) {
            self.allocator.free(self.headers);
        }
    }
};

/// HTTP response structure for efficient serialization
pub const HttpResponse = struct {
    version: HttpVersion,
    status: HttpStatus,
    headers: []HttpHeader,
    body: []const u8,

    // Internal state
    allocator: std.mem.Allocator,

    const Self = @This();

    /// Initialize response with status
    pub fn init(allocator: std.mem.Allocator, status: HttpStatus) Self {
        return Self{
            .version = .http_1_1,
            .status = status,
            .headers = &[_]HttpHeader{},
            .body = "",
            .allocator = allocator,
        };
    }

    /// Set response body
    pub fn set_body(self: *Self, body: []const u8) void {
        self.body = body;
    }

    /// Add header to response
    pub fn add_header(self: *Self, name: []const u8, value: []const u8) HttpError!void {
        const new_headers = try self.allocator.realloc(self.headers, self.headers.len + 1);
        new_headers[new_headers.len - 1] = HttpHeader{
            .name = name,
            .value = value,
        };
        self.headers = new_headers;
    }

    /// Cleanup response resources
    pub fn deinit(self: *Self) void {
        if (self.headers.len > 0) {
            self.allocator.free(self.headers);
        }
    }
};

/// Zero-copy HTTP parser with production-grade performance
pub const HttpParser = struct {
    // Configuration constants
    const MAX_REQUEST_LINE_SIZE = 8192;
    const MAX_HEADER_SIZE = 65536;
    const MAX_HEADERS_COUNT = 100;
    const MAX_URI_SIZE = 4096;

    /// Parse HTTP request from buffer with zero-copy design
    pub fn parse_request(data: []const u8, allocator: std.mem.Allocator) HttpError!HttpRequest {
        if (data.len == 0) return HttpError.IncompleteRequest;

        var request = HttpRequest.init(allocator);
        request.raw_data = data;

        // Find end of headers (double CRLF)
        const headers_end = find_headers_end(data) orelse return HttpError.IncompleteRequest;

        if (headers_end > MAX_HEADER_SIZE) return HttpError.HeadersTooLarge;

        const headers_section = data[0..headers_end];
        const body_start = headers_end + 4; // Skip \r\n\r\n

        // Parse request line
        const request_line_end = std.mem.indexOf(u8, headers_section, "\r\n") orelse return HttpError.MalformedRequest;
        const request_line = headers_section[0..request_line_end];

        if (request_line.len > MAX_REQUEST_LINE_SIZE) return HttpError.HeadersTooLarge;

        try parse_request_line(request_line, &request);

        // Parse headers
        const headers_start = request_line_end + 2; // Skip \r\n
        if (headers_start < headers_section.len) {
            const headers_data = headers_section[headers_start..];
            try parse_headers(headers_data, &request, allocator);
        }

        // Set body (zero-copy reference)
        if (body_start < data.len) {
            request.body = data[body_start..];
        }

        return request;
    }

    /// Find end of HTTP headers (double CRLF)
    fn find_headers_end(data: []const u8) ?usize {
        var i: usize = 0;
        while (i + 3 < data.len) {
            if (data[i] == '\r' and data[i + 1] == '\n' and
                data[i + 2] == '\r' and data[i + 3] == '\n') {
                return i;
            }
            i += 1;
        }
        return null;
    }

    /// Parse HTTP request line (method, URI, version)
    fn parse_request_line(line: []const u8, request: *HttpRequest) HttpError!void {
        // Split by spaces: "GET /path HTTP/1.1"
        var parts = std.mem.split(u8, line, " ");

        // Parse method
        const method_str = parts.next() orelse return HttpError.MalformedRequest;
        request.method = try HttpMethod.parse(method_str);

        // Parse URI
        const uri = parts.next() orelse return HttpError.MalformedRequest;
        if (uri.len > MAX_URI_SIZE) return HttpError.InvalidUri;
        request.uri = uri;

        // Parse version
        const version_str = parts.next() orelse return HttpError.MalformedRequest;
        request.version = try HttpVersion.parse(version_str);

        // Ensure no extra parts
        if (parts.next() != null) return HttpError.MalformedRequest;
    }

    /// Parse HTTP headers with zero-copy design
    fn parse_headers(headers_data: []const u8, request: *HttpRequest, allocator: std.mem.Allocator) HttpError!void {
        var header_lines = std.mem.split(u8, headers_data, "\r\n");
        var headers_list = std.ArrayList(HttpHeader).init(allocator);
        defer headers_list.deinit();

        while (header_lines.next()) |line| {
            if (line.len == 0) break; // End of headers

            if (headers_list.items.len >= MAX_HEADERS_COUNT) {
                return HttpError.TooManyHeaders;
            }

            // Find colon separator
            const colon_pos = std.mem.indexOf(u8, line, ":") orelse return HttpError.InvalidHeader;

            const name = std.mem.trim(u8, line[0..colon_pos], " \t");
            const value = std.mem.trim(u8, line[colon_pos + 1..], " \t");

            if (name.len == 0) return HttpError.InvalidHeader;

            try headers_list.append(HttpHeader{
                .name = name,
                .value = value,
            });
        }

        request.headers = try headers_list.toOwnedSlice();
    }

    /// Serialize HTTP response to writer
    pub fn serialize_response(response: HttpResponse, writer: anytype) HttpError!void {
        // Write status line
        try writer.print("{s} {d} {s}\r\n", .{
            response.version.to_string(),
            @intFromEnum(response.status),
            response.status.reason_phrase(),
        });

        // Write headers
        for (response.headers) |header| {
            try writer.print("{s}: {s}\r\n", .{ header.name, header.value });
        }

        // Add Content-Length if not present and body exists
        if (response.body.len > 0) {
            var has_content_length = false;
            for (response.headers) |header| {
                if (std.ascii.eqlIgnoreCase(header.name, HttpHeader.CONTENT_LENGTH)) {
                    has_content_length = true;
                    break;
                }
            }

            if (!has_content_length) {
                try writer.print("Content-Length: {d}\r\n", .{response.body.len});
            }
        }

        // End headers
        try writer.writeAll("\r\n");

        // Write body
        if (response.body.len > 0) {
            try writer.writeAll(response.body);
        }
    }
};

// =============================================================================
// PERFORMANCE OPTIMIZATIONS
// =============================================================================

/// Fast HTTP method lookup using perfect hash
const METHOD_LOOKUP = std.ComptimeStringMap(HttpMethod, .{
    .{ "GET", .GET },
    .{ "POST", .POST },
    .{ "PUT", .PUT },
    .{ "DELETE", .DELETE },
    .{ "HEAD", .HEAD },
    .{ "OPTIONS", .OPTIONS },
    .{ "PATCH", .PATCH },
    .{ "TRACE", .TRACE },
    .{ "CONNECT", .CONNECT },
});

/// Fast header name comparison (case-insensitive)
pub fn header_equals(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;

    var i: usize = 0;
    while (i < a.len) : (i += 1) {
        if (std.ascii.toLower(a[i]) != std.ascii.toLower(b[i])) {
            return false;
        }
    }
    return true;
}

/// Validate HTTP token characters (RFC 7230)
pub fn is_token_char(c: u8) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '0'...'9',
        '!', '#', '$', '%', '&', '\'', '*',
        '+', '-', '.', '^', '_', '`', '|', '~' => true,
        else => false,
    };
}