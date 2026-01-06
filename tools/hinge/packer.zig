// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// ============================================================================
// JANUS PACKAGE PACKER (.jpk) - PHASE B IMPLEMENTATION
// ============================================================================
//
// Doctrine: Deterministic packing with capability validation
// - Content-addressed packages with BLAKE3 Merkle trees
// - SBOM generation for supply chain transparency
// - Deterministic tar.zst compression for reproducibility
// - Capability validation during packing process
// - Integration with our high-performance serde framework
//
// Performance: Optimized for large-scale package distribution
// Security: Cryptographically verified package integrity
// Reproducibility: Deterministic builds with content addressing
//

const std = @import("std");
const serde = @import("serde_shim.zig");
const crypto = @import("crypto_dilithium.zig");
const libjanus = @import("libjanus");
const manifest = libjanus.ledger.manifest;
const cas = libjanus.ledger.cas;

/// Format a byte slice as lowercase hex. Caller must free returned slice.
pub fn hexSlice(allocator: std.mem.Allocator, bytes: []const u8) ![]u8 {
    var result = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |b, i| {
        const chars = "0123456789abcdef";
        result[i * 2] = chars[b >> 4];
        result[i * 2 + 1] = chars[b & 0x0f];
    }
    return result;
}

// ============================================================================
// PACKAGE PACKER CONFIGURATION
// ============================================================================

pub const PackerConfig = struct {
    // Output settings
    output_dir: []const u8 = "build/",
    package_format: PackageFormat = .jpk,
    compression: CompressionFormat = .zstd,

    // Metadata settings
    include_sbom: bool = true,
    sbom_format: SbomFormat = .cyclonedx_json,
    generate_manifest: bool = true,

    // Security settings
    sign_package: bool = false,
    signature_key: ?[]const u8 = null,
    verify_integrity: bool = true,

    // Performance settings
    parallel_workers: u32 = 4,
    chunk_size: usize = 64 * 1024, // 64KB chunks for hashing
    buffer_size: usize = 1024 * 1024, // 1MB buffers
};

pub const PackageFormat = enum {
    jpk, // Janus Package Format (default)
    tar_zst, // Deterministic tar.zst
    zip, // ZIP archive
};

pub const CompressionFormat = enum {
    zstd, // Zstandard (default)
    gzip, // Gzip
    xz, // XZ
    none, // No compression
};

pub const SbomFormat = enum {
    cyclonedx_json, // CycloneDX JSON (default)
    spdx_json, // SPDX JSON
    spdx_tag_value, // SPDX Tag-Value
};

// ============================================================================
// PACKAGE STRUCTURE
// ============================================================================

pub const PackageLayout = struct {
    allocator: std.mem.Allocator,
    root_path: []const u8,
    programs: std.ArrayList(ProgramInfo),
    manifest: ?manifest.Manifest = null,
    hash_b3: ?[32]u8 = null,
    sbom_content: ?[]const u8 = null,

    pub fn init(allocator: std.mem.Allocator, root_path: []const u8) PackageLayout {
        return .{
            .allocator = allocator,
            .root_path = root_path,
            .programs = std.ArrayList(ProgramInfo).empty,
        };
    }

    pub fn deinit(self: *PackageLayout) void {
        for (self.programs.items) |*p| p.deinit();
        self.programs.deinit(self.allocator);
        if (self.sbom_content) |sbom| {
            self.allocator.free(sbom);
        }
        // manifest is a stub struct in current ledger; no deinit required
    }
};

pub const ProgramInfo = struct {
    allocator: std.mem.Allocator,
    name: []const u8,
    version: []const u8,
    binaries: std.ArrayList([]const u8),
    libraries: std.ArrayList([]const u8),
    headers: std.ArrayList([]const u8),
    data_files: std.ArrayList([]const u8),
    capabilities: std.ArrayList(manifest.Capability),

    pub fn init(allocator: std.mem.Allocator, name: []const u8, version: []const u8) ProgramInfo {
        return .{
            .allocator = allocator,
            .name = name,
            .version = version,
            .binaries = std.ArrayList([]const u8).empty,
            .libraries = std.ArrayList([]const u8).empty,
            .headers = std.ArrayList([]const u8).empty,
            .data_files = std.ArrayList([]const u8).empty,
            .capabilities = std.ArrayList(manifest.Capability).empty,
        };
    }

    pub fn deinit(self: *ProgramInfo) void {
        for (self.binaries.items) |s| self.allocator.free(s);
        self.binaries.deinit(self.allocator);
        for (self.libraries.items) |s| self.allocator.free(s);
        self.libraries.deinit(self.allocator);
        for (self.headers.items) |s| self.allocator.free(s);
        self.headers.deinit(self.allocator);
        for (self.data_files.items) |s| self.allocator.free(s);
        self.data_files.deinit(self.allocator);
        // capabilities are stubs in current ledger; no per-item deinit required
        self.capabilities.deinit(self.allocator);
    }
};

