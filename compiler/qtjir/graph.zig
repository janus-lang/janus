// SPDX-License-Identifier: LCL-1.0
// Copyright (c) 2026 Self Sovereign Society Foundation

// Doctrine: QTJIR (Quantum-Tensor Janus IR)
// A multi-level, hyper-graph IR with explicit hardware tenancy.

const std = @import("std");
const astdb_core = @import("astdb_core");

/// The Hinge: Explicit Hardware Tenancy.
/// Defines WHERE this node executes physically.
pub const Tenancy = enum {
    CPU_Serial, // Standard thread (Janus :min)
    CPU_Parallel, // Task/Actor system (Janus :full)
    NPU_Tensor, // Matrix acceleration
    QPU_Quantum, // Quantum superposition
};

/// The Stratigraphy: Semantic lowering levels.
pub const Level = enum {
    High, // Semantic (e.g., "Matrix Multiply", "Pattern Match")
    Mid, // Optimized (e.g., SSA, Loop invariant)
    Low, // Machine (e.g., Register allocation, AVX-512)
};

/// The Operations: Atomic units of work.
pub const OpCode = enum {
    // --- Data Flow ---
    Constant, // Immediate values
    Argument, // Function Argument (Index in data.integer)
    Alloca, // Stack allocation
    Load,
    Store,
    Phi, // SSA phi node (merge point)
    Array_Construct, // Array construction [e1, e2, ...]
    Index, // Array access: arr[i] (returns pointer for GEP)
    Index_Store, // Array element store: arr[i] = v
    Slice, // Array slice: arr[start..end] - returns slice struct
    SliceIndex, // Slice element access: slice[i] - calls runtime
    SliceLen, // Get slice length: slice.len - extract from fat pointer
    Range, // Range construction: start .. end
    Struct_Construct, // Struct literal { f1: v1, f2: v2 }
    Struct_Alloca, // Struct allocation (mutable struct variable)
    Field_Access, // Struct field read: s.field
    Field_Store, // Struct field write: s.field = v

    // --- Optional Types ---
    Optional_None, // Create null/none optional: { tag: 0, value: undef }
    Optional_Some, // Wrap value in optional: { tag: 1, value: v }
    Optional_Unwrap, // Unwrap optional (returns value, panics if none)
    Optional_Is_Some, // Check if optional has value: tag == 1

    // --- Error Unions (Error Handling) ---
    Error_Union_Construct, // Create error union from payload: { ok: value, is_error: 0 }
    Error_Fail_Construct, // Create error union from error: { err: error, is_error: 1 }
    Error_Union_Is_Error, // Check if error union is error: is_error == 1
    Error_Union_Unwrap, // Unwrap payload (asserts not error, panics if error)
    Error_Union_Get_Error, // Extract error value (asserts is_error)

    // --- Tagged Unions (SPEC-023 Phase B+C) ---
    Union_Construct, // inputs[0..N] = payload values, data.integer = tag index → { i32, i64*N }
    Union_Tag_Check, // inputs[0] = union value, data.integer = expected tag → i1 (bool)
    Union_Payload_Extract, // inputs[0] = union value, data.integer = field_index|(is_float<<32) → i32 or f64

    // --- Closures (SPEC-024 Phase A) ---
    Fn_Ref, // Function reference as value. data.string = function name. No inputs.

    // --- Closures (SPEC-024 Phase B) ---
    Closure_Create, // inputs[0..N] = captured values. data.string = fn_name. Produces { fn_ptr, env_ptr }
    Closure_Env_Load, // Load capture from env. data.integer = capture_index. No inputs.
    Closure_Env_Store, // Store to mutable capture. data.integer = capture_index. inputs[0] = value.
    Closure_Call, // inputs[0] = Closure_Create node, inputs[1..N] = args. Indirect call via env.

    // --- Control Flow ---
    Call, // Function call
    Return,
    Branch, // Conditional jump (Graph edge)
    Jump, // Unconditional jump
    Label, // Basic block entry point

    // --- Arithmetic (CPU) ---
    Add,
    Sub,
    Mul,
    Div,
    Mod, // Modulo/remainder
    Pow, // Exponentiation

    // --- Comparison ---
    Equal,
    NotEqual,
    Less,
    LessEqual,
    Greater,
    GreaterEqual,

    // --- Bitwise ---
    BitAnd,
    BitOr,
    Xor,
    Shl,
    Shr,
    BitNot,

    // --- Tensor Operations (NPU) ---
    Tensor_Matmul, // Matrix multiplication: C = A @ B
    Tensor_Conv, // Convolution operation
    Tensor_Reduce, // Reduction operations (sum, max, min, etc.)
    Tensor_ScalarMul, // Scalar-tensor multiplication
    Tensor_FusedMatmulRelu, // Fused matmul + ReLU activation
    Tensor_FusedMatmulAdd, // Fused matmul + add (for residual connections)
    Tensor_Contract, // General tensor contraction (einsum)
    Tensor_Relu, // Rectified Linear Unit activation
    Tensor_Softmax, // Softmax activation function

    // --- SSM Operations (NPU) - State Space Models (Mamba-3 inspired) ---
    SSM_Scan, // Linear recurrence scan: x[t] = A*x[t-1] + B*u[t]
    SSM_SelectiveScan, // Selective scan with input-dependent dynamics

    // --- Quantum Operations (QPU) ---
    Quantum_Gate, // QPU Hinge (H, CNOT, etc.)
    Quantum_Measure, // Collapse wave function

    // --- :service Profile - Structured Concurrency ---
    Await, // Suspend until async operation completes
    Spawn, // Launch task in current nursery scope
    Nursery_Begin, // Begin nursery scope (structured concurrency boundary)
    Nursery_End, // End nursery scope (waits for all spawned tasks)
    Async_Call, // Call async function (returns task handle)

    // --- :service Profile - CSP Channels (Phase 3) ---
    Channel_Create, // Create channel: Channel(T).init(capacity)
    Channel_Send, // Blocking send: ch.send(value)
    Channel_Recv, // Blocking receive: value = ch.recv()
    Channel_Close, // Close channel: ch.close()
    Channel_TryRecv, // Non-blocking receive: ch.tryRecv()
    Channel_TrySend, // Non-blocking send: ch.trySend(value)
    Channel_IsClosed, // Check if channel is closed: ch.isClosed()

    // --- :service Profile - Select Statement (Phase 4) ---
    Select_Begin, // Begin select statement (create select context)
    Select_Add_Recv, // Add recv case to select
    Select_Add_Send, // Add send case to select
    Select_Add_Timeout, // Add timeout case to select
    Select_Add_Default, // Add default case to select
    Select_Wait, // Wait for one case to become ready (returns case index)
    Select_Get_Value, // Get received value from completed recv case
    Select_End, // End select statement (cleanup select context)

    // --- :service Profile - Resource Management (Phase 3) ---
    Using_Begin, // Begin using statement (acquire resource)
    Using_End, // End using statement (cleanup resource)

    // --- Trait/Impl Dispatch (SPEC-025) ---
    Trait_Method_Call, // Static dispatch to impl method (Phase B: lowered as Call)
    Vtable_Lookup, // Dynamic dispatch via vtable (Phase C — placeholder)
    Vtable_Construct, // Construct vtable for trait impl (Phase C — placeholder)
    Impl_Method_Ref, // Reference to impl method by qualified name
};

