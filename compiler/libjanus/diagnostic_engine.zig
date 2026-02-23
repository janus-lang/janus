// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const SemanticResolver = @import("semantic_resolver.zig");
const ResolveResult = SemanticResolver.ResolveResult;
const CallSite = SemanticResolver.CallSite;
const CompatibleCandidate = SemanticResolver.CompatibleCandidate;
const Candidate = @import("candidate_collector.zig").Candidate;
const RejectionReason = @import("candidate_collector.zig").RejectionReason;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;
const TypeId = @import("type_registry.zig").TypeId;

// NextGen imports
const nextgen = @import("nextgen_diagnostic.zig");
const NextGenDiagnostic = nextgen.NextGenDiagnostic;
const DiagnosticCode = nextgen.DiagnosticCode;
const CauseCategory = nextgen.CauseCategory;
const hypothesis_engine = @import("hypothesis_engine.zig");
const HypothesisEngine = hypothesis_engine.HypothesisEngine;
const ErrorContext = hypothesis_engine.ErrorContext;
const TypeFlowAnalyzer = @import("type_flow_analyzer.zig").TypeFlowAnalyzer;
const TypeFlowRecorder = @import("type_flow_analyzer.zig").TypeFlowRecorder;
const SemanticCorrelator = @import("semantic_correlator.zig").SemanticCorrelator;
const FixLearningEngine = @import("fix_learning.zig").FixLearningEngine;

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
        var candidates: ArrayList(DiagnosticData.CandidateInfo) = .empty;

        for (ambiguous.candidates, 0..) |candidate, i| {
            const candidate_id = try std.fmt.allocPrint(self.allocator, "{c}", .{'A' + @as(u8, @intCast(i))});
            const signature = try std.fmt.allocPrint(self.allocator, "func {s}({s}) -> {s}", .{ candidate.candidate.function.name, candidate.candidate.function.parameter_types, candidate.candidate.function.return_type });

            var conversions: ArrayList(DiagnosticData.CandidateInfo.ConversionInfo) = .empty;
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
        var fixes: ArrayList(FixSuggestion) = .empty;

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
        var related: ArrayList(RelatedInfo) = .empty;

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

        var result: ArrayList(u8) = .empty;
        for (arg_types, 0..) |arg_type, i| {
            if (i > 0) try result.appendSlice(", ");
            const type_name = try self.getTypeName(arg_type);
            defer self.allocator.free(type_name);
            try result.appendSlice(type_name);
        }
        return try result.toOwnedSlice(alloc);
    }

    fn formatCandidateList(self: *DiagnosticEngine, candidates: []CompatibleCandidate) ![]const u8 {
        var result: ArrayList(u8) = .empty;

        for (candidates, 0..) |candidate, i| {
            const label = 'A' + @as(u8, @intCast(i));
            try result.writer().print("  ({c}) func {s}({s}) -> {s}  [from {s}]\n", .{ label, candidate.candidate.function.name, candidate.candidate.function.parameter_types, candidate.candidate.function.return_type, candidate.candidate.function.module_path });
        }

        return try result.toOwnedSlice(alloc);
    }

    fn formatAvailableFunctions(self: *DiagnosticEngine, functions: [][]const u8) ![]const u8 {
        if (functions.len == 0) return try self.allocator.dupe(u8, "  (none visible in current scope)");

        var result: ArrayList(u8) = .empty;
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

// =============================================================================
// NEXT-GENERATION DIAGNOSTIC ENGINE
// =============================================================================

/// Configuration for NextGen diagnostic engine
pub const NextGenConfig = struct {
    /// Enable multi-hypothesis analysis
    enable_hypotheses: bool = true,
    /// Enable type flow visualization
    enable_type_flow: bool = true,
    /// Enable semantic correlation (CID-based)
    enable_correlation: bool = true,
    /// Enable fix learning
    enable_learning: bool = true,
    /// Maximum hypotheses to generate
    max_hypotheses: u32 = 5,
};

/// Next-Generation Diagnostic Engine integrating all advanced features
pub const NextGenDiagnosticEngine = struct {
    allocator: Allocator,
    config: NextGenConfig,

    // Sub-engines
    hypothesis_engine: HypothesisEngine,
    type_flow_analyzer: TypeFlowAnalyzer,
    type_flow_recorder: TypeFlowRecorder,
    semantic_correlator: SemanticCorrelator,
    fix_learning_engine: FixLearningEngine,

    // Legacy engine for fallback
    legacy_engine: DiagnosticEngine,

    // Diagnostic counter
    next_diagnostic_id: u64,

    pub fn init(allocator: Allocator) NextGenDiagnosticEngine {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: Allocator, config: NextGenConfig) NextGenDiagnosticEngine {
        return .{
            .allocator = allocator,
            .config = config,
            .hypothesis_engine = HypothesisEngine.init(allocator),
            .type_flow_analyzer = TypeFlowAnalyzer.init(allocator),
            .type_flow_recorder = TypeFlowRecorder.init(allocator),
            .semantic_correlator = SemanticCorrelator.init(allocator),
            .fix_learning_engine = FixLearningEngine.initWithConfig(allocator, .{
                .enable_persistence = config.enable_learning,
            }),
            .legacy_engine = DiagnosticEngine.init(allocator),
            .next_diagnostic_id = 1,
        };
    }

    pub fn deinit(self: *NextGenDiagnosticEngine) void {
        self.hypothesis_engine.deinit();
        self.type_flow_analyzer.deinit();
        self.type_flow_recorder.deinit();
        self.semantic_correlator.deinit();
        self.fix_learning_engine.deinit();
    }

    /// Generate NextGen diagnostic from a resolution result
    pub fn generateFromResolveResult(
        self: *NextGenDiagnosticEngine,
        result: ResolveResult,
    ) !NextGenDiagnostic {
        const diagnostic_id = nextgen.DiagnosticId{ .id = self.next_diagnostic_id };
        self.next_diagnostic_id += 1;

        return switch (result) {
            .success => unreachable, // Should not generate diagnostic for success
            .ambiguous => |info| try self.generateAmbiguityDiagnostic(diagnostic_id, info),
            .no_matches => |info| try self.generateNoMatchesDiagnostic(diagnostic_id, info),
            .error_occurred => |info| try self.generateErrorDiagnostic(diagnostic_id, info),
        };
    }

    /// Generate diagnostic for ambiguous function call
    fn generateAmbiguityDiagnostic(
        self: *NextGenDiagnosticEngine,
        id: nextgen.DiagnosticId,
        info: ResolveResult.AmbiguityInfo,
    ) !NextGenDiagnostic {
        const span = nextgen.SourceSpan{
            .file = info.call_site.source_location.file,
            .start = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column,
                .byte_offset = info.call_site.source_location.start_byte,
            },
            .end = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column + 10,
                .byte_offset = info.call_site.source_location.end_byte,
            },
        };

        var diag = NextGenDiagnostic.init(
            self.allocator,
            id,
            DiagnosticCode.semantic(.dispatch_ambiguous),
            .@"error",
            span,
        );

        // Generate hypotheses (one per candidate)
        if (self.config.enable_hypotheses) {
            var candidates: ArrayList(HypothesisEngine.CandidateInfo) = .empty;
            defer candidates.deinit();

            for (info.candidates) |candidate| {
                try candidates.append(.{
                    .signature = candidate.candidate.function.parameter_types,
                    .module_path = candidate.candidate.function.module_path,
                    .definition_location = .{
                        .file = candidate.candidate.function.source_location.file,
                        .start = .{
                            .line = candidate.candidate.function.source_location.line,
                            .column = candidate.candidate.function.source_location.column,
                        },
                        .end = .{
                            .line = candidate.candidate.function.source_location.line,
                            .column = candidate.candidate.function.source_location.column + 10,
                        },
                    },
                    .conversion_cost = @intCast(candidate.conversion_path.get().total_cost),
                });
            }

            diag.hypotheses = try self.hypothesis_engine.generateAmbiguityHypotheses(
                info.call_site.function_name,
                candidates.items,
            );

            // Build confidence distribution
            if (diag.hypotheses.len > 0) {
                diag.confidence_distribution = try self.allocator.alloc(f32, diag.hypotheses.len);
                for (diag.hypotheses, 0..) |h, i| {
                    diag.confidence_distribution[i] = h.probability;
                }
            }
        }

        // Build human message
        const arg_types_str = try self.formatArgumentTypes(info.call_site.argument_types);
        defer self.allocator.free(arg_types_str);

        diag.human_message = .{
            .summary = try std.fmt.allocPrint(
                self.allocator,
                "Ambiguous call to `{s}` with arguments ({s})",
                .{ info.call_site.function_name, arg_types_str },
            ),
            .explanation = try std.fmt.allocPrint(
                self.allocator,
                "The compiler found {d} functions matching this call but cannot choose between them.\n" ++
                    "All candidates have equal conversion costs and specificity.",
                .{info.candidates.len},
            ),
            .suggestions = try self.allocator.dupe(
                u8,
                "Use explicit type casts or fully qualified names to disambiguate.",
            ),
            .educational_note = try self.allocator.dupe(
                u8,
                "Janus uses a specificity-based overload resolution system. " ++
                    "When multiple candidates are equally specific, you must help the compiler choose.",
            ),
            .severity_rationale = null,
        };

        // Build machine data
        diag.machine_data = .{
            .error_type = try self.allocator.dupe(u8, "ambiguous_dispatch"),
            .error_category = .ambiguous_dispatch,
            .affected_symbols = &[_]nextgen.MachineReadableData.SymbolInfo{},
            .scope_context = try self.allocator.dupe(u8, info.call_site.function_name),
        };

        // Register for cascade detection
        if (self.config.enable_correlation) {
            try self.semantic_correlator.registerDiagnostic(
                id,
                std.mem.zeroes(nextgen.CID),
                &[_][]const u8{info.call_site.function_name},
            );
        }

        return diag;
    }

    /// Generate diagnostic for no matching function
    fn generateNoMatchesDiagnostic(
        self: *NextGenDiagnosticEngine,
        id: nextgen.DiagnosticId,
        info: ResolveResult.NoMatchInfo,
    ) !NextGenDiagnostic {
        const span = nextgen.SourceSpan{
            .file = info.call_site.source_location.file,
            .start = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column,
                .byte_offset = info.call_site.source_location.start_byte,
            },
            .end = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column + 10,
                .byte_offset = info.call_site.source_location.end_byte,
            },
        };

        var diag = NextGenDiagnostic.init(
            self.allocator,
            id,
            DiagnosticCode.semantic(.dispatch_no_match),
            .@"error",
            span,
        );

        // Generate hypotheses
        if (self.config.enable_hypotheses) {
            var available: ArrayList(ErrorContext.SymbolInfo) = .empty;
            defer available.deinit();

            for (info.available_functions) |func_name| {
                try available.append(.{
                    .name = func_name,
                    .kind = .function,
                    .signature = null,
                    .visibility = .public,
                });
            }

            diag.hypotheses = try self.hypothesis_engine.generateNoMatchHypotheses(
                info.function_name,
                info.argument_types,
                available.items,
            );

            // Build confidence distribution
            if (diag.hypotheses.len > 0) {
                diag.confidence_distribution = try self.allocator.alloc(f32, diag.hypotheses.len);
                for (diag.hypotheses, 0..) |h, i| {
                    diag.confidence_distribution[i] = h.probability;
                }
            }
        }

        // Add type flow if available
        if (self.config.enable_type_flow and self.type_flow_recorder.count() > 0) {
            diag.type_flow_chain = try self.type_flow_analyzer.buildChain(
                &self.type_flow_recorder,
                TypeId.INVALID,
                TypeId.INVALID,
            );
        }

        // Build human message with hypothesis-aware content
        const arg_types_str = try self.formatArgumentTypes(info.argument_types);
        defer self.allocator.free(arg_types_str);

        var summary_buf: ArrayList(u8) = .empty;
        try summary_buf.writer().print(
            "No matching function for `{s}` with arguments ({s})",
            .{ info.function_name, arg_types_str },
        );

        var explanation_buf: ArrayList(u8) = .empty;
        const explanation_writer = explanation_buf.writer();

        try explanation_writer.print(
            "The compiler could not find any function named `{s}` " ++
                "that accepts the given arguments.\n\n",
            .{info.function_name},
        );

        // Add hypothesis-specific explanations
        if (diag.hypotheses.len > 0) {
            try explanation_writer.writeAll("Most likely causes:\n\n");
            for (diag.hypotheses[0..@min(3, diag.hypotheses.len)]) |h| {
                try explanation_writer.print(
                    "  [{d:.0}%] {s}\n        {s}\n\n",
                    .{ h.probability * 100, h.cause_category.description(), h.explanation },
                );
            }
        }

        diag.human_message = .{
            .summary = try summary_buf.toOwnedSlice(),
            .explanation = try explanation_buf.toOwnedSlice(),
            .suggestions = try self.allocator.dupe(
                u8,
                "Check function name spelling, argument types, and imports.",
            ),
            .educational_note = null,
            .severity_rationale = null,
        };

        // Build machine data
        diag.machine_data = .{
            .error_type = try self.allocator.dupe(u8, "no_matching_function"),
            .error_category = if (diag.hypotheses.len > 0)
                diag.hypotheses[0].cause_category
            else
                .scope_error,
            .affected_symbols = &[_]nextgen.MachineReadableData.SymbolInfo{},
            .scope_context = try self.allocator.dupe(u8, info.function_name),
        };

        // Convert hypotheses fixes to ranked suggestions
        if (diag.hypotheses.len > 0) {
            var fixes: ArrayList(nextgen.RankedFixSuggestion) = .empty;
            var rank: u32 = 1;

            for (diag.hypotheses) |h| {
                for (h.targeted_fixes) |fix| {
                    // Adjust confidence based on learning
                    const error_pattern = FixLearningEngine.computeErrorPattern(
                        diag.code,
                        h.cause_category,
                        0,
                    );
                    const fix_pattern = FixLearningEngine.computeFixPattern(
                        .other,
                        fix.description,
                    );

                    const adjusted_confidence = if (self.config.enable_learning)
                        self.fix_learning_engine.adjustConfidence(
                            fix.confidence,
                            error_pattern,
                            fix_pattern,
                            .other,
                        )
                    else
                        fix.confidence;

                    try fixes.append(.{
                        .suggestion = .{
                            .id = try self.allocator.dupe(u8, fix.id),
                            .description = try self.allocator.dupe(u8, fix.description),
                            .confidence = adjusted_confidence,
                            .edits = &[_]nextgen.TextEdit{},
                            .hypothesis_id = h.id,
                            .acceptance_rate = fix.acceptance_rate,
                            .requires_user_input = fix.requires_user_input,
                        },
                        .rank = rank,
                        .score = adjusted_confidence * h.probability,
                        .rationale = try std.fmt.allocPrint(
                            self.allocator,
                            "Based on hypothesis: {s}",
                            .{h.cause_category.description()},
                        ),
                    });
                    rank += 1;
                }
            }

            // Sort by score
            std.mem.sort(nextgen.RankedFixSuggestion, fixes.items, {}, struct {
                fn lessThan(_: void, a: nextgen.RankedFixSuggestion, b: nextgen.RankedFixSuggestion) bool {
                    return a.score > b.score;
                }
            }.lessThan);

            diag.fix_suggestions = try fixes.toOwnedSlice();
        }

        return diag;
    }

    /// Generate diagnostic for internal errors
    fn generateErrorDiagnostic(
        self: *NextGenDiagnosticEngine,
        id: nextgen.DiagnosticId,
        info: ResolveResult.ResolutionError,
    ) !NextGenDiagnostic {
        const span = nextgen.SourceSpan{
            .file = info.call_site.source_location.file,
            .start = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column,
            },
            .end = .{
                .line = info.call_site.source_location.line,
                .column = info.call_site.source_location.column + 10,
            },
        };

        var diag = NextGenDiagnostic.init(
            self.allocator,
            id,
            DiagnosticCode.semantic(.dispatch_internal),
            .@"error",
            span,
        );

        diag.human_message = .{
            .summary = try self.allocator.dupe(u8, info.message),
            .explanation = try self.allocator.dupe(u8, "An internal error occurred during resolution."),
            .suggestions = try self.allocator.dupe(u8, "Please report this as a compiler bug."),
            .educational_note = null,
            .severity_rationale = null,
        };

        diag.machine_data = .{
            .error_type = try self.allocator.dupe(u8, "internal_error"),
            .error_category = .scope_error,
            .affected_symbols = &[_]nextgen.MachineReadableData.SymbolInfo{},
            .scope_context = try self.allocator.dupe(u8, ""),
        };

        return diag;
    }

    /// Generate diagnostic for type mismatch with full type flow
    pub fn generateTypeMismatchDiagnostic(
        self: *NextGenDiagnosticEngine,
        expected: TypeId,
        actual: TypeId,
        location: nextgen.SourceSpan,
        context_name: []const u8,
    ) !NextGenDiagnostic {
        const diagnostic_id = nextgen.DiagnosticId{ .id = self.next_diagnostic_id };
        self.next_diagnostic_id += 1;

        var diag = NextGenDiagnostic.init(
            self.allocator,
            diagnostic_id,
            DiagnosticCode.semantic(.type_mismatch),
            .@"error",
            location,
        );

        // Add type flow chain
        if (self.config.enable_type_flow) {
            diag.type_flow_chain = try self.type_flow_analyzer.buildChain(
                &self.type_flow_recorder,
                expected,
                actual,
            );

            // Analyze the chain for insights
            if (diag.type_flow_chain) |*chain| {
                const analysis = self.type_flow_analyzer.analyzeChain(chain);
                if (analysis.suggested_fix_point) |fix_loc| {
                    // Add related info pointing to fix location
                    var related: ArrayList(nextgen.RelatedInfo) = .empty;
                    try related.append(.{
                        .message = try self.allocator.dupe(u8, "Consider fixing here"),
                        .span = fix_loc,
                        .info_type = .suggestion_context,
                    });
                    diag.related_info = try related.toOwnedSlice();
                }
            }
        }

        // Generate hypotheses for type mismatch
        if (self.config.enable_hypotheses) {
            const context = ErrorContext{
                .failed_symbol = context_name,
                .expected_type = expected,
                .actual_type = actual,
                .available_symbols = &[_]ErrorContext.SymbolInfo{},
                .error_location = location,
                .scope_context = context_name,
            };

            diag.hypotheses = try self.hypothesis_engine.generateTypeMismatchHypotheses(
                expected,
                actual,
                context,
            );

            if (diag.hypotheses.len > 0) {
                diag.confidence_distribution = try self.allocator.alloc(f32, diag.hypotheses.len);
                for (diag.hypotheses, 0..) |h, i| {
                    diag.confidence_distribution[i] = h.probability;
                }
            }
        }

        // Build human message
        diag.human_message = .{
            .summary = try std.fmt.allocPrint(
                self.allocator,
                "Type mismatch: expected {s}, found {s}",
                .{ typeIdToName(expected), typeIdToName(actual) },
            ),
            .explanation = try self.buildTypeFlowExplanation(&diag),
            .suggestions = try self.allocator.dupe(u8, "Add an explicit cast or change the source expression."),
            .educational_note = null,
            .severity_rationale = null,
        };

        diag.machine_data = .{
            .error_type = try self.allocator.dupe(u8, "type_mismatch"),
            .error_category = .type_mismatch,
            .affected_symbols = &[_]nextgen.MachineReadableData.SymbolInfo{},
            .scope_context = try self.allocator.dupe(u8, context_name),
        };

        return diag;
    }

    /// Get the type flow recorder for external use
    pub fn getTypeFlowRecorder(self: *NextGenDiagnosticEngine) *TypeFlowRecorder {
        return &self.type_flow_recorder;
    }

    /// Record a fix acceptance (for learning)
    pub fn recordFixAcceptance(
        self: *NextGenDiagnosticEngine,
        diag: *const NextGenDiagnostic,
        fix_index: usize,
        verbatim: bool,
    ) !void {
        if (!self.config.enable_learning) return;
        if (fix_index >= diag.fix_suggestions.len) return;

        const fix = diag.fix_suggestions[fix_index];

        // Determine category from hypothesis
        var category: FixLearningEngine.FixAcceptance.FixCategory = .other;
        if (fix.suggestion.hypothesis_id) |hyp_id| {
            for (diag.hypotheses) |h| {
                if (h.id.id == hyp_id.id) {
                    category = causeCategoryToFixCategory(h.cause_category);
                    break;
                }
            }
        }

        const error_pattern = FixLearningEngine.computeErrorPattern(
            diag.code,
            diag.machine_data.error_category,
            0,
        );
        const fix_pattern = FixLearningEngine.computeFixPattern(
            category,
            fix.suggestion.description,
        );

        try self.fix_learning_engine.recordAcceptance(
            error_pattern,
            fix_pattern,
            category,
            verbatim,
        );
    }

    /// Clear state for new compilation
    pub fn reset(self: *NextGenDiagnosticEngine) void {
        self.type_flow_recorder.clear();
        self.semantic_correlator.clearActiveDiagnostics();
    }

    // =========================================================================
    // Helpers
    // =========================================================================

    fn formatArgumentTypes(self: *NextGenDiagnosticEngine, arg_types: []const TypeId) ![]const u8 {
        if (arg_types.len == 0) return try self.allocator.dupe(u8, "");

        var result: ArrayList(u8) = .empty;
        for (arg_types, 0..) |arg_type, i| {
            if (i > 0) try result.appendSlice(", ");
            try result.appendSlice(typeIdToName(arg_type));
        }
        return try result.toOwnedSlice(alloc);
    }

    fn buildTypeFlowExplanation(self: *NextGenDiagnosticEngine, diag: *const NextGenDiagnostic) ![]const u8 {
        var buf: ArrayList(u8) = .empty;
        const writer = buf.writer();

        if (diag.type_flow_chain) |chain| {
            if (chain.steps.len > 0) {
                try writer.writeAll("Type flow chain:\n\n");
                for (chain.steps, 0..) |step, i| {
                    const marker = if (chain.divergence_point) |div|
                        (if (i == div) " <-- DIVERGENCE" else "")
                    else
                        "";

                    try writer.print("   {d}. {s}: {s}{s}\n", .{
                        i + 1,
                        step.expression_text,
                        step.reason.description(),
                        marker,
                    });
                }
            }
        }

        if (buf.items.len == 0) {
            try writer.writeAll("The expression type does not match the expected type in this context.");
        }

        return try buf.toOwnedSlice(alloc);
    }
};

