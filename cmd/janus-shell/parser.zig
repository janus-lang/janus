// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// The full text of the license can be found in the LICENSE file at the root of the repository.

//! Command parser for the Janus Shell
//!
//! Implements lexical analysis and parsing to build Command AST from shell input.
//! Follows our doctrine of Syntactic Honesty - no hidden shell magic, everything explicit.

const std = @import("std");
const types = @import("types.zig");

/// Token types for lexical analysis
const TokenType = enum {
    word,
    pipe, // |
    redirect_in, // <
    redirect_out, // >
    redirect_append, // >>
    semicolon, // ;
    ampersand, // &
    newline,
    eof,
};

const Token = struct {
    type: TokenType,
    value: []const u8,
    position: usize,
};

/// Lexical analyzer for shell commands
const Lexer = struct {
    input: []const u8,
    position: usize = 0,
    current_char: ?u8 = null,

    pub fn init(input: []const u8) Lexer {
        const lexer = Lexer{
            .input = input,
            .current_char = if (input.len > 0) input[0] else null,
        };
        return lexer;
    }

    fn advance(self: *Lexer) void {
        self.position += 1;
        if (self.position >= self.input.len) {
            self.current_char = null;
        } else {
            self.current_char = self.input[self.position];
        }
    }

    fn skipWhitespace(self: *Lexer) void {
        while (self.current_char) |ch| {
            if (ch == ' ' or ch == '\t') {
                self.advance();
            } else {
                break;
            }
        }
    }

    fn readWord(self: *Lexer, allocator: std.mem.Allocator) ![]u8 {
        const start = self.position;

        while (self.current_char) |ch| {
            switch (ch) {
                ' ', '\t', '\n', '|', '<', '>', ';', '&' => break,
                else => self.advance(),
            }
        }

        return try allocator.dupe(u8, self.input[start..self.position]);
    }

    pub fn nextToken(self: *Lexer, allocator: std.mem.Allocator) !Token {
        while (self.current_char) |ch| {
            switch (ch) {
                ' ', '\t' => {
                    self.skipWhitespace();
                    continue;
                },
                '\n' => {
                    const pos = self.position;
                    self.advance();
                    return Token{ .type = .newline, .value = "\n", .position = pos };
                },
                '|' => {
                    const pos = self.position;
                    self.advance();
                    return Token{ .type = .pipe, .value = "|", .position = pos };
                },
                '<' => {
                    const pos = self.position;
                    self.advance();
                    return Token{ .type = .redirect_in, .value = "<", .position = pos };
                },
                '>' => {
                    const pos = self.position;
                    self.advance();
                    if (self.current_char == '>') {
                        self.advance();
                        return Token{ .type = .redirect_append, .value = ">>", .position = pos };
                    }
                    return Token{ .type = .redirect_out, .value = ">", .position = pos };
                },
                ';' => {
                    const pos = self.position;
                    self.advance();
                    return Token{ .type = .semicolon, .value = ";", .position = pos };
                },
                '&' => {
                    const pos = self.position;
                    self.advance();
                    return Token{ .type = .ampersand, .value = "&", .position = pos };
                },
                else => {
                    const pos = self.position;
                    const word = try self.readWord(allocator);
                    return Token{ .type = .word, .value = word, .position = pos };
                },
            }
        }

        return Token{ .type = .eof, .value = "", .position = self.position };
    }
};

