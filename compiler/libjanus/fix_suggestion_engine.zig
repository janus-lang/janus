// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const DiagnosticEngine = @import("diagnostic_engine.zig");
const FixSuggestion = DiagnosticEngine.FixSuggestion;
const TextEdit = DiagnosticEngine.TextEdit;
const SourceSpan = DiagnosticEngine.SourceSpan;
const SemanticResolver = @import("semantic_resolver.zig");
const ResolveResult = SemanticResolver.ResolveResult;
const CallSite = SemanticResolver.CallSite;
const CompatibleCandidate = SemanticResolver.CompatibleCandidate;
const TypeId = @import("type_registry.zig").TypeId;
const Conversion = @import("conversion_registry.zig").Conversion;

/// Fix suggestion engine for generating automated code repairs
pub const FixSuggestionEngine = struct {
    allocator: Allocator,

    pub fn init(allocator: Allocator) FixSuggestionEngine {
        return FixSuggestionEngine{
            .allocator = allocator,
        };
    }

    /// Generate fix suggestions for ambiguous function calls
    pub fn generateAmbiguityFixes(
        self: *FixSuggestionEngine,
        candidates: []CompatibleCandidate,
        call_site: CallSite,
    ) ![]FixSuggestion {
        var fixes = std.ArrayList(FixSuggestion).init(self.allocator);

        for (candidates, 0..) |candidate, i| {
            // Generate explicit cast suggestions
            try self.addCastSuggestions(&fixes, candidate, call_site, i);

            // Generate qualified name suggestions
            try self.addQualifiedNameSuggestions(&fixes, candidate, call_site, i);

            // Generate type annotation suggestions
            try self.addTypeAnnotationSuggestions(&fixes, candidate, call_site, i);
        }

        // Add function definition suggestion
        try self.addFunctionDefinitionSuggestion(&fixes, call_site);

        return fixes.toOwnedSlice();
    }

    /// Generate fix suggestions for no matching functions
    pub fn generateNoMatchFixes(
        self: *FixSuggestionEngine,
        call_site: CallSite,
        available_functions: []const []const u8,
    ) ![]FixSuggestion {
        var fixes = std.ArrayList(FixSuggestion).init(self.allocator);

        // Suggest similar function names (typo corrections)
        try self.addTypoCorrections(&fixes, call_site, available_functions);

        // Suggest import statements
        try self.addImportSuggestions(&fixes, call_site);

        // Suggest function definition
        try self.addFunctionDefinitionSuggestion(&fixes, call_site);

        return fixes.toOwnedSlice();
    }

    fn addCastSuggestions(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        candidate: CompatibleCandidate,
        call_site: CallSite,
        candidate_index: usize,
    ) !void {
        for (candidate.conversion_path.conversions, 0..) |conversion, arg_index| {
            if (conversion.cost > 0) { // Only suggest for actual conversions
                const fix_id = try std.fmt.allocPrint(self.allocator, "cast_arg_{d}_{d}", .{ candidate_index, arg_index });

                const target_type = try self.getTypeName(conversion.to);
                defer self.allocator.free(target_type);
                const description = try std.fmt.allocPrint(self.allocator, "Cast argument {d} to {s} (selects candidate {c})", .{ arg_index, target_type, 'A' + @as(u8, @intCast(candidate_index)) });

                // Generate the cast syntax
                const cast_syntax = try self.generateCastSyntax(conversion, arg_index);

                // Create text edit for the specific argument
                const edit_span = self.getArgumentSpan(call_site, arg_index);
                var edits = try self.allocator.alloc(TextEdit, 1);
                edits[0] = TextEdit{
                    .span = edit_span,
                    .replacement = cast_syntax,
                };

                try fixes.append(FixSuggestion{
                    .id = fix_id,
                    .description = description,
                    .confidence = self.calculateCastConfidence(conversion),
                    .edits = edits,
                });
            }
        }
    }

    fn addQualifiedNameSuggestions(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        candidate: CompatibleCandidate,
        call_site: CallSite,
        candidate_index: usize,
    ) !void {
        if (candidate.candidate.import_path) |import_path| {
            if (import_path.len > 0) {
                const fix_id = try std.fmt.allocPrint(self.allocator, "qualified_{d}", .{candidate_index});

                const description = try std.fmt.allocPrint(self.allocator, "Use fully qualified name from module {s}", .{import_path});

                const qualified_name = try std.fmt.allocPrint(self.allocator, "{s}::{s}", .{ import_path, call_site.function_name });

                // Create text edit for the function name
                const name_span = self.getFunctionNameSpan(call_site);
                var edits = try self.allocator.alloc(TextEdit, 1);
                edits[0] = TextEdit{
                    .span = name_span,
                    .replacement = qualified_name,
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

    fn addTypeAnnotationSuggestions(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        candidate: CompatibleCandidate,
        call_site: CallSite,
        candidate_index: usize,
    ) !void {
        // Suggest adding type annotations to variables to make intent clear
        for (candidate.conversion_path.conversions, 0..) |conversion, arg_index| {
            if (conversion.cost > 0) {
                const fix_id = try std.fmt.allocPrint(self.allocator, "annotate_var_{d}_{d}", .{ candidate_index, arg_index });

                const target_type = try self.getTypeName(conversion.to);
                defer self.allocator.free(target_type);
                const description = try std.fmt.allocPrint(self.allocator, "Add type annotation to make argument {d} type {s} explicit", .{ arg_index, target_type });

                // This would require more sophisticated source analysis
                // For now, provide a template suggestion
                const annotation_template = try std.fmt.allocPrint(self.allocator, "let arg_{d}: {s} = ...", .{ arg_index, target_type });

                const edit_span = self.getArgumentSpan(call_site, arg_index);
                var edits = try self.allocator.alloc(TextEdit, 1);
                edits[0] = TextEdit{
                    .span = edit_span,
                    .replacement = annotation_template,
                };

                try fixes.append(FixSuggestion{
                    .id = fix_id,
                    .description = description,
                    .confidence = 0.5, // Lower confidence for template suggestions
                    .edits = edits,
                });
            }
        }
    }

    fn addFunctionDefinitionSuggestion(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        call_site: CallSite,
    ) !void {
        const fix_id = try std.fmt.allocPrint(self.allocator, "define_function_{s}", .{call_site.function_name});

        const description = try std.fmt.allocPrint(self.allocator, "Define function {s} with the required signature", .{call_site.function_name});

        // Generate function signature from call site
        const signature = try self.generateFunctionSignature(call_site);

        // Insert at end of file (simplified)
        const insert_span = SourceSpan{
            .file = call_site.source_location.file,
            .start_line = 999999, // End of file
            .start_col = 1,
            .end_line = 999999,
            .end_col = 1,
            .start_byte = 999999,
            .end_byte = 999999,
        };

        var edits = try self.allocator.alloc(TextEdit, 1);
        edits[0] = TextEdit{
            .span = insert_span,
            .replacement = signature,
        };

        try fixes.append(FixSuggestion{
            .id = fix_id,
            .description = description,
            .confidence = 0.6,
            .edits = edits,
        });
    }

    fn addTypoCorrections(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        call_site: CallSite,
        available_functions: []const []const u8,
    ) !void {
        for (available_functions) |func_name| {
            const distance = self.calculateEditDistance(call_site.function_name, func_name);

            // Only suggest if edit distance is small (likely typo)
            if (distance <= 2 and distance > 0) {
                const fix_id = try std.fmt.allocPrint(self.allocator, "typo_correction_{s}", .{func_name});

                const description = try std.fmt.allocPrint(self.allocator, "Did you mean '{s}'?", .{func_name});

                const name_span = self.getFunctionNameSpan(call_site);
                var edits = try self.allocator.alloc(TextEdit, 1);
                edits[0] = TextEdit{
                    .span = name_span,
                    .replacement = try self.allocator.dupe(u8, func_name),
                };

                // Higher confidence for smaller edit distances
                const confidence = 1.0 - (@as(f32, @floatFromInt(distance)) / 3.0);

                try fixes.append(FixSuggestion{
                    .id = fix_id,
                    .description = description,
                    .confidence = confidence,
                    .edits = edits,
                });
            }
        }
    }

    fn addImportSuggestions(
        self: *FixSuggestionEngine,
        fixes: *std.ArrayList(FixSuggestion),
        call_site: CallSite,
    ) !void {
        // Common modules that might contain the function
        const common_modules = [_][]const u8{ "std.math", "std.string", "std.array", "std.io" };

        for (common_modules) |module| {
            const fix_id = try std.fmt.allocPrint(self.allocator, "import_{s}", .{module});

            const description = try std.fmt.allocPrint(self.allocator, "Import module {s} (may contain function {s})", .{ module, call_site.function_name });

            const import_statement = try std.fmt.allocPrint(self.allocator, "import {s};\n", .{module});

            // Insert at top of file
            const import_span = SourceSpan{
                .file = call_site.source_location.file,
                .start_line = 1,
                .start_col = 1,
                .end_line = 1,
                .end_col = 1,
                .start_byte = 0,
                .end_byte = 0,
            };

            var edits = try self.allocator.alloc(TextEdit, 1);
            edits[0] = TextEdit{
                .span = import_span,
                .replacement = import_statement,
            };

            try fixes.append(FixSuggestion{
                .id = fix_id,
                .description = description,
                .confidence = 0.3, // Low confidence for speculative imports
                .edits = edits,
            });
        }
    }

    // Helper functions
    fn generateCastSyntax(self: *FixSuggestionEngine, conversion: Conversion, arg_index: usize) ![]const u8 {
        const target_type = try self.getTypeName(conversion.to);
        defer self.allocator.free(target_type);
        return std.fmt.allocPrint(self.allocator, "arg_{d} as {s}", .{ arg_index, target_type });
    }

    fn calculateCastConfidence(self: *FixSuggestionEngine, conversion: Conversion) f32 {
        _ = self;

        // Higher confidence for safe conversions, lower for lossy ones
        if (conversion.is_lossy) {
            return 0.7;
        } else {
            return 0.9;
        }
    }

    fn getArgumentSpan(self: *FixSuggestionEngine, call_site: CallSite, arg_index: usize) SourceSpan {
        _ = self;
        _ = arg_index;

        // Simplified - would need actual source analysis
        return SourceSpan{
            .file = call_site.source_location.file,
            .start_line = call_site.source_location.line,
            .start_col = call_site.source_location.column + 10, // Approximate
            .end_line = call_site.source_location.line,
            .end_col = call_site.source_location.column + 15,
            .start_byte = call_site.source_location.start_byte + 10,
            .end_byte = call_site.source_location.start_byte + 15,
        };
    }

    fn getFunctionNameSpan(self: *FixSuggestionEngine, call_site: CallSite) SourceSpan {
        _ = self;

        return SourceSpan{
            .file = call_site.source_location.file,
            .start_line = call_site.source_location.line,
            .start_col = call_site.source_location.column,
            .end_line = call_site.source_location.line,
            .end_col = call_site.source_location.column + @as(u32, @intCast(call_site.function_name.len)),
            .start_byte = call_site.source_location.start_byte,
            .end_byte = call_site.source_location.start_byte + @as(u32, @intCast(call_site.function_name.len)),
        };
    }

    fn generateFunctionSignature(self: *FixSuggestionEngine, call_site: CallSite) ![]const u8 {
        var signature = std.ArrayList(u8).init(self.allocator);

        try signature.writer().print("func {s}(", .{call_site.function_name});

        for (call_site.argument_types, 0..) |arg_type, i| {
            if (i > 0) try signature.appendSlice(", ");
            const type_name = try self.getTypeName(arg_type);
            defer self.allocator.free(type_name);
            try signature.writer().print("arg_{d}: {s}", .{ i, type_name });
        }

        try signature.appendSlice(") -> ReturnType {\n    // TODO: Implement\n}\n\n");

        return signature.toOwnedSlice();
    }

    pub fn calculateEditDistance(self: *FixSuggestionEngine, a: []const u8, b: []const u8) u32 {

        // Simple Levenshtein distance implementation
        if (a.len == 0) return @intCast(b.len);
        if (b.len == 0) return @intCast(a.len);

        var matrix = std.ArrayList(std.ArrayList(u32)).init(self.allocator);
        defer {
            for (matrix.items) |row| {
                row.deinit();
            }
            matrix.deinit();
        }

        // Initialize matrix (simplified implementation)
        for (0..a.len + 1) |i| {
            var row = std.ArrayList(u32).init(self.allocator);
            for (0..b.len + 1) |j| {
                if (i == 0) {
                    row.append(@intCast(j)) catch return 999;
                } else if (j == 0) {
                    row.append(@intCast(i)) catch return 999;
                } else {
                    const cost: u32 = if (a[i - 1] == b[j - 1]) 0 else 1;
                    const deletion = matrix.items[i - 1].items[j] + 1;
                    const insertion = row.items[j - 1] + 1;
                    const substitution = matrix.items[i - 1].items[j - 1] + cost;

                    const min_val = @min(@min(deletion, insertion), substitution);
                    row.append(min_val) catch return 999;
                }
            }
            matrix.append(row) catch return 999;
        }

        return matrix.items[a.len].items[b.len];
    }

    pub fn getTypeName(self: *FixSuggestionEngine, type_id: TypeId) ![]const u8 {
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
test "FixSuggestionEngine typo correction" {
    var engine = FixSuggestionEngine.init(std.testing.allocator);

    const call_site = CallSite{
        .function_name = "lenght", // Typo for "length"
        .argument_types = &[_]TypeId{},
        .source_location = CallSite.SourceLocation{
            .file = "test.jan",
            .line = 10,
            .column = 5,
            .start_byte = 100,
            .end_byte = 107,
        },
    };

    const available_functions = [_][]const u8{ "length", "size", "count" };

    const fixes = try engine.generateNoMatchFixes(call_site, available_functions[0..]);
    defer {
        for (fixes) |*fix| {
            fix.deinit(std.testing.allocator);
        }
        std.testing.allocator.free(fixes);
    }

    // Should suggest "length" as a typo correction
    var found_typo_fix = false;
    for (fixes) |fix| {
        if (std.mem.indexOf(u8, fix.description, "length") != null) {
            found_typo_fix = true;
            try std.testing.expect(fix.confidence > 0.2); // Reasonable threshold for edit distance 2
        }
    }
    try std.testing.expect(found_typo_fix);
}

test "FixSuggestionEngine edit distance" {
    var engine = FixSuggestionEngine.init(std.testing.allocator);

    // Test edit distance calculation
    try std.testing.expect(engine.calculateEditDistance("hello", "hello") == 0);
    try std.testing.expect(engine.calculateEditDistance("hello", "helo") == 1);
    try std.testing.expect(engine.calculateEditDistance("hello", "world") == 4);
}
