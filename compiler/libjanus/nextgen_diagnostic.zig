// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Next-Generation Diagnostic System
//!
//! A diagnostic system that treats errors as probabilistic hypotheses within
//! a semantic web. Key innovations:
//!
//! - Multi-Hypothesis: Multiple possible causes with probability scores
//! - Type Flow Visualization: Full inference chain with divergence detection
//! - CID-based Semantic Correlation: Track "what changed that broke this"
//! - Cascade Prevention: Group errors, show root cause first
//! - AI-Native Output: Complete JSON for automated fixing
//! - Effect Chain Visualization: Capability violations with call chain
//! - Fix Learning: System improves suggestions based on acceptance patterns

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;
const TypeId = @import("type_registry.zig").TypeId;
const ids = @import("astdb/ids.zig");

// =============================================================================
// CORE IDENTIFIERS
// =============================================================================

/// Unique identifier for a diagnostic
pub const DiagnosticId = struct {
    id: u64,

    pub fn format(self: DiagnosticId, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("D{d:0>8}", .{self.id});
    }
};

/// Unique identifier for a hypothesis
pub const HypothesisId = struct {
    id: u32,

    pub fn format(self: HypothesisId, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("H{d:0>4}", .{self.id});
    }
};

/// BLAKE3 Content ID (32 bytes)
pub const CID = [32]u8;

// =============================================================================
// DIAGNOSTIC CODE SYSTEM
// =============================================================================

/// Diagnostic code with phase and numeric identifier
pub const DiagnosticCode = struct {
    phase: Phase,
    code: u16,

    pub const Phase = enum(u8) {
        lexer = 'L',
        parser = 'P',
        semantic = 'S',
        codegen = 'C',
        linker = 'K',
        warning = 'W',
        info = 'I',

        pub fn prefix(self: Phase) []const u8 {
            return switch (self) {
                .lexer => "L",
                .parser => "P",
                .semantic => "S",
                .codegen => "C",
                .linker => "K",
                .warning => "W",
                .info => "I",
            };
        }
    };

    /// Semantic error subcategories (S0xxx)
    pub const SemanticCategory = enum(u16) {
        // S1xxx - Dispatch and Resolution
        dispatch_ambiguous = 1101,
        dispatch_no_match = 1102,
        dispatch_internal = 1103,
        dispatch_visibility = 1104,

        // S2xxx - Type Inference
        type_mismatch = 2001,
        type_inference_failed = 2002,
        type_constraint_violation = 2003,
        type_flow_divergence = 2004,

        // S3xxx - Effect System
        effect_missing_capability = 3001,
        effect_leak = 3002,
        effect_purity_violation = 3003,
        effect_unhandled = 3004,

        // S4xxx - Module and Import
        import_not_found = 4001,
        import_ambiguous = 4002,
        import_circular = 4003,
        visibility_violation = 4004,

        // S5xxx - Pattern Matching
        pattern_incomplete = 5001,
        pattern_unreachable = 5002,
        pattern_type_mismatch = 5003,

        // S6xxx - Lifetime and Memory
        lifetime_exceeded = 6001,
        borrow_conflict = 6002,
        use_after_move = 6003,
    };

    pub fn init(phase: Phase, code: u16) DiagnosticCode {
        return .{ .phase = phase, .code = code };
    }

    pub fn semantic(category: SemanticCategory) DiagnosticCode {
        return .{ .phase = .semantic, .code = @intFromEnum(category) };
    }

    pub fn format(self: DiagnosticCode, allocator: Allocator) ![]const u8 {
        return std.fmt.allocPrint(allocator, "{s}{d:0>4}", .{ self.phase.prefix(), self.code });
    }

    pub fn formatBuf(self: DiagnosticCode, buf: *[6]u8) []const u8 {
        _ = std.fmt.bufPrint(buf, "{s}{d:0>4}", .{ self.phase.prefix(), self.code }) catch return "?????";
        return buf[0..5];
    }
};

// =============================================================================
// SEVERITY
// =============================================================================

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

    pub fn isError(self: Severity) bool {
        return self == .@"error";
    }
};

// =============================================================================
// SOURCE LOCATION
// =============================================================================

pub const SourcePos = struct {
    line: u32 = 1,
    column: u32 = 1,
    byte_offset: u32 = 0,

    pub fn format(self: SourcePos, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.column });
    }
};

