// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const compat_fs = @import("compat_fs");
const janus_lib = @import("janus_lib");

// Janus SBOM Generator
// Generates CycloneDX and SPDX Software Bill of Materials
// Implements the security transparency commitments from SECURITY.md

const SBOMFormat = enum {
    cyclonedx,
    spdx,
    both,
};

const SBOMConfig = struct {
    format: SBOMFormat,
    output_dir: []const u8,
    project_version: []const u8,
    include_dev_dependencies: bool,

    const Self = @This();

    pub fn parseArgs(allocator: std.mem.Allocator, args: [][]const u8) !Self {
        var config = Self{
            .format = .both,
            .output_dir = "dist",
            .project_version = "0.1.0-pre-alpha",
            .include_dev_dependencies = false,
        };

        for (args) |arg| {
            if (std.mem.startsWith(u8, arg, "--format=")) {
                const format_str = arg[9..];
                if (std.mem.eql(u8, format_str, "cyclonedx")) {
                    config.format = .cyclonedx;
                } else if (std.mem.eql(u8, format_str, "spdx")) {
                    config.format = .spdx;
                } else if (std.mem.eql(u8, format_str, "cyclonedx,spdx") or std.mem.eql(u8, format_str, "both")) {
                    config.format = .both;
                }
            } else if (std.mem.startsWith(u8, arg, "--output-dir=")) {
                config.output_dir = arg[12..];
            } else if (std.mem.startsWith(u8, arg, "--project-version=")) {
                config.project_version = arg[17..];
            } else if (std.mem.startsWith(u8, arg, "--include-dev-dependencies=")) {
                const value = arg[27..];
                config.include_dev_dependencies = std.mem.eql(u8, value, "true");
            }
        }

        return config;
    }
};

const Component = struct {
    name: []const u8,
    version: []const u8,
    type: []const u8,
    supplier: ?[]const u8,
    description: ?[]const u8,
    licenses: [][]const u8,
    []Hash,

    const Hash = struct {
        algorithm: []const u8,
        value: []const u8,
    };
};

const JanusProject = struct {
    name: []const u8,
    version: []const u8,
    description: []const u8,
    components: []Component,

    const Self = @This();

    pub fn analyze(allocator: std.mem.Allocator, version: []const u8) !Self {
        // Analyze the Janus project structure and dependencies
        var components: std.ArrayList(Component) = .empty;
        defer components.deinit();

        // Core compiler component
        try components.append(Component{
            .name = "libjanus",
            .version = version,
            .type = "library",
            .supplier = "Janus Language Project",
            .description = "Janus compiler core library",
            .licenses = &[_][]const u8{"LSL-1.0"},
            .hashes = &[_]Component.Hash{
                .{ .algorithm = "BLAKE3", .value = "placeholder-hash" },
            },
        });

        // Standard library component
        try components.append(Component{
            .name = "janus-std",
            .version = version,
            .type = "library",
            .supplier = "Janus Language Project",
            .description = "Janus standard library",
            .licenses = &[_][]const u8{"Apache-2.0"},
            .hashes = &[_]Component.Hash{
                .{ .algorithm = "BLAKE3", .value = "placeholder-hash" },
            },
        });

        // BLAKE3 dependency
        try components.append(Component{
            .name = "blake3",
            .version = "1.5.0",
            .type = "library",
            .supplier = "BLAKE3 Team",
            .description = "BLAKE3 cryptographic hash function",
            .licenses = &[_][]const u8{ "CC0-1.0", "Apache-2.0" },
            .hashes = &[_]Component.Hash{
                .{ .algorithm = "SHA-256", .value = "placeholder-hash" },
            },
        });

        // Zig compiler (build dependency)
        try components.append(Component{
            .name = "zig",
            .version = "0.13.0",
            .type = "application",
            .supplier = "Zig Software Foundation",
            .description = "Zig programming language compiler",
            .licenses = &[_][]const u8{"MIT"},
            .hashes = &[_]Component.Hash{
                .{ .algorithm = "SHA-256", .value = "placeholder-hash" },
            },
        });

        return Self{
            .name = "janus",
            .version = version,
            .description = "A systems language combining fluent ergonomics with explicit control",
            .components = try components.toOwnedSlice(),
        };
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        allocator.free(self.components);
    }
};

