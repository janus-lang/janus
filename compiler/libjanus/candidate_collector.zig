// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const Allocator = std.mem.Allocator;
const ScopeManager = @import("scope_manager.zig").ScopeManager;
const Scope = @import("scope_manager.zig").Scope;
const FunctionDecl = @import("scope_manager.zig").FunctionDecl;
const VisibilityLevel = @import("scope_manager.zig").VisibilityLevel;

/// Rejection reason for candidates that cannot be used
pub const RejectionReason = union(enum) {
    visibility_violation: VisibilityViolation,
    arity_mismatch: ArityMismatch,
    not_found: NotFound,

    pub const VisibilityViolation = struct {
        required_visibility: VisibilityLevel,
        actual_visibility: VisibilityLevel,
        module_context: []const u8,
    };

    pub const ArityMismatch = struct {
        expected_arity: u32,
        actual_arity: u32,
    };

    pub const NotFound = struct {
        function_name: []const u8,
        searched_scopes: []const []const u8,
    };
};

/// Candidate represents a potentially matching function
pub const Candidate = struct {
    function: *FunctionDecl,
    source_scope: *Scope,
    import_path: ?[]const u8,
    visibility_level: VisibilityLevel,
    rejection_reason: ?RejectionReason,

    pub fn isViable(self: *const Candidate) bool {
        return self.rejection_reason == null;
    }

    pub fn getQualifiedName(self: *const Candidate, allocator: Allocator) ![]const u8 {
        if (self.import_path) |path| {
            return std.fmt.allocPrint(allocator, "{s}::{s}", .{ path, self.function.name });
        }
        return try allocator.dupe(u8, self.function.name);
    }
};

/// CandidateSet holds all candidates for a function call
pub const CandidateSet = struct {
    candidates: []Candidate,
    viable_candidates: []Candidate,
    rejected_candidates: []Candidate,
    function_name: []const u8,
    call_arity: u32,
    allocator: Allocator,

    pub fn init(allocator: Allocator, function_name: []const u8, call_arity: u32) CandidateSet {
        return CandidateSet{
            .candidates = &[_]Candidate{},
            .viable_candidates = &[_]Candidate{},
            .rejected_candidates = &[_]Candidate{},
            .function_name = function_name,
            .call_arity = call_arity,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CandidateSet) void {
        // Free any allocated rejection reason data
        for (self.candidates) |candidate| {
            if (candidate.rejection_reason) |reason| {
                switch (reason) {
                    .not_found => |not_found| {
                        self.allocator.free(not_found.searched_scopes);
                    },
                    else => {},
                }
            }
        }

        self.allocator.free(self.candidates);
        self.allocator.free(self.viable_candidates);
        self.allocator.free(self.rejected_candidates);
    }

    pub fn addCandidate(self: *CandidateSet, candidate: Candidate) !void {
        const new_candidates = try self.allocator.realloc(self.candidates, self.candidates.len + 1);
        new_candidates[new_candidates.len - 1] = candidate;
        self.candidates = new_candidates;
    }

    pub fn finalize(self: *CandidateSet) !void {
        var viable = std.ArrayList(Candidate).init(self.allocator);
        var rejected = std.ArrayList(Candidate).init(self.allocator);

        for (self.candidates) |candidate| {
            if (candidate.isViable()) {
                try viable.append(candidate);
            } else {
                try rejected.append(candidate);
            }
        }

        self.viable_candidates = try viable.toOwnedSlice();
        self.rejected_candidates = try rejected.toOwnedSlice();
    }

    pub fn hasViableCandidates(self: *const CandidateSet) bool {
        return self.viable_candidates.len > 0;
    }

    pub fn isAmbiguous(self: *const CandidateSet) bool {
        return self.viable_candidates.len > 1;
    }
};

/// CandidateCollector discovers and filters function candidates
pub const CandidateCollector = struct {
    scope_manager: *ScopeManager,
    allocator: Allocator,

    pub fn init(allocator: Allocator, scope_manager: *ScopeManager) CandidateCollector {
        return CandidateCollector{
            .scope_manager = scope_manager,
            .allocator = allocator,
        };
    }

    pub fn collect(self: *CandidateCollector, function_name: []const u8, call_arity: u32) !CandidateSet {
        var candidate_set = CandidateSet.init(self.allocator, function_name, call_arity);

        // Get all accessible scopes
        const accessible_scopes = try self.scope_manager.getAccessibleScopes(self.allocator);
        defer self.allocator.free(accessible_scopes);

        // Search each scope for matching functions
        for (accessible_scopes) |scope| {
            const functions = scope.getFunctionsByName(function_name);

            for (functions) |function| {
                var candidate = Candidate{
                    .function = function,
                    .source_scope = scope,
                    .import_path = scope.module_path,
                    .visibility_level = function.visibility,
                    .rejection_reason = null,
                };

                // Apply filters
                self.applyVisibilityFilter(&candidate);
                self.applyArityFilter(&candidate, call_arity);

                try candidate_set.addCandidate(candidate);
            }
        }

        // If no candidates found, create a rejection reason
        if (candidate_set.candidates.len == 0) {
            var searched_scopes = std.ArrayList([]const u8).init(self.allocator);
            defer searched_scopes.deinit();

            for (accessible_scopes) |scope| {
                try searched_scopes.append(scope.name);
            }

            const not_found_candidate = Candidate{
                .function = undefined, // Will not be used
                .source_scope = undefined,
                .import_path = null,
                .visibility_level = .private,
                .rejection_reason = RejectionReason{
                    .not_found = RejectionReason.NotFound{
                        .function_name = function_name,
                        .searched_scopes = try searched_scopes.toOwnedSlice(),
                    },
                },
            };

            try candidate_set.addCandidate(not_found_candidate);
        }

        try candidate_set.finalize();
        return candidate_set;
    }

    fn applyVisibilityFilter(self: *CandidateCollector, candidate: *Candidate) void {
        if (candidate.rejection_reason != null) return;

        if (!self.scope_manager.isVisible(candidate.function, candidate.source_scope)) {
            candidate.rejection_reason = RejectionReason{
                .visibility_violation = RejectionReason.VisibilityViolation{
                    .required_visibility = .public, // Simplified
                    .actual_visibility = candidate.function.visibility,
                    .module_context = candidate.source_scope.getModulePath(),
                },
            };
        }
    }

    fn applyArityFilter(self: *CandidateCollector, candidate: *Candidate, expected_arity: u32) void {
        _ = self;
        if (candidate.rejection_reason != null) return;

        // Count parameters (simplified - just count commas + 1)
        const param_str = candidate.function.parameter_types;
        var actual_arity: u32 = 0;

        if (param_str.len > 0) {
            actual_arity = 1;
            for (param_str) |char| {
                if (char == ',') actual_arity += 1;
            }
        }

        if (actual_arity != expected_arity) {
            candidate.rejection_reason = RejectionReason{
                .arity_mismatch = RejectionReason.ArityMismatch{
                    .expected_arity = expected_arity,
                    .actual_arity = actual_arity,
                },
            };
        }
    }

    pub fn collectWithTypeInfo(
        self: *CandidateCollector,
        function_name: []const u8,
        argument_types: []const []const u8,
    ) !CandidateSet {
        return self.collect(function_name, @intCast(argument_types.len));
    }

    pub fn getAvailableFunctions(self: *CandidateCollector, allocator: Allocator) ![][]const u8 {
        var function_names = std.ArrayList([]const u8).init(allocator);
        var seen_names = std.HashMap([]const u8, void, std.hash_map.StringContext, std.hash_map.default_max_load_percentage).init(allocator);
        defer seen_names.deinit();

        const accessible_scopes = try self.scope_manager.getAccessibleScopes(allocator);
        defer allocator.free(accessible_scopes);

        for (accessible_scopes) |scope| {
            var func_iterator = scope.functions.iterator();
            while (func_iterator.next()) |entry| {
                const name = entry.key_ptr.*;
                if (!seen_names.contains(name)) {
                    try seen_names.put(name, {});
                    try function_names.append(try allocator.dupe(u8, name));
                }
            }
        }

        return function_names.toOwnedSlice();
    }
};

// Tests
test "CandidateCollector basic collection" {
    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var collector = CandidateCollector.init(std.testing.allocator, &scope_manager);

    // Add a test function to the current scope
    var function = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&function);

    // Collect candidates
    var candidates = try collector.collect("add", 2);
    defer candidates.deinit();

    try std.testing.expect(candidates.hasViableCandidates());
    try std.testing.expect(!candidates.isAmbiguous());
    try std.testing.expect(candidates.viable_candidates.len == 1);
    try std.testing.expectEqualStrings(candidates.viable_candidates[0].function.name, "add");
}