pub const SourceSpan = struct {
    file: []const u8 = "",
    start: SourcePos = .{},
    end: SourcePos = .{},

    pub fn format(self: SourceSpan, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        if (self.file.len > 0) {
            try writer.print("{s}:", .{self.file});
        }
        try writer.print("{}:{}", .{ self.start.line, self.start.column });
    }

    pub fn clone(self: SourceSpan, allocator: Allocator) !SourceSpan {
        return .{
            .file = try allocator.dupe(u8, self.file),
            .start = self.start,
            .end = self.end,
        };
    }
};

// =============================================================================
// HYPOTHESIS SYSTEM
// =============================================================================

/// Category of error causes
pub const CauseCategory = enum {
    // Type-related
    type_mismatch,
    missing_conversion,
    generic_constraint_violation,
    inference_failure,

    // Name-related
    typo,
    wrong_import,
    visibility_error,
    scope_error,

    // Structural
    missing_argument,
    extra_argument,
    wrong_argument_order,
    arity_mismatch,

    // Effect-related
    missing_capability,
    effect_leak,
    purity_violation,
    unhandled_effect,

    // Semantic
    ambiguous_dispatch,
    changed_dependency,
    version_mismatch,
    circular_dependency,

    pub fn description(self: CauseCategory) []const u8 {
        return switch (self) {
            .type_mismatch => "Type does not match expected",
            .missing_conversion => "No conversion path exists",
            .generic_constraint_violation => "Generic constraint not satisfied",
            .inference_failure => "Type inference failed",
            .typo => "Possible typo in identifier",
            .wrong_import => "Wrong module imported",
            .visibility_error => "Symbol not visible in current scope",
            .scope_error => "Symbol not found in scope",
            .missing_argument => "Required argument not provided",
            .extra_argument => "Too many arguments provided",
            .wrong_argument_order => "Arguments in wrong order",
            .arity_mismatch => "Wrong number of arguments",
            .missing_capability => "Required capability not available",
            .effect_leak => "Effect escapes its handler",
            .purity_violation => "Impure operation in pure context",
            .unhandled_effect => "Effect not handled",
            .ambiguous_dispatch => "Multiple candidates match equally",
            .changed_dependency => "Dependency signature changed",
            .version_mismatch => "Version incompatibility detected",
            .circular_dependency => "Circular dependency detected",
        };
    }
};

/// Evidence supporting or refuting a hypothesis
pub const Evidence = struct {
    evidence_type: EvidenceType,
    description: []const u8,
    location: ?SourceSpan,
    strength: f32, // 0.0 to 1.0, how strongly this affects probability

    pub const EvidenceType = enum {
        // Supporting evidence
        signature_match,
        name_similarity,
        conversion_available,
        pattern_match,
        historical_fix,

        // Refuting evidence
        type_incompatible,
        visibility_blocked,
        constraint_violated,
        arity_wrong,
    };

    pub fn isSupporting(self: Evidence) bool {
        return switch (self.evidence_type) {
            .signature_match, .name_similarity, .conversion_available, .pattern_match, .historical_fix => true,
            .type_incompatible, .visibility_blocked, .constraint_violated, .arity_wrong => false,
        };
    }

    pub fn deinit(self: *Evidence, allocator: Allocator) void {
        allocator.free(self.description);
    }
};

/// A single hypothesis about the error cause
pub const Hypothesis = struct {
    id: HypothesisId,
    cause_category: CauseCategory,
    probability: f32, // 0.0 to 1.0
    explanation: []const u8,
    evidence: []Evidence,
    counter_evidence: []Evidence,
    targeted_fixes: []FixSuggestion,

    pub fn deinit(self: *Hypothesis, allocator: Allocator) void {
        allocator.free(self.explanation);
        for (self.evidence) |*ev| {
            ev.deinit(allocator);
        }
        allocator.free(self.evidence);
        for (self.counter_evidence) |*ev| {
            ev.deinit(allocator);
        }
        allocator.free(self.counter_evidence);
        for (self.targeted_fixes) |*fix| {
            fix.deinit(allocator);
        }
        allocator.free(self.targeted_fixes);
    }

    /// Recalculate probability based on evidence
    pub fn recalculateProbability(self: *Hypothesis) void {
        var base: f32 = 0.5; // Start neutral

        for (self.evidence) |ev| {
            base += ev.strength * 0.3; // Supporting evidence increases probability
        }
        for (self.counter_evidence) |ev| {
            base -= ev.strength * 0.3; // Counter evidence decreases probability
        }

        // Clamp to valid range
        self.probability = @min(0.99, @max(0.01, base));
    }
};

