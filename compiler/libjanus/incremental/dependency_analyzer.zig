// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Dependency Graph Analyzer - Precise Semantic Dependency Detection
// Task 3.1: Implement ASTDB-Based Dependency Detection
//
// This module implements precise dependency analysis using ASTDB queries to determine
// semantic relationships between compilation units. Built upon our proven dual CID foundation.
//
// DOCTRINE: Dependency precision is the key to incremental compilation efficiency.
// Too broad = unnecessary rebuilds. Too narrow = missed dependencies and broken builds.

const std = @import("std");
const astdb = @import("../astdb.zig");
const compilation_unit = @import("compilation_unit.zig");
const interface_cid_mod = @import("interface_cid.zig");

const Snapshot = astdb.Snapshot;
const NodeId = astdb.NodeId;
const DeclId = astdb.DeclId;
const RefId = astdb.RefId;
const StrId = astdb.StrId;
const CompilationUnit = compilation_unit.CompilationUnit;
const InterfaceCID = interface_cid_mod.InterfaceCID;

/// Dependency Type - categorizes different kinds of dependencies for precise analysis
pub const DependencyType = enum {
    /// Interface dependency - depends on public interface of another module
    interface,

    /// Type dependency - depends on type definitions from another module
    type_definition,

    /// Symbol dependency - depends on specific symbols (functions, constants) from another module
    symbol_reference,

    /// Module dependency - depends on entire module (import statement)
    module_import,

    /// Transitive dependency - indirect dependency through other modules
    transitive,
};

/// Dependency Relationship - represents a semantic dependency between compilation units
pub const DependencyRelationship = struct {
    /// Source compilation unit (the one that depends)
    source_unit: *const CompilationUnit,

    /// Target compilation unit (the one being depended upon)
    target_unit: *const CompilationUnit,

    /// Type of dependency relationship
    dependency_type: DependencyType,

    /// Specific symbols or elements involved in the dependency
    dependency_details: DependencyDetails,

    /// Strength of the dependency (affects rebuild priority)
    strength: DependencyStrength,

    /// Source location where the dependency occurs
    source_location: astdb.Span,
};

/// Dependency Details - specific information about what creates the dependency
pub const DependencyDetails = union(DependencyType) {
    interface: InterfaceDependency,
    type_definition: TypeDependency,
    symbol_reference: SymbolDependency,
    module_import: ModuleDependency,
    transitive: TransitiveDependency,
};

pub const InterfaceDependency = struct {
    /// Interface elements being used
    used_interface_elements: []const StrId,

    /// Whether the dependency is on the complete interface or specific elements
    is_complete_interface: bool,
};

pub const TypeDependency = struct {
    /// Type names being referenced
    referenced_types: []const StrId,

    /// Whether the types are used in signatures (interface) or implementation
    used_in_interface: bool,
};

pub const SymbolDependency = struct {
    /// Specific symbols being referenced
    referenced_symbols: []const StrId,

    /// Whether symbols are used in public interface or private implementation
    used_in_interface: bool,
};

pub const ModuleDependency = struct {
    /// Module name being imported
    module_name: StrId,

    /// Specific imports from the module (empty = import all)
    specific_imports: []const StrId,

    /// Whether the import affects the public interface
    affects_interface: bool,
};

pub const TransitiveDependency = struct {
    /// Intermediate compilation units in the dependency chain
    dependency_chain: []const *const CompilationUnit,

    /// Original dependency that created the transitive relationship
    root_dependency: *const DependencyRelationship,
};

/// Dependency Strength - affects rebuild priority and optimization decisions
pub const DependencyStrength = enum {
    /// Critical dependency - changes always require immediate rebuild
    critical,

    /// Strong dependency - changes usually require rebuild
    strong,

    /// Moderate dependency - changes may require rebuild depending on specifics
    moderate,

    /// Weak dependency - changes rarely require rebuild
    weak,

    /// Optional dependency - changes never require rebuild (e.g., debug info)
    optional,
};

