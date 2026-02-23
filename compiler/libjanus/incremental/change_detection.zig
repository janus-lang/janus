// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Change Detection Engine - Incremental Compilation
// Task 4.1: Create Change Set Analysis
//
// This module implements the change detection engine that compares current vs cached CIDs,
// propagates changes through the dependency graph, and generates minimal rebuild sets.
// Built upon our proven dual CID foundation and dependency graph analyzer.
//
// DOCTRINE: Change detection is the moment of truth for incremental compilation.
// Perfect precision here means perfect efficiency everywhere else.

const std = @import("std");
const compat_time = @import("compat_time");
const astdb = @import("../astdb.zig");
const compilation_unit = @import("compilation_unit.zig");
const interface_cid_mod = @import("interface_cid.zig");
const dependency_graph_mod = @import("dependency_graph.zig");
const cid_validation = @import("cid_validation.zig");

const CompilationUnit = compilation_unit.CompilationUnit;
const SemanticCID = compilation_unit.SemanticCID;
const InterfaceCID = interface_cid_mod.InterfaceCID;
const DependencyGraph = dependency_graph_mod.DependencyGraph;
const CIDValidator = cid_validation.CIDValidator;

/// Change Type - categorizes different kinds of changes for precise analysis
pub const ChangeType = enum {
    /// Interface change - affects dependent compilation units
    interface_change,

    /// Implementation change - affects only this compilation unit
    implementation_change,

    /// Dependency change - dependencies have changed, affecting this unit
    dependency_change,

    /// New file - compilation unit added to the project
    new_file,

    /// Deleted file - compilation unit removed from the project
    deleted_file,

    /// No change - compilation unit is unchanged
    no_change,
};

/// Change Detection Result - detailed analysis of what changed and why
pub const ChangeDetectionResult = struct {
    /// The compilation unit being analyzed
    unit: *const CompilationUnit,

    /// Type of change detected
    change_type: ChangeType,

    /// Detailed change information
    change_details: ChangeDetails,

    /// Whether this unit needs recompilation
    needs_recompilation: bool,

    /// Whether dependents need rebuilding
    affects_dependents: bool,

    /// Performance metrics for change detection
    detection_metrics: DetectionMetrics,
};

/// Change Details - specific information about what changed
pub const ChangeDetails = union(ChangeType) {
    interface_change: InterfaceChangeDetails,
    implementation_change: ImplementationChangeDetails,
    dependency_change: DependencyChangeDetails,
    new_file: NewFileDetails,
    deleted_file: DeletedFileDetails,
    no_change: NoChangeDetails,
};

pub const InterfaceChangeDetails = struct {
    /// Previous interface CID
    previous_interface_cid: InterfaceCID,

    /// Current interface CID
    current_interface_cid: InterfaceCID,

    /// Number of bytes different in the hash
    hash_difference_count: u32,

    /// Estimated impact on dependents
    dependent_impact: DependentImpact,
};

pub const ImplementationChangeDetails = struct {
    /// Previous semantic CID
    previous_semantic_cid: SemanticCID,

    /// Current semantic CID
    current_semantic_cid: SemanticCID,

    /// Interface CID (unchanged)
    interface_cid: InterfaceCID,

    /// Scope of implementation changes
    change_scope: ImplementationScope,
};

pub const DependencyChangeDetails = struct {
    /// Previous dependency CID
    previous_dependency_cid: InterfaceCID,

    /// Current dependency CID
    current_dependency_cid: InterfaceCID,

    /// Number of dependencies that changed
    changed_dependency_count: u32,

    /// List of changed dependencies
    changed_dependencies: []const *const CompilationUnit,
};

pub const NewFileDetails = struct {
    /// Source file path
    source_file: []const u8,

    /// Generated CIDs for the new file
    interface_cid: InterfaceCID,
    semantic_cid: SemanticCID,

    /// Dependencies of the new file
    dependencies: []const *const CompilationUnit,
};

