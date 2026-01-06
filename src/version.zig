// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Auto-generated version information for Janus
// Do not edit manually - managed by build system

pub const version = "2026.1.0";
pub const year = 2026;
pub const quarter = 1;
pub const patch = 0;
pub const is_lts = false; // true for Q4 even years
pub const git_hash = "e0895c7";
pub const build_date = "2026-01-06";
pub const is_dirty = false;

// Version reporting utility
pub fn getFullVersion() []const u8 {
    return version;
}

pub fn getVersionInfo() []const u8 {
    if (is_lts) {
        return "Janus " ++ version ++ " LTS (" ++ git_hash ++ ") built on " ++ build_date;
    } else {
        return "Janus " ++ version ++ " (" ++ git_hash ++ ") built on " ++ build_date;
    }
}

pub fn getSupportInfo() []const u8 {
    if (is_lts) {
        return "LTS Release (4-year support)";
    } else {
        return "Standard Release (6-month support)";
    }
}