// =============================================================================
// TYPE FLOW SYSTEM
// =============================================================================

/// Reason why a type was inferred at a step
pub const InferenceReason = enum {
    // Direct sources
    literal_value, // Type from literal: 42 -> i32
    explicit_annotation, // User wrote: x: i32
    function_parameter, // From function signature
    function_return, // Return type of called function

    // Propagation
    variable_binding, // From let x = expr
    assignment, // From x = expr
    field_access, // Type from field lookup
    method_call, // Type from method return

    // Generic
    generic_instantiation, // Generic parameter bound
    generic_constraint, // Type from constraint
    trait_bound, // Type from trait requirement

    // Context
    expected_type, // Type expected by context
    coercion, // Implicit coercion applied
    default_type, // Default type applied

    pub fn description(self: InferenceReason) []const u8 {
        return switch (self) {
            .literal_value => "inferred from literal",
            .explicit_annotation => "explicitly annotated",
            .function_parameter => "from function parameter",
            .function_return => "from function return type",
            .variable_binding => "from variable binding",
            .assignment => "from assignment",
            .field_access => "from field access",
            .method_call => "from method call",
            .generic_instantiation => "from generic instantiation",
            .generic_constraint => "from generic constraint",
            .trait_bound => "from trait bound",
            .expected_type => "expected by context",
            .coercion => "implicit coercion",
            .default_type => "default type",
        };
    }
};

/// A single step in the type inference chain
pub const InferenceStep = struct {
    location: SourceSpan,
    node_cid: CID,
    type_before: ?TypeId,
    type_after: TypeId,
    reason: InferenceReason,
    constraint_source: ?SourceSpan,
    expression_text: []const u8, // The code at this step

    pub fn deinit(self: *InferenceStep, allocator: Allocator) void {
        allocator.free(self.expression_text);
    }
};

/// Complete type flow chain showing inference history
pub const TypeFlowChain = struct {
    steps: []InferenceStep,
    divergence_point: ?usize, // Index where expected != actual
    expected_type: TypeId,
    actual_type: TypeId,

    pub fn deinit(self: *TypeFlowChain, allocator: Allocator) void {
        for (self.steps) |*step| {
            step.deinit(allocator);
        }
        allocator.free(self.steps);
    }

    /// Find where the type chain diverges from expected
    pub fn findDivergence(self: *TypeFlowChain) void {
        for (self.steps, 0..) |step, i| {
            if (!step.type_after.equals(self.expected_type)) {
                self.divergence_point = i;
                return;
            }
        }
        self.divergence_point = null;
    }
};

// =============================================================================
// SEMANTIC CORRELATION SYSTEM
// =============================================================================

/// Type of semantic change detected
pub const ChangeType = enum {
    signature_changed,
    type_changed,
    removed,
    renamed,
    visibility_changed,
    moved,
    deprecated,

    pub fn description(self: ChangeType) []const u8 {
        return switch (self) {
            .signature_changed => "function signature changed",
            .type_changed => "type definition changed",
            .removed => "symbol was removed",
            .renamed => "symbol was renamed",
            .visibility_changed => "visibility changed",
            .moved => "symbol was moved",
            .deprecated => "symbol was deprecated",
        };
    }
};

/// A detected semantic change
pub const SemanticChange = struct {
    entity_cid: CID,
    entity_name: []const u8,
    change_type: ChangeType,
    old_signature: ?[]const u8,
    new_signature: ?[]const u8,
    change_location: ?SourceSpan,
    timestamp: i64, // Unix timestamp of change

    pub fn deinit(self: *SemanticChange, allocator: Allocator) void {
        allocator.free(self.entity_name);
        if (self.old_signature) |sig| allocator.free(sig);
        if (self.new_signature) |sig| allocator.free(sig);
    }
};

/// CID reference to related code
pub const RelatedCID = struct {
    cid: CID,
    relationship: Relationship,
    name: []const u8,
    location: ?SourceSpan,

    pub const Relationship = enum {
        definition,
        usage,
        overload,
        implementation,
        dependency,
        caller,
        callee,
    };

    pub fn deinit(self: *RelatedCID, allocator: Allocator) void {
        allocator.free(self.name);
    }
};