/// Command parser that builds AST from tokens
pub const Parser = struct {
    allocator: std.mem.Allocator,
    tokens: std.ArrayList(Token),
    current_token_index: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Parser {
        return Parser{
            .allocator = allocator,
            .tokens = .empty,
        };
    }

    pub fn deinit(self: *Parser) void {
        // Free token values
        for (self.tokens.items) |token| {
            if (token.type == .word) {
                self.allocator.free(token.value);
            }
        }
        self.tokens.deinit();
    }

    /// Parse shell input into Command AST
    pub fn parse(self: *Parser, input: []const u8) !types.Command {
        // Clear previous tokens
        for (self.tokens.items) |token| {
            if (token.type == .word) {
                self.allocator.free(token.value);
            }
        }
        self.tokens.clearRetainingCapacity();
        self.current_token_index = 0;

        // Tokenize input
        var lexer = Lexer.init(input);
        while (true) {
            const token = try lexer.nextToken(self.allocator);
            try self.tokens.append(token);
            if (token.type == .eof) break;
        }

        // Parse tokens into command
        return try self.parseCommand();
    }

    fn currentToken(self: *Parser) ?Token {
        if (self.current_token_index >= self.tokens.items.len) return null;
        return self.tokens.items[self.current_token_index];
    }

    fn advance(self: *Parser) void {
        if (self.current_token_index < self.tokens.items.len) {
            self.current_token_index += 1;
        }
    }

    fn parseCommand(self: *Parser) !types.Command {
        // Check for built-in commands first
        if (self.currentToken()) |token| {
            if (token.type == .word) {
                if (self.isBuiltinCommand(token.value)) {
                    return try self.parseBuiltinCommand();
                }
            }
        }

        // Parse as simple command or pipeline
        var commands: std.ArrayList(types.Command) = .empty;
        defer commands.deinit();

        // Parse first command
        try commands.append(try self.parseSimpleCommand());

        // Check for pipeline
        while (self.currentToken()) |token| {
            if (token.type == .pipe) {
                self.advance(); // consume pipe
                try commands.append(try self.parseSimpleCommand());
            } else {
                break;
            }
        }

        if (commands.items.len == 1) {
            return commands.items[0];
        } else {
            return types.Command{
                .pipeline = types.Command.Pipeline{
                    .stages = try self.allocator.dupe(types.Command, commands.items),
                },
            };
        }
    }

    fn parseSimpleCommand(self: *Parser) !types.Command {
        var argv: std.ArrayList([]const u8) = .empty;
        defer argv.deinit();

        var redirections: std.ArrayList(types.Redirection) = .empty;
        defer redirections.deinit();

        // Parse command and arguments
        while (self.currentToken()) |token| {
            switch (token.type) {
                .word => {
                    try argv.append(try self.allocator.dupe(u8, token.value));
                    self.advance();
                },
                .redirect_in => {
                    self.advance();
                    if (self.currentToken()) |path_token| {
                        if (path_token.type == .word) {
                            try redirections.append(types.Redirection{
                                .input = try self.allocator.dupe(u8, path_token.value),
                            });
                            self.advance();
                        } else {
                            return types.ShellError.ParseError;
                        }
                    } else {
                        return types.ShellError.ParseError;
                    }
                },
                .redirect_out => {
                    self.advance();
                    if (self.currentToken()) |path_token| {
                        if (path_token.type == .word) {
                            try redirections.append(types.Redirection{
                                .output = types.Redirection.OutputSpec{
                                    .path = try self.allocator.dupe(u8, path_token.value),
                                    .append = false,
                                },
                            });
                            self.advance();
                        } else {
                            return types.ShellError.ParseError;
                        }
                    } else {
                        return types.ShellError.ParseError;
                    }
                },
                .redirect_append => {
                    self.advance();
                    if (self.currentToken()) |path_token| {
                        if (path_token.type == .word) {
                            try redirections.append(types.Redirection{
                                .output = types.Redirection.OutputSpec{
                                    .path = try self.allocator.dupe(u8, path_token.value),
                                    .append = true,
                                },
                            });
                            self.advance();
                        } else {
                            return types.ShellError.ParseError;
                        }
                    } else {
                        return types.ShellError.ParseError;
                    }
                },
                else => break,
            }
        }

        if (argv.items.len == 0) {
            return types.ShellError.ParseError;
        }

        const process_spec = types.ProcessSpec{
            .argv = try self.allocator.dupe([]const u8, argv.items),
            .required_capabilities = &.{.proc_spawn}, // Basic capability
        };

        return types.Command{
            .simple = types.Command.SimpleCommand{
                .spec = process_spec,
                .redirections = try self.allocator.dupe(types.Redirection, redirections.items),
            },
        };
    }

    fn parseBuiltinCommand(self: *Parser) !types.Command {
        const name_token = self.currentToken().?;
        self.advance();

        var args: std.ArrayList([]const u8) = .empty;
        defer args.deinit();

        // Parse arguments
        while (self.currentToken()) |token| {
            if (token.type == .word) {
                try args.append(try self.allocator.dupe(u8, token.value));
                self.advance();
            } else {
                break;
            }
        }

        return types.Command{
            .builtin = types.Command.BuiltinCommand{
                .name = try self.allocator.dupe(u8, name_token.value),
                .args = try self.allocator.dupe([]const u8, args.items),
            },
        };
    }

    fn isBuiltinCommand(self: *Parser, name: []const u8) bool {
        _ = self;
        const builtins = [_][]const u8{
            "cd", "pwd", "exit", "help", "set", "unset", "export", "history", "caps",
        };

        for (builtins) |builtin| {
            if (std.mem.eql(u8, name, builtin)) {
                return true;
            }
        }
        return false;
    }
};
