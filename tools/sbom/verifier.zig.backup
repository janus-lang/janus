// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");

// Janus SBOM Verifier
// Verifies the integrity and completeness of generated SBOMs
// Implements security verification requirements from SECURITY.md

const SBOMVerificationResult = struct {
    valid: bool,
    errors: [][]const u8,
    warnings: [][]const u8,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.errors) |error_msg| {
            allocator.free(error_msg);
        }
        for (self.warnings) |warning_msg| {
            allocator.free(warning_msg);
        }
        allocator.free(self.errors);
        allocator.free(self.warnings);
    }
};

fn verifyCycloneDX(allocator: std.mem.Allocator, file_path: []const u8) !SBOMVerificationResult {
    var errors = std.ArrayList([]const u8).init(allocator);
    var warnings = std.ArrayList([]const u8).init(allocator);

    // Read and parse the CycloneDX SBOM file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        try errors.append(try std.fmt.allocPrint(allocator, "Failed to open file: {}", .{err}));
        return SBOMVerificationResult{
            .valid = false,
            .errors = try errors.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    // Basic JSON validation
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
        try errors.append(try std.fmt.allocPrint(allocator, "Invalid JSON format: {}", .{err}));
        return SBOMVerificationResult{
            .valid = false,
            .errors = try errors.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
        };
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Verify required CycloneDX fields
    if (!root.contains("bomFormat")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: bomFormat"));
    } else if (!std.mem.eql(u8, root.get("bomFormat").?.string, "CycloneDX")) {
        try errors.append(try allocator.dupe(u8, "Invalid bomFormat: expected 'CycloneDX'"));
    }

    if (!root.contains("specVersion")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: specVersion"));
    }

    if (!root.contains("serialNumber")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: serialNumber"));
    }

    if (!root.contains("metadata")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: metadata"));
    } else {
        const metadata = root.get("metadata").?.object;
        if (!metadata.contains("timestamp")) {
            try warnings.append(try allocator.dupe(u8, "Missing recommended field: metadata.timestamp"));
        }
        if (!metadata.contains("tools")) {
            try warnings.append(try allocator.dupe(u8, "Missing recommended field: metadata.tools"));
        }
    }

    if (!root.contains("components")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: components"));
    } else {
        const components = root.get("components").?.array;
        if (components.items.len == 0) {
            try warnings.append(try allocator.dupe(u8, "No components found in SBOM"));
        }

        // Verify each component has required fields
        for (components.items, 0..) |component, i| {
            const comp_obj = component.object;
            const comp_name = try std.fmt.allocPrint(allocator, "component[{d}]", .{i});
            defer allocator.free(comp_name);

            if (!comp_obj.contains("name")) {
                try errors.append(try std.fmt.allocPrint(allocator, "{s}: Missing required field 'name'", .{comp_name}));
            }
            if (!comp_obj.contains("version")) {
                try errors.append(try std.fmt.allocPrint(allocator, "{s}: Missing required field 'version'", .{comp_name}));
            }
            if (!comp_obj.contains("type")) {
                try errors.append(try std.fmt.allocPrint(allocator, "{s}: Missing required field 'type'", .{comp_name}));
            }
        }
    }

    const is_valid = errors.items.len == 0;

    return SBOMVerificationResult{
        .valid = is_valid,
        .errors = try errors.toOwnedSlice(),
        .warnings = try warnings.toOwnedSlice(),
    };
}

fn verifySPDX(allocator: std.mem.Allocator, file_path: []const u8) !SBOMVerificationResult {
    var errors = std.ArrayList([]const u8).init(allocator);
    var warnings = std.ArrayList([]const u8).init(allocator);

    // Read and parse the SPDX SBOM file
    const file = std.fs.cwd().openFile(file_path, .{}) catch |err| {
        try errors.append(try std.fmt.allocPrint(allocator, "Failed to open file: {}", .{err}));
        return SBOMVerificationResult{
            .valid = false,
            .errors = try errors.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
        };
    };
    defer file.close();

    const content = try file.readToEndAlloc(allocator, 1024 * 1024); // 1MB max
    defer allocator.free(content);

    // Basic JSON validation
    var parsed = std.json.parseFromSlice(std.json.Value, allocator, content, .{}) catch |err| {
        try errors.append(try std.fmt.allocPrint(allocator, "Invalid JSON format: {}", .{err}));
        return SBOMVerificationResult{
            .valid = false,
            .errors = try errors.toOwnedSlice(),
            .warnings = try warnings.toOwnedSlice(),
        };
    };
    defer parsed.deinit();

    const root = parsed.value.object;

    // Verify required SPDX fields
    if (!root.contains("spdxVersion")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: spdxVersion"));
    }

    if (!root.contains("dataLicense")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: dataLicense"));
    } else if (!std.mem.eql(u8, root.get("dataLicense").?.string, "CC0-1.0")) {
        try errors.append(try allocator.dupe(u8, "Invalid dataLicense: expected 'CC0-1.0'"));
    }

    if (!root.contains("SPDXID")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: SPDXID"));
    }

    if (!root.contains("name")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: name"));
    }

    if (!root.contains("documentNamespace")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: documentNamespace"));
    }

    if (!root.contains("creationInfo")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: creationInfo"));
    }

    if (!root.contains("packages")) {
        try errors.append(try allocator.dupe(u8, "Missing required field: packages"));
    } else {
        const packages = root.get("packages").?.array;
        if (packages.items.len == 0) {
            try warnings.append(try allocator.dupe(u8, "No packages found in SPDX document"));
        }
    }

    const is_valid = errors.items.len == 0;

    return SBOMVerificationResult{
        .valid = is_valid,
        .errors = try errors.toOwnedSlice(),
        .warnings = try warnings.toOwnedSlice(),
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Usage: janus-sbom-verifier <sbom-file>", .{});
        return;
    }

    const file_path = args[1];

    // Determine SBOM format based on file content or name
    const is_cyclonedx = std.mem.indexOf(u8, file_path, "cyclonedx") != null;
    const is_spdx = std.mem.indexOf(u8, file_path, "spdx") != null;

    var result = if (is_cyclonedx)
        try verifyCycloneDX(allocator, file_path)
    else if (is_spdx)
        try verifySPDX(allocator, file_path)
    else {
        // Try to auto-detect by reading the file
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        var buffer: [1024]u8 = undefined;
        const bytes_read = try file.readAll(&buffer);
        const content = buffer[0..bytes_read];

        if (std.mem.indexOf(u8, content, "bomFormat") != null) {
            try verifyCycloneDX(allocator, file_path)
        } else if (std.mem.indexOf(u8, content, "spdxVersion") != null) {
            try verifySPDX(allocator, file_path)
        } else {
            std.log.err("Unable to determine SBOM format for file: {s}", .{file_path});
            return;
        }
    };

    defer result.deinit(allocator);

    // Print results
    std.log.info("SBOM Verification Results for: {s}", .{file_path});
    std.log.info("Valid: {}", .{result.valid});

    if (result.errors.len > 0) {
        std.log.err("Errors found:", .{});
        for (result.errors) |error_msg| {
            std.log.err("  - {s}", .{error_msg});
        }
    }

    if (result.warnings.len > 0) {
        std.log.warn("Warnings:", .{});
        for (result.warnings) |warning_msg| {
            std.log.warn("  - {s}", .{warning_msg});
        }
    }

    if (result.valid) {
        std.log.info("✅ SBOM verification passed", .{});
    } else {
        std.log.err("❌ SBOM verification failed", .{});
        std.process.exit(1);
    }
}