/// Data types supported by tensor operations
pub const DataType = enum {
    // Floating point types
    f16, // Half precision (16-bit)
    f32, // Single precision (32-bit)
    f64, // Double precision (64-bit)

    // Signed integer types
    i8, // 8-bit signed
    i16, // 16-bit signed
    i32, // 32-bit signed
    i64, // 64-bit signed

    // Unsigned integer types
    u8, // 8-bit unsigned
    u16, // 16-bit unsigned
    u32, // 32-bit unsigned
    u64, // 64-bit unsigned
};

/// Memory layout strategies for tensor data
pub const MemoryLayout = enum {
    RowMajor, // C-style: rightmost index varies fastest
    ColumnMajor, // Fortran-style: leftmost index varies fastest
    NCHW, // Batch, Channel, Height, Width (common in CNNs)
    NHWC, // Batch, Height, Width, Channel (TensorFlow default)
};

/// Metadata for tensor operations
pub const TensorMetadata = struct {
    shape: []const usize, // Tensor dimensions (e.g., [128, 256] for 128x256 matrix)
    dtype: DataType, // Element data type
    layout: MemoryLayout, // Memory layout strategy
};

/// Quantum gate types for QPU operations
pub const GateType = enum {
    // Single-qubit gates
    Hadamard, // H gate: creates superposition
    PauliX, // X gate: bit flip
    PauliY, // Y gate: bit and phase flip
    PauliZ, // Z gate: phase flip
    Phase, // S gate: phase gate (√Z)
    T, // T gate: π/8 gate

    // Two-qubit gates
    CNOT, // Controlled-NOT gate
    CZ, // Controlled-Z gate
    SWAP, // SWAP gate: exchanges qubit states

    // Three-qubit gates
    Toffoli, // CCNOT: controlled-controlled-NOT
    Fredkin, // CSWAP: controlled-SWAP

    // Rotation gates (parameterized)
    RX, // Rotation around X-axis
    RY, // Rotation around Y-axis
    RZ, // Rotation around Z-axis
};

/// Metadata for quantum operations
pub const QuantumMetadata = struct {
    gate_type: GateType, // Type of quantum gate
    qubits: []const usize, // Qubit indices (1 for single-qubit, 2+ for multi-qubit gates)
    parameters: []const f64, // Gate parameters (e.g., rotation angles for RX/RY/RZ)
};

/// Payload for constant values
pub const ConstantValue = union(enum) {
    integer: i64,
    float: f64,
    // CRITICAL: Must be [:0]const u8 (sentinel-terminated) to match dupeZ allocation
    // This ensures allocator.free() knows the correct allocation size (len + 1)
    string: [:0]const u8,
    boolean: bool,
};

/// The Atom: A single node in the QTJIR Hyper-Graph.
pub const IRNode = struct {
    id: u32,
    op: OpCode,
    level: Level,
    tenancy: Tenancy,

    // Topology (Graph Edges)
    inputs: std.ArrayListUnmanaged(u32) = .{}, // Dependencies (Data flowing IN)

    // The Truth (ASTDB Traceability)
    source_node: ?astdb_core.NodeId = null,

    // Payload (for constants/literals)
    data: ConstantValue = .{ .integer = 0 },

    // Tensor metadata (for tensor operations)
    tensor_metadata: ?TensorMetadata = null,

    // Quantum metadata (for quantum operations)
    quantum_metadata: ?QuantumMetadata = null,

    pub fn init(id: u32, op: OpCode, ten: Tenancy) IRNode {
        return IRNode{
            .id = id,
            .op = op,
            .level = .High, // Default to High level on creation
            .tenancy = ten,
            .inputs = .{},
        };
    }

    pub fn deinit(self: *IRNode, allocator: std.mem.Allocator) void {
        self.inputs.deinit(allocator);
        switch (self.data) {
            // Sovereign Graph: unconditionally free
            // CRITICAL: dupeZ allocates len+1 bytes, so we must free the sentinel-terminated slice
            // to match the allocation size and avoid GPA warnings
            .string => |s| {
                // s is [:0]u8, allocator.free needs the full allocation including sentinel
                allocator.free(s);
            },
            else => {},
        }

        // Free quantum metadata (qubits and parameters arrays)
        if (self.quantum_metadata) |qm| {
            allocator.free(qm.qubits);
            allocator.free(qm.parameters);
        }

        // Free tensor metadata (shape array)
        if (self.tensor_metadata) |tm| {
            allocator.free(tm.shape);
        }
    }
};

/// Validation diagnostic information
pub const ValidationDiagnostic = struct {
    level: DiagnosticLevel,
    message: []const u8,
    node_id: ?u32,
    related_node_id: ?u32,

    pub const DiagnosticLevel = enum {
        Error,
        Warning,
        Note,
    };

    pub fn format(
        self: ValidationDiagnostic,
        comptime fmt: []const u8,
        options: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        _ = fmt;
        _ = options;

        const level_str = switch (self.level) {
            .Error => "ERROR",
            .Warning => "WARNING",
            .Note => "NOTE",
        };

        try writer.print("{s}: {s}", .{ level_str, self.message });
        if (self.node_id) |nid| {
            try writer.print(" (node {d})", .{nid});
        }
        if (self.related_node_id) |rnid| {
            try writer.print(" -> (node {d})", .{rnid});
        }
    }
};

