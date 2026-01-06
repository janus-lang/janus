// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

//! Janus Type System with canonical hashing and O(1) performance
//!
//! This is the canonical Type System implementation with O(1) type deduplication
//! using canonical hashing. The old O(N²) brute-force implementation has been
//! DEMOLISHED.
//!
//! PERFORMANCE VICTORY: All type operations are now O(1) using HashMap lookups

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.array_list.Managed;

const TypeCanonicalHasher = @import("type_canonical_hash.zig").TypeCanonicalHasher;
const computeCanonicalHash = @import("type_canonical_hash.zig").computeCanonicalHash;

// Forward declarations for validation engine integration
const astdb = @import("astdb");
const NodeId = astdb.NodeId;
const SymbolTable = @import("symbol_table.zig").SymbolTable;

/// Unique identifier for types in the system
pub const TypeId = struct {
    id: u32,

    pub fn eql(self: TypeId, other: TypeId) bool {
        return self.id == other.id;
    }

    pub fn format(self: TypeId, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print("TypeId({})", .{self.id});
    }
};

/// Primitive types supported by Janus
pub const PrimitiveType = enum {
    i32,
    i64,
    f32,
    f64,
    bool,
    string,
    void,
    never,

    pub fn getSize(self: PrimitiveType) u32 {
        return switch (self) {
            .i32 => 4,
            .i64 => 8,
            .f32 => 4,
            .f64 => 8,
            .bool => 1,
            .string => 16, // pointer + length
            .void => 0,
            .never => 0,
        };
    }

    pub fn getAlignment(self: PrimitiveType) u32 {
        return switch (self) {
            .i32 => 4,
            .i64 => 8,
            .f32 => 4,
            .f64 => 8,
            .bool => 1,
            .string => 8,
            .void => 1,
            .never => 1,
        };
    }
};

/// Function calling conventions
pub const CallingConvention = enum {
    janus_call,
    c_call,
    fast_call,
};

/// Pointer type information
pub const PointerInfo = struct {
    pointee_type: TypeId,
    is_mutable: bool,
};

/// Array type information
pub const ArrayInfo = struct {
    element_type: TypeId,
    size: u32,
};

/// Slice type information
pub const SliceInfo = struct {
    element_type: TypeId,
    is_mutable: bool,
};

/// Range type information
pub const RangeInfo = struct {
    element_type: TypeId,
    is_inclusive: bool,  // true for .., false for ..<
};

/// Function type information
pub const FunctionInfo = struct {
    parameter_types: []TypeId,
    return_type: TypeId,
    calling_convention: CallingConvention,
};

/// Structure field information
pub const StructField = struct {
    name: []const u8,
    type_id: TypeId,
    offset: u32,
};

/// Structure type information
pub const StructInfo = struct {
    name: []const u8,
    fields: []StructField,
};

/// Enumeration variant information
pub const EnumVariant = struct {
    name: []const u8,
    value: i64,
};

/// Enumeration type information
pub const EnumInfo = struct {
    name: []const u8,
    underlying_type: TypeId,
    variants: []EnumVariant,
};

/// Optional type information
pub const OptionalInfo = struct {
    inner_type: TypeId,
};

/// Error union type information
pub const ErrorUnionInfo = struct {
    error_type: TypeId,
    payload_type: TypeId,
};

/// Memory spaces for NPU-native tensors (profile-gated at frontend)
pub const MemSpace = enum { sram, dram, vram, host };

/// Tensor type information (NPU-native)
pub const TensorInfo = struct {
    element_type: TypeId,
    rank: u8,
    dims: []u32, // owned by type system
    memspace: ?MemSpace,
};

/// Allocator kind information
pub const AllocatorInfo = struct {
    allocator_kind: AllocatorKind,
};

/// Allocator kinds for context-bound types
pub const AllocatorKind = enum {
    heap,
    arena,
    region,
    tls,
    custom,
};

/// Context-bound Type information
pub const ContextBoundInfo = struct {
    /// The underlying type (e.g., Buffer, List, Map)
    inner_type: TypeId,
    /// The allocator bound to this type
    allocator_type: TypeId,
    /// The specific allocator kind used
    allocator_kind: AllocatorKind,
};