/// Semantic context for an error
pub const SemanticContext = struct {
    error_site_cid: CID,
    related_cids: []RelatedCID,
    detected_changes: []SemanticChange,
    scope_chain: []ScopeId,

    pub const ScopeId = u32;

    pub fn deinit(self: *SemanticContext, allocator: Allocator) void {
        for (self.related_cids) |*cid| {
            cid.deinit(allocator);
        }
        allocator.free(self.related_cids);
        for (self.detected_changes) |*change| {
            change.deinit(allocator);
        }
        allocator.free(self.detected_changes);
        allocator.free(self.scope_chain);
    }
};

/// An error correlated with this diagnostic
pub const CorrelatedError = struct {
    diagnostic_id: DiagnosticId,
    correlation_type: CorrelationType,
    shared_cause_probability: f32, // Probability they share a root cause

    pub const CorrelationType = enum {
        same_root_cause, // Both stem from same change
        cascade_effect, // This error caused the other
        related_scope, // Errors in same scope
        same_change, // Triggered by same semantic change
    };
};

// =============================================================================
// EFFECT SYSTEM
// =============================================================================

/// A capability required but not available
pub const EffectViolation = struct {
    required_capability: []const u8,
    violation_type: ViolationType,
    effect_chain: []EffectChainLink,
    handler_location: ?SourceSpan,

    pub const ViolationType = enum {
        missing_capability,
        effect_leak,
        purity_violation,
        unhandled_effect,
    };

    pub const EffectChainLink = struct {
        function_name: []const u8,
        location: SourceSpan,
        effect_introduced: []const u8,

        pub fn deinit(self: *EffectChainLink, allocator: Allocator) void {
            allocator.free(self.function_name);
            allocator.free(self.effect_introduced);
        }
    };

    pub fn deinit(self: *EffectViolation, allocator: Allocator) void {
        allocator.free(self.required_capability);
        for (self.effect_chain) |*link| {
            link.deinit(allocator);
        }
        allocator.free(self.effect_chain);
    }
};

// =============================================================================
// FIX SUGGESTIONS
// =============================================================================

/// Text edit for automated fixes
pub const TextEdit = struct {
    span: SourceSpan,
    replacement: []const u8,

    pub fn deinit(self: *TextEdit, allocator: Allocator) void {
        allocator.free(self.replacement);
    }
};

/// Enhanced fix suggestion with learning context
pub const FixSuggestion = struct {
    id: []const u8,
    description: []const u8,
    confidence: f32, // 0.0 to 1.0
    edits: []TextEdit,
    hypothesis_id: ?HypothesisId, // Which hypothesis this fix addresses
    acceptance_rate: f32, // Historical acceptance rate for similar fixes
    requires_user_input: bool, // Does this fix need user clarification?

    pub fn deinit(self: *FixSuggestion, allocator: Allocator) void {
        allocator.free(self.id);
        allocator.free(self.description);
        for (self.edits) |*edit| {
            edit.deinit(allocator);
        }
        allocator.free(self.edits);
    }
};

/// Ranked fix suggestion with additional context
pub const RankedFixSuggestion = struct {
    suggestion: FixSuggestion,
    rank: u32,
    score: f32, // Combined score from confidence, acceptance rate, relevance
    rationale: []const u8,

    pub fn deinit(self: *RankedFixSuggestion, allocator: Allocator) void {
        self.suggestion.deinit(allocator);
        allocator.free(self.rationale);
    }
};

// =============================================================================
// LEARNING CONTEXT
// =============================================================================

/// Context for fix learning system
pub const LearningContext = struct {
    error_pattern_id: u64, // Hash of error characteristics
    similar_past_errors: u32, // How many similar errors seen
    best_past_fix: ?[]const u8, // Most commonly accepted fix for similar errors
    user_preference_signals: []PreferenceSignal,

    pub const PreferenceSignal = struct {
        signal_type: SignalType,
        weight: f32,

        pub const SignalType = enum {
            explicit_cast_preferred,
            qualified_name_preferred,
            import_preferred,
            inline_fix_preferred,
        };
    };

    pub fn deinit(self: *LearningContext, allocator: Allocator) void {
        if (self.best_past_fix) |fix| allocator.free(fix);
        allocator.free(self.user_preference_signals);
    }
};