pub const DeletedFileDetails = struct {
    /// Source file path that was deleted
    source_file: []const u8,

    /// Previous CIDs of the deleted file
    previous_interface_cid: InterfaceCID,
    previous_semantic_cid: SemanticCID,

    /// Units that depended on the deleted file
    affected_dependents: []const *const CompilationUnit,
};

pub const NoChangeDetails = struct {
    /// Confirmed CIDs (all unchanged)
    interface_cid: InterfaceCID,
    semantic_cid: SemanticCID,
    dependency_cid: InterfaceCID,

    /// Cache hit confirmation
    cache_hit: bool,
};

/// Dependent Impact - estimated impact on dependent compilation units
pub const DependentImpact = enum {
    /// Critical impact - all dependents must rebuild immediately
    critical,

    /// Major impact - most dependents will need rebuilding
    major,

    /// Moderate impact - some dependents may need rebuilding
    moderate,

    /// Minor impact - few dependents will need rebuilding
    minor,

    /// No impact - dependents are unaffected
    none,
};

/// Implementation Scope - scope of implementation changes
pub const ImplementationScope = enum {
    /// Function bodies only
    function_bodies,

    /// Private fields and methods
    private_members,

    /// Local variables and constants
    local_scope,

    /// Implementation algorithms
    algorithms,

    /// Comments and formatting
    cosmetic,

    /// Multiple implementation areas
    mixed,
};

/// Detection Metrics - performance metrics for change detection
pub const DetectionMetrics = struct {
    /// Time spent on change detection
    detection_time_ns: u64,

    /// Number of CID comparisons performed
    cid_comparisons: u32,

    /// Number of dependency checks performed
    dependency_checks: u32,

    /// Memory used during detection
    memory_used_bytes: u64,

    /// Cache hit rate during detection
    cache_hit_rate: f32,
};

/// Change Set - collection of all detected changes
pub const ChangeSet = struct {
    allocator: std.mem.Allocator,

    /// All change detection results
    changes: std.ArrayList(ChangeDetectionResult),

    /// Units that need recompilation
    units_to_recompile: std.ArrayList(*const CompilationUnit),

    /// Units that are affected by dependency changes
    units_affected_by_dependencies: std.ArrayList(*const CompilationUnit),

    /// New files to compile
    new_files: std.ArrayList(*const CompilationUnit),

    /// Deleted files to remove from cache
    deleted_files: std.ArrayList([]const u8),

    /// Overall change statistics
    statistics: ChangeStatistics,

    pub fn init(allocator: std.mem.Allocator) ChangeSet {
        return ChangeSet{
            .allocator = allocator,
            .changes = .empty,
            .units_to_recompile = .empty,
            .units_affected_by_dependencies = .empty,
            .new_files = .empty,
            .deleted_files = .empty,
            .statistics = ChangeStatistics.init(),
        };
    }

    pub fn deinit(self: *ChangeSet) void {
        self.changes.deinit();
        self.units_to_recompile.deinit();
        self.units_affected_by_dependencies.deinit();
        self.new_files.deinit();

        // Free deleted file paths
        for (self.deleted_files.items) |path| {
            self.allocator.free(path);
        }
        self.deleted_files.deinit();
    }

    /// Add a change detection result to the set
    pub fn addChange(self: *ChangeSet, result: ChangeDetectionResult) !void {
        try self.changes.append(result);

        // Update categorized lists
        switch (result.change_type) {
            .interface_change, .implementation_change => {
                if (result.needs_recompilation) {
                    try self.units_to_recompile.append(result.unit);
                }
            },
            .dependency_change => {
                try self.units_affected_by_dependencies.append(result.unit);
                if (result.needs_recompilation) {
                    try self.units_to_recompile.append(result.unit);
                }
            },
            .new_file => {
                try self.new_files.append(result.unit);
                try self.units_to_recompile.append(result.unit);
            },
            .deleted_file => {
                const path = try self.allocator.dupe(u8, result.change_details.deleted_file.source_file);
                try self.deleted_files.append(path);
            },
            .no_change => {
                // No action needed
            },
        }

        // Update statistics
        self.statistics.updateWithResult(result);
    }

    /// Get total number of units that need rebuilding
    pub fn getTotalRebuildCount(self: *const ChangeSet) u32 {
        return @as(u32, @intCast(self.units_to_recompile.items.len));
    }

    /// Check if any interface changes were detected
    pub fn hasInterfaceChanges(self: *const ChangeSet) bool {
        for (self.changes.items) |change| {
            if (change.change_type == .interface_change) return true;
        }
        return false;
    }

    /// Get summary of changes for reporting
    pub fn getSummary(self: *const ChangeSet) ChangeSummary {
        return ChangeSummary{
            .total_units_analyzed = @as(u32, @intCast(self.changes.items.len)),
            .units_to_recompile = @as(u32, @intCast(self.units_to_recompile.items.len)),
            .interface_changes = self.statistics.interface_changes,
            .implementation_changes = self.statistics.implementation_changes,
            .dependency_changes = self.statistics.dependency_changes,
            .new_files = @as(u32, @intCast(self.new_files.items.len)),
            .deleted_files = @as(u32, @intCast(self.deleted_files.items.len)),
            .cache_hit_rate = self.statistics.overall_cache_hit_rate,
        };
    }
};

