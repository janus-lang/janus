// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// lsp-bridge - The Hand for IDE Integration
// Thin LSP server that communicates with janusd for profile-aware IDE support
// Implements Language Server Protocol with Janus profile awareness

const std = @import("std");
const libjanus = @import("libjanus");

const print = std.debug.print;

// LSP Server configuration
const LspConfig = struct {
    janusd_host: []const u8 = "127.0.0.1",
    janusd_port: u16 = 7777,
    log_level: LogLevel = .info,

    const LogLevel = enum {
        debug,
        info,
        warn,
        err,
    };
};

// Project profile information
const ProjectProfile = struct {
    profile: Profile,
    project_root: []const u8,

    const Profile = enum {
        min,
        go,
        full,

        pub fn toString(self: Profile) []const u8 {
            return switch (self) {
                .min => ":min",
                .go => ":go",
                .full => ":full",
            };
        }

        pub fn fromString(s: []const u8) ?Profile {
            if (std.mem.eql(u8, s, ":min") or std.mem.eql(u8, s, "min")) return .min;
            if (std.mem.eql(u8, s, ":go") or std.mem.eql(u8, s, "go")) return .go;
            if (std.mem.eql(u8, s, ":full") or std.mem.eql(u8, s, "full")) return .full;
            return null;
        }
    };
};

