// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Janus Compilation Pipeline
//
// This module provides the unified compilation pipeline used by both
// the CLI and integration tests. It ensures consistency across all
// compilation paths.
//
// Pipeline Stages:
// 1. Parse: Source → ASTDB
// 2. Lower: ASTDB → QTJIR
// 3. Emit: QTJIR → LLVM IR
// 4. Compile: LLVM IR → Object File
// 5. Link: Object File + Runtime → Executable

const std = @import("std");
const compat_fs = @import("compat_fs");
const janus_lib = @import("janus_lib");
const janus_parser = janus_lib.parser;
const qtjir = @import("qtjir");
const astdb_core = @import("astdb_core");

/// Result from running a child process (compat shim for 0.16 Io-based API).
const CmdResult = struct {
    term: Term,
    stdout: []u8,
    stderr: []u8,

    const Term = union(enum) { Exited: u8, other };
};

/// Run a command using 0.16's Io-threaded process API.
fn runCmd(allocator: std.mem.Allocator, argv: []const []const u8) !CmdResult {
    const io = std.Io.Threaded.global_single_threaded.io();
    const result = try std.process.run(allocator, io, .{ .argv = argv });
    const exit_code: u8 = switch (result.term) {
        .exited => |code| code,
        else => 255,
    };
    return CmdResult{
        .term = .{ .Exited = exit_code },
        .stdout = result.stdout,
        .stderr = result.stderr,
    };
}

/// Embedded Zig runtime source - Maximum Sovereignty
/// The compiler is self-contained and carries its own pure Zig runtime.
/// Imported from runtime/ directory via build.zig anonymous import.
const janus_runtime_embed = @import("janus_runtime_embed");
const RUNTIME_SOURCE_ZIG = janus_runtime_embed.source;

/// Compilation result
pub const CompilationResult = struct {
    executable_path: []const u8,
    llvm_ir: ?[]const u8 = null, // Optional, for debugging

    pub fn deinit(self: *CompilationResult, allocator: std.mem.Allocator) void {
        allocator.free(self.executable_path);
        if (self.llvm_ir) |ir| {
            allocator.free(ir);
        }
    }
};

/// Compilation options
pub const CompileOptions = struct {
    source_path: []const u8,
    output_path: ?[]const u8 = null, // If null, derives from source_path
    emit_llvm_ir: bool = false, // Save LLVM IR to .ll file
    verbose: bool = false,
    /// Path to runtime directory containing janus_rt.zig and scheduler/
    /// If null, attempts to use embedded source (deprecated, won't work with scheduler)
    runtime_dir: ?[]const u8 = null,
};

/// Compilation error types
pub const CompileError = error{
    ParseFailed,
    LoweringFailed,
    EmitFailed,
    LLCFailed,
    LinkFailed,
    ExecutionFailed,
    OutOfMemory,
    FileNotFound,
    InvalidSource,
};