// =============================================================================
// HUMAN MESSAGE
// =============================================================================

/// Enhanced human-readable message
pub const EnhancedHumanMessage = struct {
    summary: []const u8, // One-line summary
    explanation: []const u8, // Detailed explanation
    suggestions: []const u8, // How to fix
    educational_note: ?[]const u8, // Optional educational content
    severity_rationale: ?[]const u8, // Why this severity level

    pub fn deinit(self: *EnhancedHumanMessage, allocator: Allocator) void {
        allocator.free(self.summary);
        allocator.free(self.explanation);
        allocator.free(self.suggestions);
        if (self.educational_note) |note| allocator.free(note);
        if (self.severity_rationale) |rationale| allocator.free(rationale);
    }
};

// =============================================================================
// MACHINE READABLE DATA
// =============================================================================

/// Complete machine-readable diagnostic for AI agents
pub const MachineReadableData = struct {
    /// Schema version for forward compatibility
    schema_version: u32 = 1,

    /// Error classification
    error_type: []const u8,
    error_category: CauseCategory,

    /// Structured context
    affected_symbols: []SymbolInfo,
    scope_context: []const u8,

    /// For JSON serialization
    pub const SymbolInfo = struct {
        name: []const u8,
        kind: []const u8,
        file: []const u8,
        line: u32,
        cid: ?CID,
    };

    pub fn deinit(self: *MachineReadableData, allocator: Allocator) void {
        allocator.free(self.error_type);
        for (self.affected_symbols) |*sym| {
            allocator.free(sym.name);
            allocator.free(sym.kind);
            allocator.free(sym.file);
        }
        allocator.free(self.affected_symbols);
        allocator.free(self.scope_context);
    }
};

// =============================================================================
// RELATED INFO
// =============================================================================

/// Related information with enhanced context
pub const RelatedInfo = struct {
    message: []const u8,
    span: SourceSpan,
    info_type: InfoType,

    pub const InfoType = enum {
        definition_site,
        previous_usage,
        conflict_site,
        suggestion_context,
        similar_error,
    };

    pub fn deinit(self: *RelatedInfo, allocator: Allocator) void {
        allocator.free(self.message);
    }
};

// =============================================================================
// NEXT-GEN DIAGNOSTIC (Main structure)
// =============================================================================

