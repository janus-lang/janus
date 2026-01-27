// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const cache_support = @import("build_support/global_cache.zig");
const global_cache = @import("build_support/global_cache.zig");

fn ensureWritableGlobalCache(b: *std.Build) void {
    if (globalCacheWritable(b)) return;

    const local_cache = cache_support.ensureLocalGlobalCache(b.cache_root, b.allocator, "global-cache") catch |err| {
        std.debug.panic("failed to prepare local global cache: {s}", .{@errorName(err)});
    };
    applyGlobalCacheOverride(b, local_cache);
}

fn globalCacheWritable(b: *std.Build) bool {
    const probe_name = "janus-cache-write-probe";
    var file = b.graph.global_cache_root.handle.createFile(probe_name, .{}) catch {
        return false;
    };
    file.close();
    b.graph.global_cache_root.handle.deleteFile(probe_name) catch {};
    return true;
}

fn applyGlobalCacheOverride(b: *std.Build, new_cache: cache_support.CacheDirectory) void {
    const old_cache = b.graph.global_cache_root;
    b.graph.global_cache_root = new_cache;

    var replaced = false;
    var i: usize = 0;
    while (i < b.graph.cache.prefixes_len) : (i += 1) {
        const prefix_ptr = &b.graph.cache.prefixes_buffer[i];
        if (directoriesEqual(prefix_ptr.*, old_cache)) {
            prefix_ptr.* = new_cache;
            replaced = true;
            break;
        }
    }
    if (!replaced and b.graph.cache.prefixes_len < b.graph.cache.prefixes_buffer.len) {
        b.graph.cache.prefixes_buffer[b.graph.cache.prefixes_len] = new_cache;
        b.graph.cache.prefixes_len += 1;
    }

    var old_handle = old_cache.handle;
    old_handle.close();
}

fn directoriesEqual(a: cache_support.CacheDirectory, bdir: cache_support.CacheDirectory) bool {
    if (a.handle.fd == bdir.handle.fd) return true;
    if (a.path) |ap| {
        if (bdir.path) |bp| {
            if (std.mem.eql(u8, ap, bp)) return true;
        }
    }
    return false;
}