fn generateCycloneDX(allocator: std.mem.Allocator, project: *const JanusProject, output_path: []const u8) !void {
    const file = try compat_fs.createFile(output_path, .{});
    defer file.close();

    var writer = file.writer();

    // Generate CycloneDX JSON format
    try writer.print(
        \\{{
        \\  "bomFormat": "CycloneDX",
        \\  "specVersion": "1.5",
        \\  "serialNumber": "urn:uuid:janus-{s}-cyclonedx",
        \\  "version": 1,
        \\  "metadata": {{
        \\    "timestamp": "{s}",
        \\    "tools": [
        \\      {{
        \\        "vendor": "Janus Language Project",
        \\        "name": "janus-sbom-generator",
        \\        "version": "{s}"
        \\      }}
        \\    ],
        \\    "component": {{
        \\      "type": "application",
        \\      "bom-ref": "janus-root",
        \\      "name": "{s}",
        \\      "version": "{s}",
        \\      "description": "{s}",
        \\      "licenses": [
        \\        {{
        \\          "license": {{
        \\            "id": "LSL-1.0"
        \\          }}
        \\        }}
        \\      ]
        \\    }}
        \\  }},
        \\  "components": [
    , .{ project.version, getCurrentTimestamp(), project.version, project.name, project.version, project.description });

    // Add components
    for (project.components, 0..) |component, i| {
        if (i > 0) try writer.writeAll(",");
        try writer.print(
            \\
            \\    {{
            \\      "type": "{s}",
            \\      "bom-ref": "{s}-{s}",
            \\      "name": "{s}",
            \\      "version": "{s}",
            \\      "supplier": {{
            \\        "name": "{s}"
            \\      }},
            \\      "description": "{s}",
            \\      "licenses": [
        , .{ component.type, component.name, component.version, component.name, component.version, component.supplier orelse "Unknown", component.description orelse "" });

        // Add licenses
        for (component.licenses, 0..) |license, j| {
            if (j > 0) try writer.writeAll(",");
            try writer.print(
                \\
                \\        {{
                \\          "license": {{
                \\            "id": "{s}"
                \\          }}
                \\        }}
            , .{license});
        }

        try writer.writeAll(
            \\
            \\      ],
            \\      "hashes": [
        );

        // Add hashes
        for (component.hashes, 0..) |hash, k| {
            if (k > 0) try writer.writeAll(",");
            try writer.print(
                \\
                \\        {{
                \\          "alg": "{s}",
                \\          "content": "{s}"
                \\        }}
            , .{ hash.algorithm, hash.value });
        }

        try writer.writeAll(
            \\
            \\      ]
            \\    }
        );
    }

    try writer.writeAll(
        \\
        \\  ]
        \\}
    );

    std.log.info("Generated CycloneDX SBOM: {s}", .{output_path});
}

fn generateSPDX(allocator: std.mem.Allocator, project: *const JanusProject, output_path: []const u8) !void {
    const file = try compat_fs.createFile(output_path, .{});
    defer file.close();

    var writer = file.writer();

    // Generate SPDX JSON format
    try writer.print(
        \\{{
        \\  "spdxVersion": "SPDX-2.3",
        \\  "dataLicense": "CC0-1.0",
        \\  "SPDXID": "SPDXRef-DOCUMENT",
        \\  "name": "Janus-{s}-SPDX",
        \\  "documentNamespace": "https://janus-lang.org/spdx/janus-{s}",
        \\  "creationInfo": {{
        \\    "created": "{s}",
        \\    "creators": [
        \\      "Tool: janus-sbom-generator-{s}"
        \\    ]
        \\  }},
        \\  "packages": [
        \\    {{
        \\      "SPDXID": "SPDXRef-Package-Janus",
        \\      "name": "{s}",
        \\      "versionInfo": "{s}",
        \\      "downloadLocation": "https://github.com/janus-lang/janus",
        \\      "filesAnalyzed": false,
        \\      "licenseConcluded": "LSL-1.0",
        \\      "licenseDeclared": "LSL-1.0",
        \\      "copyrightText": "Copyright (c) 2025 Janus Language Project"
        \\    }}
    , .{ project.version, project.version, getCurrentTimestamp(), project.version, project.name, project.version });

    // Add component packages
    for (project.components) |component| {
        try writer.print(
            \\,
            \\    {{
            \\      "SPDXID": "SPDXRef-Package-{s}",
            \\      "name": "{s}",
            \\      "versionInfo": "{s}",
            \\      "downloadLocation": "NOASSERTION",
            \\      "filesAnalyzed": false,
            \\      "licenseConcluded": "{s}",
            \\      "licenseDeclared": "{s}",
            \\      "copyrightText": "NOASSERTION"
            \\    }}
        , .{ component.name, component.name, component.version, component.licenses[0], component.licenses[0] });
    }

    try writer.writeAll(
        \\
        \\  ]
        \\}
    );

    std.log.info("Generated SPDX SBOM: {s}", .{output_path});
}

fn getCurrentTimestamp() []const u8 {
    // Return current timestamp in ISO 8601 format
    // For now, return a placeholder - in real implementation, use std.time
    return "2025-08-21T13:50:00Z";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    const config = try SBOMConfig.parseArgs(allocator, args[1..]);

    // Ensure output directory exists
    compat_fs.makeDir(config.output_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };

    // Analyze project
    var project = try JanusProject.analyze(allocator, config.project_version);
    defer project.deinit(allocator);

    // Generate SBOMs based on format
    switch (config.format) {
        .cyclonedx => {
            const output_path = try std.fmt.allocPrint(allocator, "{s}/janus-{s}-cyclonedx.json", .{ config.output_dir, config.project_version });
            defer allocator.free(output_path);
            try generateCycloneDX(allocator, &project, output_path);
        },
        .spdx => {
            const output_path = try std.fmt.allocPrint(allocator, "{s}/janus-{s}-spdx.json", .{ config.output_dir, config.project_version });
            defer allocator.free(output_path);
            try generateSPDX(allocator, &project, output_path);
        },
        .both => {
            const cyclonedx_path = try std.fmt.allocPrint(allocator, "{s}/janus-{s}-cyclonedx.json", .{ config.output_dir, config.project_version });
            defer allocator.free(cyclonedx_path);
            try generateCycloneDX(allocator, &project, cyclonedx_path);

            const spdx_path = try std.fmt.allocPrint(allocator, "{s}/janus-{s}-spdx.json", .{ config.output_dir, config.project_version });
            defer allocator.free(spdx_path);
            try generateSPDX(allocator, &project, spdx_path);
        },
    }

    std.log.info("SBOM generation completed successfully", .{});
}