/// Collection of validation diagnostics
pub const ValidationResult = struct {
    diagnostics: std.ArrayListUnmanaged(ValidationDiagnostic),
    has_errors: bool,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) ValidationResult {
        return ValidationResult{
            .diagnostics = .{},
            .has_errors = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *ValidationResult) void {
        for (self.diagnostics.items) |diag| {
            self.allocator.free(diag.message);
        }
        self.diagnostics.deinit(self.allocator);
    }

    pub fn addError(self: *ValidationResult, message: []const u8, node_id: ?u32, related: ?u32) !void {
        try self.diagnostics.append(self.allocator, .{
            .level = .Error,
            .message = message,
            .node_id = node_id,
            .related_node_id = related,
        });
        self.has_errors = true;
    }

    pub fn addWarning(self: *ValidationResult, message: []const u8, node_id: ?u32, related: ?u32) !void {
        try self.diagnostics.append(self.allocator, .{
            .level = .Warning,
            .message = message,
            .node_id = node_id,
            .related_node_id = related,
        });
    }

    pub fn dump(self: *const ValidationResult) void {
        if (self.diagnostics.items.len == 0) {
            std.debug.print("✓ Validation passed with no issues\n", .{});
            return;
        }

        std.debug.print("=== Validation Diagnostics ===\n", .{});
        for (self.diagnostics.items) |diag| {
            std.debug.print("{}\n", .{diag});
        }
        std.debug.print("==============================\n", .{});
    }
};

/// Function parameter metadata
pub const Parameter = struct {
    name: []const u8,
    type_name: []const u8,
};

/// Captured variable metadata (SPEC-024 Phase B+C)
/// Describes a variable captured from an enclosing scope by a closure.
pub const CapturedVar = struct {
    name: []const u8, // Variable name in the parent scope
    parent_alloca_id: u32, // The Alloca node ID in the parent graph
    index: u32, // Position in the environment struct
    is_mutable: bool = false, // Phase C: true for `var` captures (by-reference via pointer)
};