pub fn build(b: *std.Build) void {
    ensureWritableGlobalCache(b);
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const enable_s0_gate = b.option(bool, "s0", "Enable S0 bootstrap gate (restricts to minimal Janus syntax)") orelse true;
    const enable_s0_extended = b.option(bool, "enable-s0-extended", "Run extended S0 bootstrap tests") orelse false;
    const enable_full_suite = b.option(bool, "enable-full-tests", "Run full compiler/unit test suite") orelse false;
    const enable_qtjir_trace = b.option(bool, "trace-qtjir", "Enable QTJIR lowering trace output for debugging") orelse false;

    const s0_options = b.addOptions();
    s0_options.addOption(bool, "enable_s0", enable_s0_gate);

    const compiler_options = b.addOptions();
    compiler_options.addOption(bool, "trace_qtjir", enable_qtjir_trace);

    const astdb_core_mod = b.addModule("astdb_core", .{
        .root_source_file = b.path("compiler/astdb/core.zig"),
        .target = target,
        .optimize = optimize,
    });

    const bootstrap_s0_mod = b.addModule("bootstrap_s0", .{
        .root_source_file = b.path("src/bootstrap_s0.zig"),
        .target = target,
        .optimize = optimize,
    });
    bootstrap_s0_mod.addOptions("s0_options", s0_options);

    // Note: astdb.zig is just a compatibility wrapper around core.zig
    // We use astdb_core directly to avoid module conflicts

    const lexer_mod = b.addModule("lexer", .{
        .root_source_file = b.path("compiler/astdb/lexer.zig"),
        .target = target,
        .optimize = optimize,
    });
    lexer_mod.addImport("astdb_core", astdb_core_mod);

    const region_mod = b.addModule("region", .{
        .root_source_file = b.path("compiler/astdb/region.zig"),
        .target = target,
        .optimize = optimize,
    });
    region_mod.addImport("astdb_core", astdb_core_mod);
    region_mod.addImport("bootstrap_s0", bootstrap_s0_mod);
    region_mod.addImport("lexer", lexer_mod);

    const capabilities_mod = b.addModule("capabilities", .{
        .root_source_file = b.path("std/capabilities.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Unified Compiler Errors Module
    const compiler_errors_mod = b.addModule("compiler_errors", .{
        .root_source_file = b.path("compiler/libjanus/compiler_errors.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tokenizer_mod = b.addModule("janus_tokenizer", .{
        .root_source_file = b.path("compiler/libjanus/janus_tokenizer.zig"),
        .target = target,
        .optimize = optimize,
    });
    tokenizer_mod.addImport("compiler_errors", compiler_errors_mod);

    const libjanus_parser_mod = b.addModule("janus_parser", .{
        .root_source_file = b.path("compiler/libjanus/janus_parser.zig"),
        .target = target,
        .optimize = optimize,
    });
    libjanus_parser_mod.addImport("janus_tokenizer", tokenizer_mod);
    libjanus_parser_mod.addImport("astdb_core", astdb_core_mod);
    libjanus_parser_mod.addImport("bootstrap_s0", bootstrap_s0_mod);
    libjanus_parser_mod.addImport("region", region_mod);

    const astdb_binder_mod = b.addModule("astdb_binder_only", .{
        .root_source_file = b.path("compiler/astdb/binder.zig"),
        .target = target,
        .optimize = optimize,
    });
    astdb_binder_mod.addImport("astdb_core", astdb_core_mod);

    const astdb_query_mod = b.addModule("astdb_query", .{
        .root_source_file = b.path("compiler/astdb/query.zig"),
        .target = target,
        .optimize = optimize,
    });
    astdb_query_mod.addImport("astdb_core", astdb_core_mod);

    const libjanus_astdb_mod = b.addModule("libjanus_astdb", .{
        .root_source_file = b.path("compiler/libjanus/libjanus_astdb.zig"),
        .target = target,
        .optimize = optimize,
    });
    libjanus_astdb_mod.addImport("astdb_core", astdb_core_mod);

    const lib_mod = b.addModule("libjanus", .{
        .root_source_file = b.path("compiler/libjanus/libjanus.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_mod.addImport("astdb_core", astdb_core_mod);
    lib_mod.addImport("libjanus_astdb", libjanus_astdb_mod);
    lib_mod.addImport("bootstrap_s0", bootstrap_s0_mod);
    lib_mod.addImport("janus_tokenizer", tokenizer_mod);
    lib_mod.addImport("janus_parser", libjanus_parser_mod);
    lib_mod.addImport("compiler_errors", compiler_errors_mod);

    // Semantic Analysis Module - The Soul of the Compiler
    const semantic_mod = b.addModule("semantic", .{
        .root_source_file = b.path("compiler/semantic/semantic_module.zig"),
        .target = target,
        .optimize = optimize,
    });
    semantic_mod.addImport("astdb", lib_mod);

    const semantic_analyzer_mod = b.addModule("semantic_analyzer_only", .{
        .root_source_file = b.path("compiler/semantic_analyzer.zig"),
        .target = target,
        .optimize = optimize,
    });
    semantic_analyzer_mod.addImport("astdb", astdb_core_mod);
    semantic_analyzer_mod.addImport("bootstrap_s0", bootstrap_s0_mod);
    semantic_analyzer_mod.addImport("lexer", lexer_mod);
    semantic_analyzer_mod.addImport("janus_parser", libjanus_parser_mod);
    semantic_analyzer_mod.addImport("capabilities", capabilities_mod);

    // Zig Parser - For native Zig integration
    const zig_parser_mod = b.addModule("zig_parser", .{
        .root_source_file = b.path("compiler/libjanus/zig_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    // QTJIR - The Revolutionary Multi-Level IR
    const qtjir_mod = b.addModule("qtjir", .{
        .root_source_file = b.path("compiler/qtjir.zig"), // Updated to Sovereign Index
        .target = target,
        .optimize = optimize,
    });
    qtjir_mod.addImport("astdb_core", astdb_core_mod);
    qtjir_mod.addImport("janus_parser", libjanus_parser_mod);
    qtjir_mod.addImport("zig_parser", zig_parser_mod);
    qtjir_mod.addOptions("compiler_options", compiler_options);

    // Add qtjir to libjanus for core_profile_codegen
    lib_mod.addImport("qtjir", qtjir_mod);

    // Inspector - Introspection Oracle (Epic 3.4)
    const inspect_mod = b.addModule("inspect", .{
        .root_source_file = b.path("compiler/inspect.zig"),
        .target = target,
        .optimize = optimize,
    });
    inspect_mod.addImport("astdb_core", astdb_core_mod);
    inspect_mod.addImport("libjanus", lib_mod);

    // Now we can add the dependency to semantic_analyzer_mod

    semantic_analyzer_mod.addImport("qtjir", qtjir_mod);
    semantic_analyzer_mod.addImport("inspect", inspect_mod);

    // Note: Allocator Contexts implementation in std/mem/ctx.zig
    // .jan files in std/mem/ctx/ are specifications for future self-hosting

    // Pipeline Module - For Unified Compilation
    const pipeline_mod = b.addModule("pipeline", .{
        .root_source_file = b.path("src/pipeline.zig"),
        .target = target,
        .optimize = optimize,
    });
    pipeline_mod.addImport("janus_lib", lib_mod);
    pipeline_mod.addImport("qtjir", qtjir_mod);
    pipeline_mod.addImport("astdb_core", astdb_core_mod);
    pipeline_mod.addAnonymousImport("janus_runtime_embed", .{
        .root_source_file = b.path("runtime/runtime_embed.zig"),
    });

    // Context Module (for capability system)
    const janus_context_mod = b.addModule("janus_context", .{
        .root_source_file = b.path("std/core/context.zig"),
        .target = target,
        .optimize = optimize,
    });

    // JIT Forge Module (std/ai/jit)
    const jit_forge_mod = b.addModule("jit_forge", .{
        .root_source_file = b.path("std/ai/jit/_module.zig"),
        .target = target,
        .optimize = optimize,
    });
    jit_forge_mod.addImport("janus_context", janus_context_mod);

    // Additional modules needed for CLI imports (Zig 0.15 module hygiene)
    const vfs_mod = b.addModule("vfs_adapter", .{
        .root_source_file = b.path("std/vfs_adapter.zig"),
        .target = target,
        .optimize = optimize,
    });

    const rogue_ast_checker = b.addExecutable(.{
        .name = "check_rogue_ast",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/check_rogue_ast.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_rogue_ast_checker = b.addRunArtifact(rogue_ast_checker);
    const rogue_ast_step = b.step("check-rogue-ast", "Detect rogue AST definitions outside ASTDB");
    rogue_ast_step.dependOn(&run_rogue_ast_checker.step);

    // Feature gates
    const enable_daemon = b.option(bool, "daemon", "Build janusd daemon and UTCP tests") orelse true;

    // Security gates: sanitizer support
    const enable_asan = b.option(bool, "asan", "Enable AddressSanitizer") orelse false;
    const enable_tsan = b.option(bool, "tsan", "Enable ThreadSanitizer") orelse false;
    const enable_sanitizers = enable_asan or enable_tsan;

    // Add BLAKE3 C library (fixed syntax; original had invalid .target/.optimize in options)
    const blake3_lib = b.addLibrary(.{
        .name = "blake3",
        .root_module = b.addModule("blake3", .{
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    blake3_lib.linkLibC();
    if (enable_sanitizers) {
        blake3_lib.addCSourceFiles(.{
            .files = &[_][]const u8{},
            .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
        });
    }

    // Base C sources (always included)
    const base_flags = &[_][]const u8{ "-std=c99", "-DBLAKE3_NO_AVX512" };
    inline for ([_]std.Build.LazyPath{
        b.path("third_party/blake3/c/blake3.c"),
        b.path("third_party/blake3/c/blake3_dispatch.c"),
        b.path("third_party/blake3/c/blake3_portable.c"),
    }) |src| {
        blake3_lib.addCSourceFile(.{ .file = src, .flags = base_flags });
    }

    // Conditional optimized implementations (error handling: check target CPU for SIMD support)
    const cpu = target.result.cpu;
    const is_x86 = cpu.arch == .x86_64 or cpu.arch == .x86;
    if (is_x86) {
        // SSE2 (baseline x86_64; always include if x86)
        blake3_lib.addCSourceFile(.{
            .file = b.path("third_party/blake3/c/blake3_sse2.c"),
            .flags = base_flags ++ &[_][]const u8{ "-msse2", "-DIS_X86=1" },
        });

        // SSE4.1 (common; check availability) - DISABLED: API compatibility issue in Zig 0.14.1
        // if (cpu.features.isEnabled(.sse4_1)) {
        //     blake3_lib.addCSourceFile(.{
        //         .file = b.path("third_party/blake3/c/blake3_sse41.c"),
        //         .flags = base_flags ++ &[_][]const u8{ "-msse4.1", "-DIS_X86=1" },
        //     });
        // } else {
        //     std.debug.print("Warning: SSE4.1 not available on target; skipping blake3_sse41.c\n", .{});
        // }

        // AVX2 (advanced; conditional) - DISABLED: API compatibility issue in Zig 0.14.1
        // if (cpu.features.isEnabled(.avx2)) {
        //     blake3_lib.addCSourceFile(.{
        //         .file = b.path("third_party/blake3/c/blake3_avx2.c"),
        //         .flags = base_flags ++ &[_][]const u8{ "-mavx2", "-DIS_X86=1" },
        //     });
        // } else {
        //     std.debug.print("Warning: AVX2 not available on target; skipping blake3_avx2.c\n", .{});
        // }
    } else {
        std.debug.print("Warning: BLAKE3 SIMD optimizations skipped for non-x86 target {s}\n", .{@tagName(cpu.arch)});
        // Fallback: Only portable (already added)
    }

    blake3_lib.addIncludePath(b.path("third_party/blake3/c"));
    b.installArtifact(blake3_lib);

    // libjanus - The Brain (Static Library) - Apply consistent options
    const libjanus = b.addLibrary(.{
        .name = "libjanus",
        .root_module = b.addModule("libjanus_module", .{
            .root_source_file = b.path("compiler/libjanus/api.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    libjanus.linkLibC();
    if (enable_sanitizers) {
        libjanus.addCSourceFiles(.{
            .files = &[_][]const u8{},
            .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
        });
    }

    libjanus.root_module.addImport("semantic", semantic_mod);
    libjanus.linkLibrary(blake3_lib);
    if (enable_sanitizers) {
        // libjanus.addCSourceFiles(.{
        //     .files = &[_][]const u8{},
        //     .flags = &[_][]const u8{"-fsanitize=address", "-fsanitize=undefined"},
        // });
    }
    b.installArtifact(libjanus);

    // ============================================================================
    // Janus Runtime - Native Zig runtime for compiled Janus programs
    // This is the foundation of :core/:min profile - provides all std functions
    // ============================================================================
    const janus_runtime = b.addLibrary(.{
        .name = "janus_runtime",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/janus_rt.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    janus_runtime.linkLibC();
    b.installArtifact(janus_runtime);

    // Also create an object file for direct linking (used by integration tests)
    const janus_runtime_obj = b.addObject(.{
        .name = "janus_rt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("runtime/janus_rt.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    janus_runtime_obj.linkLibC();

    // Install the object file to zig-out/obj/ for easy access
    const install_rt_obj = b.addInstallArtifact(janus_runtime_obj, .{
        .dest_dir = .{ .override = .{ .custom = "obj" } },
    });
    b.getInstallStep().dependOn(&install_rt_obj.step);

    // janus CLI - Apply consistent options
    const janus_cli = b.addExecutable(.{
        .name = "janus",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/janus_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    janus_cli.linkLibC();
    if (enable_sanitizers) {
        janus_cli.addCSourceFiles(.{
            .files = &[_][]const u8{},
            .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
        });
    }

    janus_cli.root_module.addImport("janus_lib", lib_mod);
    janus_cli.root_module.addImport("semantic", semantic_mod);
    janus_cli.root_module.addImport("vfs_adapter", vfs_mod);
    janus_cli.root_module.addImport("astdb_core", astdb_core_mod);
    janus_cli.root_module.addImport("bootstrap_s0", bootstrap_s0_mod);
    janus_cli.root_module.addImport("qtjir", qtjir_mod); // For pipeline.zig
    janus_cli.root_module.addImport("inspect", inspect_mod); // For janus inspect
    janus_cli.root_module.addImport("jit_forge", jit_forge_mod);
    janus_cli.root_module.addImport("janus_context", janus_context_mod);
    // Runtime source embed module - enables pipeline.zig to embed runtime from runtime/ directory
    janus_cli.root_module.addAnonymousImport("janus_runtime_embed", .{
        .root_source_file = b.path("runtime/runtime_embed.zig"),
    });
    janus_cli.linkLibrary(blake3_lib);
    janus_cli.linkSystemLibrary("LLVM-21"); // For pipeline LLVM emitter
    janus_cli.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" }); // For LLVM headers
    janus_cli.root_module.addIncludePath(b.path("third_party/blake3/c"));
    if (enable_sanitizers) {
        // janus_cli.addCSourceFiles(.{
        //     .files = &[_][]const u8{},
        //     .flags = &[_][]const u8{"-fsanitize=address", "-fsanitize=undefined"},
        // });
    }
    b.installArtifact(janus_cli);

    // Run step
    const run_cmd = b.addRunArtifact(janus_cli);
    run_cmd.step.dependOn(b.getInstallStep());
    run_cmd.setEnvironmentVariable("JANUS_BOOTSTRAP_S0", if (enable_s0_gate) "true" else "false");
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    // Install only janus (skip other artifacts)
    const install_janus = b.step("install-janus", "Install janus binary only");
    const install_janus_art = b.addInstallArtifact(janus_cli, .{});
    install_janus.dependOn(&install_janus_art.step);

    var utcp_registry_mod: ?*std.Build.Module = null;
    var janusd_main_mod: ?*std.Build.Module = null;

    // janusd daemon (UTCP bootstrap) — gated behind -Ddaemon
    if (enable_daemon) {
        utcp_registry_mod = b.createModule(.{
            .root_source_file = b.path("std/utcp_registry.zig"),
            .target = target,
            .optimize = optimize,
        });
        janusd_main_mod = b.addModule("janusd_main", .{
            .root_source_file = b.path("cmd/janusd/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        janusd_main_mod.?.addImport("utcp_registry", utcp_registry_mod.?);
        const janusd = b.addExecutable(.{
            .name = "janusd",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        janusd.linkLibC();
        if (enable_sanitizers) {
            janusd.addCSourceFiles(.{
                .files = &[_][]const u8{},
                .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
            });
        }
        const lsp_mod = b.addModule("lsp_server", .{
            .root_source_file = b.path("daemon/lsp_server.zig"),
            .target = target,
            .optimize = optimize,
        });
        lsp_mod.addImport("astdb", astdb_core_mod);
        lsp_mod.addImport("janus_parser", libjanus_parser_mod);
        lsp_mod.addImport("semantic", semantic_mod);
        lsp_mod.addImport("astdb_binder", astdb_binder_mod);
        lsp_mod.addImport("astdb_query", astdb_query_mod);

        janusd.root_module.addImport("janus_lib", lib_mod);
        janusd.root_module.addImport("semantic", semantic_mod);
        janusd.root_module.addImport("utcp_registry", utcp_registry_mod.?);
        janusd.root_module.addImport("lsp_server", lsp_mod);
        janusd.linkLibrary(blake3_lib);
        b.installArtifact(janusd);

        // Standalone LSP Server (Direct ASTDB Access)
        const janus_lsp = b.addExecutable(.{
            .name = "janus-lsp",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janus-lsp/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        janus_lsp.root_module.addImport("astdb", astdb_core_mod);
        janus_lsp.root_module.addImport("lsp_server", lsp_mod);
        janus_lsp.root_module.addImport("janus_parser", libjanus_parser_mod);
        janus_lsp.root_module.addImport("semantic", semantic_mod);
        b.installArtifact(janus_lsp);
    }

    // Test step
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_rogue_ast_checker.step);
    if (enable_full_suite) {
        const lib_unit_tests = b.addTest(.{
            .name = "libjanus_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("compiler/libjanus/api.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        lib_unit_tests.linkLibC();
        if (enable_sanitizers) {
            lib_unit_tests.addCSourceFiles(.{
                .files = &[_][]const u8{},
                .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
            });
        }
        lib_unit_tests.root_module.addImport("semantic", semantic_mod);
        lib_unit_tests.root_module.addImport("astdb_core", astdb_core_mod);
        lib_unit_tests.root_module.addImport("libjanus_astdb", libjanus_astdb_mod);
        lib_unit_tests.linkLibrary(blake3_lib);
        lib_unit_tests.root_module.addIncludePath(b.path("third_party/blake3/c"));
        const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
        test_step.dependOn(&run_lib_unit_tests.step);

        const exe_unit_tests = b.addTest(.{
            .name = "janus_exe_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("src/janus_main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        exe_unit_tests.linkLibC();
        if (enable_sanitizers) {
            exe_unit_tests.addCSourceFiles(.{
                .files = &[_][]const u8{},
                .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
            });
        }
        exe_unit_tests.root_module.addImport("janus_lib", lib_mod);
        exe_unit_tests.root_module.addImport("semantic", semantic_mod);
        exe_unit_tests.linkLibrary(blake3_lib);
        exe_unit_tests.root_module.addIncludePath(b.path("third_party/blake3/c"));
        const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
        test_step.dependOn(&run_exe_unit_tests.step);
    }

    // RSP-1 crypto unit tests
    const rsp1_tests = b.addTest(.{
        .name = "rsp1_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/test_rsp1_crypto.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    rsp1_tests.linkLibC();
    rsp1_tests.linkLibrary(blake3_lib);
    rsp1_tests.root_module.addIncludePath(b.path("third_party/blake3/c"));
    const rsp1_mod = b.addModule("rsp1", .{ .root_source_file = b.path("std/rsp1_crypto.zig"), .target = target, .optimize = optimize });
    rsp1_tests.root_module.addImport("rsp1", rsp1_mod);
    const run_rsp1_tests = b.addRunArtifact(rsp1_tests);
    test_step.dependOn(&run_rsp1_tests.step);

    // const global_cache_tests = b.addTest(.{
    //     .name = "global_cache_layout_tests",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tests/unit/test_global_cache_layout.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });
    // // const run_global_cache_tests = b.addRunArtifact(global_cache_tests);
    // // test_step.dependOn(&run_global_cache_tests.step); // Temporarily disabled due to FileNotFound error

    const s0_smoke_tests = b.addTest(.{
        .name = "s0_smoke_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/s0_smoke.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    s0_smoke_tests.root_module.addIncludePath(b.path("."));
    s0_smoke_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    s0_smoke_tests.root_module.addImport("astdb", astdb_core_mod);
    s0_smoke_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    s0_smoke_tests.root_module.addImport("bootstrap_s0", bootstrap_s0_mod);
    const run_s0_smoke_tests = b.addRunArtifact(s0_smoke_tests);
    test_step.dependOn(&run_s0_smoke_tests.step);

    const grep_command_mod = b.createModule(.{
        .root_source_file = b.path("src/grep_command.zig"),
        .target = target,
        .optimize = optimize,
    });

    const grep_spec_tests = b.addTest(.{
        .name = "grep_spec_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/grep_spec.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    grep_spec_tests.root_module.addImport("grep_command", grep_command_mod);
    const run_grep_spec_tests = b.addRunArtifact(grep_spec_tests);
    test_step.dependOn(&run_grep_spec_tests.step);

    const s0_gate_tests = b.addTest(.{
        .name = "s0_gate_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/s0_gate.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    s0_gate_tests.root_module.addIncludePath(b.path("."));
    s0_gate_tests.root_module.addImport("bootstrap_s0", bootstrap_s0_mod);
    s0_gate_tests.root_module.addImport("region", region_mod);
    s0_gate_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    s0_gate_tests.root_module.addImport("astdb", astdb_core_mod);
    const run_s0_gate_tests = b.addRunArtifact(s0_gate_tests);
    test_step.dependOn(&run_s0_gate_tests.step);

    const type_checking_tests = b.addTest(.{
        .name = "type_checking_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/type_checking.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    type_checking_tests.root_module.addIncludePath(b.path("."));
    type_checking_tests.root_module.addImport("libjanus", lib_mod);
    const run_type_checking_tests = b.addRunArtifact(type_checking_tests);
    test_step.dependOn(&run_type_checking_tests.step);

    const type_inference_tests = b.addTest(.{
        .name = "type_inference_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/type_inference.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    type_inference_tests.root_module.addIncludePath(b.path("."));
    type_inference_tests.root_module.addImport("libjanus", lib_mod);
    type_inference_tests.root_module.addImport("semantic", semantic_mod);
    const run_type_inference_tests = b.addRunArtifact(type_inference_tests);
    test_step.dependOn(&run_type_inference_tests.step);

    const type_system_tests = b.addTest(.{
        .name = "type_system_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/semantic/type_system_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    type_system_tests.root_module.addIncludePath(b.path("."));
    type_system_tests.root_module.addImport("astdb", astdb_core_mod);
    const run_type_system_tests = b.addRunArtifact(type_system_tests);
    test_step.dependOn(&run_type_system_tests.step);

    const test_type_system_step = b.step("test-type-system", "Run Type System unit tests");
    test_type_system_step.dependOn(&run_type_system_tests.step);

    const array_literal_inference_tests = b.addTest(.{
        .name = "array_literal_inference_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/array_literal_inference.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    array_literal_inference_tests.root_module.addIncludePath(b.path("."));
    array_literal_inference_tests.root_module.addImport("libjanus", lib_mod);
    const run_array_literal_inference_tests = b.addRunArtifact(array_literal_inference_tests);
    test_step.dependOn(&run_array_literal_inference_tests.step);

    const symbol_resolution_tests = b.addTest(.{
        .name = "symbol_resolution_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/symbol_resolution.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    symbol_resolution_tests.root_module.addIncludePath(b.path("."));
    symbol_resolution_tests.root_module.addImport("libjanus", lib_mod);
    const run_symbol_resolution_tests = b.addRunArtifact(symbol_resolution_tests);
    test_step.dependOn(&run_symbol_resolution_tests.step);

    const pattern_coverage_tests = b.addTest(.{
        .name = "pattern_coverage_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/semantic/pattern_coverage.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    pattern_coverage_tests.root_module.addIncludePath(b.path("."));
    pattern_coverage_tests.root_module.addImport("astdb", astdb_core_mod);
    pattern_coverage_tests.root_module.addImport("semantic", semantic_mod);
    const run_pattern_coverage_tests = b.addRunArtifact(pattern_coverage_tests);
    test_step.dependOn(&run_pattern_coverage_tests.step);

    const test_pattern_coverage_step = b.step("test-pattern-coverage", "Run Pattern Coverage unit tests");
    test_pattern_coverage_step.dependOn(&run_pattern_coverage_tests.step);

    const arraylist_report_tests = b.addTest(.{
        .name = "arraylist_report_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/codemods/arraylist_report.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    const identifier_inference_tests = b.addTest(.{
        .name = "identifier_inference_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/semantic/test_identifier_inference.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    identifier_inference_tests.root_module.addIncludePath(b.path("."));
    identifier_inference_tests.root_module.addImport("astdb", lib_mod);
    const run_identifier_inference_tests = b.addRunArtifact(identifier_inference_tests);

    const test_identifier_inference_step = b.step("test-identifier-inference", "Run Identifier Inference tests");
    test_identifier_inference_step.dependOn(&run_identifier_inference_tests.step);
    const run_arraylist_report_tests = b.addRunArtifact(arraylist_report_tests);
    test_step.dependOn(&run_arraylist_report_tests.step);

    // Min Profile Constraints Tests (Epic 1.1)
    const min_profile_constraints_tests = b.addTest(.{
        .name = "min_profile_constraints_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/min_profile_constraints.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    min_profile_constraints_tests.root_module.addIncludePath(b.path("."));
    min_profile_constraints_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    min_profile_constraints_tests.root_module.addImport("astdb", astdb_core_mod);
    min_profile_constraints_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_min_profile_constraints_tests = b.addRunArtifact(min_profile_constraints_tests);
    const test_min_profile_step = b.step("test-min-profile", "Run Min Profile constraints tests");
    test_min_profile_step.dependOn(&run_min_profile_constraints_tests.step);
    test_step.dependOn(&run_min_profile_constraints_tests.step);

    // Type Checking Calls Tests (Epic 1.1)
    const type_checking_calls_tests = b.addTest(.{
        .name = "type_checking_calls_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/type_checking_calls.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    type_checking_calls_tests.root_module.addIncludePath(b.path("."));
    type_checking_calls_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    type_checking_calls_tests.root_module.addImport("astdb", astdb_core_mod);
    type_checking_calls_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_type_checking_calls_tests = b.addRunArtifact(type_checking_calls_tests);
    const test_type_calls_step = b.step("test-type-calls", "Run Type Checking calls tests");
    test_type_calls_step.dependOn(&run_type_checking_calls_tests.step);
    test_step.dependOn(&run_type_checking_calls_tests.step);

    const var_decl_tests = b.addTest(.{
        .name = "var_decl_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/test_var_decl.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    var_decl_tests.root_module.addIncludePath(b.path("."));
    var_decl_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    var_decl_tests.root_module.addImport("astdb", astdb_core_mod);
    var_decl_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_var_decl_tests = b.addRunArtifact(var_decl_tests);
    const test_var_decl_step = b.step("test-var-decl", "Run Variable Declaration tests");
    test_var_decl_step.dependOn(&run_var_decl_tests.step);
    test_step.dependOn(&run_var_decl_tests.step);

    const if_stmt_tests = b.addTest(.{
        .name = "if_stmt_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/test_if_stmt.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if_stmt_tests.root_module.addIncludePath(b.path("."));
    if_stmt_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    if_stmt_tests.root_module.addImport("astdb", astdb_core_mod);
    if_stmt_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_if_stmt_tests = b.addRunArtifact(if_stmt_tests);
    const test_if_stmt_step = b.step("test-if-stmt", "Run If Statement tests");
    test_if_stmt_step.dependOn(&run_if_stmt_tests.step);

    test_step.dependOn(&run_if_stmt_tests.step);

    const while_stmt_tests = b.addTest(.{
        .name = "while_stmt_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/test_while_stmt.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    while_stmt_tests.root_module.addIncludePath(b.path("."));
    while_stmt_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    while_stmt_tests.root_module.addImport("astdb", astdb_core_mod);
    while_stmt_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_while_stmt_tests = b.addRunArtifact(while_stmt_tests);
    const test_while_stmt_step = b.step("test-while-stmt", "Run While Statement tests");
    test_while_stmt_step.dependOn(&run_while_stmt_tests.step);
    test_step.dependOn(&run_while_stmt_tests.step);

    // Error Handling Syntax Tests (:core profile)
    const error_syntax_tests = b.addTest(.{
        .name = "error_syntax_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/test_error_syntax.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_syntax_tests.root_module.addIncludePath(b.path("."));
    error_syntax_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    error_syntax_tests.root_module.addImport("astdb_core", astdb_core_mod);

    const run_error_syntax_tests = b.addRunArtifact(error_syntax_tests);
    const test_error_syntax_step = b.step("test-error-syntax", "Run Error Handling Syntax tests");
    test_error_syntax_step.dependOn(&run_error_syntax_tests.step);
    test_step.dependOn(&run_error_syntax_tests.step);

    // Error Symbol Table Tests (:core profile)
    const error_symbol_table_tests = b.addTest(.{
        .name = "error_symbol_table_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/semantic/error_symbol_table_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_symbol_table_tests.root_module.addIncludePath(b.path("."));
    error_symbol_table_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    error_symbol_table_tests.root_module.addImport("astdb_core", astdb_core_mod);
    error_symbol_table_tests.root_module.addImport("semantic", semantic_mod);

    const run_error_symbol_table_tests = b.addRunArtifact(error_symbol_table_tests);
    const test_error_symbol_table_step = b.step("test-error-symbols", "Run Error Symbol Table tests");
    test_error_symbol_table_step.dependOn(&run_error_symbol_table_tests.step);
    test_step.dependOn(&run_error_symbol_table_tests.step);

    // Error Type System Tests (:core profile)
    const error_type_system_tests = b.addTest(.{
        .name = "error_type_system_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/semantic/error_type_system_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_type_system_tests.root_module.addIncludePath(b.path("."));
    error_type_system_tests.root_module.addImport("semantic", semantic_mod);

    const run_error_type_system_tests = b.addRunArtifact(error_type_system_tests);
    const test_error_types_step = b.step("test-error-types", "Run Error Type System tests");
    test_error_types_step.dependOn(&run_error_type_system_tests.step);
    test_step.dependOn(&run_error_type_system_tests.step);

    // Error Handling Integration Tests (:core profile)
    const error_integration_tests = b.addTest(.{
        .name = "error_integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/semantic/error_integration_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_integration_tests.root_module.addIncludePath(b.path("."));
    error_integration_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    error_integration_tests.root_module.addImport("astdb_core", astdb_core_mod);
    error_integration_tests.root_module.addImport("semantic", semantic_mod);

    const run_error_integration_tests = b.addRunArtifact(error_integration_tests);
    const test_error_integration_step = b.step("test-error-integration", "Run Error Handling Integration tests");
    test_error_integration_step.dependOn(&run_error_integration_tests.step);
    test_step.dependOn(&run_error_integration_tests.step);

    // Full Stack Verification
    const verify_tests = b.addTest(.{
        .name = "full_stack_verify",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/full_stack_verify.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    verify_tests.root_module.addIncludePath(b.path("."));
    verify_tests.root_module.addImport("astdb", astdb_core_mod); // For test compat
    verify_tests.root_module.addImport("astdb_core", astdb_core_mod);
    verify_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    verify_tests.root_module.addImport("qtjir", qtjir_mod);

    verify_tests.linkLibC();
    verify_tests.linkSystemLibrary("LLVM-21");
    // Some systems need explicit include path for LLVM-C headers if not in standard path
    verify_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });

    const run_verify_tests = b.addRunArtifact(verify_tests);
    test_step.dependOn(&run_verify_tests.step);

    // QTJIR graph validation tests (Phase 1 - IR01)
    const qtjir_tests = b.addTest(.{
        .name = "qtjir_graph_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/graph.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_tests = b.addRunArtifact(qtjir_tests);
    test_step.dependOn(&run_qtjir_tests.step);

    const test_qtjir_step = b.step("test-qtjir", "Run QTJIR unit tests");
    test_qtjir_step.dependOn(&run_qtjir_tests.step);

    // QTJIR Extended Graph Tests (Phase 5 - Task 5.1.1)
    const qtjir_graph_extended_tests = b.addTest(.{
        .name = "qtjir_graph_extended_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_graph_extended.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_graph_extended_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_graph_extended_tests = b.addRunArtifact(qtjir_graph_extended_tests);

    const test_graph_extended_step = b.step("test-graph-extended", "Run QTJIR extended graph tests");
    test_graph_extended_step.dependOn(&run_qtjir_graph_extended_tests.step);
    test_step.dependOn(&run_qtjir_graph_extended_tests.step);

    // QTJIR Extended Lowering Tests (Phase 5 - Task 5.1.2)
    const qtjir_lower_extended_tests = b.addTest(.{
        .name = "qtjir_lower_extended_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_lower_extended.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lower_extended_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_lower_extended_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_lower_extended_tests.root_module.addImport("zig_parser", zig_parser_mod);

    const run_qtjir_lower_extended_tests = b.addRunArtifact(qtjir_lower_extended_tests);
    const test_lower_extended_step = b.step("test-lower-extended", "Run QTJIR extended lowering tests");
    test_lower_extended_step.dependOn(&run_qtjir_lower_extended_tests.step);
    test_step.dependOn(&run_qtjir_lower_extended_tests.step);

    // Range Lowering Tests
    const range_lower_tests = b.addTest(.{
        .name = "range_lower_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_range_lower.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    range_lower_tests.root_module.addImport("astdb_core", astdb_core_mod);
    range_lower_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    range_lower_tests.root_module.addImport("zig_parser", zig_parser_mod);

    const run_range_lower_tests = b.addRunArtifact(range_lower_tests);
    const test_range_lower_step = b.step("test-range-lower", "Run Range Lowering tests");
    test_range_lower_step.dependOn(&run_range_lower_tests.step);
    test_step.dependOn(&run_range_lower_tests.step);

    // Range Semantic Tests
    const range_semantic_tests = b.addTest(.{
        .name = "range_semantic_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/test_range_semantic.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    range_semantic_tests.root_module.addImport("astdb", astdb_core_mod);
    range_semantic_tests.root_module.addImport("semantic_analyzer_only", semantic_analyzer_mod);
    range_semantic_tests.root_module.addImport("janus_parser", libjanus_parser_mod);

    const run_range_semantic_tests = b.addRunArtifact(range_semantic_tests);
    const test_range_semantic_step = b.step("test-range-semantic", "Run Range Semantic tests");
    test_range_semantic_step.dependOn(&run_range_semantic_tests.step);
    test_step.dependOn(&run_range_semantic_tests.step);

    // For Loop Lowering Tests
    const for_lower_tests = b.addTest(.{
        .name = "for_lower_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_for_lower.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    for_lower_tests.root_module.addImport("astdb_core", astdb_core_mod);
    for_lower_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    for_lower_tests.root_module.addImport("qtjir", qtjir_mod);
    for_lower_tests.root_module.addImport("zig_parser", zig_parser_mod);

    const run_for_lower_tests = b.addRunArtifact(for_lower_tests);
    const test_for_lower_step = b.step("test-for-lower", "Run For Loop Lowering tests");
    test_for_lower_step.dependOn(&run_for_lower_tests.step);
    test_step.dependOn(&run_for_lower_tests.step);

    // Array Literal Lowering Tests
    const array_lower_tests = b.addTest(.{
        .name = "array_lower_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_array_lower.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    array_lower_tests.root_module.addImport("astdb_core", astdb_core_mod);
    array_lower_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    array_lower_tests.root_module.addImport("qtjir", qtjir_mod);
    array_lower_tests.root_module.addImport("zig_parser", zig_parser_mod);

    const run_array_lower_tests = b.addRunArtifact(array_lower_tests);
    const test_array_lower_step = b.step("test-array-lower", "Run Array Literal Lowering tests");
    test_array_lower_step.dependOn(&run_array_lower_tests.step);
    test_step.dependOn(&run_array_lower_tests.step);

    // QTJIR Tensor/SSM Lowering Tests (Phase 2 - AI-First Runtime)
    const qtjir_lower_tensor_ssm_tests = b.addTest(.{
        .name = "qtjir_lower_tensor_ssm_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/qtjir/test_lower_tensor_ssm.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lower_tensor_ssm_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_lower_tensor_ssm_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_lower_tensor_ssm_tests.root_module.addImport("qtjir", qtjir_mod);

    const run_qtjir_lower_tensor_ssm_tests = b.addRunArtifact(qtjir_lower_tensor_ssm_tests);
    const test_lower_tensor_ssm_step = b.step("test-lower-tensor-ssm", "Run QTJIR tensor/SSM lowering tests");
    test_lower_tensor_ssm_step.dependOn(&run_qtjir_lower_tensor_ssm_tests.step);
    test_step.dependOn(&run_qtjir_lower_tensor_ssm_tests.step);

    // NPU Backend Tests (Panopticum-compliant feature module)
    const npu_backend_tests = b.addTest(.{
        .name = "npu_backend_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/npu_backend.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    npu_backend_tests.root_module.addImport("astdb_core", astdb_core_mod);
    npu_backend_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    npu_backend_tests.root_module.addImport("qtjir", qtjir_mod);

    const run_npu_backend_tests = b.addRunArtifact(npu_backend_tests);
    const test_npu_backend_step = b.step("test-npu-backend", "Run NPU backend simulator tests");
    test_npu_backend_step.dependOn(&run_npu_backend_tests.step);
    test_step.dependOn(&run_npu_backend_tests.step);

    // QTJIR Array Lowering Tests (Phase 1)
    const qtjir_lower_arrays_tests = b.addTest(.{
        .name = "qtjir_lower_arrays_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/qtjir/test_lower_arrays.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lower_arrays_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_lower_arrays_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_lower_arrays_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_lower_arrays_tests = b.addRunArtifact(qtjir_lower_arrays_tests);
    test_step.dependOn(&run_qtjir_lower_arrays_tests.step);

    const test_qtjir_lower_arrays_step = b.step("test-qtjir-lower-arrays", "Run QTJIR array lowering tests");
    test_qtjir_lower_arrays_step.dependOn(&run_qtjir_lower_arrays_tests.step);

    // QTJIR Range Lowering Tests
    const qtjir_lower_ranges_tests = b.addTest(.{
        .name = "qtjir_lower_ranges_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/qtjir/test_lower_ranges.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lower_ranges_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_lower_ranges_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_lower_ranges_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_lower_ranges_tests = b.addRunArtifact(qtjir_lower_ranges_tests);
    test_step.dependOn(&run_qtjir_lower_ranges_tests.step);

    const test_qtjir_lower_ranges_step = b.step("test-qtjir-lower-ranges", "Run QTJIR range lowering tests");
    test_qtjir_lower_ranges_step.dependOn(&run_qtjir_lower_ranges_tests.step);

    // Inspector Tests
    const inspect_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/inspect.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    inspect_tests.root_module.addImport("astdb_core", astdb_core_mod);
    inspect_tests.root_module.addImport("libjanus", lib_mod);

    const run_inspect_tests = b.addRunArtifact(inspect_tests);
    const test_inspect_step = b.step("test-inspect", "Run Inspector unit tests");
    test_inspect_step.dependOn(&run_inspect_tests.step);
    test_step.dependOn(&run_inspect_tests.step);

    // Forge Cycle 1: Hello World Integration Test
    const forge_hello_tests = b.addTest(.{
        .name = "forge_hello_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/forge_hello_world.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    forge_hello_tests.linkLibC();
    forge_hello_tests.linkSystemLibrary("LLVM-21"); // Pipeline needs LLVM
    forge_hello_tests.root_module.addImport("janus_lib", lib_mod);
    forge_hello_tests.root_module.addImport("qtjir", qtjir_mod);
    forge_hello_tests.root_module.addImport("astdb_core", astdb_core_mod);
    forge_hello_tests.root_module.addImport("pipeline", pipeline_mod);
    forge_hello_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" }); // For LLVM headers

    const run_forge_hello = b.addRunArtifact(forge_hello_tests);
    run_forge_hello.cwd = b.path(".");
    const test_forge_hello_step = b.step("test-forge-hello", "Run Hello World Forge integration test");
    test_forge_hello_step.dependOn(&run_forge_hello.step);
    test_step.dependOn(&run_forge_hello.step);

    // QTJIR Standard Library Tests
    const qtjir_std_tests = b.addTest(.{
        .name = "qtjir_std_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/std/test_array_create.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_std_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_std_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_std_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_std_tests = b.addRunArtifact(qtjir_std_tests);
    test_step.dependOn(&run_qtjir_std_tests.step);

    const test_qtjir_std_step = b.step("test-qtjir-std", "Run QTJIR standard library tests");
    test_qtjir_std_step.dependOn(&run_qtjir_std_tests.step);

    // QTJIR Error Handling Opcodes Tests (:core profile)
    const qtjir_error_opcodes_tests = b.addTest(.{
        .name = "qtjir_error_opcodes_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/qtjir/error_opcodes_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_error_opcodes_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_error_opcodes_tests = b.addRunArtifact(qtjir_error_opcodes_tests);
    const test_qtjir_error_opcodes_step = b.step("test-error-opcodes", "Run QTJIR error handling opcodes tests");
    test_qtjir_error_opcodes_step.dependOn(&run_qtjir_error_opcodes_tests.step);
    test_step.dependOn(&run_qtjir_error_opcodes_tests.step);

    // QTJIR Error Handling Lowering Tests (:core profile)
    const qtjir_error_lowering_tests = b.addTest(.{
        .name = "qtjir_error_lowering_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/qtjir/error_lowering_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_error_lowering_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_error_lowering_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_error_lowering_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_error_lowering_tests = b.addRunArtifact(qtjir_error_lowering_tests);
    const test_qtjir_error_lowering_step = b.step("test-error-lowering", "Run QTJIR error handling lowering tests");
    test_qtjir_error_lowering_step.dependOn(&run_qtjir_error_lowering_tests.step);
    test_step.dependOn(&run_qtjir_error_lowering_tests.step);

    // Add QTJIR tensor operation tests (Task 2.1.1)
    const qtjir_tensor_tests = b.addTest(.{
        .name = "qtjir_tensor_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_tensor_ops.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_tensor_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_tensor_tests = b.addRunArtifact(qtjir_tensor_tests);

    const test_tensor_step = b.step("test-tensor", "Run QTJIR tensor operation tests");
    test_tensor_step.dependOn(&run_qtjir_tensor_tests.step);
    test_step.dependOn(&run_qtjir_tensor_tests.step);

    // Add QTJIR tensor lowering tests (Task 2.1.2)
    const qtjir_lowering_tests = b.addTest(.{
        .name = "qtjir_lowering_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_tensor_lowering.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lowering_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_lowering_tests = b.addRunArtifact(qtjir_lowering_tests);

    const test_lowering_step = b.step("test-lowering", "Run QTJIR tensor lowering tests");
    test_lowering_step.dependOn(&run_qtjir_lowering_tests.step);
    test_step.dependOn(&run_qtjir_lowering_tests.step);

    // Add QTJIR tensor validation tests (Task 2.1.3)
    const qtjir_validation_tests = b.addTest(.{
        .name = "qtjir_validation_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_tensor_validation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_validation_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_validation_tests = b.addRunArtifact(qtjir_validation_tests);

    // Add QTJIR general validation tests (Phase 1/5)
    const qtjir_general_validation_tests = b.addTest(.{
        .name = "qtjir_general_validation_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_validation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_general_validation_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_general_validation_tests = b.addRunArtifact(qtjir_general_validation_tests);

    const test_validation_step = b.step("test-validation", "Run QTJIR validation tests");
    test_validation_step.dependOn(&run_qtjir_validation_tests.step);
    test_validation_step.dependOn(&run_qtjir_general_validation_tests.step);
    test_step.dependOn(&run_qtjir_validation_tests.step);
    test_step.dependOn(&run_qtjir_general_validation_tests.step);

    // Add QTJIR quantum operation tests (Task 2.2.1)
    const qtjir_quantum_tests = b.addTest(.{
        .name = "qtjir_quantum_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_quantum_ops.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_quantum_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_quantum_tests = b.addRunArtifact(qtjir_quantum_tests);

    const test_quantum_step = b.step("test-quantum", "Run QTJIR quantum operation tests");
    test_quantum_step.dependOn(&run_qtjir_quantum_tests.step);
    test_step.dependOn(&run_qtjir_quantum_tests.step);

    // Add QTJIR quantum lowering tests (Task 2.2.2)
    const qtjir_quantum_lowering_tests = b.addTest(.{
        .name = "qtjir_quantum_lowering_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_quantum_lowering.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_quantum_lowering_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_quantum_lowering_tests.root_module.addImport("zig_parser", zig_parser_mod);
    const run_qtjir_quantum_lowering_tests = b.addRunArtifact(qtjir_quantum_lowering_tests);

    const test_quantum_lowering_step = b.step("test-quantum-lowering", "Run QTJIR quantum lowering tests");
    test_quantum_lowering_step.dependOn(&run_qtjir_quantum_lowering_tests.step);
    test_step.dependOn(&run_qtjir_quantum_lowering_tests.step);

    // Add QTJIR quantum validation tests (Task 2.2.3)
    const qtjir_quantum_validation_tests = b.addTest(.{
        .name = "qtjir_quantum_validation_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_quantum_validation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_quantum_validation_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_quantum_validation_tests = b.addRunArtifact(qtjir_quantum_validation_tests);

    const test_quantum_validation_step = b.step("test-quantum-validation", "Run QTJIR quantum validation tests");
    test_quantum_validation_step.dependOn(&run_qtjir_quantum_validation_tests.step);
    test_step.dependOn(&run_qtjir_quantum_validation_tests.step);

    // Add QTJIR transformation tests (Phase 1)
    const qtjir_transforms_tests = b.addTest(.{
        .name = "qtjir_transforms_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_transforms.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_transforms_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_transforms_tests = b.addRunArtifact(qtjir_transforms_tests);

    const test_transforms_step = b.step("test-transforms", "Run QTJIR transformation tests");
    test_transforms_step.dependOn(&run_qtjir_transforms_tests.step);
    test_step.dependOn(&run_qtjir_transforms_tests.step);

    // Add QTJIR fusion tests (Phase 2)
    const qtjir_fusion_tests = b.addTest(.{
        .name = "qtjir_fusion_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_fusion.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_fusion_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_fusion_tests = b.addRunArtifact(qtjir_fusion_tests);

    const test_fusion_step = b.step("test-fusion", "Run QTJIR tensor fusion tests");
    test_fusion_step.dependOn(&run_qtjir_fusion_tests.step);
    test_step.dependOn(&run_qtjir_fusion_tests.step);

    // Add QTJIR quantum optimization tests (Phase 2)
    const qtjir_quantum_opt_tests = b.addTest(.{
        .name = "qtjir_quantum_opt_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_quantum_opt.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_quantum_opt_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_quantum_opt_tests = b.addRunArtifact(qtjir_quantum_opt_tests);

    const test_quantum_opt_step = b.step("test-quantum-opt", "Run QTJIR quantum optimization tests");
    test_quantum_opt_step.dependOn(&run_qtjir_quantum_opt_tests.step);
    test_step.dependOn(&run_qtjir_quantum_opt_tests.step);

    // Add QTJIR SSA transformation tests (Phase 3 - Task 3.1.1)
    const qtjir_ssa_tests = b.addTest(.{
        .name = "qtjir_ssa_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_ssa.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_ssa_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_ssa_tests = b.addRunArtifact(qtjir_ssa_tests);

    const test_ssa_step = b.step("test-ssa", "Run QTJIR SSA transformation tests");
    test_ssa_step.dependOn(&run_qtjir_ssa_tests.step);
    test_step.dependOn(&run_qtjir_ssa_tests.step);

    // Add QTJIR register allocation tests (Phase 3 - Task 3.1.2)
    const qtjir_regalloc_tests = b.addTest(.{
        .name = "qtjir_regalloc_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_register_allocation.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_regalloc_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_regalloc_tests = b.addRunArtifact(qtjir_regalloc_tests);

    const test_regalloc_step = b.step("test-regalloc", "Run QTJIR register allocation tests");
    test_regalloc_step.dependOn(&run_qtjir_regalloc_tests.step);
    test_step.dependOn(&run_qtjir_regalloc_tests.step);

    // Add QTJIR platform lowering tests (Phase 3 - Epic 3.2)
    const qtjir_platform_tests = b.addTest(.{
        .name = "qtjir_platform_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_platform_lowering.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_platform_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_platform_tests = b.addRunArtifact(qtjir_platform_tests);

    const test_platform_step = b.step("test-platform", "Run QTJIR platform lowering tests");
    test_platform_step.dependOn(&run_qtjir_platform_tests.step);
    test_step.dependOn(&run_qtjir_platform_tests.step);

    // Add QTJIR LLVM IR emitter tests (Phase 4 - Epic 4.1)
    const qtjir_emitter_tests = b.addTest(.{
        .name = "qtjir_emitter_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_emitter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_emitter_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_emitter_tests = b.addRunArtifact(qtjir_emitter_tests);

    const test_emitter_step = b.step("test-emitter", "Run QTJIR LLVM IR emitter tests");
    test_emitter_step.dependOn(&run_qtjir_emitter_tests.step);
    test_step.dependOn(&run_qtjir_emitter_tests.step);

    // QTJIR LLVM-C Emitter Tests (Production backend)
    const qtjir_llvm_emitter_tests = b.addTest(.{
        .name = "qtjir_llvm_emitter_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_llvm_emitter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_llvm_emitter_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_llvm_emitter_tests.linkLibC();
    qtjir_llvm_emitter_tests.linkSystemLibrary("LLVM");
    const run_qtjir_llvm_emitter_tests = b.addRunArtifact(qtjir_llvm_emitter_tests);

    const test_llvm_emitter_step = b.step("test-llvm-emitter", "Run QTJIR LLVM-C emitter tests");
    test_llvm_emitter_step.dependOn(&run_qtjir_llvm_emitter_tests.step);
    // Note: Not adding to main test_step yet until it's stable

    // QTJIR E2E Compilation Tests
    const qtjir_e2e_tests = b.addTest(.{
        .name = "qtjir_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_e2e.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_e2e_tests.linkLibC();
    qtjir_e2e_tests.linkSystemLibrary("LLVM");
    const run_qtjir_e2e_tests = b.addRunArtifact(qtjir_e2e_tests);

    const test_e2e_step = b.step("test-e2e", "Run QTJIR End-to-End compilation tests");
    test_e2e_step.dependOn(&run_qtjir_e2e_tests.step);

    // QTJIR JFind Hello Compilation Tests
    const qtjir_jfind_hello_tests = b.addTest(.{
        .name = "qtjir_jfind_hello_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_jfind_hello.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_jfind_hello_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_jfind_hello_tests.linkLibC();
    qtjir_jfind_hello_tests.linkSystemLibrary("LLVM");
    const run_qtjir_jfind_hello_tests = b.addRunArtifact(qtjir_jfind_hello_tests);

    const test_jfind_hello_step = b.step("test-jfind-hello", "Run QTJIR JFind Hello compilation tests");
    test_jfind_hello_step.dependOn(&run_qtjir_jfind_hello_tests.step);

    // QTJIR Lowering Tests
    const qtjir_lower_tests = b.addTest(.{
        .name = "qtjir_lower_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_lower.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_lower_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_lower_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_lower_tests.linkLibC();
    const run_qtjir_lower_tests = b.addRunArtifact(qtjir_lower_tests);

    const test_lower_step = b.step("test-lower", "Run QTJIR Lowering tests");
    test_lower_step.dependOn(&run_qtjir_lower_tests.step);

    // Add QTJIR comprehensive tests (Phase 5 - Epic 5.1)
    const qtjir_comprehensive_tests = b.addTest(.{
        .name = "qtjir_comprehensive_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_comprehensive.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_comprehensive_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_comprehensive_tests = b.addRunArtifact(qtjir_comprehensive_tests);

    const test_comprehensive_step = b.step("test-comprehensive", "Run QTJIR comprehensive tests");
    test_comprehensive_step.dependOn(&run_qtjir_comprehensive_tests.step);
    test_step.dependOn(&run_qtjir_comprehensive_tests.step);

    // Add QTJIR integration tests (Phase 5 - Epic 5.2)
    const qtjir_integration_tests = b.addTest(.{
        .name = "qtjir_integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/qtjir/test_integration.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_integration_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_qtjir_integration_tests = b.addRunArtifact(qtjir_integration_tests);

    const test_integration_step = b.step("test-integration", "Run QTJIR integration tests");
    test_integration_step.dependOn(&run_qtjir_integration_tests.step);
    test_step.dependOn(&run_qtjir_integration_tests.step);

    // Add Hello World End-to-End Integration Test (Epic 1.4.1)
    const hello_world_e2e_tests = b.addTest(.{
        .name = "hello_world_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/hello_world_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    hello_world_e2e_tests.linkLibC();
    hello_world_e2e_tests.linkSystemLibrary("LLVM-21");
    hello_world_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    hello_world_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    hello_world_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    hello_world_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_hello_world_e2e_tests = b.addRunArtifact(hello_world_e2e_tests);

    const test_hello_world_e2e_step = b.step("test-hello-world-e2e", "Run Hello World end-to-end integration test");
    test_hello_world_e2e_step.dependOn(&run_hello_world_e2e_tests.step);
    test_step.dependOn(&run_hello_world_e2e_tests.step);

    // Error Handling End-to-End Integration Test (:core profile)
    const error_handling_e2e_tests = b.addTest(.{
        .name = "error_handling_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/error_handling_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_handling_e2e_tests.linkLibC();
    error_handling_e2e_tests.linkSystemLibrary("LLVM-21");
    error_handling_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    error_handling_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    error_handling_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    error_handling_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_error_handling_e2e_tests = b.addRunArtifact(error_handling_e2e_tests);

    const test_error_handling_e2e_step = b.step("test-error-handling-e2e", "Run Error Handling end-to-end integration test");
    test_error_handling_e2e_step.dependOn(&run_error_handling_e2e_tests.step);
    test_step.dependOn(&run_error_handling_e2e_tests.step);

    // Add jfind End-to-End Integration Test (Native Zig Grafting)
    const jfind_e2e_tests = b.addTest(.{
        .name = "jfind_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/jfind_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    jfind_e2e_tests.linkLibC();
    jfind_e2e_tests.linkSystemLibrary("LLVM-21");
    jfind_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    jfind_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    jfind_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    jfind_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_jfind_e2e_tests = b.addRunArtifact(jfind_e2e_tests);

    const test_jfind_e2e_step = b.step("test-jfind-e2e", "Run jfind end-to-end integration test");
    test_jfind_e2e_step.dependOn(&run_jfind_e2e_tests.step);

    // Add For Loop End-to-End Integration Test (Epic 1.5)
    const for_loop_e2e_tests = b.addTest(.{
        .name = "for_loop_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/for_loop_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    for_loop_e2e_tests.linkLibC();
    for_loop_e2e_tests.linkSystemLibrary("LLVM-21");
    for_loop_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    for_loop_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    for_loop_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    for_loop_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_for_loop_e2e_tests = b.addRunArtifact(for_loop_e2e_tests);

    const test_for_loop_e2e_step = b.step("test-for-loop-e2e", "Run For Loop end-to-end integration test");
    test_for_loop_e2e_step.dependOn(&run_for_loop_e2e_tests.step);
    test_step.dependOn(&run_for_loop_e2e_tests.step);

    // Add If/Else End-to-End Integration Test (Epic 1.6)
    const if_else_e2e_tests = b.addTest(.{
        .name = "if_else_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/if_else_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    if_else_e2e_tests.linkLibC();
    if_else_e2e_tests.linkSystemLibrary("LLVM-21");
    if_else_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    if_else_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    if_else_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    if_else_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_if_else_e2e_tests = b.addRunArtifact(if_else_e2e_tests);

    const test_if_else_e2e_step = b.step("test-if-else-e2e", "Run If/Else end-to-end integration test");
    test_if_else_e2e_step.dependOn(&run_if_else_e2e_tests.step);
    test_step.dependOn(&run_if_else_e2e_tests.step);

    // Add While Loop End-to-End Integration Test (Epic 1.7)
    const while_loop_e2e_tests = b.addTest(.{
        .name = "while_loop_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/while_loop_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    while_loop_e2e_tests.linkLibC();
    while_loop_e2e_tests.linkSystemLibrary("LLVM-21");
    while_loop_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    while_loop_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    while_loop_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    while_loop_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_while_loop_e2e_tests = b.addRunArtifact(while_loop_e2e_tests);

    const test_while_loop_e2e_step = b.step("test-while-loop-e2e", "Run While Loop end-to-end integration test");
    test_while_loop_e2e_step.dependOn(&run_while_loop_e2e_tests.step);
    test_step.dependOn(&run_while_loop_e2e_tests.step);

    // Function Call E2E Tests
    const function_call_e2e_tests = b.addTest(.{
        .name = "function_call_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/function_call_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    function_call_e2e_tests.linkLibC();
    function_call_e2e_tests.linkSystemLibrary("LLVM-21");
    function_call_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    function_call_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    function_call_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    function_call_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_function_call_e2e_tests = b.addRunArtifact(function_call_e2e_tests);

    const test_function_call_e2e_step = b.step("test-function-call-e2e", "Run Function Call end-to-end integration test");
    test_function_call_e2e_step.dependOn(&run_function_call_e2e_tests.step);
    test_step.dependOn(&run_function_call_e2e_tests.step);

    // Continue Statement E2E Tests
    const continue_e2e_tests = b.addTest(.{
        .name = "continue_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/continue_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    continue_e2e_tests.linkLibC();
    continue_e2e_tests.linkSystemLibrary("LLVM-21");
    continue_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    continue_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    continue_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    continue_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_continue_e2e_tests = b.addRunArtifact(continue_e2e_tests);

    const test_continue_e2e_step = b.step("test-continue-e2e", "Run Continue Statement end-to-end integration test");
    test_continue_e2e_step.dependOn(&run_continue_e2e_tests.step);
    test_step.dependOn(&run_continue_e2e_tests.step);

    // Match Statement E2E Tests
    const match_e2e_tests = b.addTest(.{
        .name = "match_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/match_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    match_e2e_tests.linkLibC();
    match_e2e_tests.linkSystemLibrary("LLVM-21");
    match_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    match_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    match_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    match_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_match_e2e_tests = b.addRunArtifact(match_e2e_tests);

    const test_match_e2e_step = b.step("test-match-e2e", "Run Match Statement end-to-end integration test");
    test_match_e2e_step.dependOn(&run_match_e2e_tests.step);
    test_step.dependOn(&run_match_e2e_tests.step);

    // Struct Types E2E Tests
    const struct_e2e_tests = b.addTest(.{
        .name = "struct_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/struct_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    struct_e2e_tests.linkLibC();
    struct_e2e_tests.linkSystemLibrary("LLVM-21");
    struct_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    struct_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    struct_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    struct_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_struct_e2e_tests = b.addRunArtifact(struct_e2e_tests);

    const test_struct_e2e_step = b.step("test-struct-e2e", "Run Struct Types end-to-end integration test");
    test_struct_e2e_step.dependOn(&run_struct_e2e_tests.step);
    test_step.dependOn(&run_struct_e2e_tests.step);

    // String Literals E2E Tests
    const string_e2e_tests = b.addTest(.{
        .name = "string_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/string_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    string_e2e_tests.linkLibC();
    string_e2e_tests.linkSystemLibrary("LLVM-21");
    string_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    string_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    string_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    string_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_string_e2e_tests = b.addRunArtifact(string_e2e_tests);

    const test_string_e2e_step = b.step("test-string-e2e", "Run String Literals end-to-end integration test");
    test_string_e2e_step.dependOn(&run_string_e2e_tests.step);
    test_step.dependOn(&run_string_e2e_tests.step);

    // Type Annotation E2E Tests
    const type_annotation_e2e_tests = b.addTest(.{
        .name = "type_annotation_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/type_annotation_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    type_annotation_e2e_tests.linkLibC();
    type_annotation_e2e_tests.linkSystemLibrary("LLVM-21");
    type_annotation_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    type_annotation_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    type_annotation_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    type_annotation_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_type_annotation_e2e_tests = b.addRunArtifact(type_annotation_e2e_tests);

    const test_type_annotation_e2e_step = b.step("test-type-annotation-e2e", "Run Type Annotation end-to-end integration test");
    test_type_annotation_e2e_step.dependOn(&run_type_annotation_e2e_tests.step);
    test_step.dependOn(&run_type_annotation_e2e_tests.step);

    // Array E2E Tests
    const array_e2e_tests = b.addTest(.{
        .name = "array_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/array_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    array_e2e_tests.linkLibC();
    array_e2e_tests.linkSystemLibrary("LLVM-21");
    array_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    array_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    array_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    array_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_array_e2e_tests = b.addRunArtifact(array_e2e_tests);

    const test_array_e2e_step = b.step("test-array-e2e", "Run Array end-to-end integration test");
    test_array_e2e_step.dependOn(&run_array_e2e_tests.step);
    test_step.dependOn(&run_array_e2e_tests.step);

    // Import/Module E2E Tests
    const import_e2e_tests = b.addTest(.{
        .name = "import_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/import_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    import_e2e_tests.linkLibC();
    import_e2e_tests.linkSystemLibrary("LLVM-21");
    import_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    import_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    import_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    import_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_import_e2e_tests = b.addRunArtifact(import_e2e_tests);

    const test_import_e2e_step = b.step("test-import-e2e", "Run Import/Module end-to-end integration test");
    test_import_e2e_step.dependOn(&run_import_e2e_tests.step);
    test_step.dependOn(&run_import_e2e_tests.step);

    // Unary Operators E2E Tests
    const unary_e2e_tests = b.addTest(.{
        .name = "unary_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/unary_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    unary_e2e_tests.linkLibC();
    unary_e2e_tests.linkSystemLibrary("LLVM-21");
    unary_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    unary_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    unary_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    unary_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_unary_e2e_tests = b.addRunArtifact(unary_e2e_tests);

    const test_unary_e2e_step = b.step("test-unary-e2e", "Run Unary Operators end-to-end integration test");
    test_unary_e2e_step.dependOn(&run_unary_e2e_tests.step);
    test_step.dependOn(&run_unary_e2e_tests.step);

    // Logical Operators E2E Tests
    const logical_e2e_tests = b.addTest(.{
        .name = "logical_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/logical_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    logical_e2e_tests.linkLibC();
    logical_e2e_tests.linkSystemLibrary("LLVM-21");
    logical_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    logical_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    logical_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    logical_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_logical_e2e_tests = b.addRunArtifact(logical_e2e_tests);

    const test_logical_e2e_step = b.step("test-logical-e2e", "Run Logical Operators end-to-end integration test");
    test_logical_e2e_step.dependOn(&run_logical_e2e_tests.step);
    test_step.dependOn(&run_logical_e2e_tests.step);

    // Modulo Operator E2E Tests
    const modulo_e2e_tests = b.addTest(.{
        .name = "modulo_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/modulo_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    modulo_e2e_tests.linkLibC();
    modulo_e2e_tests.linkSystemLibrary("LLVM-21");
    modulo_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    modulo_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    modulo_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    modulo_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_modulo_e2e_tests = b.addRunArtifact(modulo_e2e_tests);

    const test_modulo_e2e_step = b.step("test-modulo-e2e", "Run Modulo Operator end-to-end integration test");
    test_modulo_e2e_step.dependOn(&run_modulo_e2e_tests.step);
    test_step.dependOn(&run_modulo_e2e_tests.step);

    // Bitwise Operators E2E Tests
    const bitwise_e2e_tests = b.addTest(.{
        .name = "bitwise_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/bitwise_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    bitwise_e2e_tests.linkLibC();
    bitwise_e2e_tests.linkSystemLibrary("LLVM-21");
    bitwise_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    bitwise_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    bitwise_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    bitwise_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_bitwise_e2e_tests = b.addRunArtifact(bitwise_e2e_tests);

    const test_bitwise_e2e_step = b.step("test-bitwise-e2e", "Run Bitwise Operators end-to-end integration test");
    test_bitwise_e2e_step.dependOn(&run_bitwise_e2e_tests.step);
    test_step.dependOn(&run_bitwise_e2e_tests.step);

    // Numeric Literals E2E Tests
    const numeric_literals_e2e_tests = b.addTest(.{
        .name = "numeric_literals_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/numeric_literals_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    numeric_literals_e2e_tests.linkLibC();
    numeric_literals_e2e_tests.linkSystemLibrary("LLVM-21");
    numeric_literals_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    numeric_literals_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    numeric_literals_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    numeric_literals_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_numeric_literals_e2e_tests = b.addRunArtifact(numeric_literals_e2e_tests);

    const test_numeric_literals_e2e_step = b.step("test-numeric-literals-e2e", "Run Numeric Literals end-to-end integration test");
    test_numeric_literals_e2e_step.dependOn(&run_numeric_literals_e2e_tests.step);
    test_step.dependOn(&run_numeric_literals_e2e_tests.step);

    // Compound Assignment E2E Tests
    const compound_assignment_e2e_tests = b.addTest(.{
        .name = "compound_assignment_e2e_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/compound_assignment_e2e_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    compound_assignment_e2e_tests.linkLibC();
    compound_assignment_e2e_tests.linkSystemLibrary("LLVM-21");
    compound_assignment_e2e_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    compound_assignment_e2e_tests.root_module.addImport("astdb_core", astdb_core_mod);
    compound_assignment_e2e_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    compound_assignment_e2e_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_compound_assignment_e2e_tests = b.addRunArtifact(compound_assignment_e2e_tests);

    const test_compound_assignment_e2e_step = b.step("test-compound-assignment-e2e", "Run Compound Assignment end-to-end integration test");
    test_compound_assignment_e2e_step.dependOn(&run_compound_assignment_e2e_tests.step);
    test_step.dependOn(&run_compound_assignment_e2e_tests.step);

    if (enable_s0_extended) {
        const s0_neg = b.addTest(.{
            .name = "s0_negative_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/specs/s0_negative.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        s0_neg.root_module.addIncludePath(b.path("."));
        s0_neg.root_module.addImport("astdb", astdb_core_mod);

        s0_neg.root_module.addImport("region", region_mod);

        const run_s0_neg = b.addRunArtifact(s0_neg);
        test_step.dependOn(&run_s0_neg.step);
    }

    // S0 binder tests
    const s0_binder = b.addTest(.{
        .name = "s0_binder_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/specs/s0_binder.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    s0_binder.root_module.addIncludePath(b.path("."));
    s0_binder.root_module.addImport("astdb", astdb_core_mod);
    s0_binder.root_module.addImport("astdb_binder_only", astdb_binder_mod);
    const run_s0_binder = b.addRunArtifact(s0_binder);
    test_step.dependOn(&run_s0_binder.step);

    if (enable_daemon) {
        // UTCP ManualBuilder unit tests
        const utcp_manual_tests = b.addTest(.{
            .name = "utcp_manual_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/utcp_manual.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_utcp_manual_tests = b.addRunArtifact(utcp_manual_tests);
        test_step.dependOn(&run_utcp_manual_tests.step);

        // janusd main tests (HTTP routing)
        const janusd_tests = b.addTest(.{
            .name = "janusd_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/main.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        janusd_tests.linkLibC();
        janusd_tests.root_module.addImport("utcp_registry", utcp_registry_mod.?);
        // add imports for janusd tests if needed in future
        const run_janusd_tests = b.addRunArtifact(janusd_tests);
        test_step.dependOn(&run_janusd_tests.step);
    }
    if (enable_daemon) {
        // capabilities unit tests
        const caps_tests = b.addTest(.{
            .name = "caps_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/capabilities.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_caps_tests = b.addRunArtifact(caps_tests);
        test_step.dependOn(&run_caps_tests.step);

        // validator unit tests
        const validator_tests = b.addTest(.{
            .name = "validator_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/validator.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_validator_tests = b.addRunArtifact(validator_tests);
        test_step.dependOn(&run_validator_tests.step);

        // adapters unit tests
        const adapters_tests = b.addTest(.{
            .name = "adapters_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/adapters.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_adapters_tests = b.addRunArtifact(adapters_tests);
        test_step.dependOn(&run_adapters_tests.step);

        // errors unit tests
        const errors_tests = b.addTest(.{
            .name = "errors_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/errors.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_errors_tests = b.addRunArtifact(errors_tests);
        test_step.dependOn(&run_errors_tests.step);

        // metrics unit tests
        const metrics_tests = b.addTest(.{
            .name = "metrics_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("cmd/janusd/metrics.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        const run_metrics_tests = b.addRunArtifact(metrics_tests);
        test_step.dependOn(&run_metrics_tests.step);

        // end-to-end HTTP tests for UTCP routing
        const e2e_http_tests = b.addTest(.{
            .name = "e2e_http_tests",
            .root_module = b.createModule(.{
                .root_source_file = b.path("tests/unit/utcp/test_http_end_to_end.zig"),
                .target = target,
                .optimize = optimize,
            }),
        });
        e2e_http_tests.root_module.addImport("janusd_main", janusd_main_mod.?);
        const run_e2e_http_tests = b.addRunArtifact(e2e_http_tests);
        test_step.dependOn(&run_e2e_http_tests.step);
    }

    // Fuzz target for tokenizer/parser
    const fuzz = b.addExecutable(.{
        .name = "janus_fuzz",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/fuzz_tokenizer.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fuzz.linkLibC();
    if (enable_sanitizers) {
        fuzz.addCSourceFiles(.{
            .files = &[_][]const u8{},
            .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
        });
    }
    fuzz.root_module.addImport("janus_lib", lib_mod);
    b.installArtifact(fuzz);

    const fuzz_run = b.addRunArtifact(fuzz);
    fuzz_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        fuzz_run.addArgs(args);
    }

    // Standard Library Integration Tests - Allocator Contexts (Zig Implementation)
    // Note: .jan test files are specifications; actual tests in std/mem/ctx.zig
    const std_ctx_tests = b.addTest(.{
        .name = "std_ctx_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("std/mem/ctx.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const run_std_ctx_tests = b.addRunArtifact(std_ctx_tests);
    test_step.dependOn(&run_std_ctx_tests.step);

    const fuzz_step = b.step("fuzz", "Run simple tokenizer/parser fuzz");
    fuzz_step.dependOn(&fuzz_run.step);

    // QTJIR fuzz: parse → analyze → QTJIR → verify
    const fuzz_qtjir = b.addExecutable(.{
        .name = "janus_fuzz_qtjir",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/fuzz_qtjir.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fuzz_qtjir.linkLibC();
    if (enable_sanitizers) {
        fuzz_qtjir.addCSourceFiles(.{
            .files = &[_][]const u8{},
            .flags = &[_][]const u8{ "-fsanitize=address", "-fsanitize=thread", "-fsanitize=undefined" },
        });
    }
    fuzz_qtjir.root_module.addImport("janus_lib", lib_mod);
    b.installArtifact(fuzz_qtjir);

    const fuzz_qtjir_run = b.addRunArtifact(fuzz_qtjir);
    fuzz_qtjir_run.step.dependOn(b.getInstallStep());
    if (b.args) |args| fuzz_qtjir_run.addArgs(args);
    const fuzz_qtjir_step = b.step("fuzz-qtjir", "Run QTJIR fuzz (parse→analyze→QTJIR→verify)");
    fuzz_qtjir_step.dependOn(&fuzz_qtjir_run.step);

    // CAS hash tool: compute BLAKE3 ContentId for a file or stdin
    const cas_hash = b.addExecutable(.{
        .name = "cas-hash",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tools/cas_hash.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    cas_hash.root_module.addImport("janus_lib", lib_mod);
    b.installArtifact(cas_hash);

    // Graft prototype: tiny Zig static library with C-ABI surface for bridging tests
    const zig_graft_proto = b.addLibrary(.{
        .name = "zig_graft_proto",
        .root_module = b.addModule("zig_graft_proto_mod", .{
            .root_source_file = b.path("grafts/zig_proto/src/lib.zig"),
            .target = target,
            .optimize = optimize,
        }),
        .linkage = .static,
    });
    zig_graft_proto.linkLibC();
    b.installArtifact(zig_graft_proto);

    // Unit tests for graft adapter
    const graft_proto_tests = b.addTest(.{
        .name = "graft_proto_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/test_graft_proto.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    graft_proto_tests.linkLibC();
    const graft_proto_mod = b.addModule("graft_proto", .{
        .root_source_file = b.path("std/graft/proto.zig"),
        .target = target,
        .optimize = optimize,
    });
    graft_proto_tests.root_module.addImport("graft_proto", graft_proto_mod);
    const std_caps_mod = b.addModule("std_caps", .{
        .root_source_file = b.path("std/capabilities.zig"),
        .target = target,
        .optimize = optimize,
    });
    graft_proto_mod.addImport("std_caps", std_caps_mod);
    graft_proto_tests.root_module.addImport("std_caps", std_caps_mod);
    // std_caps module intentionally not wired here to keep graft tests independent
    graft_proto_tests.linkLibrary(zig_graft_proto);
    const run_graft_proto_tests = b.addRunArtifact(graft_proto_tests);
    test_step.dependOn(&run_graft_proto_tests.step);

    const graft_only = b.step("test-graft", "Run graft proto tests only");
    graft_only.dependOn(&run_graft_proto_tests.step);

    // UTCP manual test for graft proto
    const graft_utcp_tests = b.addTest(.{
        .name = "graft_utcp_manual_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/test_graft_utcp_manual.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    const std_utcp_mod = b.addModule("std_utcp", .{
        .root_source_file = b.path("std/utcp_registry.zig"),
        .target = target,
        .optimize = optimize,
    });
    graft_utcp_tests.root_module.addImport("std_utcp", std_utcp_mod);
    const graft_manuals_mod = b.addModule("graft_manuals", .{
        .root_source_file = b.path("std/graft/manuals.zig"),
        .target = target,
        .optimize = optimize,
    });
    graft_manuals_mod.addImport("std_utcp", std_utcp_mod);
    graft_utcp_tests.root_module.addImport("graft_manuals", graft_manuals_mod);
    const run_graft_utcp_tests = b.addRunArtifact(graft_utcp_tests);
    graft_only.dependOn(&run_graft_utcp_tests.step);

    // QTJIR Arrays Integration Tests (Epic 1.5)
    const qtjir_arrays_integration_tests = b.addTest(.{
        .name = "qtjir_arrays_integration_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/arrays_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    qtjir_arrays_integration_tests.linkLibC();
    qtjir_arrays_integration_tests.linkSystemLibrary("LLVM-21");
    qtjir_arrays_integration_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    qtjir_arrays_integration_tests.root_module.addImport("astdb_core", astdb_core_mod);
    qtjir_arrays_integration_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    qtjir_arrays_integration_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_qtjir_arrays_integration_tests = b.addRunArtifact(qtjir_arrays_integration_tests);

    const test_qtjir_arrays_integration_step = b.step("test-qtjir-arrays-integration", "Run QTJIR arrays integration tests");
    test_qtjir_arrays_integration_step.dependOn(&run_qtjir_arrays_integration_tests.step);
    test_step.dependOn(&run_qtjir_arrays_integration_tests.step);

    // QTJIR Panic Integration Tests (Epic 3.1)
    const panic_tests = b.addTest(.{
        .name = "panic_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/panic_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    panic_tests.linkLibC();
    panic_tests.linkSystemLibrary("LLVM-21"); // Assuming LLVM-21 as used above
    panic_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    panic_tests.root_module.addImport("astdb_core", astdb_core_mod);
    panic_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    panic_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_panic_tests = b.addRunArtifact(panic_tests);

    const test_panic_step = b.step("test-panic", "Run panic integration tests");
    test_panic_step.dependOn(&run_panic_tests.step);
    test_step.dependOn(&run_panic_tests.step);

    // QTJIR String API Integration Tests (Epic 3.1)
    const string_tests = b.addTest(.{
        .name = "string_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/string_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    string_tests.linkLibC();
    string_tests.linkSystemLibrary("LLVM-21");
    string_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    string_tests.root_module.addImport("astdb_core", astdb_core_mod);
    string_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    string_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_string_tests = b.addRunArtifact(string_tests);

    const test_string_step = b.step("test-string", "Run string API integration tests");
    test_string_step.dependOn(&run_string_tests.step);
    test_step.dependOn(&run_string_tests.step);

    // QTJIR Allocator Integration Tests (Epic 1.2)
    const allocator_tests = b.addTest(.{
        .name = "allocator_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/allocator_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    allocator_tests.linkLibC();
    allocator_tests.linkSystemLibrary("LLVM-21");
    allocator_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    allocator_tests.root_module.addImport("astdb_core", astdb_core_mod);
    allocator_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    allocator_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_allocator_tests = b.addRunArtifact(allocator_tests);

    const test_allocator_step = b.step("test-allocator", "Run allocator integration tests");
    test_allocator_step.dependOn(&run_allocator_tests.step);
    test_step.dependOn(&run_allocator_tests.step);

    // QTJIR Recursion Integration Tests (Epic 3.2)
    const recursion_tests = b.addTest(.{
        .name = "recursion_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/recursion_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    recursion_tests.linkLibC();
    recursion_tests.linkSystemLibrary("LLVM-21");
    recursion_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    recursion_tests.root_module.addImport("astdb_core", astdb_core_mod);
    recursion_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    recursion_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_recursion_tests = b.addRunArtifact(recursion_tests);

    const test_recursion_step = b.step("test-recursion", "Run recursion integration tests");
    test_recursion_step.dependOn(&run_recursion_tests.step);
    test_step.dependOn(&run_recursion_tests.step);

    // While Loop Integration Tests
    const while_tests = b.addTest(.{
        .name = "while_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/while_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    while_tests.linkLibC();
    while_tests.linkSystemLibrary("LLVM-21");
    while_tests.root_module.addIncludePath(.{ .cwd_relative = "/usr/include" });
    while_tests.root_module.addImport("astdb_core", astdb_core_mod);
    while_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    while_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_while_tests = b.addRunArtifact(while_tests);

    const test_while_step = b.step("test-while", "Run while loop integration tests");
    test_while_step.dependOn(&run_while_tests.step);
    test_step.dependOn(&run_while_tests.step);

    // Postfix Guard Clauses Tests (RFC-018)
    const postfix_guards_tests = b.addTest(.{
        .name = "postfix_guards_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/postfix_guards_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    postfix_guards_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    postfix_guards_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_postfix_guards_tests = b.addRunArtifact(postfix_guards_tests);

    const test_postfix_guards_step = b.step("test-postfix-guards", "Run postfix guard clauses integration tests");
    test_postfix_guards_step.dependOn(&run_postfix_guards_tests.step);
    test_step.dependOn(&run_postfix_guards_tests.step);

    // Postfix Guard Parser Unit Tests
    const postfix_guards_parser_tests = b.addTest(.{
        .name = "postfix_guards_parser_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/unit/postfix_guards_parser_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    postfix_guards_parser_tests.root_module.addImport("janus_parser", libjanus_parser_mod);
    postfix_guards_parser_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_postfix_guards_parser_tests = b.addRunArtifact(postfix_guards_parser_tests);

    const test_postfix_guards_parser_step = b.step("test-postfix-parser", "Run postfix guard parser unit tests");
    test_postfix_guards_parser_step.dependOn(&run_postfix_guards_parser_tests.step);
    test_step.dependOn(&run_postfix_guards_parser_tests.step);

    // Semantic Pipeline Integration Tests
    // TODO: This test file needs updating to match current API (TypeInference.init signature, etc.)
    // For now, use test-e2e-semantic which covers the essential semantic pipeline functionality
    // const semantic_pipeline_tests = b.addTest(.{
    //     .name = "semantic_pipeline_integration_tests",
    //     .root_module = b.createModule(.{
    //         .root_source_file = b.path("tests/integration/semantic/test_semantic_pipeline_integration.zig"),
    //         .target = target,
    //         .optimize = optimize,
    //     }),
    // });
    // semantic_pipeline_tests.root_module.addImport("astdb_core", astdb_core_mod);
    // semantic_pipeline_tests.root_module.addImport("astdb", lib_mod);
    // semantic_pipeline_tests.root_module.addImport("semantic", semantic_mod);
    // const run_semantic_pipeline_tests = b.addRunArtifact(semantic_pipeline_tests);
    //
    // const test_semantic_pipeline_step = b.step("test-semantic-pipeline", "Run semantic pipeline integration tests");
    // test_semantic_pipeline_step.dependOn(&run_semantic_pipeline_tests.step);
    // test_step.dependOn(&run_semantic_pipeline_tests.step);

    // End-to-End Semantic Pipeline Tests
    const e2e_semantic_tests = b.addTest(.{
        .name = "e2e_semantic_pipeline_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/semantic/test_end_to_end_semantic_pipeline.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    e2e_semantic_tests.root_module.addImport("astdb", astdb_core_mod);
    e2e_semantic_tests.root_module.addImport("semantic", semantic_mod);
    const run_e2e_semantic_tests = b.addRunArtifact(e2e_semantic_tests);

    const test_e2e_semantic_step = b.step("test-e2e-semantic", "Run end-to-end semantic pipeline tests");
    test_e2e_semantic_step.dependOn(&run_e2e_semantic_tests.step);
    test_step.dependOn(&run_e2e_semantic_tests.step);

    // Match Expression Parser Tests
    const match_expression_tests = b.addTest(.{
        .name = "match_expression_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/integration/semantic/test_match_expression.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    match_expression_tests.root_module.addImport("libjanus", lib_mod);
    match_expression_tests.root_module.addImport("astdb", astdb_core_mod);
    const run_match_expression_tests = b.addRunArtifact(match_expression_tests);

    const test_match_step = b.step("test-match", "Run match expression integration tests");
    test_match_step.dependOn(&run_match_expression_tests.step);
    test_step.dependOn(&run_match_expression_tests.step);

    // Grafting Features (Pipeline + UFCS)
    const grafting_tests = b.addTest(.{
        .name = "grafting_features_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/libjanus/tests/pipeline_desugar_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    grafting_tests.root_module.addImport("libjanus", lib_mod);
    grafting_tests.root_module.addImport("astdb_core", astdb_core_mod);
    const run_grafting_tests = b.addRunArtifact(grafting_tests);

    const test_grafting_step = b.step("test-grafting", "Run grafting features (pipeline, UFCS) tests");
    test_grafting_step.dependOn(&run_grafting_tests.step);
    test_step.dependOn(&run_grafting_tests.step);

    // Core Profile CodeGen Tests
    const core_codegen_tests = b.addTest(.{
        .name = "core_codegen_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/libjanus/tests/core_codegen_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    core_codegen_tests.root_module.addImport("libjanus", lib_mod);
    core_codegen_tests.root_module.addImport("astdb_core", astdb_core_mod);
    core_codegen_tests.root_module.addImport("qtjir", qtjir_mod);
    const run_core_codegen_tests = b.addRunArtifact(core_codegen_tests);

    const test_core_codegen_step = b.step("test-core-codegen", "Run core profile code generator tests");
    test_core_codegen_step.dependOn(&run_core_codegen_tests.step);
    test_step.dependOn(&run_core_codegen_tests.step);

    // Error Framework Tests
    const error_framework_tests = b.addTest(.{
        .name = "error_framework_tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("compiler/libjanus/tests/error_framework_test.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    error_framework_tests.root_module.addImport("compiler_errors", compiler_errors_mod);
    error_framework_tests.root_module.addImport("janus_tokenizer", tokenizer_mod);
    const run_error_framework_tests = b.addRunArtifact(error_framework_tests);

    const test_error_framework_step = b.step("test-errors", "Run error framework tests");
    test_error_framework_step.dependOn(&run_error_framework_tests.step);
    test_step.dependOn(&run_error_framework_tests.step);
}
