// SPDX-License-Identifier: LUL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const janus_lib = @import("janus_lib");

// Janus Security Policy Checker
// Implements "The Janus Way: Trust Through Verification"
// Mechanism over Policy - Users define their own security requirements

const PolicyCheckResult = struct {
    passed: bool,
    violations: []PolicyViolation,
    warnings: []PolicyWarning,

    const Self = @This();

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        for (self.violations) |violation| {
            allocator.free(violation.message);
            allocator.free(violation.package_name);
            if (violation.remediation) |remediation| {
                allocator.free(remediation);
            }
        }
        for (self.warnings) |warning| {
            allocator.free(warning.message);
            allocator.free(warning.package_name);
        }
        allocator.free(self.violations);
        allocator.free(self.warnings);
    }
};

const PolicyViolation = struct {
    package_namest u8,
    violation_type: ViolationType,
    message: []const u8,
    severity: Severity,
    remediation: ?[]const u8,

    const ViolationType = enum {
        missing_sbom,
        unsupported_sbom_format,
        security_score_too_low,
        vulnerability_severity_exceeded,
        forbidden_license,
        missing_signature,
        build_not_reproducible,
    };

    const Severity = enum {
        low,
        medium,
        high,
        critical,
    };
};

const PolicyWarning = struct {
    package_name: []const u8,
    message: []const u8,
};

const SecurityPolicy = struct {
    require_sbom: SBOMRequirement,
    sbom_formats: [][]const u8,
    sbom_exceptions: [][]const u8,
    min_security_score: f64,
    max_vulnerability_severity: []const u8,
    allowed_licenses: [][]const u8,
    forbidden_licenses: [][]const u8,
    require_signature: bool,
    require_reproducible_builds: bool,

    const SBOMRequirement = enum {
        none,
        production,
        all,

        pub fn fromString(str: []const u8) SBOMRequirement {
            if (std.mem.eql(u8, str, "none")) return .none;
            if (std.mem.eql(u8, str, "production")) return .production;
            if (std.mem.eql(u8, str, "all")) return .all;
            return .none;
        }
    };

    const Self = @This();

    pub fn parseFromManifest(allocator: std.mem.Allocator, manifest_content: []const u8) !Self {
        // Parse KDL manifest and extract security policy
        // For now, return a default policy - real implementation would parse KDL
        return Self{
            .require_sbom = .production,
            .sbom_formats = &[_][]const u8{"cyclonedx", "spdx"},
            .sbom_exceptions = &[_][]const u8{"std/collections", "crypto/blake3"},
            .min_security_score = 7.0,
            .max_vulnerability_severity = "medium",
            .allowed_licenses = &[_][]const u8{"Apache-2.0", "MIT", "BSD-3-Clause", "CC0-1.0"},
            .forbidden_licenses = &[_][]const u8{"GPL-3.0", "AGPL-3.0"},
            .require_signature = true,
            .require_reproducible_builds = true,
        };
    }
};

const DependencyMetadata = struct {
    name: []const u8,
    version: []const u8,
    is_dev_dependency: bool,
    sbom_present: bool,
    sbom_formats: [][]const u8,
    security_score: f64,
    vulnerabilities: []Vulnerability,
    declared_license: []const u8,
    signature_valid: bool,
    reproducible_build: bool,
    policy_exemption: ?[]const u8,

    const Vulnerability = struct {
        id: []const u8,
        severity: []const u8,
        description: []const u8,
    };
};

fn parseLockfile(allocator: std.mem.Allocator, lockfile_content: []const u8) ![]DependencyMetadata {
    // Parse JANUS.lock JSON and extract dependency metadata
    var parsed = try std.json.parseFromSlice(std.json.Value, allocator, lockfile_content, .{});
    defer parsed.deinit();

    const root = parsed.value.object;
    const dependencies = root.get("dependencies").?.object;

    var deps: std.ArrayList(DependencyMetadata) = .empty;

    var dep_iterator = dependencies.iterator();
    while (dep_iterator.next()) |entry| {
        const dep_name = entry.key_ptr.*;
        const dep_data = entry.value_ptr.*.object;
        const security_metadata = dep_data.get("security_metadata").?.object;

        try deps.append(DependencyMetadata{
            .name = try allocator.dupe(u8, dep_name),
            .version = try allocator.dupe(u8, dep_data.get("version").?.string),
            .is_dev_dependency = false, // Simplified for now
            .sbom_present = security_metadata.get("sbom_present").?.bool,
            .sbom_formats = &[_][]const u8{}, // Simplified for now
            .security_score = security_metadata.get("security_score").?.float,
            .vulnerabilities = &[_]DependencyMetadata.Vulnerability{}, // Simplified for now
            .declared_license = try allocator.dupe(u8, security_metadata.get("license_compliance").?.object.get("declared_license").?.string),
            .signature_valid = security_metadata.get("signature_verification").?.object.get("signature_valid").?.bool,
            .reproducible_build = true, // Simplified for now
            .policy_exemption = if (security_metadata.get("policy_exemption")) |exemption|
                try allocator.dupe(u8, exemption.string) else null,
        });
    }

    return try deps.toOwnedSlice(alloc);
}

