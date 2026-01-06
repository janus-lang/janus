// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

const std = @import("std");
const astdb = @import("astdb.zig");
const semantic = @import("semantic.zig");

// Janus Multiple Dispatch System - The Power Engine
//
// Multiple dispatch is the power that makes Janus distinct. Unlike single dispatch
// (method calls on objects), multiple dispatch selects functions based on the
// runtime types of ALL arguments, enabling powerful polymorphism and extensibility.
//
// Core Principles:
// 1. Signature-based function grouping: Functions with the same name form a multimethod
// 2. Specificity-based resolution: Most specific match wins at runtime
// 3. Ambiguity detection: Compile-time error for ambiguous calls
// 4. Static dispatch optimization: Sealed types enable compile-time resolution
// 5. Compressed dispatch tables: Efficient runtime dispatch for open types

pub const DispatchError = error{
    AmbiguousCall,
    NoMatchingMethod,
    InvalidSignature,
    CircularSpecificity,
    OutOfMemory,
};

// A multimethod is a collection of functions with the same name but different signatures
pub const Multimethod = struct {
    name: []const u8,
    methods: std.ArrayList(Method),
    dispatch_table: ?DispatchTable,
    is_sealed: bool, // Can we do static dispatch?

    allocator: std.mem.Allocator,

    pub fn init(name: []const u8, allocator: std.mem.Allocator) Multimethod {
        return Multimethod{
            .name = name,
            .methods = std.ArrayList(Method).init(allocator),
            .dispatch_table = null,
            .is_sealed = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Multimethod) void {
        for (self.methods.items) |*method| {
            method.deinit();
        }
        self.methods.deinit();

        if (self.dispatch_table) |*table| {
            table.deinit();
        }
    }

    // Add a method to this multimethod
    pub fn addMethod(self: *Multimethod, method: Method) !void {
        // Check for exact signature duplicates
        for (self.methods.items) |existing| {
            if (signaturesEqual(method.signature, existing.signature)) {
                return DispatchError.InvalidSignature;
            }
        }

        try self.methods.append(method);

        // Invalidate dispatch table - will be rebuilt on next resolution
        if (self.dispatch_table) |*table| {
            table.deinit();
            self.dispatch_table = null;
        }
    }

    // Resolve a call to this multimethod
    pub fn resolve(self: *Multimethod, call_signature: Signature) !?*Method {
        // Build dispatch table if needed
        if (self.dispatch_table == null) {
            self.dispatch_table = try self.buildDispatchTable();
        }

        return self.dispatch_table.?.resolve(call_signature);
    }

    // Check if this multimethod can be statically dispatched
    pub fn canStaticDispatch(self: *const Multimethod, call_signature: Signature) bool {
        if (!self.is_sealed) return false;

        // For sealed types, we can determine the exact method at compile time
        var best_match: ?*const Method = null;
        var match_count: u32 = 0;

        for (self.methods.items) |*method| {
            if (signatureMatches(call_signature, method.signature)) {
                if (best_match == null or isMoreSpecific(method.signature, best_match.?.signature, call_signature)) {
                    best_match = method;
                    match_count = 1;
                } else if (!isMoreSpecific(best_match.?.signature, method.signature, call_signature)) {
                    match_count += 1; // Ambiguous
                }
            }
        }

        return match_count == 1;
    }

    // Build the dispatch table for runtime resolution
    fn buildDispatchTable(self: *Multimethod) !DispatchTable {
        var table = DispatchTable.init(self.allocator);

        // Sort methods by specificity for efficient lookup
        var sorted_methods = try self.allocator.dupe(Method, self.methods.items);
        defer self.allocator.free(sorted_methods);

        std.sort.insertion(Method, sorted_methods, {}, compareMethodSpecificity);

        // Build dispatch entries
        for (sorted_methods) |method| {
            try table.addEntry(method.signature, &method);
        }

        return table;
    }
};

// A single method within a multimethod
pub const Method = struct {
    signature: Signature,
    function_node: astdb.NodeId,
    specificity_score: u32,

    pub fn init(signature: Signature, function_node: astdb.NodeId) Method {
        return Method{
            .signature = signature,
            .function_node = function_node,
            .specificity_score = calculateSpecificity(signature),
        };
    }

    pub fn deinit(self: *Method) void {
        self.signature.deinit();
    }
};

// Function signature for dispatch resolution
pub const Signature = struct {
    parameter_types: []TypeInfo,
    return_type: TypeInfo,

    allocator: std.mem.Allocator,

    pub fn init(parameter_types: []TypeInfo, return_type: TypeInfo, allocator: std.mem.Allocator) !Signature {
        return Signature{
            .parameter_types = try allocator.dupe(TypeInfo, parameter_types),
            .return_type = return_type,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Signature) void {
        for (self.parameter_types) |*param_type| {
            param_type.deinit();
        }
        self.allocator.free(self.parameter_types);
        self.return_type.deinit();
    }
};

// Type information for dispatch
pub const TypeInfo = struct {
    name: []const u8,
    kind: TypeKind,
    is_sealed: bool,
    specificity: u32,

    allocator: std.mem.Allocator,

    pub const TypeKind = enum {
        primitive,
        struct_type,
        union_type,
        interface_type,
        generic_type,
    };

    pub fn init(name: []const u8, kind: TypeKind, is_sealed: bool, allocator: std.mem.Allocator) !TypeInfo {
        return TypeInfo{
            .name = try allocator.dupe(u8, name),
            .kind = kind,
            .is_sealed = is_sealed,
            .specificity = calculateTypeSpecificity(kind, is_sealed),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TypeInfo) void {
        self.allocator.free(self.name);
    }
};

// Runtime dispatch table for efficient method resolution
pub const DispatchTable = struct {
    entries: std.ArrayList(DispatchEntry),
    type_cache: std.StringHashMap(*Method),

    allocator: std.mem.Allocator,

    const DispatchEntry = struct {
        signature: Signature,
        method: *Method,
    };

    pub fn init(allocator: std.mem.Allocator) DispatchTable {
        return DispatchTable{
            .entries = std.ArrayList(DispatchEntry).init(allocator),
            .type_cache = std.StringHashMap(*Method).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DispatchTable) void {
        for (self.entries.items) |*entry| {
            entry.signature.deinit();
        }
        self.entries.deinit();
        self.type_cache.deinit();
    }

    pub fn addEntry(self: *DispatchTable, signature: Signature, method: *Method) !void {
        try self.entries.append(DispatchEntry{
            .signature = signature,
            .method = method,
        });

        // Clear cache when adding new entries
        self.type_cache.clearAndFree();
    }

    pub fn resolve(self: *DispatchTable, call_signature: Signature) !?*Method {
        // Create cache key from call signature
        const cache_key = try self.createCacheKey(call_signature);
        defer self.allocator.free(cache_key);

        // Check cache first
        if (self.type_cache.get(cache_key)) |cached_method| {
            return cached_method;
        }

        // Find best matching method
        var best_match: ?*Method = null;
        var best_specificity: u32 = 0;
        var ambiguous_count: u32 = 0;

        for (self.entries.items) |entry| {
            if (signatureMatches(call_signature, entry.signature)) {
                const specificity = entry.method.specificity_score;

                if (best_match == null or specificity > best_specificity) {
                    best_match = entry.method;
                    best_specificity = specificity;
                    ambiguous_count = 1;
                } else if (specificity == best_specificity) {
                    ambiguous_count += 1;
                }
            }
        }

        if (ambiguous_count > 1) {
            return DispatchError.AmbiguousCall;
        }

        // Cache the result
        if (best_match) |method| {
            try self.type_cache.put(try self.allocator.dupe(u8, cache_key), method);
        }

        return best_match;
    }

    fn createCacheKey(self: *DispatchTable, signature: Signature) ![]u8 {
        var key = std.ArrayList(u8).init(self.allocator);
        defer key.deinit();

        for (signature.parameter_types, 0..) |param_type, i| {
            if (i > 0) try key.append(',');
            try key.appendSlice(param_type.name);
        }

        return key.toOwnedSlice();
    }
};

// Multiple dispatch registry - manages all multimethods in the system
pub const DispatchRegistry = struct {
    multimethods: std.StringHashMap(Multimethod),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DispatchRegistry {
        return DispatchRegistry{
            .multimethods = std.StringHashMap(Multimethod).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DispatchRegistry) void {
        var iterator = self.multimethods.iterator();
        while (iterator.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.multimethods.deinit();
    }

    // Register a function as part of a multimethod
    pub fn registerFunction(self: *DispatchRegistry, function_node: astdb.NodeId) !void {
        const function_name = function_node.name;

        // Create signature from function declaration
        const signature = try self.createSignatureFromFunction(function_node);
        const method = Method.init(signature, function_node);

        // Get or create multimethod
        var multimethod = self.multimethods.getPtr(function_name);
        if (multimethod == null) {
            var new_multimethod = Multimethod.init(function_name, self.allocator);
            try self.multimethods.put(try self.allocator.dupe(u8, function_name), new_multimethod);
            multimethod = self.multimethods.getPtr(function_name);
        }

        // Add method to multimethod
        try multimethod.?.addMethod(method);
    }

    // Resolve a function call to the best matching method
    pub fn resolveCall(self: *DispatchRegistry, function_name: []const u8, call_signature: Signature) !?*Method {
        const multimethod = self.multimethods.getPtr(function_name) orelse return null;
        return multimethod.resolve(call_signature);
    }

    // Check if a call can be statically dispatched
    pub fn canStaticDispatch(self: *const DispatchRegistry, function_name: []const u8, call_signature: Signature) bool {
        const multimethod = self.multimethods.get(function_name) orelse return false;
        return multimethod.canStaticDispatch(call_signature);
    }

    // Mark a multimethod as sealed (enables static dispatch optimization)
    pub fn sealMultimethod(self: *DispatchRegistry, function_name: []const u8) !void {
        const multimethod = self.multimethods.getPtr(function_name) orelse return DispatchError.NoMatchingMethod;
        multimethod.is_sealed = true;
    }

    // Create signature from function declaration
    fn createSignatureFromFunction(self: *DispatchRegistry, function_node: astdb.NodeId) !Signature {
        var param_types = std.ArrayList(TypeInfo).init(self.allocator);
        defer param_types.deinit();

        for (function_node.parameters) |param| {
            const type_info = try self.createTypeInfoFromAst(param.type_node);
            try param_types.append(type_info);
        }

        const return_type = try self.createTypeInfoFromAst(function_node.return_type);

        return Signature.init(try param_types.toOwnedSlice(), return_type, self.allocator);
    }

    // Create type info from AST type node
    fn createTypeInfoFromAst(self: *DispatchRegistry, type_node: astdb.NodeId) !TypeInfo {
        // Simplified type info creation - in a full implementation this would
        // integrate with the complete type system and query ASTDB for node details
        _ = self;
        _ = type_node;

        // TODO: Query ASTDB to get actual type information
        // For now, return a placeholder type info
        return TypeInfo{
            .name = "unknown",
            .kind = .primitive,
            .specificity = 1,
        };
    }
};

// ===== SPECIFICITY AND MATCHING ALGORITHMS =====

// Check if two signatures are exactly equal
fn signaturesEqual(sig1: Signature, sig2: Signature) bool {
    if (sig1.parameter_types.len != sig2.parameter_types.len) return false;

    for (sig1.parameter_types, sig2.parameter_types) |type1, type2| {
        if (!std.mem.eql(u8, type1.name, type2.name)) return false;
    }

    return std.mem.eql(u8, sig1.return_type.name, sig2.return_type.name);
}

// Check if a call signature matches a method signature
fn signatureMatches(call_sig: Signature, method_sig: Signature) bool {
    if (call_sig.parameter_types.len != method_sig.parameter_types.len) return false;

    for (call_sig.parameter_types, method_sig.parameter_types) |call_type, method_type| {
        if (!typeMatches(call_type, method_type)) return false;
    }

    return true;
}

// Check if a call type matches a method parameter type
fn typeMatches(call_type: TypeInfo, method_type: TypeInfo) bool {
    // Exact match
    if (std.mem.eql(u8, call_type.name, method_type.name)) return true;

    // Subtype relationship (simplified - would integrate with full type system)
    return isSubtype(call_type, method_type);
}

// Check if type1 is a subtype of type2 (simplified)
fn isSubtype(type1: TypeInfo, type2: TypeInfo) bool {
    // Simplified subtype checking - in a full implementation this would
    // integrate with the complete type system and handle inheritance,
    // interfaces, structural typing, etc.

    // For now, just handle some basic cases
    if (std.mem.eql(u8, type1.name, "i32") and std.mem.eql(u8, type2.name, "i64")) return true;
    if (std.mem.eql(u8, type1.name, "f32") and std.mem.eql(u8, type2.name, "f64")) return true;

    return false;
}

// Check if signature1 is more specific than signature2 for the given call
fn isMoreSpecific(sig1: Signature, sig2: Signature, call_sig: Signature) bool {
    var sig1_score: u32 = 0;
    var sig2_score: u32 = 0;

    for (sig1.parameter_types, sig2.parameter_types, call_sig.parameter_types) |type1, type2, call_type| {
        sig1_score += calculateTypeDistance(call_type, type1);
        sig2_score += calculateTypeDistance(call_type, type2);
    }

    return sig1_score < sig2_score; // Lower distance = more specific
}

// Calculate the "distance" between two types for specificity ordering
fn calculateTypeDistance(from_type: TypeInfo, to_type: TypeInfo) u32 {
    if (std.mem.eql(u8, from_type.name, to_type.name)) return 0; // Exact match
    if (isSubtype(from_type, to_type)) return 1; // Direct subtype
    return 100; // No relationship
}

// Calculate overall specificity score for a signature
fn calculateSpecificity(signature: Signature) u32 {
    var score: u32 = 0;

    for (signature.parameter_types) |param_type| {
        score += param_type.specificity;
    }

    return score;
}

// Calculate specificity score for a type
fn calculateTypeSpecificity(kind: TypeInfo.TypeKind, is_sealed: bool) u32 {
    var score: u32 = switch (kind) {
        .primitive => 100,
        .struct_type => 80,
        .union_type => 60,
        .interface_type => 40,
        .generic_type => 20,
    };

    if (is_sealed) score += 10; // Sealed types are more specific

    return score;
}

// Compare methods by specificity for sorting
fn compareMethodSpecificity(context: void, method1: Method, method2: Method) bool {
    _ = context;
    return method1.specificity_score > method2.specificity_score;
}

// ===== PUBLIC API =====

// Create a new dispatch registry
pub fn createDispatchRegistry(allocator: std.mem.Allocator) DispatchRegistry {
    return DispatchRegistry.init(allocator);
}

// Analyze ambiguity in a multimethod
pub fn analyzeAmbiguity(multimethod: *const Multimethod, allocator: std.mem.Allocator) ![]AmbiguityReport {
    var reports = std.ArrayList(AmbiguityReport).init(allocator);

    // Check all pairs of methods for potential ambiguity
    for (multimethod.methods.items, 0..) |method1, i| {
        for (multimethod.methods.items[i + 1 ..]) |method2| {
            if (methodsAreAmbiguous(method1, method2)) {
                try reports.append(AmbiguityReport{
                    .method1 = method1,
                    .method2 = method2,
                    .reason = "Signatures overlap without clear specificity ordering",
                });
            }
        }
    }

    return reports.toOwnedSlice();
}

pub const AmbiguityReport = struct {
    method1: Method,
    method2: Method,
    reason: []const u8,
};

fn methodsAreAmbiguous(method1: Method, method2: Method) bool {
    // Two methods are ambiguous if there exists a call signature that could
    // match both methods with equal specificity

    // Simplified check - in a full implementation this would be more sophisticated
    if (method1.signature.parameter_types.len != method2.signature.parameter_types.len) {
        return false;
    }

    // Check if signatures have overlapping parameter types
    for (method1.signature.parameter_types, method2.signature.parameter_types) |type1, type2| {
        if (!typesOverlap(type1, type2)) {
            return false;
        }
    }

    // If we get here, the methods might be ambiguous
    return method1.specificity_score == method2.specificity_score;
}

fn typesOverlap(type1: TypeInfo, type2: TypeInfo) bool {
    // Types overlap if there exists a value that could match both types
    return std.mem.eql(u8, type1.name, type2.name) or
        isSubtype(type1, type2) or
        isSubtype(type2, type1);
}