/// The Sovereign Graph.
pub const QTJIRGraph = struct {
    nodes: std.ArrayListUnmanaged(IRNode),
    allocator: std.mem.Allocator,

    // Function metadata
    function_name: []const u8 = "main",
    name_owned: bool = false, // true if function_name was heap-allocated and must be freed
    return_type: []const u8 = "i32",
    parameters: []const Parameter = &[_]Parameter{},

    // Closure capture metadata (SPEC-024 Phase B)
    // Non-null for closures that capture variables from enclosing scopes
    captures: []const CapturedVar = &[_]CapturedVar{},

    pub fn init(allocator: std.mem.Allocator) QTJIRGraph {
        return QTJIRGraph{
            .nodes = .{},
            .allocator = allocator,
        };
    }

    pub fn initWithName(allocator: std.mem.Allocator, function_name: []const u8) QTJIRGraph {
        return QTJIRGraph{
            .nodes = .{},
            .allocator = allocator,
            .function_name = function_name,
        };
    }

    pub fn deinit(self: *QTJIRGraph) void {
        for (self.nodes.items) |*node| {
            node.deinit(self.allocator);
        }
        self.nodes.deinit(self.allocator);

        // Free parameters
        for (self.parameters) |param| {
            self.allocator.free(param.name);
            // type_name is currently constant string, not allocated
        }
        self.allocator.free(self.parameters);

        // Free capture metadata (SPEC-024 Phase B)
        for (self.captures) |cap| {
            self.allocator.free(cap.name);
        }
        self.allocator.free(self.captures);

        // Free owned function name (closures, test graphs)
        if (self.name_owned) {
            self.allocator.free(self.function_name);
        }
    }

    /// Revealed Complexity: Dump the graph topology to stdout.
    pub fn dump(self: *const QTJIRGraph) void {
        std.debug.print("=== QTJIR Topology: {s} ===\n", .{self.function_name});
        for (self.nodes.items) |node| {
            std.debug.print("[{d}] {s} ({s}::{s}) inputs: ", .{ node.id, @tagName(node.op), @tagName(node.tenancy), @tagName(node.level) });
            for (node.inputs.items) |input| {
                std.debug.print("{d} ", .{input});
            }
            std.debug.print("\n", .{});
        }
        std.debug.print("======================\n", .{});
    }

    /// Validation: Ensure graph integrity (acyclic, no dangling edges, tenancy consistency)
    /// Returns ValidationResult with detailed diagnostics
    /// Doctrine: Diagnostics as a Configurable Mechanism - collect all issues before failing
    pub fn validate(self: *const QTJIRGraph) !ValidationResult {
        var result = ValidationResult.init(self.allocator);
        errdefer result.deinit();

        // 1. Check for dangling edges (references to non-existent nodes)
        try self.validateNodeReferences(&result);

        // 2. Check for cycles using DFS
        try self.validateAcyclic(&result);

        // 3. Check tenancy consistency within subgraphs
        try self.validateTenancyConsistency(&result);

        // 4. Check for duplicate node IDs
        try self.validateUniqueNodeIds(&result);

        // 5. Check tensor shape compatibility (Phase 2 - Task 2.1.3)
        try self.validateTensorShapes(&result);

        // 6. Check quantum operation validity (Phase 2 - Task 2.2.3)
        try self.validateQuantumOperations(&result);

        return result;
    }

    /// Validate that all node input references point to valid nodes
    /// Doctrine: Open Verification - collect all dangling edges, not just first
    fn validateNodeReferences(self: *const QTJIRGraph, result: *ValidationResult) !void {
        const node_count = self.nodes.items.len;

        for (self.nodes.items) |node| {
            for (node.inputs.items) |input_id| {
                if (input_id >= node_count) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Node references non-existent input node {d} (graph has {d} nodes)", .{ input_id, node_count });
                    try result.addError(msg, node.id, input_id);
                }
            }
        }
    }

    /// Validate that the graph is acyclic using DFS-based cycle detection
    /// Doctrine: Revealed Complexity - explicit algorithm with clear state tracking
    fn validateAcyclic(self: *const QTJIRGraph, result: *ValidationResult) !void {
        const node_count = self.nodes.items.len;
        if (node_count == 0) return;

        // Track visit state: 0 = unvisited, 1 = visiting, 2 = visited
        const visit_state = try self.allocator.alloc(u8, node_count);
        defer self.allocator.free(visit_state);
        @memset(visit_state, 0);

        // Track path for better error reporting
        var path = std.ArrayListUnmanaged(u32){};
        defer path.deinit(self.allocator);

        // DFS from each unvisited node
        for (self.nodes.items) |node| {
            if (visit_state[node.id] == 0) {
                try self.dfsCheckCycle(node.id, visit_state, &path, result);
            }
        }
    }

    /// DFS helper for cycle detection with path tracking
    fn dfsCheckCycle(self: *const QTJIRGraph, node_id: u32, visit_state: []u8, path: *std.ArrayListUnmanaged(u32), result: *ValidationResult) !void {
        visit_state[node_id] = 1; // Mark as visiting
        try path.append(self.allocator, node_id);

        const node = &self.nodes.items[node_id];
        for (node.inputs.items) |input_id| {
            if (input_id >= visit_state.len) continue; // Skip dangling edges (handled by validateNodeReferences)
            if (visit_state[input_id] == 1) {
                // Back edge detected - cycle found
                // Find where the cycle starts in the path
                var cycle_start: usize = 0;
                for (path.items, 0..) |pid, i| {
                    if (pid == input_id) {
                        cycle_start = i;
                        break;
                    }
                }

                // Build cycle description
                var cycle_desc = std.ArrayListUnmanaged(u8){};
                defer cycle_desc.deinit(self.allocator);

                try cycle_desc.appendSlice(self.allocator, "Cycle detected: ");
                for (path.items[cycle_start..]) |pid| {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d} -> ", .{pid}) catch break;
                    try cycle_desc.appendSlice(self.allocator, s);
                }
                {
                    var buf: [32]u8 = undefined;
                    const s = std.fmt.bufPrint(&buf, "{d}", .{input_id}) catch "";
                    try cycle_desc.appendSlice(self.allocator, s);
                }

                const msg = try cycle_desc.toOwnedSlice(self.allocator);
                try result.addError(msg, node_id, input_id);
                return; // Stop exploring this path
            }
            if (visit_state[input_id] == 0) {
                try self.dfsCheckCycle(input_id, visit_state, path, result);
            }
        }

        visit_state[node_id] = 2; // Mark as visited
        _ = path.pop();
    }

    /// Validate tenancy consistency: nodes with different tenancies should have explicit data transfer
    /// Doctrine: Mechanism over Policy - warn in Phase 1, will enforce in Phase 2
    fn validateTenancyConsistency(self: *const QTJIRGraph, result: *ValidationResult) !void {
        for (self.nodes.items) |node| {
            const node_tenancy = node.tenancy;

            // Check if inputs have consistent tenancy
            for (node.inputs.items) |input_id| {
                if (input_id >= self.nodes.items.len) continue; // Skip dangling edges
                const input_node = &self.nodes.items[input_id];
                const input_tenancy = input_node.tenancy;

                // If tenancies differ, this is a potential issue
                // In Phase 2, we'll add explicit data transfer nodes
                if (node_tenancy != input_tenancy) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Tenancy mismatch: {s} node uses {s} input (data transfer node needed in Phase 2)", .{ @tagName(node_tenancy), @tagName(input_tenancy) });
                    try result.addWarning(msg, node.id, input_id);
                }
            }
        }
    }

    /// Validate that all node IDs are unique and sequential
    /// Doctrine: Syntactic Honesty - node IDs must match their array indices
    fn validateUniqueNodeIds(self: *const QTJIRGraph, result: *ValidationResult) !void {
        for (self.nodes.items, 0..) |node, expected_id| {
            if (node.id != expected_id) {
                const msg = try std.fmt.allocPrint(self.allocator, "Node ID mismatch: expected {d}, got {d} (IDs must be sequential)", .{ expected_id, node.id });
                try result.addError(msg, node.id, null);
            }
        }
    }

    /// Validate tensor operation shape compatibility (Phase 2 - Task 2.1.3)
    /// Doctrine: Revealed Complexity - explicit shape checking with clear diagnostics
    fn validateTensorShapes(self: *const QTJIRGraph, result: *ValidationResult) !void {
        for (self.nodes.items) |node| {
            switch (node.op) {
                .Tensor_Matmul => try self.validateMatmulShapes(&node, result),
                .Tensor_Contract => try self.validateContractionShapes(&node, result),
                .Tensor_Conv => try self.validateConvolutionShapes(&node, result),
                .Tensor_Reduce => try self.validateReductionShapes(&node, result),
                .Tensor_ScalarMul => try self.validateScalarMulShapes(&node, result),
                else => {}, // Non-tensor operations don't need shape validation
            }
        }
    }

    /// Validate matrix multiplication shape compatibility
    /// Rule: [M×N] @ [N×P] = [M×P] (inner dimensions must match)
    fn validateMatmulShapes(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult) !void {
        if (node.inputs.items.len != 2) {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul requires exactly 2 inputs, got {d}", .{node.inputs.items.len});
            try result.addError(msg, node.id, null);
            return;
        }

        const a_id = node.inputs.items[0];
        const b_id = node.inputs.items[1];

        if (a_id >= self.nodes.items.len or b_id >= self.nodes.items.len) {
            return; // Dangling edges handled by validateNodeReferences
        }

        const a_node = &self.nodes.items[a_id];
        const b_node = &self.nodes.items[b_id];

        // Check if both inputs have tensor metadata
        const a_meta = a_node.tensor_metadata orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul input A (node {d}) missing tensor metadata", .{a_id});
            try result.addWarning(msg, node.id, a_id);
            return;
        };

        const b_meta = b_node.tensor_metadata orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul input B (node {d}) missing tensor metadata", .{b_id});
            try result.addWarning(msg, node.id, b_id);
            return;
        };

        // Both inputs must be 2D matrices
        if (a_meta.shape.len != 2) {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul input A must be 2D matrix, got {d}D tensor", .{a_meta.shape.len});
            try result.addError(msg, node.id, a_id);
            return;
        }

        if (b_meta.shape.len != 2) {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul input B must be 2D matrix, got {d}D tensor", .{b_meta.shape.len});
            try result.addError(msg, node.id, b_id);
            return;
        }

        // Check inner dimension compatibility: A[M×N] @ B[N×P]
        const a_cols = a_meta.shape[1];
        const b_rows = b_meta.shape[0];

        if (a_cols != b_rows) {
            const msg = try std.fmt.allocPrint(self.allocator, "Tensor_Matmul shape mismatch: A[{d}×{d}] @ B[{d}×{d}] - inner dimensions must match ({d} != {d})", .{ a_meta.shape[0], a_meta.shape[1], b_meta.shape[0], b_meta.shape[1], a_cols, b_rows });
            try result.addError(msg, node.id, null);
        }
    }

    /// Validate tensor contraction shape compatibility
    /// Note: Full einsum index validation deferred to future enhancement
    fn validateContractionShapes(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult) !void {
        _ = self;
        _ = node;
        _ = result;
        // Placeholder: Full contraction validation requires parsing einsum notation
        // This will be implemented in a future enhancement
    }

    /// Validate convolution shape compatibility
    /// Note: Convolution validation deferred to future enhancement
    fn validateConvolutionShapes(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult) !void {
        _ = self;
        _ = node;
        _ = result;
        // Placeholder: Convolution validation requires kernel size and stride information
    }

    /// Validate reduction operation shapes
    /// Note: Reduction validation deferred to future enhancement
    fn validateReductionShapes(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult) !void {
        _ = self;
        _ = node;
        _ = result;
        // Placeholder: Reduction validation requires axis information
    }

    /// Validate scalar-tensor multiplication shapes
    /// Note: Scalar-tensor validation deferred to future enhancement
    fn validateScalarMulShapes(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult) !void {
        _ = self;
        _ = node;
        _ = result;
        // Placeholder: Scalar-tensor validation requires type checking
    }

    /// Validate quantum operation validity (Phase 2 - Task 2.2.3)
    /// Doctrine: Revealed Complexity - explicit quantum validation with clear diagnostics
    fn validateQuantumOperations(self: *const QTJIRGraph, result: *ValidationResult) !void {
        // Track maximum qubit index seen to validate range
        var max_qubit_index: usize = 0;
        var has_quantum_ops = false;

        for (self.nodes.items) |node| {
            switch (node.op) {
                .Quantum_Gate => {
                    has_quantum_ops = true;
                    try self.validateQuantumGate(&node, result, &max_qubit_index);
                },
                .Quantum_Measure => {
                    has_quantum_ops = true;
                    try self.validateQuantumMeasurement(&node, result, &max_qubit_index);
                },
                else => {}, // Non-quantum operations don't need quantum validation
            }
        }

        // Validate reasonable qubit count (warn if > 50 qubits, which is unrealistic for near-term quantum computers)
        if (has_quantum_ops and max_qubit_index > 50) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum circuit uses qubit index {d}, which exceeds typical quantum computer capacity (50 qubits)", .{max_qubit_index});
            try result.addWarning(msg, null, null);
        }
    }

    /// Validate quantum gate operation
    fn validateQuantumGate(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult, max_qubit: *usize) !void {
        // Check that gate has quantum metadata
        const meta = node.quantum_metadata orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} missing quantum metadata", .{node.id});
            try result.addError(msg, node.id, null);
            return;
        };

        // Check that gate has at least one qubit
        if (meta.qubits.len == 0) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} has no qubits specified", .{node.id});
            try result.addError(msg, node.id, null);
            return;
        }

        // Validate qubit count for gate type
        const expected_qubits = switch (meta.gate_type) {
            .Hadamard, .PauliX, .PauliY, .PauliZ, .Phase, .T, .RX, .RY, .RZ => @as(usize, 1),
            .CNOT, .CZ, .SWAP, .Fredkin => @as(usize, 2),
            .Toffoli => @as(usize, 3),
        };

        if (meta.qubits.len != expected_qubits) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} ({s}) requires {d} qubit(s), got {d}", .{ node.id, @tagName(meta.gate_type), expected_qubits, meta.qubits.len });
            try result.addError(msg, node.id, null);
            return;
        }

        // Track maximum qubit index and check for duplicates in multi-qubit gates
        for (meta.qubits, 0..) |qubit_idx, i| {
            if (qubit_idx > max_qubit.*) {
                max_qubit.* = qubit_idx;
            }

            // Check for duplicate qubits in multi-qubit gates
            if (meta.qubits.len > 1) {
                for (meta.qubits[i + 1 ..]) |other_qubit| {
                    if (qubit_idx == other_qubit) {
                        const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} ({s}) has duplicate qubit index {d}", .{ node.id, @tagName(meta.gate_type), qubit_idx });
                        try result.addError(msg, node.id, null);
                        return;
                    }
                }
            }
        }

        // Validate rotation gate parameters
        switch (meta.gate_type) {
            .RX, .RY, .RZ => {
                if (meta.parameters.len != 1) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} ({s}) requires 1 parameter (rotation angle), got {d}", .{ node.id, @tagName(meta.gate_type), meta.parameters.len });
                    try result.addError(msg, node.id, null);
                    return;
                }

                // Check for NaN or infinite angles
                const angle = meta.parameters[0];
                if (std.math.isNan(angle) or std.math.isInf(angle)) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} ({s}) has invalid rotation angle (NaN or Inf)", .{ node.id, @tagName(meta.gate_type) });
                    try result.addError(msg, node.id, null);
                    return;
                }
            },
            else => {
                // Non-rotation gates should not have parameters
                if (meta.parameters.len > 0) {
                    const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} ({s}) should not have parameters, got {d}", .{ node.id, @tagName(meta.gate_type), meta.parameters.len });
                    try result.addWarning(msg, node.id, null);
                }
            },
        }

        // Validate tenancy
        if (node.tenancy != .QPU_Quantum) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Gate node {d} has incorrect tenancy {s} (should be QPU_Quantum)", .{ node.id, @tagName(node.tenancy) });
            try result.addWarning(msg, node.id, null);
        }
    }

    /// Validate quantum measurement operation
    fn validateQuantumMeasurement(self: *const QTJIRGraph, node: *const IRNode, result: *ValidationResult, max_qubit: *usize) !void {
        // Check that measurement has quantum metadata
        const meta = node.quantum_metadata orelse {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Measure node {d} missing quantum metadata", .{node.id});
            try result.addError(msg, node.id, null);
            return;
        };

        // Check that measurement has at least one qubit
        if (meta.qubits.len == 0) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Measure node {d} has no qubits specified", .{node.id});
            try result.addError(msg, node.id, null);
            return;
        }

        // Track maximum qubit index
        for (meta.qubits) |qubit_idx| {
            if (qubit_idx > max_qubit.*) {
                max_qubit.* = qubit_idx;
            }
        }

        // Validate tenancy
        if (node.tenancy != .QPU_Quantum) {
            const msg = try std.fmt.allocPrint(self.allocator, "Quantum_Measure node {d} has incorrect tenancy {s} (should be QPU_Quantum)", .{ node.id, @tagName(node.tenancy) });
            try result.addWarning(msg, node.id, null);
        }
    }
};

