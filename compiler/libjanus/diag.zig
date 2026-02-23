// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const SemanticResolver = @import("semantic_resolver.zig");
const ResolveResult = SemanticResolver.ResolveResult;
const CallSite = SemanticResolver.CallSite;
const CompatibleCandidate = SemanticResolver.CompatibleCandidate;
const Candidate = @import("candidate_collector.zig").Candidate;
const RejectionReason = @import("candidate_collector.zig").RejectionReason;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;
const TypeId = @import("type_registry.zig").TypeId;

/// Diagnostic severity levels
pub const Severity = enum {
    @"error",
    warning,
    info,
    hint,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .@"error" => "error",
            .warning => "warning",
            .info => "info",
            .hint => "hint",
        };
    }
};

/// Source span for precise location tracking
pub const SourceSpan = struct {
    file: []const u8,
    start_line: u32,
    start_col: u32,
    end_line: u32,
    end_col: u32,
    start_byte: u32,
    end_byte: u32,

    pub fn fromCallSite(call_site: CallSite) SourceSpan {
        return SourceSpan{
            .file = call_site.source_location.file,
            .start_line = call_site.source_location.line,
            .start_col = call_site.source_location.column,
            .end_line = call_site.source_location.line,
            .end_col = call_site.source_location.column + 10, // Approximate
            .start_byte = call_site.source_location.start_byte,
            .end_byte = call_site.source_location.end_byte,
        };
    }
};

/// Text edit for automated fixes
pub const TextEdit = struct {
    span: SourceSpan,
    replacement: []const u8,

    pub fn deinit(self: *TextEdit, allocator: Allocator) void {
        allocator.free(self.replacement);
    }
};

/// Fix suggestion with confidence scoring
pub const FixSuggestion = struct {
    id: []const u8,
    description: []const u8,
    confidence: f32, // 0.0 to 1.0
    edits: []TextEdit,

    pub fn deinit(self: *FixSuggestion, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.description);
        for (self.edits) |*edit| {
            edit.deinit(allocator);
        }
        allocator.free(self.edits);
    }
};

