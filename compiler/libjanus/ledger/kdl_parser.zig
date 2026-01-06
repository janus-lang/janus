// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const manifest = @import("manifest.zig");

// KDL Parser for janus.pkg files
//
// KDL (KubeConf Document Language) is a human-friendly configuration format
// that's perfect for package manifests. This parser implements a subset of KDL
// sufficient for Janus package manifests.
//
// Example janus.pkg:
// ```
// name "my-package"
// version "1.0.0"
//
// dependency "crypto" {
//     git "https://github.com/example/crypto.git" tag="v2.1.0"
//     capability "fs" path="./data"
//     capability "net" hosts=["api.example.com"]
// }
// ```

pub const KDLError = error{
    UnexpectedToken,
    UnexpectedEOF,
    InvalidString,
    InvalidNumber,
    Invalidentifier,
    OutOfMemory,
};

pub const TokenType = enum {
    identifier,
    string,
    number,
    left_brace,
    right_brace,
    left_bracket,
    right_bracket,
    equals,
    semicolon,
    eof,
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
    line: u32,
    column: u32,
};

pub const Lexer = struct {
    input: []const u8,
    position: usize,
    line: u32,
    column: u32,

    pub fn init(input: []const u8) Lexer {
        return Lexer{
            .input = input,
            .position = 0,
            .line = 1,
            .column = 1,
        };
    }

    pub fn nextToken(self: *Lexer) KDLError!Token {
        self.skipWhitespace();

        if (self.position >= self.input.len) {
            return Token{
                .type = .eof,
                .value = "",
                .line = self.line,
                .column = self.column,
            };
        }

        const start_line = self.line;
        const start_column = self.column;
        const ch = self.input[self.position];

        switch (ch) {
            '{' => {
                self.advance();
                return Token{
                    .type = .left_brace,
                    .value = "{",
                    .line = start_line,
                    .column = start_column,
                };
            },
            '}' => {
                self.advance();
                return Token{
                    .type = .right_brace,
                    .value = "}",
                    .line = start_line,
                    .column = start_column,
                };
            },
            '[' => {
                self.advance();
                return Token{
                    .type = .left_bracket,
                    .value = "[",
                    .line = start_line,
                    .column = start_column,
                };
            },
            ']' => {
                self.advance();
                return Token{
                    .type = .right_bracket,
                    .value = "]",
                    .line = start_line,
                    .column = start_column,
                };
            },
            '=' => {
                self.advance();
                return Token{
                    .type = .equals,
                    .value = "=",
                    .line = start_line,
                    .column = start_column,
                };
            },
            ';' => {
                self.advance();
                return Token{
                    .type = .semicolon,
                    .value = ";",
                    .line = start_line,
                    .column = start_column,
                };
            },
            '"' => {
                return self.readString();
            },
            else => {
                if (std.ascii.isAlphabetic(ch) or ch == '_') {
                    return self.readIdentifier();
                } else if (std.ascii.isDigit(ch)) {
                    return self.readNumber();
                } else {
                    return KDLError.UnexpectedToken;
                }
            },
        }
    }

    fn advance(self: *Lexer) void {
        if (self.position < self.input.len) {
            if (self.input[self.position] == '\n') {
                self.line += 1;
                self.column = 1;
            } else {
                self.column += 1;
            }
            self.position += 1;
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.position < self.input.len) {
            const ch = self.input[self.position];
            if (std.ascii.isWhitespace(ch)) {
                self.advance();
            } else if (ch == '/' and self.position + 1 < self.input.len and self.input[self.position + 1] == '/') {
                // Skip line comment
                while (self.position < self.input.len and self.input[self.position] != '\n') {
                    self.advance();
                }
            } else {
                break;
            }
        }
    }

    fn readString(self: *Lexer) KDLError!Token {
        const start_line = self.line;
        const start_column = self.column;
        const start_pos = self.position;

        self.advance(); // Skip opening quote

        while (self.position < self.input.len and self.input[self.position] != '"') {
            if (self.input[self.position] == '\\') {
                self.advance(); // Skip escape character
                if (self.position < self.input.len) {
                    self.advance(); // Skip escaped character
                }
            } else {
                self.advance();
            }
        }

        if (self.position >= self.input.len) {
            return KDLError.UnexpectedEOF;
        }

        self.advance(); // Skip closing quote

        return Token{
            .type = .string,
            .value = self.input[start_pos..self.position],
            .line = start_line,
            .column = start_column,
        };
    }

    fn readIdentifier(self: *Lexer) KDLError!Token {
        const start_line = self.line;
        const start_column = self.column;
        const start_pos = self.position;

        while (self.position < self.input.len) {
            const ch = self.input[self.position];
            if (std.ascii.isAlphanumeric(ch) or ch == '_' or ch == '-') {
                self.advance();
            } else {
                break;
            }
        }

        return Token{
            .type = .identifier,
            .value = self.input[start_pos..self.position],
            .line = start_line,
            .column = start_column,
        };
    }

    fn readNumber(self: *Lexer) KDLError!Token {
        const start_line = self.line;
        const start_column = self.column;
        const start_pos = self.position;

        while (self.position < self.input.len) {
            const ch = self.input[self.position];
            if (std.ascii.isDigit(ch) or ch == '.') {
                self.advance();
            } else {
                break;
            }
        }

        return Token{
            .type = .number,
            .value = self.input[start_pos..self.position],
            .line = start_line,
            .column = start_column,
        };
    }
};