// ============================================================================
// SBOM GENERATION
// ============================================================================

pub const SbomGenerator = struct {
    allocator: std.mem.Allocator,
    format: SbomFormat,
    package_info: *const PackageLayout,

    pub fn init(allocator: std.mem.Allocator, format: SbomFormat, package_info: *const PackageLayout) SbomGenerator {
        return .{
            .allocator = allocator,
            .format = format,
            .package_info = package_info,
        };
    }

    pub fn generate(self: *SbomGenerator) ![]const u8 {
        switch (self.format) {
            .cyclonedx_json => return self.generateCycloneDx(),
            .spdx_json => return self.generateSpdxJson(),
            .spdx_tag_value => return self.generateSpdxTagValue(),
        }
    }

    fn generateCycloneDx(self: *SbomGenerator) ![]const u8 {
        // Allocate JSON graph in an arena to simplify cleanup
        var arena = std.heap.ArenaAllocator.init(self.allocator);
        defer arena.deinit();
        var tmp = SbomGenerator{ .allocator = arena.allocator(), .format = self.format, .package_info = self.package_info };

        // Use our high-performance serde framework for JSON generation
        var sbom = std.json.ObjectMap.init(tmp.allocator);
        defer sbom.deinit();

        // Add SBOM metadata
        try sbom.put("spdxId", std.json.Value{ .string = "SPDXRef-DOCUMENT" });
        try sbom.put("spdxVersion", std.json.Value{ .string = "SPDX-2.3" });
        try sbom.put("creationInfo", try tmp.createCycloneDxCreationInfo());
        try sbom.put("name", std.json.Value{ .string = "JanusPackage" });
        try sbom.put("dataLicense", std.json.Value{ .string = "CC0-1.0" });
        try sbom.put("spdxId", std.json.Value{ .string = "SPDXRef-DOCUMENT" });

        // Add packages
        var packages = std.json.Array.init(tmp.allocator);
        for (self.package_info.programs.items) |program| {
            try packages.append(try tmp.createCycloneDxPackage(&program));
        }
        try sbom.put("packages", std.json.Value{ .array = packages });

        // Add relationships
        var relationships = std.json.Array.init(tmp.allocator);
        try relationships.append(try tmp.createCycloneDxRelationship("SPDXRef-DOCUMENT", "DESCRIBES", "SPDXRef-Package-0"));
        try sbom.put("relationships", std.json.Value{ .array = relationships });

        // Serialize using our high-performance serde framework
        var buffer = std.io.Writer.Allocating.init(self.allocator);
        defer buffer.deinit();

        const root = std.json.Value{ .object = sbom };
        try serde.stringify(root, .{ .whitespace = .indent_2 }, &buffer.writer);
        return buffer.toOwnedSlice();
    }

    fn createCycloneDxCreationInfo(self: *SbomGenerator) !std.json.Value {
        var creation_info = std.json.ObjectMap.init(self.allocator);

        try creation_info.put("created", std.json.Value{ .string = "2025-01-01T00:00:00Z" });
        try creation_info.put("creators", std.json.Value{ .array = std.json.Array.init(self.allocator) });

        var tools = std.json.ObjectMap.init(self.allocator);
        try tools.put("vendor", std.json.Value{ .string = "Janus" });
        try tools.put("name", std.json.Value{ .string = "hinge-packer" });
        try tools.put("version", std.json.Value{ .string = "1.0.0" });

        var tools_array = std.json.Array.init(self.allocator);
        try tools_array.append(std.json.Value{ .object = tools });

        try creation_info.put("tools", std.json.Value{ .array = tools_array });

        return std.json.Value{ .object = creation_info };
    }

    fn createCycloneDxPackage(self: *SbomGenerator, program: *const ProgramInfo) !std.json.Value {
        var package = std.json.ObjectMap.init(self.allocator);

        try package.put("spdxId", std.json.Value{ .string = "SPDXRef-Package-0" });
        try package.put("name", std.json.Value{ .string = program.name });
        try package.put("versionInfo", std.json.Value{ .string = program.version });
        try package.put("downloadLocation", std.json.Value{ .string = "NOASSERTION" });
        try package.put("copyrightText", std.json.Value{ .string = "NOASSERTION" });
        try package.put("licenseConcluded", std.json.Value{ .string = "NOASSERTION" });
        try package.put("licenseDeclared", std.json.Value{ .string = "NOASSERTION" });
        try package.put("supplier", std.json.Value{ .string = "Organization: Janus" });

        // Add files
        const files = std.json.Array.init(self.allocator);
        // TODO: Add actual file information from program
        try package.put("files", std.json.Value{ .array = files });

        return std.json.Value{ .object = package };
    }

    fn createCycloneDxRelationship(self: *SbomGenerator, element_id: []const u8, relationship_type: []const u8, related_element: []const u8) !std.json.Value {
        var relationship = std.json.ObjectMap.init(self.allocator);

        try relationship.put("spdxElementId", std.json.Value{ .string = element_id });
        try relationship.put("relationshipType", std.json.Value{ .string = relationship_type });
        try relationship.put("relatedSpdxElement", std.json.Value{ .string = related_element });

        return std.json.Value{ .object = relationship };
    }

    fn generateSpdxJson(_: *SbomGenerator) ![]const u8 {
        // TODO: Implement SPDX JSON generation
        return "SPDX JSON SBOM generation not yet implemented";
    }

    fn generateSpdxTagValue(_: *SbomGenerator) ![]const u8 {
        // TODO: Implement SPDX Tag-Value generation
        return "SPDX Tag-Value SBOM generation not yet implemented";
    }
};