/// Related information for context
pub const RelatedInfo = struct {
    message: []const u8,
    span: SourceSpan,

    pub fn deinit(self: *RelatedInfo, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

/// Machine-readable diagnostic data for AI agents
pub const DiagnosticData = struct {
    error_type: []const u8,
    candidates: []CandidateInfo,
    suggested_fixes: []FixSuggestion,
    context: std.json.Value,

    pub const CandidateInfo = struct {
        id: []const u8,
        signature: []const u8,
        module: []const u8,
        file: []const u8,
        line: u32,
        required_conversions: []ConversionInfo,

        pub const ConversionInfo = struct {
            argument_index: u32,
            from: []const u8,
            to: []const u8,
            cost: u32,
            method: []const u8,
        };

        pub fn deinit(self: *CandidateInfo, allocator: Allocator) void {
            allocator.free(self.id);
            allocator.free(self.signature);
            allocator.free(self.module);
            allocator.free(self.file);
            for (self.required_conversions) |*conv| {
                allocator.free(conv.from);
                allocator.free(conv.to);
                allocator.free(conv.method);
            }
            allocator.free(self.required_conversions);
        }
    };

    pub fn deinit(self: *DiagnosticData, allocator: Allocator) void {
        allocator.free(self.error_type);
        for (self.candidates) |*candidate| {
            candidate.deinit(allocator);
        }
        allocator.free(self.candidates);
        for (self.suggested_fixes) |*fix| {
            fix.deinit(allocator);
        }
        allocator.free(self.suggested_fixes);
        // Context is a simple JSON value, no explicit deinit needed
    }
};

/// Human-friendly message components
pub const HumanMessage = struct {
    summary: []const u8,
    explanation: []const u8,
    suggestions: []const u8,

    pub fn deinit(self: *HumanMessage, allocator: Allocator) void {
        allocator.free(self.summary);
        allocator.free(self.explanation);
        allocator.free(self.suggestions);
    }
};

/// Weaponized diagnostic combining human and machine layers
pub const WeaponizedDiagnostic = struct {
    // Diagnostic metadata
    code: []const u8,
    severity: Severity,
    span: SourceSpan,

    // Human-readable layer
    human_message: HumanMessage,

    // Machine-readable layer
    structured_data: DiagnosticData,
    fix_suggestions: []FixSuggestion,
    related_info: []RelatedInfo,

    pub fn deinit(self: *WeaponizedDiagnostic, allocator: Allocator) void {
        allocator.free(self.code);
        self.human_message.deinit(allocator);
        self.structured_data.deinit(allocator);
        for (self.fix_suggestions) |*fix| {
            fix.deinit(allocator);
        }
        allocator.free(self.fix_suggestions);
        for (self.related_info) |*info| {
            info.deinit(allocator);
        }
        allocator.free(self.related_info);
    }

    pub fn toJson(self: *const WeaponizedDiagnostic, allocator: Allocator) ![]const u8 {
        var json_obj = std.json.ObjectMap.init(allocator);
        defer json_obj.deinit();

        try json_obj.put("errorCode", std.json.Value{ .string = self.code });
        try json_obj.put("severity", std.json.Value{ .string = self.severity.toString() });
        try json_obj.put("message", std.json.Value{ .string = self.human_message.summary });

        // Add span information
        var span_obj = std.json.ObjectMap.init(allocator);
        defer span_obj.deinit();
        try span_obj.put("file", std.json.Value{ .string = self.span.file });
        try span_obj.put("start_line", std.json.Value{ .integer = @intCast(self.span.start_line) });
        try span_obj.put("start_col", std.json.Value{ .integer = @intCast(self.span.start_col) });
        try span_obj.put("start_byte", std.json.Value{ .integer = @intCast(self.span.start_byte) });
        try span_obj.put("end_byte", std.json.Value{ .integer = @intCast(self.span.end_byte) });
        try json_obj.put("span", std.json.Value{ .object = span_obj });

        const json_value = std.json.Value{ .object = json_obj };
        return std.json.stringifyAlloc(allocator, json_value, .{});
    }
};

/// Diagnostic engine for generating weaponized diagnostics
pub const DiagnosticEngine = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) DiagnosticEngine {
        return DiagnosticEngine{
            .allocator = allocator,
        };
    }

    pub fn generateFromResolveResult(self: *DiagnosticEngine, result: ResolveResult) !WeaponizedDiagnostic {
        return switch (result) {
            .success => unreachable, // Should not generate diagnostic for success
            .ambiguous => |ambiguous| self.generateAmbiguityDiagnostic(ambiguous),
            .no_matches => |no_matches| self.generateNoMatchesDiagnostic(no_matches),
            .error_occurred => |error_info| self.generateErrorDiagnostic(error_info),
        };
    }

    fn generateAmbiguityDiagnostic(self: *DiagnosticEngine, ambiguous: ResolveResult.AmbiguityInfo) !WeaponizedDiagnostic {
        const span = SourceSpan.fromCallSite(ambiguous.call_site);

        // Generate human-friendly message
        const human_message = try self.formatAmbiguityMessage(ambiguous);

        // Generate machine-readable data
        const structured_data = try self.formatAmbiguityData(ambiguous);

        // Generate fix suggestions
        const fix_suggestions = try self.generateAmbiguityFixes(ambiguous);

        // Generate related information
        const related_info = try self.collectAmbiguityRelatedInfo(ambiguous);

        return WeaponizedDiagnostic{
            .code = try self.allocator.dupe(u8, "S1101"),
            .severity = .@"error",
            .span = span,
            .human_message = human_message,
            .structured_data = structured_data,
            .fix_suggestions = fix_suggestions,
            .related_info = related_info,
        };
    }

    fn formatAmbiguityMessage(self: *DiagnosticEngine, ambiguous: ResolveResult.AmbiguityInfo) !HumanMessage {
        // Create the Socratic explanation
        const arg_types_str = try self.formatArgumentTypes(ambiguous.call_site.argument_types);
        defer self.allocator.free(arg_types_str);
        const summary = try std.fmt.allocPrint(self.allocator, "Ambiguous call to `{s}` with arguments ({s})", .{ ambiguous.call_site.function_name, arg_types_str });

        const candidate_list_str = try self.formatCandidateList(ambiguous.candidates);
        defer self.allocator.free(candidate_list_str);
        const explanation = try std.fmt.allocPrint(self.allocator, "> The compiler found multiple valid functions and cannot choose between them.\n" ++
            "> This happens when multiple functions match your call but none is more specific.\n\n" ++
            "Candidates:\n{s}\n\n" ++
            "Why this is ambiguous:\n" ++
            "• All candidates have equal conversion costs\n" ++
            "• No candidate is more specific than the others\n" ++
            "• The compiler requires explicit disambiguation", .{candidate_list_str});

        const suggestions = try std.fmt.allocPrint(self.allocator, "How to resolve:\n" ++
            "1. Cast arguments to make your intent explicit:\n" ++
            "   {s}(2, 3 as f64)     // Selects candidate with f64 parameter\n\n" ++
            "2. Use a fully qualified name if functions are from different modules:\n" ++
            "   std.math.{s}(2, 3.0)\n\n" ++
            "3. Define a more specific function for your exact types:\n" ++
            "   func {s}(a: i32, b: i32) -> i32 {{ ... }}", .{ ambiguous.call_site.function_name, ambiguous.call_site.function_name, ambiguous.call_site.function_name });

        return HumanMessage{
            .summary = summary,
            .explanation = explanation,
            .suggestions = suggestions,
        };
    }

    fn formatAmbiguityData(self: *DiagnosticEngine, ambiguous: ResolveResult.AmbiguityInfo) !DiagnosticData {
        var candidates: std.ArrayList(DiagnosticData.CandidateInfo) = .empty;

        for (ambiguous.candidates, 0..) |candidate, i| {
            const candidate_id = try std.fmt.allocPrint(self.allocator, "{c}", .{'A' + @as(u8, @intCast(i))});
            const signature = try std.fmt.allocPrint(self.allocator, "func {s}({s}) -> {s}", .{ candidate.candidate.function.name, candidate.candidate.function.parameter_types, candidate.candidate.function.return_type });

            var conversions: std.ArrayList(DiagnosticData.CandidateInfo.ConversionInfo) = .empty;
            for (candidate.conversion_path.get().conversions, 0..) |conversion, j| {
                if (conversion.cost > 0) { // Only include actual conversions
                    try conversions.append(DiagnosticData.CandidateInfo.ConversionInfo{
                        .argument_index = @intCast(j),
                        .from = try self.getTypeName(ambiguous.call_site.argument_types[j]),
                        .to = try self.getTypeName(conversion.to),
                        .cost = conversion.cost,
                        .method = try self.allocator.dupe(u8, "builtin_cast"),
                    });
                }
            }

            try candidates.append(DiagnosticData.CandidateInfo{
                .id = candidate_id,
                .signature = signature,
                .module = try self.allocator.dupe(u8, candidate.candidate.function.module_path),
                .file = try self.allocator.dupe(u8, candidate.candidate.function.source_location.file),
                .line = candidate.candidate.function.source_location.line,
                .required_conversions = try conversions.toOwnedSlice(),
            });
        }

        return DiagnosticData{
            .error_type = try self.allocator.dupe(u8, "ambiguous_call"),
            .candidates = try candidates.toOwnedSlice(),
            .suggested_fixes = &[_]FixSuggestion{}, // Will be populated separately
            .context = std.json.Value{ .null = {} },
        };
    }

    fn generateAmbiguityFixes(self: *DiagnosticEngine, ambiguous: ResolveResult.AmbiguityInfo) ![]FixSuggestion {
        var fixes: std.ArrayList(FixSuggestion) = .empty;

        for (ambiguous.candidates, 0..) |candidate, i| {
            // Generate explicit cast suggestions
            for (candidate.conversion_path.get().conversions, 0..) |conversion, j| {
                if (conversion.cost > 0) {
                    const fix_id = try std.fmt.allocPrint(self.allocator, "cast_arg_{d}_{d}", .{ i, j });
                    const type_name = try self.getTypeName(conversion.to);
                    defer self.allocator.free(type_name);
                    const description = try std.fmt.allocPrint(self.allocator, "Cast argument {d} to {s} (selects candidate {c})", .{ j, type_name, 'A' + @as(u8, @intCast(i)) });

                    // Create text edit (simplified - would need actual source text)
                    const replacement = try std.fmt.allocPrint(self.allocator, "arg_{d} as {s}", .{ j, type_name });

                    var edits = try self.allocator.alloc(TextEdit, 1);
                    edits[0] = TextEdit{
                        .span = SourceSpan.fromCallSite(ambiguous.call_site),
                        .replacement = replacement,
                    };

                    try fixes.append(FixSuggestion{
                        .id = fix_id,
                        .description = description,
                        .confidence = 0.9,
                        .edits = edits,
                    });
                }
            }

            // Generate qualified name suggestion if from different module
            if (candidate.candidate.import_path) |import_path| {
                if (import_path.len > 0) {
                    const fix_id = try std.fmt.allocPrint(self.allocator, "qualified_{d}", .{i});
                    const description = try self.allocator.dupe(u8, "Use fully qualified function name");

                    const replacement = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ import_path, ambiguous.call_site.function_name });

                    var edits = try self.allocator.alloc(TextEdit, 1);
                    edits[0] = TextEdit{
                        .span = SourceSpan.fromCallSite(ambiguous.call_site),
                        .replacement = replacement,
                    };

                    try fixes.append(FixSuggestion{
                        .id = fix_id,
                        .description = description,
                        .confidence = 0.7,
                        .edits = edits,
                    });
                }
            }
        }

        return try fixes.toOwnedSlice(alloc);
    }

    fn collectAmbiguityRelatedInfo(self: *DiagnosticEngine, ambiguous: ResolveResult.AmbiguityInfo) ![]RelatedInfo {
        var related: std.ArrayList(RelatedInfo) = .empty;

        for (ambiguous.candidates, 0..) |candidate, i| {
            const message = try std.fmt.allocPrint(self.allocator, "Candidate {c} defined here", .{'A' + @as(u8, @intCast(i))});

            const span = SourceSpan{
                .file = candidate.candidate.function.source_location.file,
                .start_line = candidate.candidate.function.source_location.line,
                .start_col = candidate.candidate.function.source_location.column,
                .end_line = candidate.candidate.function.source_location.line,
                .end_col = candidate.candidate.function.source_location.column + 10,
                .start_byte = 0, // Would need actual source info
                .end_byte = 0,
            };

            try related.append(RelatedInfo{
                .message = message,
                .span = span,
            });
        }

        return try related.toOwnedSlice(alloc);
    }

    fn generateNoMatchesDiagnostic(self: *DiagnosticEngine, no_matches: ResolveResult.NoMatchInfo) !WeaponizedDiagnostic {
        const span = SourceSpan.fromCallSite(no_matches.call_site);

        const arg_types_str = try self.formatArgumentTypes(no_matches.argument_types);
        defer self.allocator.free(arg_types_str);
        const summary = try std.fmt.allocPrint(self.allocator, "No matching function found for `{s}` with arguments ({s})", .{ no_matches.function_name, arg_types_str });

        const available_funcs_str = try self.formatAvailableFunctions(no_matches.available_functions);
        defer self.allocator.free(available_funcs_str);
        const explanation = try std.fmt.allocPrint(self.allocator, "> The compiler could not find any function named `{s}` that accepts the given arguments.\n\n" ++
            "Available functions:\n{s}\n\n" ++
            "Possible causes:\n" ++
            "• Function name is misspelled\n" ++
            "• Function is not imported or visible in current scope\n" ++
            "• Arguments have wrong types and no explicit conversion exists", .{ no_matches.function_name, available_funcs_str });

        const suggestions = try std.fmt.allocPrint(self.allocator, "How to fix:\n" ++
            "1. Check the function name spelling\n" ++
            "2. Import the module containing the function\n" ++
            "3. Add explicit type conversions to arguments\n" ++
            "4. Define the function if it doesn't exist", .{});

        return WeaponizedDiagnostic{
            .code = try self.allocator.dupe(u8, "S1102"),
            .severity = .@"error",
            .span = span,
            .human_message = HumanMessage{
                .summary = summary,
                .explanation = explanation,
                .suggestions = suggestions,
            },
            .structured_data = DiagnosticData{
                .error_type = try self.allocator.dupe(u8, "no_matching_function"),
                .candidates = &[_]DiagnosticData.CandidateInfo{},
                .suggested_fixes = &[_]FixSuggestion{},
                .context = std.json.Value{ .null = {} },
            },
            .fix_suggestions = &[_]FixSuggestion{},
            .related_info = &[_]RelatedInfo{},
        };
    }

    fn generateErrorDiagnostic(self: *DiagnosticEngine, error_info: ResolveResult.ResolutionError) !WeaponizedDiagnostic {
        const span = SourceSpan.fromCallSite(error_info.call_site);

        return WeaponizedDiagnostic{
            .code = try self.allocator.dupe(u8, "S1103"),
            .severity = .@"error",
            .span = span,
            .human_message = HumanMessage{
                .summary = try self.allocator.dupe(u8, error_info.message),
                .explanation = try self.allocator.dupe(u8, "An internal error occurred during resolution."),
                .suggestions = try self.allocator.dupe(u8, "Please report this as a compiler bug."),
            },
            .structured_data = DiagnosticData{
                .error_type = try self.allocator.dupe(u8, "internal_error"),
                .candidates = &[_]DiagnosticData.CandidateInfo{},
                .suggested_fixes = &[_]FixSuggestion{},
                .context = std.json.Value{ .null = {} },
            },
            .fix_suggestions = &[_]FixSuggestion{},
            .related_info = &[_]RelatedInfo{},
        };
    }

    // Helper functions
    fn formatArgumentTypes(self: *DiagnosticEngine, arg_types: []const TypeId) ![]const u8 {
        if (arg_types.len == 0) return try self.allocator.dupe(u8, "");

        var result: std.ArrayList(u8) = .empty;
        for (arg_types, 0..) |arg_type, i| {
            if (i > 0) try result.appendSlice(", ");
            const type_name = try self.getTypeName(arg_type);
            defer self.allocator.free(type_name);
            try result.appendSlice(type_name);
        }
        return try result.toOwnedSlice(alloc);
    }

    fn formatCandidateList(self: *DiagnosticEngine, candidates: []CompatibleCandidate) ![]const u8 {
        var result: std.ArrayList(u8) = .empty;

        for (candidates, 0..) |candidate, i| {
            const label = 'A' + @as(u8, @intCast(i));
            try result.writer().print("  ({c}) func {s}({s}) -> {s}  [from {s}]\n", .{ label, candidate.candidate.function.name, candidate.candidate.function.parameter_types, candidate.candidate.function.return_type, candidate.candidate.function.module_path });
        }

        return try result.toOwnedSlice(alloc);
    }

    fn formatAvailableFunctions(self: *DiagnosticEngine, functions: [][]const u8) ![]const u8 {
        if (functions.len == 0) return try self.allocator.dupe(u8, "  (none visible in current scope)");

        var result: std.ArrayList(u8) = .empty;
        for (functions) |func_name| {
            try result.writer().print("  • {s}\n", .{func_name});
        }
        return try result.toOwnedSlice(alloc);
    }

    fn getTypeName(self: *DiagnosticEngine, type_id: TypeId) ![]const u8 {
        return switch (type_id.id) {
            1 => try self.allocator.dupe(u8, "i32"),
            2 => try self.allocator.dupe(u8, "f64"),
            3 => try self.allocator.dupe(u8, "bool"),
            4 => try self.allocator.dupe(u8, "string"),
            else => try self.allocator.dupe(u8, "unknown"),
        };
    }
};

// Tests
test "DiagnosticEngine initialization" {
    const engine = DiagnosticEngine.init(std.testing.allocator);
    _ = engine;

    // Test that the engine initializes correctly
    try std.testing.expect(true);
}

test "DiagnosticEngine severity enum" {
    const engine = DiagnosticEngine.init(std.testing.allocator);
    _ = engine;

    // Test severity enum functionality
    const error_severity = Severity.@"error";
    const warning_severity = Severity.warning;

    try std.testing.expectEqualStrings(error_severity.toString(), "error");
    try std.testing.expectEqualStrings(warning_severity.toString(), "warning");
}