/// The Compilation Pipeline
pub const Pipeline = struct {
    allocator: std.mem.Allocator,
    options: CompileOptions,

    pub fn init(allocator: std.mem.Allocator, options: CompileOptions) Pipeline {
        return Pipeline{
            .allocator = allocator,
            .options = options,
        };
    }

    /// Execute the full compilation pipeline
    pub fn compile(self: *Pipeline) !CompilationResult {
        const allocator = self.allocator;

        // ========== STAGE 1: READ SOURCE ==========
        if (self.options.verbose) {
            std.debug.print("Reading source: {s}\n", .{self.options.source_path});
        }

        const source = compat_fs.readFileAlloc(
            allocator,
            self.options.source_path,
            10 * 1024 * 1024, // 10MB max
        ) catch |err| {
            std.debug.print("Error reading source file: {s}\n", .{@errorName(err)});
            return CompileError.FileNotFound;
        };
        defer allocator.free(source);

        // ========== STAGE 2: PARSE SOURCE → ASTDB ==========
        if (self.options.verbose) {
            std.debug.print("Parsing source...\n", .{});
        }

        var parser = janus_parser.Parser.init(allocator);
        defer parser.deinit();

        const snapshot = parser.parseWithSource(source) catch |err| {
            std.debug.print("Parse error: {s}\n", .{@errorName(err)});
            return CompileError.ParseFailed;
        };
        defer snapshot.deinit();

        if (snapshot.nodeCount() == 0) {
            std.debug.print("Error: No AST nodes generated\n", .{});
            return CompileError.InvalidSource;
        }

        // ========== STAGE 3: LOWER ASTDB → QTJIR ==========
        if (self.options.verbose) {
            std.debug.print("Lowering to QTJIR...\n", .{});
        }

        // Get source directory for resolving `use zig` relative paths
        const source_dir = std.fs.path.dirname(self.options.source_path);

        const unit_id: astdb_core.UnitId = @enumFromInt(0);
        var lowering_result = qtjir.lowerUnitWithExterns(allocator, &snapshot.core_snapshot, unit_id, source_dir) catch |err| {
            std.debug.print("Lowering error: {s}\n", .{@errorName(err)});
            return CompileError.LoweringFailed;
        };
        defer lowering_result.deinit(allocator);

        if (lowering_result.graphs.items.len == 0) {
            std.debug.print("Error: No functions generated\n", .{});
            return CompileError.LoweringFailed;
        }

        // ========== STAGE 4: EMIT QTJIR → LLVM IR ==========
        if (self.options.verbose) {
            std.debug.print("Emitting LLVM IR...\n", .{});
        }

        var emitter = qtjir.llvm_emitter.LLVMEmitter.init(allocator, "janus_module") catch |err| {
            std.debug.print("LLVM emitter init error: {s}\n", .{@errorName(err)});
            return CompileError.EmitFailed;
        };
        defer emitter.deinit();

        // Set extern registry for native Zig function resolution
        emitter.setExternRegistry(&lowering_result.extern_registry);

        emitter.emit(lowering_result.graphs.items) catch |err| {
            std.debug.print("LLVM emit error: {s}\n", .{@errorName(err)});
            return CompileError.EmitFailed;
        };

        const llvm_ir = emitter.toString() catch |err| {
            std.debug.print("LLVM toString error: {s}\n", .{@errorName(err)});
            return CompileError.EmitFailed;
        };
        defer allocator.free(llvm_ir);

        // ========== STAGE 5: COMPILE LLVM IR → OBJECT FILE ==========
        // Create temporary directory for intermediate files
        const pid = std.os.linux.getpid();
        const tmp_path = try std.fmt.allocPrint(allocator, "/tmp/janus-compile-{d}", .{pid});
        defer allocator.free(tmp_path);
        compat_fs.makeDir(tmp_path) catch {}; // ignore if exists
        defer compat_fs.deleteTree(tmp_path) catch {};

        // Write LLVM IR to file
        const ir_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.ll" });
        defer allocator.free(ir_file_path);

        try compat_fs.writeFile(ir_file_path, llvm_ir);

        if (self.options.verbose) {
            std.debug.print("Compiling LLVM IR to object file...\n", .{});
        }

        // Compile to object file using llc
        const obj_file_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "output.o" });
        defer allocator.free(obj_file_path);

        const llc_result = try runCmd(allocator, &[_][]const u8{
            "llc",
            "-filetype=obj",
            ir_file_path,
            "-o",
            obj_file_path,
        });
        defer allocator.free(llc_result.stdout);
        defer allocator.free(llc_result.stderr);

        switch (llc_result.term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("LLC failed:\n{s}\n", .{llc_result.stderr});
                    return CompileError.LLCFailed;
                }
            },
            else => return CompileError.LLCFailed,
        }

        // ========== STAGE 6: COMPILE ZIG RUNTIME → OBJECT FILE ==========
        if (self.options.verbose) {
            std.debug.print("Compiling Zig runtime...\n", .{});
        }

        // Compile janus_rt.zig to object file
        const runtime_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "janus_rt.o" });
        defer allocator.free(runtime_obj_path);

        // Determine runtime source path - prefer source tree for scheduler support
        var runtime_source_path_owned: ?[]const u8 = null;
        defer if (runtime_source_path_owned) |p| allocator.free(p);

        const runtime_source_path = if (self.options.runtime_dir) |runtime_dir| blk: {
            // Use source tree path (supports scheduler imports)
            const path = try std.fs.path.join(allocator, &[_][]const u8{ runtime_dir, "janus_rt.zig" });
            runtime_source_path_owned = path;
            break :blk path;
        } else blk: {
            // Fallback: write embedded source to temp (won't work with scheduler)
            const path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "janus_rt.zig" });
            runtime_source_path_owned = path;
            try compat_fs.writeFile(path, RUNTIME_SOURCE_ZIG);
            break :blk path;
        };

        // Create the -femit-bin argument
        const emit_bin_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{runtime_obj_path});
        defer allocator.free(emit_bin_arg);

        const zig_compile_result = try runCmd(allocator, &[_][]const u8{
            "zig",
            "build-obj",
            runtime_source_path,
            "-O",
            "ReleaseSafe",
            "-fno-stack-check",
            "-lc",
            emit_bin_arg,
        });
        defer allocator.free(zig_compile_result.stdout);
        defer allocator.free(zig_compile_result.stderr);

        switch (zig_compile_result.term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("Zig runtime compilation failed:\n{s}\n", .{zig_compile_result.stderr});
                    return CompileError.LinkFailed;
                }
            },
            else => return CompileError.LinkFailed,
        }

        // ========== STAGE 6a: COMPILE CONTEXT SWITCH ASSEMBLY (CBC-MN) ==========
        // The scheduler requires x86_64 assembly for fiber context switching
        var asm_obj_path: ?[]const u8 = null;
        defer if (asm_obj_path) |p| allocator.free(p);

        if (self.options.runtime_dir) |runtime_dir| {
            const asm_source_path = try std.fs.path.join(allocator, &[_][]const u8{ runtime_dir, "scheduler", "context_switch.s" });
            defer allocator.free(asm_source_path);

            // Check if assembly file exists
            _ = compat_fs.statFile(asm_source_path) catch {
                // Assembly file not found - scheduler fiber support disabled
                if (self.options.verbose) {
                    std.debug.print("Note: context_switch.s not found, fiber support disabled\n", .{});
                }
            };

            // Compile assembly to object file
            const asm_obj = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "context_switch.o" });
            asm_obj_path = asm_obj;

            const asm_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{asm_obj});
            defer allocator.free(asm_emit_arg);

            if (self.options.verbose) {
                std.debug.print("Compiling context switch assembly...\n", .{});
            }

            const asm_compile_result = try runCmd(allocator, &[_][]const u8{
                "zig",
                "build-obj",
                asm_source_path,
                asm_emit_arg,
            });
            defer allocator.free(asm_compile_result.stdout);
            defer allocator.free(asm_compile_result.stderr);

            switch (asm_compile_result.term) {
                .Exited => |code| {
                    if (code != 0) {
                        std.debug.print("Assembly compilation failed:\n{s}\n", .{asm_compile_result.stderr});
                        return CompileError.LinkFailed;
                    }
                },
                else => return CompileError.LinkFailed,
            }
        }

        // ========== STAGE 6b: COMPILE ZIG MODULES FROM `use zig` ==========
        var zig_module_objs = std.ArrayListUnmanaged([]const u8){};
        defer {
            for (zig_module_objs.items) |path| allocator.free(path);
            zig_module_objs.deinit(allocator);
        }

        // Get registered Zig module paths from extern registry
        if (self.options.verbose) {
            std.debug.print("Registered Zig paths: {d}\n", .{lowering_result.extern_registry.registered_paths.count()});
        }
        var path_it = lowering_result.extern_registry.registered_paths.keyIterator();
        while (path_it.next()) |zig_path| {
            if (self.options.verbose) {
                std.debug.print("Compiling Zig module: {s}\n", .{zig_path.*});
            }

            // Create unique object file name
            const basename = std.fs.path.basename(zig_path.*);
            const name_without_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
                basename[0..idx]
            else
                basename;
            const module_obj_name = try std.fmt.allocPrint(allocator, "{s}.o", .{name_without_ext});
            defer allocator.free(module_obj_name);

            const module_obj_path = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, module_obj_name });
            try zig_module_objs.append(allocator, module_obj_path);

            const module_emit_arg = try std.fmt.allocPrint(allocator, "-femit-bin={s}", .{module_obj_path});
            defer allocator.free(module_emit_arg);

            const module_compile_result = try runCmd(allocator, &[_][]const u8{
                "zig",
                "build-obj",
                zig_path.*,
                "-O",
                "ReleaseSafe",
                "-fno-stack-check",
                "-lc",
                module_emit_arg,
            });
            defer allocator.free(module_compile_result.stdout);
            defer allocator.free(module_compile_result.stderr);

            switch (module_compile_result.term) {
                .Exited => |code| {
                    if (code != 0) {
                        std.debug.print("Zig module compilation failed ({s}):\n{s}\n", .{ zig_path.*, module_compile_result.stderr });
                        return CompileError.LinkFailed;
                    }
                },
                else => return CompileError.LinkFailed,
            }
        }

        // ========== STAGE 7: LINK OBJECT FILES → EXECUTABLE ==========
        if (self.options.verbose) {
            std.debug.print("Linking executable...\n", .{});
        }

        // Determine output path
        const output_path = if (self.options.output_path) |path|
            try allocator.dupe(u8, path)
        else blk: {
            // Derive from source path: hello.jan → hello
            const basename = std.fs.path.basename(self.options.source_path);
            const name_without_ext = if (std.mem.lastIndexOf(u8, basename, ".")) |idx|
                basename[0..idx]
            else
                basename;
            break :blk try allocator.dupe(u8, name_without_ext);
        };

        // Build link arguments: main object + runtime + asm + all zig modules
        var link_argv = std.ArrayListUnmanaged([]const u8){};
        defer link_argv.deinit(allocator);
        try link_argv.append(allocator, "cc");
        try link_argv.append(allocator, obj_file_path);
        try link_argv.append(allocator, runtime_obj_path);
        // Include context switch assembly for CBC-MN scheduler fiber support
        if (asm_obj_path) |asm_obj| {
            try link_argv.append(allocator, asm_obj);
        }
        for (zig_module_objs.items) |mod_obj| {
            try link_argv.append(allocator, mod_obj);
        }
        try link_argv.append(allocator, "-o");
        try link_argv.append(allocator, output_path);

        // Link with cc (still needed for startup code)
        const link_result = try runCmd(allocator, link_argv.items);
        defer allocator.free(link_result.stdout);
        defer allocator.free(link_result.stderr);

        switch (link_result.term) {
            .Exited => |code| {
                if (code != 0) {
                    std.debug.print("Linker failed:\n{s}\n", .{link_result.stderr});
                    allocator.free(output_path);
                    return CompileError.LinkFailed;
                }
            },
            else => {
                allocator.free(output_path);
                return CompileError.LinkFailed;
            },
        }

        // ========== STAGE 7: OPTIONALLY SAVE LLVM IR ==========
        var saved_llvm_ir: ?[]const u8 = null;
        if (self.options.emit_llvm_ir) {
            const ir_output_path = try std.fmt.allocPrint(allocator, "{s}.ll", .{output_path});
            defer allocator.free(ir_output_path);

            try compat_fs.writeFile(ir_output_path, llvm_ir);
            saved_llvm_ir = try allocator.dupe(u8, llvm_ir);

            if (self.options.verbose) {
                std.debug.print("LLVM IR saved to: {s}\n", .{ir_output_path});
            }
        }

        if (self.options.verbose) {
            std.debug.print("✅ Compilation successful: {s}\n", .{output_path});
        }

        return CompilationResult{
            .executable_path = output_path,
            .llvm_ir = saved_llvm_ir,
        };
    }
};