/// Next-Generation Diagnostic combining all components
pub const NextGenDiagnostic = struct {
    allocator: Allocator,

    // Core identification
    id: DiagnosticId,
    code: DiagnosticCode,
    severity: Severity,
    primary_span: SourceSpan,

    // Multi-Hypothesis System
    hypotheses: []Hypothesis,
    confidence_distribution: []f32, // Probability per hypothesis (sums to 1.0)

    // Type Flow Visualization
    type_flow_chain: ?TypeFlowChain,

    // Semantic Correlation (CID-based)
    semantic_context: ?SemanticContext,
    correlated_errors: []CorrelatedError,
    cascade_root: ?DiagnosticId, // If this is a cascade effect

    // Effect System
    effect_violations: []EffectViolation,

    // Human Layer
    human_message: EnhancedHumanMessage,

    // Machine Layer
    machine_data: MachineReadableData,

    // Fix Suggestions (ranked)
    fix_suggestions: []RankedFixSuggestion,

    // Context
    related_info: []RelatedInfo,

    // Learning
    learning_context: ?LearningContext,

    pub fn init(allocator: Allocator, id: DiagnosticId, code: DiagnosticCode, severity: Severity, span: SourceSpan) NextGenDiagnostic {
        return .{
            .allocator = allocator,
            .id = id,
            .code = code,
            .severity = severity,
            .primary_span = span,
            .hypotheses = &[_]Hypothesis{},
            .confidence_distribution = &[_]f32{},
            .type_flow_chain = null,
            .semantic_context = null,
            .correlated_errors = &[_]CorrelatedError{},
            .cascade_root = null,
            .effect_violations = &[_]EffectViolation{},
            .human_message = .{
                .summary = "",
                .explanation = "",
                .suggestions = "",
                .educational_note = null,
                .severity_rationale = null,
            },
            .machine_data = .{
                .error_type = "",
                .error_category = .type_mismatch,
                .affected_symbols = &[_]MachineReadableData.SymbolInfo{},
                .scope_context = "",
            },
            .fix_suggestions = &[_]RankedFixSuggestion{},
            .related_info = &[_]RelatedInfo{},
            .learning_context = null,
        };
    }

    pub fn deinit(self: *NextGenDiagnostic) void {
        for (self.hypotheses) |*h| {
            h.deinit(self.allocator);
        }
        self.allocator.free(self.hypotheses);
        self.allocator.free(self.confidence_distribution);

        if (self.type_flow_chain) |*chain| {
            chain.deinit(self.allocator);
        }

        if (self.semantic_context) |*ctx| {
            ctx.deinit(self.allocator);
        }
        self.allocator.free(self.correlated_errors);

        for (self.effect_violations) |*v| {
            v.deinit(self.allocator);
        }
        self.allocator.free(self.effect_violations);

        self.human_message.deinit(self.allocator);
        self.machine_data.deinit(self.allocator);

        for (self.fix_suggestions) |*fix| {
            fix.deinit(self.allocator);
        }
        self.allocator.free(self.fix_suggestions);

        for (self.related_info) |*info| {
            info.deinit(self.allocator);
        }
        self.allocator.free(self.related_info);

        if (self.learning_context) |*ctx| {
            ctx.deinit(self.allocator);
        }
    }

    /// Get the most likely hypothesis
    pub fn primaryHypothesis(self: *const NextGenDiagnostic) ?*const Hypothesis {
        if (self.hypotheses.len == 0) return null;

        var best_idx: usize = 0;
        var best_prob: f32 = self.hypotheses[0].probability;

        for (self.hypotheses[1..], 1..) |h, i| {
            if (h.probability > best_prob) {
                best_prob = h.probability;
                best_idx = i;
            }
        }

        return &self.hypotheses[best_idx];
    }

    /// Check if this is a cascade effect (not root cause)
    pub fn isCascadeEffect(self: *const NextGenDiagnostic) bool {
        return self.cascade_root != null;
    }

    /// Normalize confidence distribution to sum to 1.0
    pub fn normalizeConfidence(self: *NextGenDiagnostic) void {
        if (self.confidence_distribution.len == 0) return;

        var sum: f32 = 0;
        for (self.confidence_distribution) |c| {
            sum += c;
        }

        if (sum > 0) {
            for (self.confidence_distribution) |*c| {
                c.* /= sum;
            }
        }
    }

    /// Serialize to JSON for AI agents
    pub fn toJson(self: *const NextGenDiagnostic) ![]const u8 {
        var json_buf = ArrayList(u8).init(self.allocator);
        const writer = json_buf.writer();

        try writer.writeAll("{");

        // Schema version
        try writer.writeAll("\"schema_version\":1,");

        // Error identification
        var code_buf: [6]u8 = undefined;
        const code_str = self.code.formatBuf(&code_buf);
        try writer.print("\"code\":\"{s}\",", .{code_str});
        try writer.print("\"severity\":\"{s}\",", .{self.severity.toString()});

        // Location
        try writer.writeAll("\"location\":{");
        try writer.print("\"file\":\"{s}\",", .{self.primary_span.file});
        try writer.print("\"line\":{},", .{self.primary_span.start.line});
        try writer.print("\"column\":{}", .{self.primary_span.start.column});
        try writer.writeAll("},");

        // Summary
        try self.writeJsonString(writer, "summary", self.human_message.summary);
        try writer.writeAll(",");

        // Hypotheses count
        try writer.print("\"hypothesis_count\":{},", .{self.hypotheses.len});

        // Primary hypothesis
        if (self.primaryHypothesis()) |primary| {
            try writer.print("\"primary_hypothesis\":{{\"probability\":{d:.2},\"category\":\"{s}\"}},", .{ primary.probability, @tagName(primary.cause_category) });
        }

        // Is cascade
        try writer.print("\"is_cascade_effect\":{}", .{self.isCascadeEffect()});

        try writer.writeAll("}");

        return json_buf.toOwnedSlice();
    }

    fn writeJsonString(self: *const NextGenDiagnostic, writer: anytype, key: []const u8, value: []const u8) !void {
        _ = self;
        try writer.print("\"{s}\":\"", .{key});
        // Escape special characters
        for (value) |c| {
            switch (c) {
                '"' => try writer.writeAll("\\\""),
                '\\' => try writer.writeAll("\\\\"),
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                else => try writer.writeByte(c),
            }
        }
        try writer.writeAll("\"");
    }

    /// Format for terminal output
    pub fn format(self: NextGenDiagnostic, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        var code_buf: [6]u8 = undefined;
        const code_str = self.code.formatBuf(&code_buf);

        // Main error line
        try writer.print("{s}[{s}]: {s}\n", .{ self.severity.toString(), code_str, self.human_message.summary });
        try writer.print("  --> {}\n", .{self.primary_span});

        // Hypotheses (if multiple)
        if (self.hypotheses.len > 1) {
            try writer.writeAll("\n  Most likely causes:\n");
            for (self.hypotheses) |h| {
                try writer.print("\n  [{d:.0}%] {s}\n", .{ h.probability * 100, h.cause_category.description() });
                try writer.print("        {s}\n", .{h.explanation});
            }
        }

        // Type flow (if present)
        if (self.type_flow_chain) |chain| {
            if (chain.divergence_point) |div_idx| {
                try writer.writeAll("\n  Type flow chain:\n");
                for (chain.steps, 0..) |step, i| {
                    const marker = if (i == div_idx) " <-- DIVERGENCE" else "";
                    try writer.print("   {d}. {s}: {s}{s}\n", .{
                        i + 1,
                        step.expression_text,
                        step.reason.description(),
                        marker,
                    });
                }
            }
        }

        // Semantic changes (if detected)
        if (self.semantic_context) |ctx| {
            if (ctx.detected_changes.len > 0) {
                try writer.writeAll("\n  Correlated changes detected:\n");
                for (ctx.detected_changes) |change| {
                    try writer.print("\n  CHANGED: {s} ({s})\n", .{ change.entity_name, change.change_type.description() });
                    if (change.old_signature) |old| {
                        try writer.print("    - Before: {s}\n", .{old});
                    }
                    if (change.new_signature) |new| {
                        try writer.print("    - After:  {s}\n", .{new});
                    }
                }
            }
        }

        // Fix suggestions
        if (self.fix_suggestions.len > 0) {
            try writer.writeAll("\n  Suggested fixes:\n");
            for (self.fix_suggestions) |fix| {
                try writer.print("    [{d:.0}%] {s}\n", .{ fix.suggestion.confidence * 100, fix.suggestion.description });
            }
        }
    }
};