// LSP Bridge server
const LspBridge = struct {
    allocator: std.mem.Allocator,
    config: LspConfig,
    current_profile: ?ProjectProfile,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, config: LspConfig) Self {
        return Self{
            .allocator = allocator,
            .config = config,
            .current_profile = null,
        };
    }

    pub fn start(self: *Self) !void {
        print("🔌 Starting lsp-bridge (proxy to janus-lsp-server)\n", .{});
        try self.runProxyLoop();
    }

    fn runProxyLoop(self: *Self) !void {
        var backoff_ms: u64 = 100;
        const max_backoff_ms: u64 = 3000;
        while (true) {
            const restarted = try self.spawnAndProxy();
            if (!restarted) break; // Clean shutdown
            std.time.sleep(backoff_ms * std.time.ns_per_ms);
            backoff_ms = @min(backoff_ms * 2, max_backoff_ms);
            print("♻️  Restarting janus-lsp-server after crash (backoff {} ms)\n", .{backoff_ms});
        }
    }

    fn spawnAndProxy(self: *Self) !bool {
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        const aa = arena.allocator();

        var child = std.process.Child.init(&[_][]const u8{"janus-lsp-server"}, aa);
        child.stdin_behavior = .Pipe;
        child.stdout_behavior = .Pipe;
        child.stderr_behavior = .Pipe;

        print("🚀 Launching janus-lsp-server...\n", .{});
        try child.spawn();

        const child_stdin = child.stdin.?.writer();
        const child_stdout = child.stdout.?.reader();
        const child_stderr = child.stderr.?.reader();

        // Thread 1: pump our stdin -> child stdin
        const t1 = try std.Thread.spawn(.{}, pumpInputToChild, .{child_stdin});
        // Thread 2: pump child stdout -> our stdout
        const t2 = try std.Thread.spawn(.{}, pumpChildToStdout, .{child_stdout});
        // Thread 3: pump child stderr -> our stderr (debug)
        const t3 = try std.Thread.spawn(.{}, pumpChildErrToStderr, .{child_stderr});

        // Wait on child
        const term = child.wait() catch |err| {
            print("❌ janus-lsp-server wait error: {}\n", .{err});
            return true; // restart on error
        };

        // Stop pump threads (they will exit on EOF/closed pipes)
        t1.join();
        t2.join();
        t3.join();

        return switch (term) {
            .Exited => |code| blk: {
                if (code == 0) {
                    print("👋 janus-lsp-server exited cleanly\n", .{});
                    break :blk false;
                } else {
                    print("💥 janus-lsp-server crashed with code {}\n", .{code});
                    break :blk true;
                }
            },
            else => true,
        };
    }

    fn pumpInputToChild(child_stdin: anytype) void {
        var chunk: [8192]u8 = undefined;
        var stdin_reader = std.fs.File.stdin().reader(chunk[0..]);
        while (true) {
            const n = try stdin_reader.read(&chunk);
            if (n == 0) break;
            _ = child_stdin.writeAll(chunk[0..n]) catch break;
        }
    }

    fn pumpChildToStdout(child_stdout: anytype) void {
        const stdout_file = std.fs.File.stdout();
        var buf: [8192]u8 = undefined;
        while (true) {
            const n = try child_stdout.read(buf[0..]);
            if (n == 0) break;
            _ = stdout_file.writeAll(buf[0..n]) catch break;
        }
    }

    fn pumpChildErrToStderr(child_stderr: anytype) void {
        const stderr_file = std.fs.File.stderr();
        var buf: [4096]u8 = undefined;
        while (true) {
            const n = try child_stderr.read(buf[0..]);
            if (n == 0) break;
            _ = stderr_file.writeAll(buf[0..n]) catch break;
        }
    }

    fn handleInitialize(self: *Self, project_path: []const u8) !void {
        print("🔧 Initializing LSP for project: {s}\n", .{project_path});

        // Read janus.kdl to determine active profile
        const profile = try self.readProjectProfile(project_path);
        self.current_profile = profile;

        print("✅ LSP initialized with profile: {s}\n", .{profile.profile.toString()});
    }

    fn handleHover(self: *Self, position: []const u8) !void {
        print("🔍 Hover request at position: {s}\n", .{position});

        if (self.current_profile) |profile| {
            print("📊 Using profile: {s} for hover information\n", .{profile.profile.toString()});

            // TODO: Send request to janusd for hover information
            // const hover_info = try self.requestFromJanusd("hover", position);

            print("✅ Hover response: Function signature (profile-aware)\n", .{});
        } else {
            print("⚠️  No profile loaded - initialize first\n", .{});
        }
    }

    fn handleCompletion(self: *Self, position: []const u8) !void {
        print("💡 Completion request at position: {s}\n", .{position});

        if (self.current_profile) |profile| {
            print("📊 Using profile: {s} for completions\n", .{profile.profile.toString()});

            // Profile-aware completion logic
            switch (profile.profile) {
                .min => {
                    print("✅ Completions: print(), basic types, simple functions\n", .{});
                },
                .go => {
                    print("✅ Completions: print(), goroutines, channels, context\n", .{});
                },
                .full => {
                    print("✅ Completions: print(), capabilities, effects, actors\n", .{});
                },
            }
        } else {
            print("⚠️  No profile loaded - showing basic completions\n", .{});
            print("✅ Completions: print() (basic)\n", .{});
        }
    }

    fn handleDiagnostic(self: *Self, file: []const u8) !void {
        print("🔎 Diagnostic request for file: {s}\n", .{file});

        if (self.current_profile) |profile| {
            print("📊 Using profile: {s} for diagnostics\n", .{profile.profile.toString()});

            // TODO: Send request to janusd for profile-aware diagnostics
            // const diagnostics = try self.requestFromJanusd("diagnostic", file);

            // Profile-aware diagnostic logic
            switch (profile.profile) {
                .min => {
                    print("✅ Diagnostics: Basic syntax, simple type checking\n", .{});
                },
                .go => {
                    print("✅ Diagnostics: Concurrency safety, context usage\n", .{});
                },
                .full => {
                    print("✅ Diagnostics: Capability requirements, effect safety\n", .{});
                },
            }
        } else {
            print("⚠️  No profile loaded - showing basic diagnostics\n", .{});
            print("✅ Diagnostics: Basic syntax only\n", .{});
        }
    }

    fn readProjectProfile(self: *Self, project_path: []const u8) !ProjectProfile {
        // Look for janus.kdl in project root
        var path_buffer: [std.fs.max_path_bytes]u8 = undefined;
        const janus_kdl_path = try std.fmt.bufPrint(path_buffer[0..], "{s}/janus.kdl", .{project_path});

        print("🔍 Looking for profile in: {s}\n", .{janus_kdl_path});

        // Try to read janus.kdl
        const file_content = std.fs.cwd().readFileAlloc(self.allocator, janus_kdl_path, 1024 * 1024) catch |err| {
            print("⚠️  Could not read janus.kdl: {}\n", .{err});
            print("📋 Using default profile: :min\n", .{});

            return ProjectProfile{
                .profile = .min,
                .project_root = try self.allocator.dupe(u8, project_path),
            };
        };
        defer self.allocator.free(file_content);

        // Simple KDL parsing to find profile line
        var lines = std.mem.splitSequence(u8, file_content, "\n");
        while (lines.next()) |line| {
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (std.mem.startsWith(u8, trimmed, "profile ")) {
                // Extract profile value: profile ":go" -> :go
                var profile_line = trimmed[8..]; // Skip "profile "
                profile_line = std.mem.trim(u8, profile_line, " \t\"");

                if (ProjectProfile.Profile.fromString(profile_line)) |profile| {
                    print("✅ Found profile in janus.kdl: {s}\n", .{profile.toString()});

                    return ProjectProfile{
                        .profile = profile,
                        .project_root = try self.allocator.dupe(u8, project_path),
                    };
                }
            }
        }

        print("⚠️  No profile found in janus.kdl, using default: :min\n", .{});
        return ProjectProfile{
            .profile = .min,
            .project_root = try self.allocator.dupe(u8, project_path),
        };
    }

    fn showCurrentProfile(self: *Self) void {
        if (self.current_profile) |profile| {
            print("📊 Current profile: {s}\n", .{profile.profile.toString()});
            print("📁 Project root: {s}\n", .{profile.project_root});
        } else {
            print("⚠️  No profile loaded - run 'initialize <project_path>' first\n", .{});
        }
    }

    fn showHelp(self: *Self) void {
        _ = self;
        print("📚 lsp-bridge - Janus Language Server Protocol Bridge\n\n", .{});
        print("Available LSP methods (test mode):\n", .{});
        print("  initialize <path>    - Initialize LSP with project path\n", .{});
        print("  hover <position>     - Get hover information at position\n", .{});
        print("  completion <pos>     - Get profile-aware completions\n", .{});
        print("  diagnostic <file>    - Get profile-aware diagnostics\n", .{});
        print("  profile              - Show current active profile\n", .{});
        print("  help                 - Show this help message\n", .{});
        print("  exit                 - Stop the LSP server\n\n", .{});
        print("🧠 The LSP server reads janus.kdl for profile configuration\n", .{});
        print("⚡ Completions and diagnostics adapt to active profile\n", .{});
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Parse command line arguments
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var config = LspConfig{};

    // Simple argument parsing
    var i: usize = 1;
    while (i < args.len) {
        if (std.mem.eql(u8, args[i], "--janusd-port") and i + 1 < args.len) {
            config.janusd_port = try std.fmt.parseInt(u16, args[i + 1], 10);
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--janusd-host") and i + 1 < args.len) {
            config.janusd_host = args[i + 1];
            i += 2;
        } else if (std.mem.eql(u8, args[i], "--help") or std.mem.eql(u8, args[i], "-h")) {
            showUsage();
            return;
        } else {
            print("❌ Unknown argument: {s}\n", .{args[i]});
            showUsage();
            return;
        }
    }

    // Create and start LSP bridge
    var lsp_bridge = LspBridge.init(allocator, config);
    try lsp_bridge.start();
}

fn showUsage() void {
    print("lsp-bridge - Janus Language Server Protocol Bridge\n\n", .{});
    print("Usage: lsp-bridge [options]\n\n", .{});
    print("Options:\n", .{});
    print("  --janusd-host <host>  Set janusd host (default: 127.0.0.1)\n", .{});
    print("  --janusd-port <port>  Set janusd port (default: 7777)\n", .{});
    print("  --help, -h            Show this help message\n\n", .{});
    print("The LSP bridge provides profile-aware IDE integration.\n", .{});
    print("It reads janus.kdl for profile configuration and adapts\n", .{});
    print("completions and diagnostics accordingly.\n", .{});
}