/// The Builder: Ergonomic API for lowering AST to IR.
pub const IRBuilder = struct {
    graph: *QTJIRGraph,
    current_tenancy: Tenancy = .CPU_Serial,

    pub fn init(graph: *QTJIRGraph) IRBuilder {
        return IRBuilder{ .graph = graph };
    }

    pub fn createNode(self: *IRBuilder, op: OpCode) !u32 {
        const id = @as(u32, @intCast(self.graph.nodes.items.len));
        const node = IRNode.init(id, op, self.current_tenancy);
        try self.graph.nodes.append(self.graph.allocator, node);
        return id;
    }

    pub fn createConstant(self: *IRBuilder, value: ConstantValue) !u32 {
        const id = try self.createNode(.Constant);
        self.graph.nodes.items[id].data = value;
        return id;
    }

    pub fn createCall(self: *IRBuilder, args: []const u32) !u32 {
        const id = try self.createNode(.Call);
        var node = &self.graph.nodes.items[id];
        try node.inputs.appendSlice(self.graph.allocator, args);
        return id;
    }

    pub fn createReturn(self: *IRBuilder, value_id: u32) !u32 {
        const id = try self.createNode(.Return);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, value_id);
        return id;
    }

    pub fn buildAlloca(self: *IRBuilder, allocator: std.mem.Allocator, type_id: DataType, name: []const u8) !u32 {
        _ = allocator;
        _ = type_id;
        const id = try self.createNode(.Alloca);
        // Sovereign Graph: allocate null-terminated copy for graph ownership
        const owned_name = try self.graph.allocator.dupeZ(u8, name);
        self.graph.nodes.items[id].data = .{ .string = owned_name };
        return id;
    }

    pub fn buildStore(self: *IRBuilder, allocator: std.mem.Allocator, val_id: u32, ptr_id: u32) !u32 {
        const id = try self.createNode(.Store);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(allocator, ptr_id);
        try node.inputs.append(allocator, val_id);
        return id;
    }

    pub fn buildLoad(self: *IRBuilder, allocator: std.mem.Allocator, ptr_id: u32, name: []const u8) !u32 {
        const id = try self.createNode(.Load);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(allocator, ptr_id);
        // Sovereign Graph: allocate null-terminated copy for graph ownership
        const owned_name = try self.graph.allocator.dupeZ(u8, name);
        node.data = .{ .string = owned_name };
        return id;
    }

    // =========================================================================
    // Extended Builder Methods for :core profile codegen
    // =========================================================================

    /// Create alloca (stack allocation) - simplified API
    pub fn createAlloca(self: *IRBuilder) !u32 {
        return try self.createNode(.Alloca);
    }

    /// Create store instruction
    pub fn createStore(self: *IRBuilder, value_id: u32, ptr_id: u32) !u32 {
        const id = try self.createNode(.Store);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, ptr_id);
        try node.inputs.append(self.graph.allocator, value_id);
        return id;
    }

    /// Create load instruction
    pub fn createLoad(self: *IRBuilder, ptr_id: u32) !u32 {
        const id = try self.createNode(.Load);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, ptr_id);
        return id;
    }

    /// Create binary operation
    pub fn createBinaryOp(self: *IRBuilder, op: OpCode, left_id: u32, right_id: u32) !u32 {
        const id = try self.createNode(op);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, left_id);
        try node.inputs.append(self.graph.allocator, right_id);
        return id;
    }

    /// Create unary operation
    pub fn createUnaryOp(self: *IRBuilder, op: OpCode, operand_id: u32) !u32 {
        const id = try self.createNode(op);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, operand_id);
        return id;
    }

    /// Create conditional branch
    pub fn createBranch(self: *IRBuilder, cond_id: u32, then_label: u32, else_label: u32) !u32 {
        const id = try self.createNode(.Branch);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, cond_id);
        try node.inputs.append(self.graph.allocator, then_label);
        try node.inputs.append(self.graph.allocator, else_label);
        return id;
    }

    /// Create unconditional jump
    pub fn createJump(self: *IRBuilder, target_label: u32) !u32 {
        const id = try self.createNode(.Jump);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, target_label);
        return id;
    }

    /// Create label (basic block entry)
    pub fn createLabel(self: *IRBuilder, label_id: u32) !u32 {
        const id = try self.createNode(.Label);
        self.graph.nodes.items[id].data = .{ .integer = @intCast(label_id) };
        return id;
    }

    /// Create named function call
    pub fn createCallNamed(self: *IRBuilder, func_name: []const u8, args: []const u32) !u32 {
        const id = try self.createNode(.Call);
        var node = &self.graph.nodes.items[id];

        // Store function name
        const owned_name = try self.graph.allocator.dupeZ(u8, func_name);
        node.data = .{ .string = owned_name };

        // Add arguments
        try node.inputs.appendSlice(self.graph.allocator, args);
        return id;
    }

    /// Create a function reference node (function pointer to a named function)
    /// Phase A: Zero-capture closures only — references a generated anonymous function
    pub fn createFnRef(self: *IRBuilder, func_name: []const u8) !u32 {
        const id = try self.createNode(.Fn_Ref);
        var node = &self.graph.nodes.items[id];
        node.data = .{ .string = try self.graph.allocator.dupeZ(u8, func_name) };
        return id;
    }

    /// Create a Closure_Create node (SPEC-024 Phase B)
    /// inputs[0..N] = captured value nodes from the parent scope
    /// data.string = anonymous function name
    pub fn createClosureCreate(self: *IRBuilder, func_name: []const u8, captured_ids: []const u32) !u32 {
        const id = try self.createNode(.Closure_Create);
        var node = &self.graph.nodes.items[id];
        node.data = .{ .string = try self.graph.allocator.dupeZ(u8, func_name) };
        try node.inputs.appendSlice(self.graph.allocator, captured_ids);
        return id;
    }

    /// Create a Closure_Call node (SPEC-024 Phase B)
    /// inputs[0] = Closure_Create node, inputs[1..N] = call arguments
    pub fn createClosureCall(self: *IRBuilder, closure_id: u32, args: []const u32) !u32 {
        const id = try self.createNode(.Closure_Call);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, closure_id);
        try node.inputs.appendSlice(self.graph.allocator, args);
        return id;
    }

    /// Create a Closure_Env_Load node (SPEC-024 Phase B)
    /// Loads a captured variable from the environment struct at the given index
    pub fn createClosureEnvLoad(self: *IRBuilder, capture_index: u32) !u32 {
        const id = try self.createNode(.Closure_Env_Load);
        self.graph.nodes.items[id].data = .{ .integer = @intCast(capture_index) };
        return id;
    }

    /// Create a Closure_Env_Store node (SPEC-024 Phase C)
    /// Stores a value through a mutable capture's pointer in the environment struct
    pub fn createClosureEnvStore(self: *IRBuilder, capture_index: u32, value_id: u32) !u32 {
        const id = try self.createNode(.Closure_Env_Store);
        self.graph.nodes.items[id].data = .{ .integer = @intCast(capture_index) };
        try self.graph.nodes.items[id].inputs.append(self.graph.allocator, value_id);
        return id;
    }

    /// Create phi node for SSA
    pub fn createPhi(self: *IRBuilder, incoming: []const struct { value: u32, block: u32 }) !u32 {
        const id = try self.createNode(.Phi);
        var node = &self.graph.nodes.items[id];
        for (incoming) |entry| {
            try node.inputs.append(self.graph.allocator, entry.value);
            try node.inputs.append(self.graph.allocator, entry.block);
        }
        return id;
    }

    // =========================================================================
    // Error Handling Operations (:core profile)
    // =========================================================================

    /// Create error union from success payload: T ! E -> ok value
    /// Constructs: { ok: payload, is_error: false }
    pub fn createErrorUnionConstruct(self: *IRBuilder, payload_id: u32) !u32 {
        const id = try self.createNode(.Error_Union_Construct);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, payload_id);
        return id;
    }

    /// Create error union from error value: fail ErrorType.Variant
    /// Constructs: { err: error_value, is_error: true }
    pub fn createErrorFailConstruct(self: *IRBuilder, error_id: u32) !u32 {
        const id = try self.createNode(.Error_Fail_Construct);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, error_id);
        return id;
    }

    /// Check if error union contains an error
    /// Returns: boolean (true if error, false if ok)
    pub fn createErrorUnionIsError(self: *IRBuilder, error_union_id: u32) !u32 {
        const id = try self.createNode(.Error_Union_Is_Error);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, error_union_id);
        return id;
    }

    /// Unwrap payload from error union (asserts not error, panics if error)
    /// Returns: payload value T
    pub fn createErrorUnionUnwrap(self: *IRBuilder, error_union_id: u32) !u32 {
        const id = try self.createNode(.Error_Union_Unwrap);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, error_union_id);
        return id;
    }

    /// Extract error value from error union (asserts is_error)
    /// Returns: error value E
    pub fn createErrorUnionGetError(self: *IRBuilder, error_union_id: u32) !u32 {
        const id = try self.createNode(.Error_Union_Get_Error);
        var node = &self.graph.nodes.items[id];
        try node.inputs.append(self.graph.allocator, error_union_id);
        return id;
    }

    // =========================================================================
    // Tagged Union Operations (SPEC-023 Phase B+C)
    // =========================================================================

    /// Construct tagged union: { tag_index, payload_0, payload_1, ... }
    /// For unit variants (no payload), pass empty slice
    pub fn createUnionConstruct(self: *IRBuilder, tag_index: i64, payload_ids: []const u32) !u32 {
        const id = try self.createNode(.Union_Construct);
        var node = &self.graph.nodes.items[id];
        node.data = .{ .integer = tag_index };
        for (payload_ids) |pid| {
            try node.inputs.append(self.graph.allocator, pid);
        }
        return id;
    }

    /// Check if tagged union has expected tag: tag == expected
    /// Returns: boolean (true if tag matches)
    pub fn createUnionTagCheck(self: *IRBuilder, union_id: u32, expected_tag: i64) !u32 {
        const id = try self.createNode(.Union_Tag_Check);
        var node = &self.graph.nodes.items[id];
        node.data = .{ .integer = expected_tag };
        try node.inputs.append(self.graph.allocator, union_id);
        return id;
    }

    /// Extract payload field from tagged union by index
    /// field_index selects which field slot (0-based), is_float triggers f64 bitcast
    pub fn createUnionPayloadExtract(self: *IRBuilder, union_id: u32, field_index: u32, is_float: bool) !u32 {
        const id = try self.createNode(.Union_Payload_Extract);
        var node = &self.graph.nodes.items[id];
        // Encode: lower 32 bits = field_index, bit 32 = is_float
        const encoded: i64 = @as(i64, @intCast(field_index)) | (if (is_float) @as(i64, 1) << 32 else 0);
        node.data = .{ .integer = encoded };
        try node.inputs.append(self.graph.allocator, union_id);
        return id;
    }
};