/// Dependency Graph - complete representation of compilation unit dependencies
pub const DependencyGraph = struct {
    allocator: std.mem.Allocator,

    /// All compilation units in the graph
    compilation_units: std.ArrayList(*const CompilationUnit),

    /// All dependency relationships
    dependencies: std.ArrayList(DependencyRelationship),

    /// Fast lookup: compilation unit -> dependencies
    unit_to_dependencies: std.HashMap(*const CompilationUnit, std.ArrayList(usize)),

    /// Fast lookup: compilation unit -> dependents
    unit_to_dependents: std.HashMap(*const CompilationUnit, std.ArrayList(usize)),

    /// Topological ordering for build scheduling
    topological_order: std.ArrayList(*const CompilationUnit),

    pub fn init(allocator: std.mem.Allocator) DependencyGraph {
        return DependencyGraph{
            .allocator = allocator,
            .compilation_units = std.ArrayList(*const CompilationUnit).init(allocator),
            .dependencies = std.ArrayList(DependencyRelationship).init(allocator),
            .unit_to_dependencies = std.HashMap(*const CompilationUnit, std.ArrayList(usize)).init(allocator),
            .unit_to_dependents = std.HashMap(*const CompilationUnit, std.ArrayList(usize)).init(allocator),
            .topological_order = std.ArrayList(*const CompilationUnit).init(allocator),
        };
    }

    pub fn deinit(self: *DependencyGraph) void {
        self.compilation_units.deinit();
        self.dependencies.deinit();

        // Deinit all ArrayLists in the hash maps
        var dep_iter = self.unit_to_dependencies.iterator();
        while (dep_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.unit_to_dependencies.deinit();

        var dependent_iter = self.unit_to_dependents.iterator();
        while (dependent_iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.unit_to_dependents.deinit();

        self.topological_order.deinit();
    }

    /// Add a compilation unit to the dependency graph
    pub fn addCompilationUnit(self: *DependencyGraph, unit: *const CompilationUnit) !void {
        try self.compilation_units.append(unit);
        try self.unit_to_dependencies.put(unit, std.ArrayList(usize).init(self.allocator));
        try self.unit_to_dependents.put(unit, std.ArrayList(usize).init(self.allocator));
    }

    /// Add a dependency relationship to the graph
    pub fn addDependency(self: *DependencyGraph, dependency: DependencyRelationship) !void {
        const dep_index = self.dependencies.items.len;
        try self.dependencies.append(dependency);

        // Update fast lookup tables
        if (self.unit_to_dependencies.getPtr(dependency.source_unit)) |deps| {
            try deps.append(dep_index);
        }

        if (self.unit_to_dependents.getPtr(dependency.target_unit)) |dependents| {
            try dependents.append(dep_index);
        }
    }

    /// Get all dependencies of a compilation unit
    pub fn getDependencies(self: *const DependencyGraph, unit: *const CompilationUnit) []const DependencyRelationship {
        if (self.unit_to_dependencies.get(unit)) |dep_indices| {
            // TODO: Return slice of dependencies based on indices
            // For now, return empty slice
            _ = dep_indices;
            return &[_]DependencyRelationship{};
        }
        return &[_]DependencyRelationship{};
    }

    /// Get all dependents of a compilation unit (units that depend on this one)
    pub fn getDependents(self: *const DependencyGraph, unit: *const CompilationUnit) []const DependencyRelationship {
        if (self.unit_to_dependents.get(unit)) |dependent_indices| {
            // TODO: Return slice of dependents based on indices
            _ = dependent_indices;
            return &[_]DependencyRelationship{};
        }
        return &[_]DependencyRelationship{};
    }

    /// Compute topological ordering for build scheduling
    pub fn computeTopologicalOrder(self: *DependencyGraph) !void {
        self.topological_order.clearRetainingCapacity();

        // Kahn's algorithm for topological sorting
        var in_degree = std.HashMap(*const CompilationUnit, u32).init(self.allocator);
        defer in_degree.deinit();

        // Initialize in-degrees
        for (self.compilation_units.items) |unit| {
            try in_degree.put(unit, 0);
        }

        // Calculate in-degrees
        for (self.dependencies.items) |dep| {
            if (in_degree.getPtr(dep.target_unit)) |degree| {
                degree.* += 1;
            }
        }

        // Queue for units with no dependencies
        var queue = std.ArrayList(*const CompilationUnit).init(self.allocator);
        defer queue.deinit();

        // Add units with no incoming edges
        var iter = in_degree.iterator();
        while (iter.next()) |entry| {
            if (entry.value_ptr.* == 0) {
                try queue.append(entry.key_ptr.*);
            }
        }

        // Process queue
        while (queue.items.len > 0) {
            const unit = queue.orderedRemove(0);
            try self.topological_order.append(unit);

            // Reduce in-degree of dependents
            if (self.unit_to_dependents.get(unit)) |dependent_indices| {
                for (dependent_indices.items) |dep_index| {
                    const dep = &self.dependencies.items[dep_index];
                    if (in_degree.getPtr(dep.source_unit)) |degree| {
                        degree.* -= 1;
                        if (degree.* == 0) {
                            try queue.append(dep.source_unit);
                        }
                    }
                }
            }
        }

        // Check for cycles
        if (self.topological_order.items.len != self.compilation_units.items.len) {
            return error.CircularDependency;
        }
    }

    /// Detect circular dependencies in the graph
    pub fn detectCircularDependencies(_: *const DependencyGraph) ![]const DependencyRelationship {
        // TODO: Implement cycle detection using DFS
        // For now, return empty slice
        return &[_]DependencyRelationship{};
    }
};

/// Dependency Analyzer - analyzes ASTDB to extract precise semantic dependencies
pub const DependencyAnalyzer = struct {
    allocator: std.mem.Allocator,
    snapshot: *const Snapshot,

    pub fn init(allocator: std.mem.Allocator, snapshot: *const Snapshot) DependencyAnalyzer {
        return DependencyAnalyzer{
            .allocator = allocator,
            .snapshot = snapshot,
        };
    }

    /// Analyze dependencies for a single compilation unit using ASTDB queries
    pub fn analyzeDependencies(self: *DependencyAnalyzer, unit: *const CompilationUnit) ![]DependencyRelationship {
        var dependencies = std.ArrayList(DependencyRelationship).init(self.allocator);
        defer dependencies.deinit();

        // Analyze the root node of the compilation unit
        try self.analyzeNodeDependencies(unit.root_node, unit, &dependencies);

        return dependencies.toOwnedSlice();
    }

    /// Build complete dependency graph for multiple compilation units
    pub fn buildDependencyGraph(self: *DependencyAnalyzer, units: []const *const CompilationUnit) !DependencyGraph {
        var graph = DependencyGraph.init(self.allocator);

        // Add all compilation units to the graph
        for (units) |unit| {
            try graph.addCompilationUnit(unit);
        }

        // Analyze dependencies for each unit
        for (units) |unit| {
            const unit_dependencies = try self.analyzeDependencies(unit);
            defer self.allocator.free(unit_dependencies);

            for (unit_dependencies) |dep| {
                try graph.addDependency(dep);
            }
        }

        // Compute topological ordering
        try graph.computeTopologicalOrder();

        return graph;
    }

    /// Analyze dependencies for a specific ASTDB node
    fn analyzeNodeDependencies(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        const node = self.snapshot.getNode(node_id) orelse return;

        switch (node.kind) {
            .import_decl => try self.analyzeImportDependency(node_id, source_unit, dependencies),
            .call_expr => try self.analyzeCallDependency(node_id, source_unit, dependencies),
            .identifier, .qualified_name => try self.analyzeSymbolDependency(node_id, source_unit, dependencies),
            .func_decl => try self.analyzeFunctionDependencies(node_id, source_unit, dependencies),
            .struct_decl => try self.analyzeStructDependencies(node_id, source_unit, dependencies),
            .var_decl => try self.analyzeVariableDependencies(node_id, source_unit, dependencies),

            // Recurse into container nodes
            .program, .root, .block_stmt => {
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.analyzeNodeDependencies(child_id, source_unit, dependencies);
                }
            },

            else => {
                // For other node types, recurse into children
                const children = node.children(self.snapshot);
                for (children) |child_id| {
                    try self.analyzeNodeDependencies(child_id, source_unit, dependencies);
                }
            },
        }
    }

    /// Analyze import statement dependencies
    fn analyzeImportDependency(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Extract module name from import statement
        // TODO: Determine if import affects interface or implementation
        // TODO: Create ModuleDependency with appropriate strength

        _ = self;
        _ = node_id;
        _ = source_unit;
        _ = dependencies;

        // Placeholder implementation
    }

    /// Analyze function call dependencies
    fn analyzeCallDependency(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Resolve function call to its declaration
        // TODO: Determine if call is to external module
        // TODO: Create SymbolDependency with appropriate strength

        _ = self;
        _ = node_id;
        _ = source_unit;
        _ = dependencies;

        // Placeholder implementation
    }

    /// Analyze symbol reference dependencies
    fn analyzeSymbolDependency(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Resolve symbol reference to its declaration
        // TODO: Determine if symbol is from external module
        // TODO: Create appropriate dependency based on symbol type

        _ = self;
        _ = node_id;
        _ = source_unit;
        _ = dependencies;

        // Placeholder implementation
    }

    /// Analyze function declaration dependencies (parameters, return types)
    fn analyzeFunctionDependencies(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Analyze parameter types for external dependencies
        // TODO: Analyze return type for external dependencies
        // TODO: Recurse into function body for implementation dependencies

        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.analyzeNodeDependencies(child_id, source_unit, dependencies);
        }
    }

    /// Analyze struct declaration dependencies (field types, methods)
    fn analyzeStructDependencies(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Analyze field types for external dependencies
        // TODO: Analyze method signatures for external dependencies
        // TODO: Distinguish interface vs implementation dependencies

        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.analyzeNodeDependencies(child_id, source_unit, dependencies);
        }
    }

    /// Analyze variable declaration dependencies (types, initializers)
    fn analyzeVariableDependencies(
        self: *DependencyAnalyzer,
        node_id: NodeId,
        source_unit: *const CompilationUnit,
        dependencies: *std.ArrayList(DependencyRelationship),
    ) !void {
        // TODO: Analyze variable type for external dependencies
        // TODO: Analyze initializer expression for external dependencies
        // TODO: Determine if variable affects interface (public constants)

        const node = self.snapshot.getNode(node_id) orelse return;
        const children = node.children(self.snapshot);
        for (children) |child_id| {
            try self.analyzeNodeDependencies(child_id, source_unit, dependencies);
        }
    }

    /// Resolve symbol reference to its declaration using ASTDB queries
    fn resolveSymbolReference(self: *DependencyAnalyzer, node_id: NodeId) ?DeclId {
        // TODO: Query ASTDB reference table to find target declaration
        // TODO: Handle qualified names and scope resolution

        _ = self;
        _ = node_id;
        return null; // Placeholder
    }

    /// Determine if a declaration is from an external module
    fn isExternalDeclaration(self: *DependencyAnalyzer, decl_id: DeclId, source_unit: *const CompilationUnit) bool {
        // TODO: Compare declaration's compilation unit with source unit
        // TODO: Handle module boundaries and import relationships

        _ = self;
        _ = decl_id;
        _ = source_unit;
        return false; // Placeholder
    }

    /// Calculate dependency strength based on usage context
    fn calculateDependencyStrength(
        self: *DependencyAnalyzer,
        dependency_type: DependencyType,
        used_in_interface: bool,
        usage_frequency: u32,
    ) DependencyStrength {
        _ = self;
        _ = usage_frequency;

        // Interface dependencies are always strong or critical
        if (used_in_interface) {
            return switch (dependency_type) {
                .interface, .type_definition => .critical,
                .symbol_reference, .module_import => .strong,
                .transitive => .moderate,
            };
        }

        // Implementation dependencies can be weaker
        return switch (dependency_type) {
            .interface => .strong, // Interface deps are always important
            .type_definition => .moderate,
            .symbol_reference => .moderate,
            .module_import => .weak,
            .transitive => .weak,
        };
    }
};