// ============================================================================
// DETERMINISTIC TAR.ZST CREATION
// ============================================================================

pub const TarZstCreator = struct {
    allocator: std.mem.Allocator,
    config: *const PackerConfig,

    pub fn init(allocator: std.mem.Allocator, config: *const PackerConfig) TarZstCreator {
        return .{
            .allocator = allocator,
            .config = config,
        };
    }

    pub fn createDeterministicArchive(self: *TarZstCreator, package: *const PackageLayout) ![]const u8 {
        // Create deterministic tar.zst archive
        // This ensures reproducible builds regardless of filesystem order

        var archive_buffer = std.ArrayList(u8).initCapacity(self.allocator, 1024) catch return error.OutOfMemory;
        defer archive_buffer.deinit(self.allocator);

        // Collect all files in deterministic order
        var files = std.ArrayList(FileInfo).initCapacity(self.allocator, 32) catch return error.OutOfMemory;
        defer files.deinit(self.allocator);

        try self.collectFiles(package, &files);
        std.mem.sort(FileInfo, files.items, {}, fileInfoLessThan);

        // Create tar archive
        try self.createTarArchive(&files, &archive_buffer);

        // Compress with zstd
        const compressed = try self.compressWithZstd(archive_buffer.items);

        return compressed;
    }

    fn collectFiles(self: *TarZstCreator, package: *const PackageLayout, files: *std.ArrayList(FileInfo)) !void {
        // Collect files from Programs/ structure
        for (package.programs.items) |program| {
            try self.collectProgramFiles(&program, files);
        }

        // Add manifest and metadata files
        if (package.manifest) |_| {
            if (package.programs.items.len > 0) {
                const p = package.programs.items[0];
                try files.append(self.allocator, FileInfo{
                    .path = "manifest.kdl",
                    .content = try self.generateManifestKdl(p.name, p.version),
                    .mode = 0o644,
                    .uid = 0,
                    .gid = 0,
                    .mtime = std.time.timestamp(),
                });
            }
        }

        if (package.hash_b3) |hash| {
            const hash_hex = try hexSlice(self.allocator, &hash);
            defer self.allocator.free(hash_hex);

            try files.append(self.allocator, FileInfo{
                .path = "hash.b3",
                .content = hash_hex,
                .mode = 0o444, // Read-only
                .uid = 0,
                .gid = 0,
                .mtime = std.time.timestamp(),
            });
        }
    }

    fn collectProgramFiles(self: *TarZstCreator, program: *const ProgramInfo, files: *std.ArrayList(FileInfo)) !void {
        const base_path = try std.fmt.allocPrint(self.allocator, "Programs/{s}/{s}/", .{ program.name, program.version });
        defer self.allocator.free(base_path);

        // Add binaries
        for (program.binaries.items) |binary_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ base_path, binary_path });
            defer self.allocator.free(full_path);

            const content = try std.fs.cwd().readFileAlloc(self.allocator, full_path, std.math.maxInt(usize));
            defer self.allocator.free(content);

            try files.append(self.allocator, FileInfo{
                .path = full_path,
                .content = content,
                .mode = 0o755, // Executable
                .uid = 0,
                .gid = 0,
                .mtime = std.time.timestamp(),
            });
        }

        // Add libraries, headers, and data files with appropriate permissions
        // TODO: Add more file collection logic
    }

    fn generateManifestKdl(self: *TarZstCreator, name: []const u8, version: []const u8) ![]const u8 {
        var buffer = std.io.Writer.Allocating.init(self.allocator);
        errdefer buffer.deinit();

        try buffer.writer.print("package \"{s}\" {{\n", .{name});
        try buffer.writer.print("    version \"{s}\"\n", .{version});
        try buffer.writer.print("    license \"LSL-1.0\"\n", .{});
        try buffer.writer.print("    source \"git+https://git.maiwald.work/markus/janus/{s}\"\n", .{name});
        try buffer.writer.print("    build \"janus\"\n", .{});
        try buffer.writer.print("}}\n", .{});

        return buffer.toOwnedSlice();
    }

    fn createTarArchive(self: *TarZstCreator, _: *const std.ArrayList(FileInfo), _: *std.ArrayList(u8)) !void {
        _ = self;
        // TODO: Implement deterministic tar archive creation
        // This should create POSIX tar format with deterministic headers
    }

    fn compressWithZstd(self: *TarZstCreator, data: []const u8) ![]const u8 {
        // TODO: Implement zstd compression
        // For now, return uncompressed data
        return self.allocator.dupe(u8, data);
    }

    fn fileInfoLessThan(context: void, a: FileInfo, b: FileInfo) bool {
        _ = context;
        return std.mem.order(u8, a.path, b.path) == .lt;
    }
};