// --- Tests ---

test "QTJIR: Graph Construction and Topology" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Scenario: print("Hello")
    // 1. Constant String (Data)
    const str_node = try builder.createConstant(.{ .string = "Hello, World!" });

    // 2. Call Function (Consumes String)
    const args = [_]u32{str_node};
    const call_node = try builder.createCall(&args);

    // Verify Topology
    try std.testing.expectEqual(@as(usize, 2), graph.nodes.items.len);
    try std.testing.expectEqual(str_node, graph.nodes.items[call_node].inputs.items[0]);
    try std.testing.expectEqual(Tenancy.CPU_Serial, graph.nodes.items[call_node].tenancy);

    // Visual Inspection
    graph.dump();
}

test "QTJIR: Future Tenancy Hinge" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Switch Tenancy to Quantum
    builder.current_tenancy = .QPU_Quantum;
    const q_node = try builder.createNode(.Quantum_Gate);

    try std.testing.expectEqual(Tenancy.QPU_Quantum, graph.nodes.items[q_node].tenancy);
}

test "QTJIR: Tensor Metadata Support" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a Tensor Matmul node with metadata
    builder.current_tenancy = .NPU_Tensor;
    const node_id = try builder.createNode(.Tensor_Matmul);

    // Attach metadata
    const shape = try alloc.dupe(usize, &[_]usize{ 128, 256 });
    graph.nodes.items[node_id].tensor_metadata = .{
        .shape = shape,
        .dtype = .f32,
        .layout = .RowMajor,
    };

    // Verify
    const node = &graph.nodes.items[node_id];
    try std.testing.expectEqual(OpCode.Tensor_Matmul, node.op);
    try std.testing.expectEqual(Tenancy.NPU_Tensor, node.tenancy);
    try std.testing.expect(node.tensor_metadata != null);
    try std.testing.expectEqual(@as(usize, 128), node.tensor_metadata.?.shape[0]);
    try std.testing.expectEqual(DataType.f32, node.tensor_metadata.?.dtype);
}