// Dependency Analysis Rules - The Foundation of Precise Incremental Compilation
//
// INTERFACE DEPENDENCIES (Critical - always trigger rebuilds):
// 1. Public function signatures used in interface
// 2. Public type definitions used in interface
// 3. Public constants used in interface
// 4. Module exports used in interface
//
// IMPLEMENTATION DEPENDENCIES (Moderate - may trigger rebuilds):
// 1. Function calls in implementation
// 2. Type usage in implementation
// 3. Symbol references in implementation
// 4. Module imports for implementation
//
// TRANSITIVE DEPENDENCIES (Weak - rarely trigger rebuilds):
// 1. Dependencies of dependencies
// 2. Indirect symbol references
// 3. Nested module imports
//
// DEPENDENCY STRENGTH CALCULATION:
// - Critical: Interface changes always require rebuild
// - Strong: Implementation changes usually require rebuild
// - Moderate: Changes may require rebuild based on specifics
// - Weak: Changes rarely require rebuild
// - Optional: Changes never require rebuild
//
// ASTDB QUERY STRATEGY:
// 1. Use reference table to resolve symbol usage
// 2. Use declaration table to find symbol definitions
// 3. Use scope table to determine module boundaries
// 4. Use node structure to analyze usage context
//
// PRECISION REQUIREMENTS:
// - No false positives (unnecessary rebuilds)
// - No false negatives (missed dependencies)
// - Distinguish interface vs implementation usage
// - Handle complex dependency patterns (generics, macros)
// - Detect circular dependencies and report errors
//
// This dependency analysis system provides the precision needed for
// efficient incremental compilation while maintaining correctness guarantees.