/// Change Statistics - aggregate statistics for change detection
pub const ChangeStatistics = struct {
    interface_changes: u32,
    implementation_changes: u32,
    dependency_changes: u32,
    no_changes: u32,
    total_detection_time_ns: u64,
    total_cid_comparisons: u32,
    total_cache_hits: u32,
    total_cache_misses: u32,
    overall_cache_hit_rate: f32,

    pub fn init() ChangeStatistics {
        return ChangeStatistics{
            .interface_changes = 0,
            .implementation_changes = 0,
            .dependency_changes = 0,
            .no_changes = 0,
            .total_detection_time_ns = 0,
            .total_cid_comparisons = 0,
            .total_cache_hits = 0,
            .total_cache_misses = 0,
            .overall_cache_hit_rate = 0.0,
        };
    }

    pub fn updateWithResult(self: *ChangeStatistics, result: ChangeDetectionResult) void {
        switch (result.change_type) {
            .interface_change => self.interface_changes += 1,
            .implementation_change => self.implementation_changes += 1,
            .dependency_change => self.dependency_changes += 1,
            .no_change => self.no_changes += 1,
            .new_file, .deleted_file => {}, // Handled separately
        }

        self.total_detection_time_ns += result.detection_metrics.detection_time_ns;
        self.total_cid_comparisons += result.detection_metrics.cid_comparisons;

        // Update cache statistics
        const cache_hits = @as(u32, @intFromFloat(result.detection_metrics.cache_hit_rate * @as(f32, @floatFromInt(result.detection_metrics.cid_comparisons))));
        self.total_cache_hits += cache_hits;
        self.total_cache_misses += result.detection_metrics.cid_comparisons - cache_hits;

        // Recalculate overall cache hit rate
        const total_operations = self.total_cache_hits + self.total_cache_misses;
        if (total_operations > 0) {
            self.overall_cache_hit_rate = @as(f32, @floatFromInt(self.total_cache_hits)) / @as(f32, @floatFromInt(total_operations));
        }
    }
};

/// Change Summary - high-level summary for reporting
pub const ChangeSummary = struct {
    total_units_analyzed: u32,
    units_to_recompile: u32,
    interface_changes: u32,
    implementation_changes: u32,
    dependency_changes: u32,
    new_files: u32,
    deleted_files: u32,
    cache_hit_rate: f32,

    pub fn format(self: ChangeSummary, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("ChangeSummary{{ analyzed: {}, rebuild: {}, interface: {}, impl: {}, deps: {}, new: {}, deleted: {}, cache: {d:.1}% }}", .{
            self.total_units_analyzed,
            self.units_to_recompile,
            self.interface_changes,
            self.implementation_changes,
            self.dependency_changes,
            self.new_files,
            self.deleted_files,
            self.cache_hit_rate * 100.0,
        });
    }
};

