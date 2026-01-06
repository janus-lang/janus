// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const utcp = @import("std_utcp");

/// Minimal manual for graft prototype endpoints. Emits a JSON object describing
/// functions and required capabilities.
pub const GraftProtoContainer = struct {
    pub fn utcpManual(self: *const GraftProtoContainer, alloc: std.mem.Allocator) ![]const u8 {
        _ = self;
        // Keep it simple and static for now
        const json = "{\n"
            ++ "  \"module\": \"std.graft.proto\",\n"
            ++ "  \"endpoints\": [\n"
            ++ "    {\"name\":\"print_line\",\"caps\":[\"Capability\"]},\n"
            ++ "    {\"name\":\"make_greeting\",\"caps\":[\"Capability\"]},\n"
            ++ "    {\"name\":\"read_file\",\"caps\":[\"FileSystem\"]}\n"
            ++ "  ]\n"
            ++ "}\n";
        const buf = try alloc.alloc(u8, json.len);
        @memcpy(buf, json);
        return buf;
    }
};

pub fn manualFn() utcp.ManualFn {
    return utcp.makeManualAdapter(GraftProtoContainer);
}