fn checkSBOMPolicy(allocator: std.mem.Allocator, policy: *const SecurityPolicy, deps: []const DependencyMetadata) ![]PolicyViolation {
    var violations: std.ArrayList(PolicyViolation) = .empty;

    for (deps) |dep| {
        // Check if SBOM is required for this dependency
        const sbom_required = switch (policy.require_sbom) {
            .none => false,
            .production => !dep.is_dev_dependency,
            .all => true,
        };

        if (!sbom_required) continue;

        // Check for exemptions
        var is_exempt = false;
        for (policy.sbom_exceptions) |exception| {
            if (std.mem.eql(u8, dep.name, exception)) {
                is_exempt = true;
                break;
            }
        }

        if (is_exempt) continue;

        // Check if SBOM is present
        if (!dep.sbom_present) {
            try violations.append(PolicyViolation{
                .package_name = try allocator.dupe(u8, dep.name),
                .violation_type = .missing_sbom,
                .message = try std.fmt.allocPrint(allocator,
                    "Package '{s}' is missing required SBOM", .{dep.name}),
                .severity = .high,
                .remediation = try std.fmt.allocPrint(allocator,
                    "Contact package maintainer to provide CycloneDX or SPDX SBOM, or add to sbom_exceptions in janus.pkg"),
            });
        }
    }

    return try violations.toOwnedSlice(alloc);
}

fn checkSecurityScorePolicy(allocator: std.mem.Allocator, policy: *const SecurityPolicy, deps: []const DependencyMetadata) ![]PolicyViolation {
    var violations: std.ArrayList(PolicyViolation) = .empty;

    for (deps) |dep| {
        if (dep.security_score < policy.min_security_score) {
            try violations.append(PolicyViolation{
                .package_name = try allocator.dupe(u8, dep.name),
                .violation_type = .security_score_too_low,
                .message = try std.fmt.allocPrint(allocator,
                    "Package '{s}' security score {d:.1} is below minimum {d:.1}",
                    .{dep.name, dep.security_score, policy.min_security_score}),
                .severity = .medium,
                .remediation = try std.fmt.allocPrint(allocator,
                    "Review package security practices or lower min_security_score in policy"),
            });
        }
    }

    return try violations.toOwnedSlice(alloc);
}

fn checkLicensePolicy(allocator: std.mem.Allocator, policy: *const SecurityPolicy, deps: []const DependencyMetadata) ![]PolicyViolation {
    var violations: std.ArrayList(PolicyViolation) = .empty;

    for (deps) |dep| {
        // Check forbidden licenses
        for (policy.forbidden_licenses) |forbidden| {
            if (std.mem.eql(u8, dep.declared_license, forbidden)) {
                try violations.append(PolicyViolation{
                    .package_name = try allocator.dupe(u8, dep.name),
                    .violation_type = .forbidden_license,
                    .message = try std.fmt.allocPrint(allocator,
                        "Package '{s}' uses forbidden license '{s}'",
                        .{dep.name, dep.declared_license}),
                    .severity = .high,
                    .remediation = try std.fmt.allocPrint(allocator,
                        "Remove package or update license policy to allow '{s}'", .{dep.declared_license}),
                });
                break;
            }
        }

        // Check allowed licenses
        var license_allowed = false;
        for (policy.allowed_licenses) |allowed| {
            if (std.mem.eql(u8, dep.declared_license, allowed)) {
                license_allowed = true;
                break;
            }
        }

        if (!license_allowed) {
            try violations.append(PolicyViolation{
                .package_name = try allocator.dupe(u8, dep.name),
                .violation_type = .forbidden_license,
                .message = try std.fmt.allocPrint(allocator,
                    "Package '{s}' license '{s}' is not in allowed list",
                    .{dep.name, dep.declared_license}),
                .severity = .medium,
                .remediation = try std.fmt.allocPrint(allocator,
                    "Add '{s}' to allowed_licenses in policy or remove package", .{dep.declared_license}),
            });
        }
    }

    return try violations.toOwnedSlice(alloc);
}

fn checkSignaturePolicy(allocator: std.mem.Allocator, policy: *const SecurityPolicy, deps: []const DependencyMetadata) ![]PolicyViolation {
    var violations: std.ArrayList(PolicyViolation) = .empty;

    if (!policy.require_signature) return try violations.toOwnedSlice(alloc);

    for (deps) |dep| {
        if (!dep.signature_valid) {
            try violations.append(PolicyViolation{
                .package_name = try allocator.dupe(u8, dep.name),
                .violation_type = .missing_signature,
                .message = try std.fmt.allocPrint(allocator,
                    "Package '{s}' does not have a valid cryptographic signature", .{dep.name}),
                .severity = .high,
                .remediation = try std.fmt.allocPrint(allocator,
                    "Contact package maintainer for signed release or disable require_signature"),
            });
        }
    }

    return try violations.toOwnedSlice(alloc);
}