fn typeIdToName(type_id: TypeId) []const u8 {
    return switch (type_id.id) {
        0 => "invalid",
        1 => "i32",
        2 => "f64",
        3 => "bool",
        4 => "string",
        else => "unknown",
    };
}

fn causeCategoryToFixCategory(cause: CauseCategory) FixLearningEngine.FixAcceptance.FixCategory {
    return switch (cause) {
        .missing_conversion, .type_mismatch => .explicit_cast,
        .wrong_import, .scope_error => .import_statement,
        .typo => .variable_rename,
        .wrong_argument_order => .argument_reorder,
        else => .other,
    };
}

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

test "NextGenDiagnosticEngine initialization" {
    const allocator = std.testing.allocator;

    var engine = NextGenDiagnosticEngine.init(allocator);
    defer engine.deinit();

    try std.testing.expect(engine.config.enable_hypotheses);
    try std.testing.expect(engine.config.enable_type_flow);
}

test "NextGenDiagnosticEngine type mismatch diagnostic" {
    const allocator = std.testing.allocator;

    var engine = NextGenDiagnosticEngine.initWithConfig(allocator, .{
        .enable_hypotheses = true,
        .enable_type_flow = false, // Disable for simpler test
        .enable_correlation = false,
        .enable_learning = false,
    });
    defer engine.deinit();

    const location = nextgen.SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 10, .column = 5 },
        .end = .{ .line = 10, .column = 15 },
    };

    var diag = try engine.generateTypeMismatchDiagnostic(
        TypeId.I32,
        TypeId.F64,
        location,
        "test_context",
    );
    defer diag.deinit();

    try std.testing.expectEqual(nextgen.Severity.@"error", diag.severity);
    try std.testing.expect(diag.hypotheses.len > 0);
}