// =============================================================================
// TESTS
// =============================================================================

test "NextGenDiagnostic basic creation" {
    const allocator = std.testing.allocator;

    const span = SourceSpan{
        .file = "test.jan",
        .start = .{ .line = 10, .column = 5 },
        .end = .{ .line = 10, .column = 15 },
    };

    var diag = NextGenDiagnostic.init(
        allocator,
        .{ .id = 1 },
        DiagnosticCode.semantic(.dispatch_ambiguous),
        .@"error",
        span,
    );
    defer diag.deinit();

    try std.testing.expectEqual(Severity.@"error", diag.severity);
    try std.testing.expectEqual(@as(u16, 1101), diag.code.code);
}

test "DiagnosticCode formatting" {
    const allocator = std.testing.allocator;

    const code = DiagnosticCode.semantic(.type_mismatch);
    const str = try code.format(allocator);
    defer allocator.free(str);

    try std.testing.expectEqualStrings("S2001", str);
}

test "Hypothesis probability calculation" {
    const allocator = std.testing.allocator;

    var evidence_arr = try allocator.alloc(Evidence, 1);
    defer allocator.free(evidence_arr);
    evidence_arr[0] = .{
        .evidence_type = .name_similarity,
        .description = "",
        .location = null,
        .strength = 0.8,
    };

    var hypothesis = Hypothesis{
        .id = .{ .id = 1 },
        .cause_category = .typo,
        .probability = 0.5,
        .explanation = "",
        .evidence = evidence_arr,
        .counter_evidence = &[_]Evidence{},
        .targeted_fixes = &[_]FixSuggestion{},
    };

    hypothesis.recalculateProbability();

    // Should be higher than 0.5 due to supporting evidence
    try std.testing.expect(hypothesis.probability > 0.5);
}

test "CauseCategory descriptions" {
    try std.testing.expectEqualStrings("Possible typo in identifier", CauseCategory.typo.description());
    try std.testing.expectEqualStrings("Type does not match expected", CauseCategory.type_mismatch.description());
}