test "CandidateCollector arity mismatch" {
    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var collector = CandidateCollector.init(std.testing.allocator, &scope_manager);

    // Add a function with 2 parameters
    var function = FunctionDecl{
        .name = "add",
        .parameter_types = "i32,i32",
        .return_type = "i32",
        .visibility = .public,
        .module_path = "",
        .source_location = FunctionDecl.SourceLocation{
            .file = "test.jan",
            .line = 1,
            .column = 1,
        },
    };

    try scope_manager.current_scope.addFunction(&function);

    // Try to call with 3 arguments
    var candidates = try collector.collect("add", 3);
    defer candidates.deinit();

    try std.testing.expect(!candidates.hasViableCandidates());
    try std.testing.expect(candidates.rejected_candidates.len == 1);

    const rejection = candidates.rejected_candidates[0].rejection_reason.?;
    try std.testing.expect(rejection == .arity_mismatch);
    try std.testing.expect(rejection.arity_mismatch.expected_arity == 3);
    try std.testing.expect(rejection.arity_mismatch.actual_arity == 2);
}

test "CandidateCollector function not found" {
    var scope_manager = try ScopeManager.init(std.testing.allocator);
    defer scope_manager.deinit();

    var collector = CandidateCollector.init(std.testing.allocator, &scope_manager);

    // Try to collect non-existent function
    var candidates = try collector.collect("nonexistent", 1);
    defer candidates.deinit();

    try std.testing.expect(!candidates.hasViableCandidates());
    try std.testing.expect(candidates.rejected_candidates.len == 1);

    const rejection = candidates.rejected_candidates[0].rejection_reason.?;
    try std.testing.expect(rejection == .not_found);
    try std.testing.expectEqualStrings(rejection.not_found.function_name, "nonexistent");
}
