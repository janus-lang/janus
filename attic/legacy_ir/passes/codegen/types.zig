// SPDX-License-Identifier: LSL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Shared codegen types: Strategy, CallSite, ids

pub const FamilyId = u32;
pub const TypeId = u32;
pub const IRRef = usize;

/// Dispatch strategy (lightweight, no payload for now)
pub const Strategy = enum {
    Static,
    SwitchTable,
    PerfectHash,
    InlineCache,

    pub fn toString(self: Strategy) []const u8 {
        return switch (self) {
            .Static => "Static",
            .SwitchTable => "SwitchTable",
            .PerfectHash => "PerfectHash",
            .InlineCache => "InlineCache",
        };
    }
};

/// Source span for callsite mapping
pub const SourceSpan = struct {
    file_id: u32,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
};

/// Call site info used for strategy selection and IR generation
pub const CallSite = struct {
    unit_id: u32,
    loc: SourceSpan,
    family: FamilyId,
    arg_types: []const TypeId,
    hotness: f32,
};
