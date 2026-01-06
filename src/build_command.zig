// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Build Command
//
// Implements the `janus build` subcommand that compiles Janus source
// files to native executables.
//
// Usage:
//   janus build <source.jan>
//   janus build <source.jan> -o <output>
//   janus build <source.jan> --emit-llvm
//   janus build <source.jan> --verbose

const std = @import("std");
const pipeline = @import("pipeline.zig");

/// Build command options
pub const BuildOptions = struct {
    source_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    emit_llvm: bool = false,
    verbose: bool = false,
    help: bool = false,
};

/// Parse command-line arguments for build command
pub fn parseArgs(args: []const []const u8) !BuildOptions {
    var options = BuildOptions{};
    
    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            options.help = true;
        } else if (std.mem.eql(u8, arg, "--verbose") or std.mem.eql(u8, arg, "-v")) {
            options.verbose = true;
        } else if (std.mem.eql(u8, arg, "--emit-llvm")) {
            options.emit_llvm = true;
        } else if (std.mem.eql(u8, arg, "-o") or std.mem.eql(u8, arg, "--output")) {
            i += 1;
            if (i >= args.len) {
                std.debug.print("Error: -o/--output requires an argument\n", .{});
                return error.InvalidArguments;
            }
            options.output_path = args[i];
        } else if (std.mem.startsWith(u8, arg, "-")) {
            std.debug.print("Error: Unknown option: {s}\n", .{arg});
            return error.InvalidArguments;
        } else {
            // Positional argument - source file
            if (options.source_path != null) {
                std.debug.print("Error: Multiple source files specified\n", .{});
                return error.InvalidArguments;
            }
            options.source_path = arg;
        }
    }
    
    return options;
}

/// Print help message
pub fn printHelp() void {
    const help_text =
        \\Usage: janus build [options] <source.jan>
        \\
        \\Compile a Janus source file to a native executable.
        \\
        \\Options:
        \\  -o, --output <path>    Output executable path (default: derived from source)
        \\  --emit-llvm            Save LLVM IR to <output>.ll
        \\  -v, --verbose          Show compilation progress
        \\  -h, --help             Show this help message
        \\
        \\Examples:
        \\  janus build hello.jan
        \\  janus build hello.jan -o my_program
        \\  janus build hello.jan --emit-llvm --verbose
        \\
    ;
    std.debug.print("{s}", .{help_text});
}

/// Execute the build command
pub fn execute(allocator: std.mem.Allocator, args: []const []const u8) !u8 {
    const options = parseArgs(args) catch {
        printHelp();
        return 1;
    };
    
    if (options.help) {
        printHelp();
        return 0;
    }
    
    if (options.source_path == null) {
        std.debug.print("Error: No source file specified\n\n", .{});
        printHelp();
        return 1;
    }
    
    const source_path = options.source_path.?;
    
    // Verify source file exists
    std.fs.cwd().access(source_path, .{}) catch {
        std.debug.print("Error: Source file not found: {s}\n", .{source_path});
        return 1;
    };
    
    // Create pipeline
    var compiler = pipeline.Pipeline.init(allocator, .{
        .source_path = source_path,
        .output_path = options.output_path,
        .emit_llvm_ir = options.emit_llvm,
        .verbose = options.verbose,
    });
    
    // Compile
    if (!options.verbose) {
        std.debug.print("Compiling {s}...\n", .{source_path});
    }
    
    var result = compiler.compile() catch |err| {
        std.debug.print("Compilation failed: {s}\n", .{@errorName(err)});
        return 1;
    };
    defer result.deinit(allocator);
    
    std.debug.print("✅ Executable: {s}\n", .{result.executable_path});
    
    return 0;
}