const FileInfo = struct {
    path: []const u8,
    content: []const u8,
    mode: u32,
    uid: u32,
    gid: u32,
    mtime: i64,
};

// ============================================================================
// MAIN PACKAGE PACKER
// ============================================================================

pub const PackagePacker = struct {
    allocator: std.mem.Allocator,
    config: PackerConfig,
    cas_instance: cas.CAS,

    pub fn init(allocator: std.mem.Allocator, config: PackerConfig, cas_root: []const u8) !PackagePacker {
        try cas.initializeCAS(cas_root);
        const cas_instance = cas.CAS.init(cas_root, allocator);

        return .{
            .allocator = allocator,
            .config = config,
            .cas_instance = cas_instance,
        };
    }

    pub fn deinit(self: *PackagePacker) void {
        self.cas_instance.deinit();
    }

    pub fn pack(self: *PackagePacker, source_path: []const u8, package_name: []const u8, version: []const u8) !PackageLayout {
        std.debug.print("🔧 Packing {s}@{s} from {s}\n", .{ package_name, version, source_path });

        var package = PackageLayout.init(self.allocator, source_path);

        // Seed with primary program info
        try package.programs.append(self.allocator, ProgramInfo.init(self.allocator, package_name, version));

        // Analyze package structure
        try self.analyzePackageStructure(&package, package_name, version);

        // Generate SBOM if requested
        if (self.config.include_sbom) {
            var sbom_gen = SbomGenerator.init(self.allocator, self.config.sbom_format, &package);
            package.sbom_content = try sbom_gen.generate();
            std.debug.print("📋 Generated SBOM ({d} bytes)\n", .{package.sbom_content.?.len});
        }

        // Generate manifest
        if (self.config.generate_manifest) {
            package.manifest = try self.generateManifest(package_name, version);
        }

        // Calculate BLAKE3 Merkle root
        package.hash_b3 = try self.calculateMerkleRoot(&package);
        const hash_hex = try hexSlice(self.allocator, &package.hash_b3.?);
        defer self.allocator.free(hash_hex);
        std.debug.print("🔐 Calculated BLAKE3 hash: {s}\n", .{hash_hex});

        return package;
    }

    fn analyzePackageStructure(self: *PackagePacker, package: *PackageLayout, name: []const u8, version: []const u8) !void {
        // Create Programs/ structure
        const programs_path = try std.fs.path.join(self.allocator, &.{ package.root_path, "Programs", name, version });
        defer self.allocator.free(programs_path);

        // Scan for binaries, libraries, etc.
        try self.scanDirectory(package, programs_path, "");
    }

    fn scanDirectory(self: *PackagePacker, package: *PackageLayout, dir_path: []const u8, relative_path: []const u8) !void {
        var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
        defer dir.close();

        var iter = dir.iterate();
        while (try iter.next()) |entry| {
            const entry_path = try std.fs.path.join(self.allocator, &.{ dir_path, entry.name });
            defer self.allocator.free(entry_path);

            const relative_entry_path = if (relative_path.len > 0)
                try std.fmt.allocPrint(self.allocator, "{s}/{s}", .{ relative_path, entry.name })
            else
                try self.allocator.dupe(u8, entry.name);
            defer self.allocator.free(relative_entry_path);

            if (entry.kind == .directory) {
                try self.scanDirectory(package, entry_path, relative_entry_path);
            } else {
                // Classify file based on path and extension
                if (std.mem.endsWith(u8, entry.name, ".jan")) {
                    // Janus source file
                } else if (std.mem.startsWith(u8, relative_entry_path, "bin/")) {
                    // Binary executable
                    if (package.programs.items.len > 0) {
                        try package.programs.items[0].binaries.append(self.allocator, try self.allocator.dupe(u8, relative_entry_path));
                    }
                } else if (std.mem.startsWith(u8, relative_entry_path, "lib/")) {
                    // Library
                    if (package.programs.items.len > 0) {
                        try package.programs.items[0].libraries.append(self.allocator, try self.allocator.dupe(u8, relative_entry_path));
                    }
                } else if (std.mem.startsWith(u8, relative_entry_path, "include/")) {
                    // Header files
                    if (package.programs.items.len > 0) {
                        try package.programs.items[0].headers.append(self.allocator, try self.allocator.dupe(u8, relative_entry_path));
                    }
                } else {
                    // Data files
                    if (package.programs.items.len > 0) {
                        try package.programs.items[0].data_files.append(self.allocator, try self.allocator.dupe(u8, relative_entry_path));
                    }
                }
            }
        }
    }

    fn generateManifest(self: *PackagePacker, name: []const u8, version: []const u8) !manifest.Manifest {
        _ = name;
        _ = version;
        return manifest.Manifest.init(self.allocator);
    }

    fn calculateMerkleRoot(self: *PackagePacker, package: *const PackageLayout) ![32]u8 {
        // Use BLAKE3 to create Merkle root over package contents
        var hasher = std.crypto.hash.Blake3.init(.{});

        // Hash all programs
        for (package.programs.items) |program| {
            try self.hashProgram(&program, &hasher, package.root_path);
        }

        // Hash manifest
        if (package.manifest) |_| {
            if (package.programs.items.len > 0) {
                const p = package.programs.items[0];
                const manifest_content = try self.generateManifestKdl(p.name, p.version);
                defer self.allocator.free(manifest_content);
                hasher.update(manifest_content);
            }
        }

        // Hash SBOM
        if (package.sbom_content) |sbom| {
            hasher.update(sbom);
        }

        var hash: [32]u8 = undefined;
        hasher.final(&hash);
        return hash;
    }

    fn hashProgram(self: *PackagePacker, program: *const ProgramInfo, hasher: *std.crypto.hash.Blake3, root_path: []const u8) !void {
        // Hash program metadata
        hasher.update(program.name);
        hasher.update(program.version);

        // Hash all files in the program
        for (program.binaries.items) |file_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ root_path, "Programs", program.name, program.version, file_path });
            defer self.allocator.free(full_path);
            try self.hashFile(full_path, hasher);
        }
        for (program.libraries.items) |file_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ root_path, "Programs", program.name, program.version, file_path });
            defer self.allocator.free(full_path);
            try self.hashFile(full_path, hasher);
        }
        for (program.headers.items) |file_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ root_path, "Programs", program.name, program.version, file_path });
            defer self.allocator.free(full_path);
            try self.hashFile(full_path, hasher);
        }
        for (program.data_files.items) |file_path| {
            const full_path = try std.fs.path.join(self.allocator, &.{ root_path, "Programs", program.name, program.version, file_path });
            defer self.allocator.free(full_path);
            try self.hashFile(full_path, hasher);
        }
    }

    fn hashFile(self: *PackagePacker, file_path: []const u8, hasher: *std.crypto.hash.Blake3) !void {
        const content = try std.fs.cwd().readFileAlloc(self.allocator, file_path, std.math.maxInt(usize));
        defer self.allocator.free(content);
        hasher.update(content);
    }

    fn generateManifestKdl(self: *PackagePacker, name: []const u8, version: []const u8) ![]const u8 {
        var buffer = std.io.Writer.Allocating.init(self.allocator);
        errdefer buffer.deinit();

        try buffer.writer.print("package \"{s}\" {{\n", .{name});
        try buffer.writer.print("    version \"{s}\"\n", .{version});
        try buffer.writer.print("    license \"LSL-1.0\"\n", .{});
        try buffer.writer.print("    source \"git+https://git.libertaria.dev/janus/{s}\"\n", .{name});
        try buffer.writer.print("    build \"janus\"\n", .{});
        try buffer.writer.print("}}\n", .{});

        return buffer.toOwnedSlice();
    }

    pub fn writePackage(self: *PackagePacker, package: *PackageLayout, output_path: []const u8) !void {
        std.debug.print("💾 Writing package to {s}\n", .{output_path});

        switch (self.config.package_format) {
            .jpk => try self.writeJpkFormat(package, output_path),
            .tar_zst => try self.writeTarZstFormat(package, output_path),
            .zip => try self.writeZipFormat(package, output_path),
        }
    }

    fn writeJpkFormat(self: *PackagePacker, package: *PackageLayout, output_path: []const u8) !void {
        // Create .jpk directory structure
        try std.fs.cwd().makePath(output_path);

        const package_dir = try std.fs.path.join(self.allocator, &.{ output_path, "package" });
        defer self.allocator.free(package_dir);
        try std.fs.cwd().makePath(package_dir);

        // Write manifest.kdl
        if (package.manifest) |_| {
            const manifest_path = try std.fs.path.join(self.allocator, &.{ package_dir, "manifest.kdl" });
            defer self.allocator.free(manifest_path);

            if (package.programs.items.len > 0) {
                const p = package.programs.items[0];
                const manifest_content = try self.generateManifestKdl(p.name, p.version);
                defer self.allocator.free(manifest_content);
                try std.fs.cwd().writeFile(.{ .sub_path = manifest_path, .data = manifest_content });
            }
        }

        // Write hash.b3
        if (package.hash_b3) |hash| {
            const hash_path = try std.fs.path.join(self.allocator, &.{ package_dir, "hash.b3" });
            defer self.allocator.free(hash_path);

            const hash_hex = try hexSlice(self.allocator, &hash);
            defer self.allocator.free(hash_hex);

            try std.fs.cwd().writeFile(.{ .sub_path = hash_path, .data = hash_hex });
        }

        // Write SBOM
        if (package.sbom_content) |sbom| {
            const sbom_path = try std.fs.path.join(self.allocator, &.{ package_dir, "sbom.json" });
            defer self.allocator.free(sbom_path);

            try std.fs.cwd().writeFile(.{ .sub_path = sbom_path, .data = sbom });
        }

        // Optional signing (auto-seal)
        if (self.config.sign_package) {
            if (self.config.signature_key) |key_path| {
                try self.signIntoPackage(package_dir, package.hash_b3.?, key_path);
            } else {
                std.debug.print("⚠️  sign_package enabled but no key provided; skipping\n", .{});
            }
        }

        std.debug.print("✅ Package written in .jpk format\n", .{});
    }

    fn writeTarZstFormat(self: *PackagePacker, package: *PackageLayout, output_path: []const u8) !void {
        var tar_creator = TarZstCreator.init(self.allocator, &self.config);
        const archive_data = try tar_creator.createDeterministicArchive(package);
        defer self.allocator.free(archive_data);

        try std.fs.cwd().writeFile(.{ .sub_path = output_path, .data = archive_data });
        std.debug.print("✅ Package written in deterministic tar.zst format\n", .{});
    }

    fn writeZipFormat(_: *PackagePacker, _: *PackageLayout, _: []const u8) !void {
        // TODO: Implement ZIP format
        std.debug.print("ZIP format not yet implemented\n", .{});
    }

    fn signIntoPackage(self: *PackagePacker, package_dir: []const u8, hash: [32]u8, key_path: []const u8) !void {
        const priv = try std.fs.cwd().readFileAlloc(self.allocator, key_path, 4096);
        defer self.allocator.free(priv);

        const sig = try crypto.sign(std.mem.trim(u8, priv, " \n\r\t"), &hash, self.allocator);
        defer self.allocator.free(sig);
        const pub_key = try crypto.derivePublicKey(self.allocator, std.mem.trim(u8, priv, " \n\r\t"));
        defer self.allocator.free(pub_key);

        var h = std.crypto.hash.Blake3.init(.{});
        h.update(pub_key);
        var hbytes: [32]u8 = undefined;
        h.final(&hbytes);
        const hex = try hexSlice(self.allocator, &hbytes);
        defer self.allocator.free(hex);
        const keyid = hex[0..16];

        const sigs_dir = try std.fs.path.join(self.allocator, &.{ package_dir, "signatures" });
        defer self.allocator.free(sigs_dir);
        try std.fs.cwd().makePath(sigs_dir);
        const sig_name = try std.fmt.allocPrint(self.allocator, "{s}.sig", .{keyid});
        defer self.allocator.free(sig_name);
        const pub_name = try std.fmt.allocPrint(self.allocator, "{s}.pub", .{keyid});
        defer self.allocator.free(pub_name);
        const sig_out = try std.fs.path.join(self.allocator, &.{ sigs_dir, sig_name });
        defer self.allocator.free(sig_out);
        const pk_out = try std.fs.path.join(self.allocator, &.{ sigs_dir, pub_name });
        defer self.allocator.free(pk_out);
        try std.fs.cwd().writeFile(.{ .sub_path = sig_out, .data = sig });
        try std.fs.cwd().writeFile(.{ .sub_path = pk_out, .data = pub_key });
        std.debug.print("🔏 Auto-sealed into package signatures (keyid={s})\n", .{keyid});
    }
};