/// Change Detection Engine - the brain of incremental compilation
pub const ChangeDetectionEngine = struct {
    allocator: std.mem.Allocator,
    cid_validator: CIDValidator,

    pub fn init(allocator: std.mem.Allocator) ChangeDetectionEngine {
        return ChangeDetectionEngine{
            .allocator = allocator,
            .cid_validator = CIDValidator.init(allocator),
        };
    }

    /// Detect changes by comparing current vs cached CIDs
    pub fn detectChanges(
        self: *ChangeDetectionEngine,
        current_units: []const *const CompilationUnit,
        cached_units: []const *const CompilationUnit,
    ) !ChangeSet {
        var change_set = ChangeSet.init(self.allocator);

        // Create lookup map for cached units
        var cached_lookup = std.HashMap([]const u8, *const CompilationUnit).init(self.allocator);
        defer cached_lookup.deinit();

        for (cached_units) |cached_unit| {
            try cached_lookup.put(cached_unit.source_file, cached_unit);
        }

        // Analyze each current unit
        for (current_units) |current_unit| {
            const result = if (cached_lookup.get(current_unit.source_file)) |cached_unit|
                try self.analyzeUnitChange(current_unit, cached_unit)
            else
                try self.analyzeNewFile(current_unit);

            try change_set.addChange(result);
        }

        // Find deleted files
        for (cached_units) |cached_unit| {
            var found = false;
            for (current_units) |current_unit| {
                if (std.mem.eql(u8, cached_unit.source_file, current_unit.source_file)) {
                    found = true;
                    break;
                }
            }

            if (!found) {
                const result = try self.analyzeDeletedFile(cached_unit);
                try change_set.addChange(result);
            }
        }

        return change_set;
    }

    /// Propagate changes through dependency graph to compute rebuild sets
    pub fn propagateChanges(
        self: *ChangeDetectionEngine,
        change_set: *ChangeSet,
        dependency_graph: *const DependencyGraph,
    ) !void {
        // Find all units with interface changes
        var interface_changed_units: std.ArrayList(*const CompilationUnit) = .empty;
        defer interface_changed_units.deinit();

        for (change_set.changes.items) |change| {
            if (change.change_type == .interface_change or change.change_type == .new_file) {
                try interface_changed_units.append(change.unit);
            }
        }

        // Propagate changes through dependency graph
        for (interface_changed_units.items) |changed_unit| {
            if (dependency_graph.getNode(changed_unit)) |node| {
                const rebuild_set = try dependency_graph.getRebuildSet(node.node_id);
                defer self.allocator.free(rebuild_set);

                // Add affected units to rebuild set
                for (rebuild_set) |node_id| {
                    const affected_node = &dependency_graph.nodes.items[node_id];

                    // Check if already in rebuild set
                    var already_added = false;
                    for (change_set.units_to_recompile.items) |existing_unit| {
                        if (existing_unit == affected_node.unit) {
                            already_added = true;
                            break;
                        }
                    }

                    if (!already_added) {
                        try change_set.units_to_recompile.append(affected_node.unit);
                        try change_set.units_affected_by_dependencies.append(affected_node.unit);
                    }
                }
            }
        }
    }

    /// Analyze changes for a single compilation unit
    fn analyzeUnitChange(
        self: *ChangeDetectionEngine,
        current_unit: *const CompilationUnit,
        cached_unit: *const CompilationUnit,
    ) !ChangeDetectionResult {
        const start_time = compat_time.nanoTimestamp();
        var cid_comparisons: u32 = 0;
        var cache_hits: u32 = 0;

        // Compare interface CIDs
        const interface_comparison = try self.cid_validator.compareInterfaceCIDs(
            current_unit.interface_cid,
            cached_unit.interface_cid,
        );
        cid_comparisons += 1;
        if (interface_comparison.are_equal) cache_hits += 1;

        // Compare semantic CIDs
        const semantic_comparison = try self.cid_validator.compareSemanticCIDs(
            current_unit.semantic_cid,
            cached_unit.semantic_cid,
        );
        cid_comparisons += 1;
        if (semantic_comparison.are_equal) cache_hits += 1;

        // Compare dependency CIDs
        const dependency_comparison = try self.cid_validator.compareInterfaceCIDs(
            current_unit.dependency_cid,
            cached_unit.dependency_cid,
        );
        cid_comparisons += 1;
        if (dependency_comparison.are_equal) cache_hits += 1;

        const end_time = compat_time.nanoTimestamp();

        // Determine change type and details
        const change_type: ChangeType = if (!interface_comparison.are_equal)
            .interface_change
        else if (!semantic_comparison.are_equal)
            .implementation_change
        else if (!dependency_comparison.are_equal)
            .dependency_change
        else
            .no_change;

        const change_details: ChangeDetails = switch (change_type) {
            .interface_change => .{
                .interface_change = InterfaceChangeDetails{
                    .previous_interface_cid = cached_unit.interface_cid,
                    .current_interface_cid = current_unit.interface_cid,
                    .hash_difference_count = interface_comparison.details.interface_cid.hash_difference_count,
                    .dependent_impact = self.calculateDependentImpact(interface_comparison.details.interface_cid.hash_difference_count),
                },
            },
            .implementation_change => .{
                .implementation_change = ImplementationChangeDetails{
                    .previous_semantic_cid = cached_unit.semantic_cid,
                    .current_semantic_cid = current_unit.semantic_cid,
                    .interface_cid = current_unit.interface_cid,
                    .change_scope = self.analyzeImplementationScope(semantic_comparison.details.semantic_cid.hash_difference_count),
                },
            },
            .dependency_change => .{
                .dependency_change = DependencyChangeDetails{
                    .previous_dependency_cid = cached_unit.dependency_cid,
                    .current_dependency_cid = current_unit.dependency_cid,
                    .changed_dependency_count = 1, // TODO: Calculate actual count
                    .changed_dependencies = &[_]*const CompilationUnit{}, // TODO: Identify changed dependencies
                },
            },
            .no_change => .{
                .no_change = NoChangeDetails{
                    .interface_cid = current_unit.interface_cid,
                    .semantic_cid = current_unit.semantic_cid,
                    .dependency_cid = current_unit.dependency_cid,
                    .cache_hit = true,
                },
            },
            else => unreachable,
        };

        return ChangeDetectionResult{
            .unit = current_unit,
            .change_type = change_type,
            .change_details = change_details,
            .needs_recompilation = change_type != .no_change,
            .affects_dependents = change_type == .interface_change,
            .detection_metrics = DetectionMetrics{
                .detection_time_ns = @as(u64, @intCast(end_time - start_time)),
                .cid_comparisons = cid_comparisons,
                .dependency_checks = 0, // TODO: Count dependency checks
                .memory_used_bytes = 0, // TODO: Track memory usage
                .cache_hit_rate = @as(f32, @floatFromInt(cache_hits)) / @as(f32, @floatFromInt(cid_comparisons)),
            },
        };
    }

    /// Analyze a new file
    fn analyzeNewFile(_: *ChangeDetectionEngine, current_unit: *const CompilationUnit) !ChangeDetectionResult {
        const start_time = compat_time.nanoTimestamp();
        const end_time = compat_time.nanoTimestamp();

        return ChangeDetectionResult{
            .unit = current_unit,
            .change_type = .new_file,
            .change_details = .{
                .new_file = NewFileDetails{
                    .source_file = current_unit.source_file,
                    .interface_cid = current_unit.interface_cid,
                    .semantic_cid = current_unit.semantic_cid,
                    .dependencies = &[_]*const CompilationUnit{}, // TODO: Extract dependencies
                },
            },
            .needs_recompilation = true,
            .affects_dependents = true, // New files might affect dependents
            .detection_metrics = DetectionMetrics{
                .detection_time_ns = @as(u64, @intCast(end_time - start_time)),
                .cid_comparisons = 0,
                .dependency_checks = 0,
                .memory_used_bytes = 0,
                .cache_hit_rate = 0.0,
            },
        };
    }

    /// Analyze a deleted file
    fn analyzeDeletedFile(_: *ChangeDetectionEngine, cached_unit: *const CompilationUnit) !ChangeDetectionResult {
        const start_time = compat_time.nanoTimestamp();
        const end_time = compat_time.nanoTimestamp();

        return ChangeDetectionResult{
            .unit = cached_unit,
            .change_type = .deleted_file,
            .change_details = .{
                .deleted_file = DeletedFileDetails{
                    .source_file = cached_unit.source_file,
                    .previous_interface_cid = cached_unit.interface_cid,
                    .previous_semantic_cid = cached_unit.semantic_cid,
                    .affected_dependents = &[_]*const CompilationUnit{}, // TODO: Find affected dependents
                },
            },
            .needs_recompilation = false, // Can't recompile deleted files
            .affects_dependents = true, // Deleted files affect dependents
            .detection_metrics = DetectionMetrics{
                .detection_time_ns = @as(u64, @intCast(end_time - start_time)),
                .cid_comparisons = 0,
                .dependency_checks = 0,
                .memory_used_bytes = 0,
                .cache_hit_rate = 0.0,
            },
        };
    }

    /// Calculate dependent impact based on interface changes
    fn calculateDependentImpact(self: *ChangeDetectionEngine, hash_difference_count: u32) DependentImpact {
        _ = self;

        return if (hash_difference_count >= 24)
            .critical // Major interface changes
        else if (hash_difference_count >= 16)
            .major // Significant interface changes
        else if (hash_difference_count >= 8)
            .moderate // Moderate interface changes
        else if (hash_difference_count >= 1)
            .minor // Minor interface changes
        else
            .none; // No interface changes
    }

    /// Analyze implementation change scope
    fn analyzeImplementationScope(self: *ChangeDetectionEngine, hash_difference_count: u32) ImplementationScope {
        _ = self;

        return if (hash_difference_count >= 24)
            .mixed // Major implementation changes
        else if (hash_difference_count >= 16)
            .algorithms // Algorithm changes
        else if (hash_difference_count >= 8)
            .function_bodies // Function body changes
        else if (hash_difference_count >= 4)
            .private_members // Private member changes
        else if (hash_difference_count >= 1)
            .local_scope // Local variable changes
        else
            .cosmetic; // Cosmetic changes only
    }
};