// --- Validation Tests ---

test "QTJIR: Validation - Valid Graph" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a simple valid graph: Constant -> Call
    const const_node = try builder.createConstant(.{ .integer = 42 });
    const args = [_]u32{const_node};
    _ = try builder.createCall(&args);

    // Should validate successfully
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(!result.has_errors);
    try std.testing.expectEqual(@as(usize, 0), result.diagnostics.items.len);
}

test "QTJIR: Validation - Dangling Edge Detection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a node with invalid input reference
    const node_id = try builder.createNode(.Call);
    var node = &graph.nodes.items[node_id];
    try node.inputs.append(alloc, 999); // Non-existent node

    // Should detect dangling edge
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(result.has_errors);
    try std.testing.expect(result.diagnostics.items.len > 0);

    // Verify error message mentions the dangling reference
    const first_diag = result.diagnostics.items[0];
    try std.testing.expectEqual(ValidationDiagnostic.DiagnosticLevel.Error, first_diag.level);
}

test "QTJIR: Validation - Cycle Detection" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a cycle: Node 0 -> Node 1 -> Node 0
    const node0 = try builder.createNode(.Add);
    const node1 = try builder.createNode(.Add);

    // Node 1 depends on Node 0
    try graph.nodes.items[node1].inputs.append(alloc, node0);

    // Node 0 depends on Node 1 (creates cycle)
    try graph.nodes.items[node0].inputs.append(alloc, node1);

    // Should detect cycle
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(result.has_errors);

    // Verify cycle is reported with path information
    var found_cycle = false;
    for (result.diagnostics.items) |diag| {
        if (diag.level == .Error and std.mem.indexOf(u8, diag.message, "Cycle") != null) {
            found_cycle = true;
            break;
        }
    }
    try std.testing.expect(found_cycle);
}