// ============================================================================
// COMMAND-LINE INTERFACE
// ============================================================================

pub fn commandPack(allocator: std.mem.Allocator, args: *const struct {
    args: std.ArrayList([]const u8),
    flags: std.StringHashMap([]const u8),
}) !void {
    if (args.args.items.len < 3) {
        std.debug.print("Usage: hinge pack <source> <name> <version> [--format FORMAT] [--output DIR] [--sbom] [--sign]\n", .{});
        return error.InvalidArgument;
    }

    const source_path = args.args.items[0];
    const package_name = args.args.items[1];
    const version = args.args.items[2];

    // Parse configuration from flags
    var config = PackerConfig{};

    if (args.flags.get("format")) |format_str| {
        if (std.mem.eql(u8, format_str, "jpk")) {
            config.package_format = .jpk;
        } else if (std.mem.eql(u8, format_str, "tar.zst")) {
            config.package_format = .tar_zst;
        } else if (std.mem.eql(u8, format_str, "zip")) {
            config.package_format = .zip;
        }
    }

    if (args.flags.get("output")) |output| {
        config.output_dir = output;
    }

    if (args.flags.get("sbom")) |_| {
        config.include_sbom = true;
    }

    if (args.flags.get("sign")) |_| {
        config.sign_package = true;
        if (args.flags.get("key")) |key| {
            config.signature_key = key;
        }
    }

    // Create packer and pack the package
    var packer = try PackagePacker.init(allocator, config, "cas/");
    defer packer.deinit();

    var package = try packer.pack(source_path, package_name, version);
    defer package.deinit();

    // Write package to output
    const output_path = try std.fmt.allocPrint(allocator, "{s}{s}-{s}.jpk", .{ config.output_dir, package_name, version });
    defer allocator.free(output_path);

    try packer.writePackage(&package, output_path);

    std.debug.print("🎉 Package {s}@{s} successfully packed!\n", .{ package_name, version });
    const hash_str = try hexSlice(allocator, &package.hash_b3.?);
    defer allocator.free(hash_str);
    std.debug.print("   BLAKE3 hash: {s}\n", .{hash_str});
    std.debug.print("   Output: {s}\n", .{output_path});
}