// Change Detection Rules - The Brain of Incremental Compilation
//
// CHANGE CLASSIFICATION:
// 1. Interface Changes - affect dependent compilation units (trigger rebuilds)
// 2. Implementation Changes - affect only this unit (no dependent rebuilds)
// 3. Dependency Changes - dependencies changed (may trigger rebuild)
// 4. New Files - must be compiled and may affect dependents
// 5. Deleted Files - remove from cache and update dependents
// 6. No Changes - use cached results (maximum efficiency)
//
// CID COMPARISON STRATEGY:
// 1. Compare InterfaceCID first (most critical for rebuild decisions)
// 2. Compare SemanticCID second (determines if recompilation needed)
// 3. Compare DependencyCID third (determines if dependencies changed)
// 4. Use hash difference counts for impact analysis
//
// CHANGE PROPAGATION:
// 1. Interface changes propagate through dependency graph
// 2. Implementation changes do not propagate (key efficiency gain)
// 3. New files may affect existing dependents
// 4. Deleted files require dependent updates
// 5. Dependency changes may require transitive rebuilds
//
// REBUILD SET OPTIMIZATION:
// 1. Compute minimal rebuild sets using dependency graph
// 2. Avoid unnecessary rebuilds through precise change detection
// 3. Batch related changes for efficient processing
// 4. Cache rebuild decisions for performance
//
// PERFORMANCE REQUIREMENTS:
// 1. Change detection must be sub-linear where possible
// 2. CID comparisons should be cached and reused
// 3. Dependency graph traversal should be optimized
// 4. Memory usage should be bounded and predictable
//
// This change detection system provides the precision needed for
// perfect incremental compilation - rebuilding exactly what needs
// rebuilding, nothing more, nothing less.