test "QTJIR: Validation - Self-Referencing Cycle" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a self-referencing node
    const node_id = try builder.createNode(.Add);
    try graph.nodes.items[node_id].inputs.append(alloc, node_id);

    // Should detect self-cycle
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(result.has_errors);

    // Verify self-cycle is reported
    var found_self_cycle = false;
    for (result.diagnostics.items) |diag| {
        if (diag.level == .Error and
            diag.node_id == node_id and
            diag.related_node_id == node_id)
        {
            found_self_cycle = true;
            break;
        }
    }
    try std.testing.expect(found_self_cycle);
}

test "QTJIR: Validation - Complex Acyclic Graph" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create a diamond-shaped DAG:
    //     0
    //    / \
    //   1   2
    //    \ /
    //     3
    const node0 = try builder.createConstant(.{ .integer = 1 });
    const node1 = try builder.createNode(.Add);
    const node2 = try builder.createNode(.Mul);
    const node3 = try builder.createNode(.Add);

    // Node 1 and 2 depend on Node 0
    try graph.nodes.items[node1].inputs.append(alloc, node0);
    try graph.nodes.items[node2].inputs.append(alloc, node0);

    // Node 3 depends on both Node 1 and 2
    try graph.nodes.items[node3].inputs.append(alloc, node1);
    try graph.nodes.items[node3].inputs.append(alloc, node2);

    // Should validate successfully (no cycles)
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(!result.has_errors);
    // Diamond pattern is valid, should have no errors
}

test "QTJIR: Validation - Tenancy Consistency Warning" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var graph = QTJIRGraph.init(alloc);
    defer graph.deinit();

    var builder = IRBuilder.init(&graph);

    // Create CPU node
    builder.current_tenancy = .CPU_Serial;
    const cpu_node = try builder.createConstant(.{ .integer = 42 });

    // Create NPU node that depends on CPU node
    builder.current_tenancy = .NPU_Tensor;
    const npu_node = try builder.createNode(.Tensor_Contract);
    try graph.nodes.items[npu_node].inputs.append(alloc, cpu_node);

    // Should validate with warning (not error in Phase 1)
    var result = try graph.validate();
    defer result.deinit();

    try std.testing.expect(!result.has_errors); // No errors in Phase 1

    // Should have tenancy mismatch warning
    var found_tenancy_warning = false;
    for (result.diagnostics.items) |diag| {
        if (diag.level == .Warning and std.mem.indexOf(u8, diag.message, "Tenancy mismatch") != null) {
            found_tenancy_warning = true;
            break;
        }
    }
    try std.testing.expect(found_tenancy_warning);
}