/// Generic type parameter information
pub const GenericParameter = struct {
    name: []const u8,
    constraint: ?TypeId,
};

/// Generic type information
pub const GenericInfo = struct {
    name: []const u8,
    type_parameters: []GenericParameter,
};

/// Type kind enumeration
pub const TypeKind = union(enum) {
    primitive: PrimitiveType,
    pointer: PointerInfo,
    array: ArrayInfo,
    slice: SliceInfo,
    range: RangeInfo,
    function: FunctionInfo,
    structure: StructInfo,
    enumeration: EnumInfo,
    optional: OptionalInfo,
    error_union: ErrorUnionInfo,
    generic: GenericInfo,
    tensor: TensorInfo,
    allocator: AllocatorInfo,
    context_bound: ContextBoundInfo,
    inference_var: u32,
};

/// Complete type information
pub const TypeInfo = struct {
    kind: TypeKind,
    size: u32,
    alignment: u32,
};

/// Type System with O(1) Performance Guarantees
pub const TypeSystem = struct {
    allocator: Allocator,
    types: ArrayList(TypeInfo),
    canonical_hasher: TypeCanonicalHasher,
    next_type_id: u32,

    // Primitive type cache for instant access
    primitive_types: [8]TypeId, // i32, i64, f32, f64, bool, string, void, never

    pub fn init(allocator: Allocator) !TypeSystem {
        var system = TypeSystem{
            .allocator = allocator,
            .types = ArrayList(TypeInfo).init(allocator),
            .canonical_hasher = TypeCanonicalHasher.init(allocator),
            .next_type_id = 0,
            .primitive_types = undefined,
        };

        // Pre-register primitive types for O(1) access
        try system.initializePrimitiveTypes();

        return system;
    }

    // =========================
    // Shape Algebra (Helpers)
    // =========================

    /// Check exact shape equality (same rank and identical dims)
    pub fn shapesEqual(self: *TypeSystem, a: []const u32, b: []const u32) bool {
        _ = self;
        if (a.len != b.len) return false;
        var i: usize = 0;
        while (i < a.len) : (i += 1) if (a[i] != b[i]) return false;
        return true;
    }

    /// Check NumPy-style broadcast legality between shapes a and b
    /// Rules: align from the right; dims are compatible if equal or either is 1
    pub fn isBroadcastable(self: *TypeSystem, a: []const u32, b: []const u32) bool {
        _ = self; // Parameter kept for API consistency
        var ia: isize = @intCast(a.len);
        var ib: isize = @intCast(b.len);
        while (ia > 0 or ib > 0) {
            const da: u32 = if (ia > 0) a[@intCast(ia - 1)] else 1;
            const db: u32 = if (ib > 0) b[@intCast(ib - 1)] else 1;
            if (!(da == db or da == 1 or db == 1)) return false;
            ia -= 1;
            ib -= 1;
        }
        return true;
    }

    /// Compute broadcasted shape for a and b (right-aligned rules). The returned
    /// slice is allocated from `allocator` and must be freed by the caller.
    pub fn computeBroadcastShape(self: *TypeSystem, a: []const u32, b: []const u32, allocator: Allocator) ![]u32 {
        // Use self parameter to validate broadcast compatibility
        if (!self.isBroadcastable(a, b)) return error.IncompatibleShapes;
        const out_len: usize = if (a.len > b.len) a.len else b.len;
        const out = try allocator.alloc(u32, out_len);
        var ia: isize = @intCast(a.len);
        var ib: isize = @intCast(b.len);
        var io: isize = @intCast(out_len);
        while (io > 0) : (io -= 1) {
            const da: u32 = if (ia > 0) a[@intCast(ia - 1)] else 1;
            const db: u32 = if (ib > 0) b[@intCast(ib - 1)] else 1;
            out[@intCast(io - 1)] = if (da == 1) db else da;
            ia -= 1;
            ib -= 1;
        }
        return out;
    }

    /// Check divisibility of shape by tile on a per-dimension basis
    pub fn isShapeDivisibleBy(self: *TypeSystem, shape: []const u32, tile: []const u32) bool {
        _ = self; // Parameter kept for API consistency
        if (shape.len != tile.len) return false;
        var i: usize = 0;
        while (i < shape.len) : (i += 1) {
            const t = tile[i];
            if (t == 0) return false;
            if (shape[i] % t != 0) return false;
        }
        return true;
    }

    pub fn isAssignable(self: *TypeSystem, target: TypeId, source: TypeId) bool {
        // Simple equality check for now
        // TODO: Implement proper subtyping (e.g. never -> any, any -> void, etc.)
        _ = self;
        return target.eql(source);
    }

    pub fn deinit(self: *TypeSystem) void {
        // Clean up allocated parameter types for function types
        for (self.types.items) |type_info| {
            switch (type_info.kind) {
                .function => |func| {
                    self.allocator.free(func.parameter_types);
                },
                .structure => |struct_info| {
                    self.allocator.free(struct_info.name);
                    self.allocator.free(struct_info.fields);
                },
                .enumeration => |enum_info| {
                    self.allocator.free(enum_info.variants);
                },
                .tensor => |t| {
                    self.allocator.free(t.dims);
                },
                .allocator => |_| {
                    // No cleanup needed
                },
                .context_bound => |ctx_info| {
                    _ = ctx_info; // No cleanup needed
                },
                else => {},
            }
        }
        self.types.deinit();
        self.canonical_hasher.deinit();
    }

    /// Initialize primitive types with O(1) access
    fn initializePrimitiveTypes(self: *TypeSystem) !void {
        const primitives = [_]PrimitiveType{ .i32, .i64, .f32, .f64, .bool, .string, .void, .never };

        for (primitives, 0..) |primitive, i| {
            const type_info = TypeInfo{
                .kind = .{ .primitive = primitive },
                .size = primitive.getSize(),
                .alignment = primitive.getAlignment(),
            };

            const type_id = try self.registerTypeInternal(type_info);
            self.primitive_types[i] = type_id;
        }
    }

    /// Get primitive type with O(1) access - NO MORE LINEAR SEARCHES!
    pub fn getPrimitiveType(self: *TypeSystem, primitive: PrimitiveType) TypeId {
        const index: usize = switch (primitive) {
            .i32 => 0,
            .i64 => 1,
            .f32 => 2,
            .f64 => 3,
            .bool => 4,
            .string => 5,
            .void => 6,
            .never => 7,
        };
        return self.primitive_types[index];
    }

    /// Create or find existing function type - O(1) PERFORMANCE!
    pub fn createFunctionType(
        self: *TypeSystem,
        parameter_types: []const TypeId,
        return_type: TypeId,
        calling_convention: CallingConvention,
    ) !TypeId {
        // Always allocate parameter types first to ensure consistent hashing
        var param_list = ArrayList(TypeId).init(self.allocator);
        defer param_list.deinit();
        try param_list.appendSlice(parameter_types);
        const owned_params = try param_list.toOwnedSlice();

        const type_info = TypeInfo{
            .kind = .{
                .function = .{
                    .parameter_types = owned_params,
                    .return_type = return_type,
                    .calling_convention = calling_convention,
                },
            },
            .size = 8, // Function pointer size
            .alignment = 8,
        };

        // O(1) LOOKUP - Check if we already have this type
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            // Clean up allocated parameter types since we found existing
            self.allocator.free(owned_params);
            return existing_id;
        }

        // Register new type with O(1) hash insertion
        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing pointer type - O(1) PERFORMANCE!
    pub fn createPointerType(self: *TypeSystem, pointee_type: TypeId, is_mutable: bool) !TypeId {
        const type_info = TypeInfo{
            .kind = .{
                .pointer = .{
                    .pointee_type = pointee_type,
                    .is_mutable = is_mutable,
                },
            },
            .size = 8, // Pointer size
            .alignment = 8,
        };

        // O(1) LOOKUP - PERFORMANCE VICTORY!
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing array type - O(1) PERFORMANCE!
    pub fn createArrayType(self: *TypeSystem, element_type: TypeId, size: u32) !TypeId {
        const element_info = self.getTypeInfo(element_type);

        const type_info = TypeInfo{
            .kind = .{
                .array = .{
                    .element_type = element_type,
                    .size = size,
                },
            },
            .size = element_info.size * size,
            .alignment = element_info.alignment,
        };

        // O(1) LOOKUP - NO MORE LINEAR SEARCH HERESY!
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing slice type - O(1) PERFORMANCE!
    pub fn createSliceType(self: *TypeSystem, element_type: TypeId, is_mutable: bool) !TypeId {
        const type_info = TypeInfo{
            .kind = .{
                .slice = .{
                    .element_type = element_type,
                    .is_mutable = is_mutable,
                },
            },
            .size = 16, // pointer + length
            .alignment = 8,
        };

        // O(1) LOOKUP - CANONICAL HASHING VICTORY!
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing range type - O(1) PERFORMANCE!
    pub fn createRangeType(self: *TypeSystem, element_type: TypeId, is_inclusive: bool) !TypeId {
        const type_info = TypeInfo{
            .kind = .{
                .range = .{
                    .element_type = element_type,
                    .is_inclusive = is_inclusive,
                },
            },
            .size = 16, // start + end (2 elements)
            .alignment = 8,
        };

        // O(1) LOOKUP - CANONICAL HASHING VICTORY!
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing inference variable type - O(1) PERFORMANCE!
    pub fn createInferenceType(self: *TypeSystem, id: u32) !TypeId {
        const type_info = TypeInfo{
            .kind = .{ .inference_var = id },
            .size = 0,
            .alignment = 0,
        };
        
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }
        
        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing tensor type (element type, dims, memspace)
    pub fn createTensorType(self: *TypeSystem, element_type: TypeId, dims: []const u32, memspace: ?MemSpace) !TypeId {
        // Own a copy of dims for stable hashing and lifetime
        const dims_buf = try self.allocator.alloc(u32, dims.len);
        @memcpy(dims_buf, dims);

        // Compute total size and alignment based on element type
        const elem_info = self.getTypeInfo(element_type);
        var total: u64 = 1;
        for (dims) |d| total *= @as(u64, d);
        const size_u64: u64 = total * elem_info.size;
        const clamped_size: u32 = @intCast(@min(size_u64, @as(u64, std.math.maxInt(u32))));

        const tensor_info = TensorInfo{
            .element_type = element_type,
            .rank = @intCast(dims.len),
            .dims = dims_buf,
            .memspace = memspace,
        };
        const type_info = TypeInfo{
            .kind = .{ .tensor = tensor_info },
            .size = clamped_size,
            .alignment = elem_info.alignment,
        };

        // Canonical lookup; if exists, free and return existing
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            self.allocator.free(dims_buf);
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create structure type
    pub fn createStructType(self: *TypeSystem, name: []const u8, fields: []const StructField) !TypeId {
        // Calculate struct size and alignment
        var total_size: u32 = 0;
        var max_alignment: u32 = 1;

        for (fields) |field| {
            const field_info = self.getTypeInfo(field.type_id);
            max_alignment = @max(max_alignment, field_info.alignment);
            total_size = std.mem.alignForward(u32, total_size, field_info.alignment);
            total_size += field_info.size;
        }

        // Align final size to max alignment
        total_size = std.mem.alignForward(u32, total_size, max_alignment);

        const owned_name = try self.allocator.dupe(u8, name);
        const owned_fields = try self.allocator.dupe(StructField, fields);

        const type_info = TypeInfo{
            .kind = .{
                .structure = .{
                    .name = owned_name,
                    .fields = owned_fields,
                },
            },
            .size = total_size,
            .alignment = max_alignment,
        };

        // O(1) LOOKUP
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            // Clean up allocated memory since we found existing
            self.allocator.free(owned_name);
            self.allocator.free(owned_fields);
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing allocator type - O(1) PERFORMANCE!
    pub fn createAllocatorType(self: *TypeSystem, allocator_kind: AllocatorKind) !TypeId {
        const type_info = TypeInfo{
            .kind = .{
                .allocator = .{
                    .allocator_kind = allocator_kind,
                },
            },
            .size = 16, // Allocator size (id + kind + signature)
            .alignment = 8,
        };

        // O(1) LOOKUP
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create or find existing context-bound type - O(1) PERFORMANCE!
    pub fn createContextBoundType(
        self: *TypeSystem,
        inner_type: TypeId,
        allocator_type: TypeId,
        allocator_kind: AllocatorKind,
    ) !TypeId {
        const type_info = TypeInfo{
            .kind = .{
                .context_bound = .{
                    .inner_type = inner_type,
                    .allocator_type = allocator_type,
                    .allocator_kind = allocator_kind,
                },
            },
            // Size is same as inner type + allocator storage
            .size = self.getTypeInfo(inner_type).size,
            .alignment = self.getTypeInfo(inner_type).alignment,
        };

        // O(1) LOOKUP
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Create optional type
    pub fn createOptionalType(self: *TypeSystem, inner_type: TypeId) !TypeId {
        const inner_info = self.getTypeInfo(inner_type);

        const type_info = TypeInfo{
            .kind = .{
                .optional = .{
                    .inner_type = inner_type,
                },
            },
            .size = inner_info.size + 1, // Add discriminant byte
            .alignment = inner_info.alignment,
        };

        // O(1) LOOKUP
        if (self.canonical_hasher.findExistingType(&type_info)) |existing_id| {
            return existing_id;
        }

        return self.registerTypeInternal(type_info);
    }

    /// Register new type with canonical hash - O(1) operation
    fn registerTypeInternal(self: *TypeSystem, type_info: TypeInfo) !TypeId {
        const type_id = TypeId{ .id = self.next_type_id };
        self.next_type_id += 1;

        try self.types.append(type_info);

        // Register with canonical hasher using the stable reference in the array
        const stable_type_info = &self.types.items[self.types.items.len - 1];
        try self.canonical_hasher.registerType(stable_type_info, type_id);

        return type_id;
    }

    /// Get type information - O(1) array access
    pub fn getTypeInfo(self: *TypeSystem, type_id: TypeId) *const TypeInfo {
        return &self.types.items[type_id.id];
    }

    /// Check type compatibility with optimized lookups
    pub fn areTypesCompatible(self: *TypeSystem, source: TypeId, target: TypeId) bool {
        if (source.id == target.id) return true;

        const source_info = self.getTypeInfo(source);
        const target_info = self.getTypeInfo(target);

        return switch (source_info.kind) {
            .primitive => |source_prim| switch (target_info.kind) {
                .primitive => |target_prim| self.arePrimitivesCompatible(source_prim, target_prim),
                else => false,
            },
            .tensor => |src_t| switch (target_info.kind) {
                .tensor => |tgt_t| self.areTensorsCompatible(src_t, tgt_t),
                else => false,
            },
            .pointer => |source_ptr| switch (target_info.kind) {
                .pointer => |target_ptr| {
                    return self.areTypesCompatible(source_ptr.pointee_type, target_ptr.pointee_type) and
                        (!target_ptr.is_mutable or source_ptr.is_mutable);
                },
                else => false,
            },
            .array => |source_arr| switch (target_info.kind) {
                .array => |target_arr| {
                    return source_arr.size == target_arr.size and
                        self.areTypesCompatible(source_arr.element_type, target_arr.element_type);
                },
                .slice => |target_slice| {
                    // Array to slice implicit conversion requires compatible element types.
                    // Note: This logic assumes that the slice can view the array's memory.
                    return self.areTypesCompatible(source_arr.element_type, target_slice.element_type);
                },
                else => false,
            },
            else => false,
        };
    }

    /// Primitive type compatibility rules
    fn arePrimitivesCompatible(self: *TypeSystem, source: PrimitiveType, target: PrimitiveType) bool {
        _ = self;

        // Exact match
        if (source == target) return true;

        // Numeric conversions
        return switch (source) {
            .i32 => target == .i64 or target == .f32 or target == .f64,
            .i64 => target == .f64,
            .f32 => target == .f64,
            else => false,
        };
    }

    /// Tensor type compatibility rules (strict: shapes and memspace must match; elements compatible)
    fn areTensorsCompatible(self: *TypeSystem, source: TensorInfo, target: TensorInfo) bool {
        if (source.rank != target.rank) return false;
        if (source.memspace != target.memspace) return false;
        // Compare dims
        if (source.dims.len != target.dims.len) return false;
        var i: usize = 0;
        while (i < source.dims.len) : (i += 1) {
            if (source.dims[i] != target.dims[i]) return false;
        }
        // Element type compatibility (allow exact or widening numeric)
        return self.areTypesCompatible(source.element_type, target.element_type);
    }

    /// Get type size
    pub fn getTypeSize(self: *TypeSystem, type_id: TypeId) u32 {
        return self.getTypeInfo(type_id).size;
    }

    /// Get type alignment
    pub fn getTypeAlignment(self: *TypeSystem, type_id: TypeId) u32 {
        return self.getTypeInfo(type_id).alignment;
    }

    /// Check if type is primitive
    pub fn isPrimitive(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .primitive => true,
            else => false,
        };
    }

    /// Check if type is pointer
    pub fn isPointer(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .pointer => true,
            else => false,
        };
    }

    /// Check if type is function
    pub fn isFunction(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .function => true,
            else => false,
        };
    }

    /// Check if type is boolean - needed for when validation
    pub fn isBoolean(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .primitive => |prim| prim == .bool,
            else => false,
        };
    }

    /// Check if type is allocator
    pub fn isAllocator(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .allocator => true,
            else => false,
        };
    }

    /// Check if type is context-bound
    pub fn isContextBound(self: *TypeSystem, type_id: TypeId) bool {
        return switch (self.getTypeInfo(type_id).kind) {
            .context_bound => true,
            else => false,
        };
    }

    /// Get allocator kind from allocator type
    pub fn getAllocatorKind(self: *TypeSystem, type_id: TypeId) ?AllocatorKind {
        return switch (self.getTypeInfo(type_id).kind) {
            .allocator => |alloc_info| alloc_info.allocator_kind,
            .context_bound => |ctx_info| ctx_info.allocator_kind,
            else => null,
        };
    }

    /// Get inner type from context-bound type
    pub fn getContextBoundInnerType(self: *TypeSystem, type_id: TypeId) ?TypeId {
        return switch (self.getTypeInfo(type_id).kind) {
            .context_bound => |ctx_info| ctx_info.inner_type,
            else => null,
        };
    }

    /// Check if type is callable - needed for call validation
    pub fn isCallable(self: *TypeSystem, type_id: TypeId) bool {
        return self.isFunction(type_id);
    }

    /// Check if types are compatible - alias for validation engine
    pub fn areCompatible(self: *TypeSystem, source_type: u32, target_type: u32) bool {
        const source_id = TypeId{ .id = source_type };
        const target_id = TypeId{ .id = target_type };
        return self.areTypesCompatible(source_id, target_id);
    }

    /// Infer node type - integration point for validation engine
    pub fn inferNodeType(self: *TypeSystem, node_id: NodeId, astdb_instance: *astdb.ASTDBSystem, symbol_table: *SymbolTable) !u32 {
        _ = astdb_instance;
        _ = symbol_table;
        _ = node_id;

        // For now, return i32 as default - this will be expanded
        return @intFromEnum(self.getPrimitiveType(.i32));
    }
};

// Comprehensive test suite
test "type system O(1) performance" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    // Test primitive type access - should be O(1)
    const i32_type = system.getPrimitiveType(.i32);
    const f64_type = system.getPrimitiveType(.f64);

    try std.testing.expect(i32_type.id != f64_type.id);

    // Test function type deduplication - should be O(1)
    const param_types = [_]TypeId{i32_type};
    const func_type1 = try system.createFunctionType(&param_types, f64_type, .janus_call);
    const func_type2 = try system.createFunctionType(&param_types, f64_type, .janus_call);

    // Should return same type ID due to deduplication
    try std.testing.expect(func_type1.id == func_type2.id);
}

test "tensor type creation and compatibility" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    const f32_type = system.getPrimitiveType(.f32);
    const dims = [_]u32{ 128, 256 };
    const t1 = try system.createTensorType(f32_type, &dims, .sram);
    const t2 = try system.createTensorType(f32_type, &dims, .sram);
    try std.testing.expect(t1.id == t2.id); // canonicalization

    const dims_bad = [_]u32{ 256, 256 };
    const t3 = try system.createTensorType(f32_type, &dims_bad, .sram);
    try std.testing.expect(!system.areTypesCompatible(t1, t3));

    const t4 = try system.createTensorType(f32_type, &dims, .dram);
    try std.testing.expect(!system.areTypesCompatible(t1, t4));
}

test "shape algebra helpers" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    const s1 = [_]u32{ 8, 1, 32 };
    const s2 = [_]u32{ 1, 16, 32 };
    const s3 = [_]u32{ 8, 16, 32 };
    const s_bad = [_]u32{ 7, 16, 33 };

    try std.testing.expect(system.isBroadcastable(&s1, &s2));
    const out = try system.computeBroadcastShape(&s1, &s2, allocator);
    defer allocator.free(out);
    try std.testing.expect(out.len == 3);
    try std.testing.expect(out[0] == 8 and out[1] == 16 and out[2] == 32);

    try std.testing.expect(!system.isBroadcastable(&s3, &s_bad));

    const tile = [_]u32{ 2, 4, 8 };
    try std.testing.expect(system.isShapeDivisibleBy(&s3, &tile));
    const bad_tile = [_]u32{ 3, 4, 8 };
    try std.testing.expect(!system.isShapeDivisibleBy(&s3, &bad_tile));
}