pub const Parser = struct {
    lexer: Lexer,
    current_token: Token,
    allocator: std.mem.Allocator,

    pub fn init(input: []const u8, allocator: std.mem.Allocator) KDLError!Parser {
        var lexer = Lexer.init(input);
        const first_token = try lexer.nextToken();

        return Parser{
            .lexer = lexer,
            .current_token = first_token,
            .allocator = allocator,
        };
    }

    pub fn parseManifest(self: *Parser) !manifest.Manifest {
        var result = manifest.Manifest.init(self.allocator);
        var dependencies = std.ArrayList(manifest.PackageRef).init(self.allocator);
        var dev_dependencies = std.ArrayList(manifest.PackageRef).init(self.allocator);

        while (self.current_token.type != .eof) {
            if (std.mem.eql(u8, self.current_token.value, "name")) {
                try self.advance();
                if (self.current_token.type != .string) {
                    return KDLError.UnexpectedToken;
                }
                result.name = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
                try self.advance();
            } else if (std.mem.eql(u8, self.current_token.value, "version")) {
                try self.advance();
                if (self.current_token.type != .string) {
                    return KDLError.UnexpectedToken;
                }
                result.version = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
                try self.advance();
            } else if (std.mem.eql(u8, self.current_token.value, "dependency")) {
                const dep = try self.parseDependency();
                try dependencies.append(dep);
            } else if (std.mem.eql(u8, self.current_token.value, "dev-dependency")) {
                const dep = try self.parseDependency();
                try dev_dependencies.append(dep);
            } else {
                // Skip unknown top-level items
                try self.advance();
            }
        }

        result.dependencies = try dependencies.toOwnedSlice();
        result.dev_dependencies = try dev_dependencies.toOwnedSlice();

        return result;
    }

    fn parseDependency(self: *Parser) !manifest.PackageRef {
        try self.advance(); // Skip "dependency" or "dev-dependency"

        if (self.current_token.type != .string) {
            return KDLError.UnexpectedToken;
        }

        const name = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
        try self.advance();

        if (self.current_token.type != .left_brace) {
            return KDLError.UnexpectedToken;
        }
        try self.advance();

        var source: ?manifest.PackageRef.Source = null;
        var capabilities = std.ArrayList(manifest.Capability).init(self.allocator);

        while (self.current_token.type != .right_brace) {
            if (std.mem.eql(u8, self.current_token.value, "git")) {
                source = try self.parseGitSource();
            } else if (std.mem.eql(u8, self.current_token.value, "tar")) {
                source = try self.parseTarSource();
            } else if (std.mem.eql(u8, self.current_token.value, "path")) {
                source = try self.parsePathSource();
            } else if (std.mem.eql(u8, self.current_token.value, "capability")) {
                const cap = try self.parseCapability();
                try capabilities.append(cap);
            } else {
                // Skip unknown dependency properties
                try self.advance();
            }
        }

        try self.advance(); // Skip closing brace

        if (source == null) {
            return KDLError.UnexpectedToken; // Dependency must have a source
        }

        return manifest.PackageRef{
            .name = name,
            .source = source.?,
            .capabilities = try capabilities.toOwnedSlice(),
        };
    }

    fn parseGitSource(self: *Parser) !manifest.PackageRef.Source {
        try self.advance(); // Skip "git"

        if (self.current_token.type != .string) {
            return KDLError.UnexpectedToken;
        }

        const url = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
        try self.advance();

        // Look for tag, branch, or commit
        var ref: []const u8 = "main"; // default

        if (self.current_token.type == .identifier) {
            if (std.mem.eql(u8, self.current_token.value, "tag") or
                std.mem.eql(u8, self.current_token.value, "branch") or
                std.mem.eql(u8, self.current_token.value, "commit"))
            {
                try self.advance();
                if (self.current_token.type == .equals) {
                    try self.advance();
                }
                if (self.current_token.type != .string) {
                    return KDLError.UnexpectedToken;
                }
                ref = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
                try self.advance();
            }
        }

        return manifest.PackageRef.Source{
            .git = .{
                .url = url,
                .ref = ref,
            },
        };
    }

    fn parseTarSource(self: *Parser) !manifest.PackageRef.Source {
        try self.advance(); // Skip "tar"

        if (self.current_token.type != .string) {
            return KDLError.UnexpectedToken;
        }

        const url = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
        try self.advance();

        var checksum: ?[]const u8 = null;

        if (self.current_token.type == .identifier and std.mem.eql(u8, self.current_token.value, "checksum")) {
            try self.advance();
            if (self.current_token.type == .equals) {
                try self.advance();
            }
            if (self.current_token.type != .string) {
                return KDLError.UnexpectedToken;
            }
            checksum = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
            try self.advance();
        }

        return manifest.PackageRef.Source{
            .tar = .{
                .url = url,
                .checksum = checksum,
            },
        };
    }

    fn parsePathSource(self: *Parser) !manifest.PackageRef.Source {
        try self.advance(); // Skip "path"

        if (self.current_token.type != .string) {
            return KDLError.UnexpectedToken;
        }

        const path = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
        try self.advance();

        return manifest.PackageRef.Source{
            .path = .{
                .path = path,
            },
        };
    }

    fn parseCapability(self: *Parser) !manifest.Capability {
        try self.advance(); // Skip "capability"

        if (self.current_token.type != .string) {
            return KDLError.UnexpectedToken;
        }

        var cap = manifest.Capability.init(self.allocator);
        cap.name = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
        try self.advance();

        // Parse capability parameters
        while (self.current_token.type == .identifier) {
            const param_name = try self.allocator.dupe(u8, self.current_token.value);
            try self.advance();

            if (self.current_token.type == .equals) {
                try self.advance();
            }

            if (self.current_token.type == .string) {
                const param_value = try self.allocator.dupe(u8, self.unquoteString(self.current_token.value));
                try cap.params.put(param_name, param_value);
                try self.advance();
            } else {
                return KDLError.UnexpectedToken;
            }
        }

        return cap;
    }

    fn advance(self: *Parser) !void {
        self.current_token = try self.lexer.nextToken();
    }

    fn unquoteString(_: *Parser, quoted: []const u8) []const u8 {
        if (quoted.len >= 2 and quoted[0] == '"' and quoted[quoted.len - 1] == '"') {
            return quoted[1 .. quoted.len - 1];
        }
        return quoted;
    }
};

// Public API for parsing KDL manifests
pub fn parseManifest(input: []const u8, allocator: std.mem.Allocator) !manifest.Manifest {
    var parser = try Parser.init(input, allocator);
    return try parser.parseManifest();
}