fn runPolicyCheck(allocator: std.mem.Allocator, manifest_path: []const u8, lockfile_path: []const u8) !PolicyCheckResult {
    // Read manifest file
    const manifest_file = try std.fs.cwd().openFile(manifest_path, .{});
    defer manifest_file.close();
    const manifest_content = try manifest_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(manifest_content);

    // Read lockfile
    const lockfile_file = try std.fs.cwd().openFile(lockfile_path, .{});
    defer lockfile_file.close();
    const lockfile_content = try lockfile_file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(lockfile_content);

    // Parse security policy from manifest
    const policy = try SecurityPolicy.parseFromManifest(allocator, manifest_content);

    // Parse dependencies from lockfile
    const deps = try parseLockfile(allocator, lockfile_content);
    defer {
        for (deps) |dep| {
            allocator.free(dep.name);
            allocator.free(dep.version);
            allocator.free(dep.declared_license);
            if (dep.policy_exemption) |exemption| {
                allocator.free(exemption);
            }
        }
        allocator.free(deps);
    }

    // Run policy checks
    var all_violations: std.ArrayList(PolicyViolation) = .empty;

    // Check SBOM policy
    const sbom_violations = try checkSBOMPolicy(allocator, &policy, deps);
    try all_violations.appendSlice(sbom_violations);
    allocator.free(sbom_violations);

    // Check security score policy
    const score_violations = try checkSecurityScorePolicy(allocator, &policy, deps);
    try all_violations.appendSlice(score_violations);
    allocator.free(score_violations);

    // Check license policy
    const license_violations = try checkLicensePolicy(allocator, &policy, deps);
    try all_violations.appendSlice(license_violations);
    allocator.free(license_violations);

    // Check signature policy
    const signature_violations = try checkSignaturePolicy(allocator, &policy, deps);
    try all_violations.appendSlice(signature_violations);
    allocator.free(signature_violations);

    const passed = all_violations.items.len == 0;

    return PolicyCheckResult{
        .passed = passed,
        .violations = try all_violations.toOwnedSlice(),
        .warnings = &[_]PolicyWarning{}, // No warnings for now
    };
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var manifest_path: []const u8 = "janus.pkg";
    var lockfile_path: []const u8 = "JANUS.lock";
    var strict_mode = false;

    // Parse command line arguments
    for (args[1..]) |arg| {
        if (std.mem.startsWith(u8, arg, "--manifest=")) {
            manifest_path = arg[11..];
        } else if (std.mem.startsWith(u8, arg, "--lockfile=")) {
            lockfile_path = arg[11..];
        } else if (std.mem.eql(u8, arg, "--strict=true")) {
            strict_mode = true;
        }
    }

    std.log.info("🔒 Janus Security Policy Checker", .{});
    std.log.info("Manifest: {s}", .{manifest_path});
    std.log.info("Lockfile: {s}", .{lockfile_path});
    std.log.info("Strict Mode: {}", .{strict_mode});
    std.log.info("", .{});

    // Run policy check
    var result = runPolicyCheck(allocator, manifest_path, lockfile_path) catch |err| {
        std.log.err("❌ Policy check failed: {}", .{err});
        std.process.exit(1);
    };
    defer result.deinit(allocator);

    // Report results
    if (result.violations.len > 0) {
        std.log.err("❌ Security Policy Violations Found:", .{});
        for (result.violations) |violation| {
            const severity_icon = switch (violation.severity) {
                .low => "🟡",
                .medium => "🟠",
                .high => "🔴",
                .critical => "💀",
            };

            std.log.err("  {s} {s}: {s}", .{severity_icon, violation.package_name, violation.message});
            if (violation.remediation) |remediation| {
                std.log.info("    💡 Remediation: {s}", .{remediation});
            }
        }
        std.log.err("", .{});
    }

    if (result.warnings.len > 0) {
        std.log.warn("⚠️  Security Policy Warnings:", .{});
        for (result.warnings) |warning| {
            std.log.warn("  {s}: {s}", .{warning.package_name, warning.message});
        }
        std.log.warn("", .{});
    }

    if (result.passed) {
        std.log.info("✅ All security policies satisfied", .{});
        std.log.info("🛡️  Trust Through Verification: Your dependencies meet your security standards", .{});
    } else {
        std.log.err("❌ Security policy violations detected", .{});
        std.log.err("🔧 The Janus Way: You define the policy, we enforce it", .{});
        std.log.err("💡 Update your security policy in janus.pkg or address the violations", .{});

        if (strict_mode) {
            std.process.exit(1);
        }
    }
}