test "type compatibility with optimized lookups" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    const i32_type = system.getPrimitiveType(.i32);
    const i64_type = system.getPrimitiveType(.i64);
    const bool_type = system.getPrimitiveType(.bool);

    // Test compatibility rules
    try std.testing.expect(system.areTypesCompatible(i32_type, i32_type)); // Same type
    try std.testing.expect(system.areTypesCompatible(i32_type, i64_type)); // Widening conversion
    try std.testing.expect(!system.areTypesCompatible(i32_type, bool_type)); // Incompatible
}

test "allocator type creation and detection" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    // Get a primitive type for testing
    const i32_type = system.getPrimitiveType(.i32);

    // Test allocator type creation
    const heap_allocator = try system.createAllocatorType(.heap);
    const arena_allocator = try system.createAllocatorType(.arena);
    const region_allocator = try system.createAllocatorType(.region);

    // Test type detection
    try std.testing.expect(system.isAllocator(heap_allocator));
    try std.testing.expect(system.isAllocator(arena_allocator));
    try std.testing.expect(!system.isAllocator(i32_type)); // Not an allocator

    // Test kind detection
    try std.testing.expectEqual(.heap, system.getAllocatorKind(heap_allocator).?);
    try std.testing.expectEqual(.arena, system.getAllocatorKind(arena_allocator).?);
    try std.testing.expectEqual(.region, system.getAllocatorKind(region_allocator).?);

    // Test deduplication
    const heap_allocator_2 = try system.createAllocatorType(.heap);
    try std.testing.expect(heap_allocator.id == heap_allocator_2.id); // Should be same
}

test "context-bound type creation and detection" {
    const allocator = std.testing.allocator;

    var system = try TypeSystem.init(allocator);
    defer system.deinit();

    const i32_type = system.getPrimitiveType(.i32);
    const heap_allocator = try system.createAllocatorType(.heap);

    // Create a context-bound type (e.g., Buffer[i32] with heap allocator)
    const context_bound = try system.createContextBoundType(i32_type, heap_allocator, .heap);

    // Test type detection
    try std.testing.expect(system.isContextBound(context_bound));
    try std.testing.expect(!system.isContextBound(i32_type));

    // Test inner type extraction
    const extracted_inner = system.getContextBoundInnerType(context_bound);
    try std.testing.expectEqual(i32_type, extracted_inner.?);

    // Test allocator kind extraction
    const extracted_kind = system.getAllocatorKind(context_bound);
    try std.testing.expectEqual(.heap, extracted_kind.?);

    // Test deduplication
    const context_bound_2 = try system.createContextBoundType(i32_type, heap_allocator, .heap);
    try std.testing.expect(context_bound.id == context_bound_2.id); // Should be same
}
