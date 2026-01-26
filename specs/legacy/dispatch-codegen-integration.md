<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# **Dispatch Codegen Integration Spec v2**

**Status:** **RATIFIED** — Implementation Law
**Filename:** `docs/specs/dispatch-codegen-integration.md`

-----

## **1. Purpose**

This specification is the final bridge between the Janus dispatch engine and executable reality. It provides the implementation contract for translating the semantically resolved dispatch families, as defined in RFC `dispatch-semantics-v0` and RFC `dispatch-language-integration`, into high-performance, verifiable Intermediate Representation (IR) and final machine code.

**The Law:** Dispatch is not a feature until it executes. This spec makes it execute.

-----

## **2. Scope & Tasks**

### **Task 1 – IR & LLVM Backend Binding**

**Objective:** Translate resolved dispatch calls from the semantic graph into canonical IR nodes. This IR is the single source of truth for all backends (LLVM, Cranelift, etc.).

**IR Node Definitions:**

```zig
const DispatchIR = union(enum) {
    /// A direct, zero-cost function call.
    static_call: StaticCallIR,
    /// A runtime dispatch stub with a defined strategy and cost.
    dynamic_stub: DynamicStubIR,
    /// A call that resolves to a compile-time error.
    error_call: ErrorCallIR,
};

const StaticCallIR = struct {
    target_function: FunctionRef,
    /// Path of EXPLICIT conversions required for the call.
    conversion_path: []ConversionStep,
    call_convention: CallingConvention,
};

const DynamicStubIR = struct {
    family_name: []const u8,
    candidates: []CandidateIR,
    strategy: StubStrategy,
    /// Estimated worst-case cost in cycles/nanoseconds.
    cost_estimate: u32,
};

const StubStrategy = enum {
    /// Default: safe, universal.
    switch_table,
    /// For performance-critical code via {.dispatch: perfect_hash}.
    perfect_hash,
    /// For highly polymorphic sites via {.dispatch: inline_cache}.
    inline_cache,
};
```

**Doctrinal Note on Conversions:** The `conversion_path` field in `StaticCallIR` **must not** represent implicit coercions. It shall only codify explicit, language-sanctioned type conversions (`@as(T, val)`). This enforces the Janus doctrine of **Syntactic Honesty** at the IR level. All conversions are visible or they are compilation errors.

**Codegen Contract for Advanced Patterns:** The generated IR for patterns like the "Visitor Pattern Alternative" (from `advanced-patterns.md`) must be provably equivalent in performance to a hand-written, optimized visitor. The `static_call` IR for AST node processing must compile down to a direct function call with zero dispatch overhead.

-----

### **Task 2 – Memory Management**

**The Arena Sovereignty Law:** The dispatch arena is owned by the semantic graph of a single package. It is created when the package's semantic analysis begins and is destroyed only after the final code generation for that package is complete. This guarantees zero leaks across incremental compilations.

**Dispatch Table Structure:**

```zig
const DispatchTable = struct {
    family_name: []const u8,
    entries: []DispatchEntry,
    arena: *ArenaAllocator,

    /// Serialize the dispatch table for caching.
    pub fn serialize(self: *const DispatchTable, writer: anytype) !void;
    /// Deserialize from cache.
    pub fn deserialize(reader: anytype, allocator: Allocator) !DispatchTable;
};
```

**Serialization Contract:** Dispatch tables **will** be serialized to the CBOR format defined in `dispatch-map-rpc-schema.md`. They will be stored in the compiler's Content-Addressable Store (CAS), keyed by the hash of the package's semantic state. This ensures perfect cache invalidation and unifies our tooling and caching schemas.

-----

### **Task 3 – Tooling Integration**

**CLI Commands:**

```bash
# Print generated IR for a dispatch family.
janus query dispatch-ir <symbol> [--module=<name>]

# Show resolution trace and the resulting IR emission.
janus trace dispatch <call_expression> [--module=<name>]
```

**RPC Integration:** The CLI commands will be frontends to the `janusd` RPC service. This enhances the existing `dispatch.query` and `dispatch.trace` endpoints with new response fields for IR information, conforming to the schema in `dispatch-map-rpc-schema.md`.

**The Cost Revelation Mandate:** All tooling outputs (`janus` CLI and `janusd` RPC) must include a `cost` field for each resolved call, valued at either `"static"` or `"dynamic"`. The IR itself must contain estimated performance characteristics.

**Example RPC JSON Response (`dispatch.trace`):**

```json
{
  "call": "process(my_data)",
  "resolution_strategy": "runtime_dispatch",
  "selected": "process(any) -> string",
  "cost": "dynamic",
  "ir": {
    "node_type": "dynamic_stub",
    "strategy": "switch_table",
    "candidates": 5,
    "estimated_cycles": 12,
    "stub_size_bytes": 128
  },
  "location": "src/main.jan:42"
}
```

-----

### **Task 4 – Diagnostics & Error Codes**

**Stable Codegen Error Codes (prefix C1xxx):**

  - `C1001`: Missing dispatch family IR for symbol.
  - `C1002`: Invalid or forbidden conversion path in IR emission.
  - `C1003`: ABI mismatch in generated stub for function family.
  - `C1004`: Unsupported backend target for requested dispatch stub strategy.
  - `C1005`: Perfect hash generation failed for family marked `{.dispatch: perfect_hash}`.

**The AI-Friendly Mandate:** All diagnostics must conform to a structured JSON format with stable error codes, human-readable messages, precise source spans, and machine-readable fix-it suggestions.

**Example Structured Diagnostic:**

```json
{
  "error": {
    "code": "C1003",
    "message": "ABI mismatch in dynamic dispatch stub for 'process'",
    "details": "Candidate 'process(f64)' has calling convention 'vectorcall' which is incompatible with the default 'sysv64' used by the dispatch stub.",
    "span": {
      "file": "src/modules/processing.jan",
      "line_start": 25,
      "line_end": 25,
      "column_start": 5,
      "column_end": 30
    },
    "suggestion": {
      "text": "Ensure all members of a dynamically dispatched function family share the same calling convention or use a compatible wrapper.",
      "fixit": null
    }
  }
}
```

-----

### **Task 5 – Cross-Platform Testing**

**Mandatory Targets:**

  - Linux (x86\_64, aarch64)
  - macOS (aarch64)
  - Windows (x86\_64)

**CI Pipeline Requirements:**

  - Build and test dispatch codegen across all mandatory targets.
  - Compare emitted IR for determinism. Hashes of IR for the same source must match.
  - Run golden tests: known Janus source code inputs must produce known, snapshotted IR outputs.

-----

### **Task 6 – CI & Performance Enforcement**

**CI Must:**

  - Run the full regression suite for dispatch codegen on every commit.
  - Execute performance benchmarks against a stable baseline. The following are **build-breaking** regressions:
      - Dynamic dispatch stub overhead \> 5% vs. a direct virtual function call in C++.
      - P99 dispatch resolution time \> 1ms for a moderately-sized project.
  - Store golden IR snapshots in version control to explicitly track and approve any changes to code generation.

-----

## **3. The Stub Generation Policy**

**Default Policy:** For dynamic dispatch (`.dispatch: dynamic` or calls involving `any`), the compiler **will** generate a `switch_table` based jump stub. This is the safe, predictable default.

**The Performance Dial:** For performance-critical code, architects **will** use comptime annotations to command the code generator:

```janus
// Force perfect hash generation. Fails compilation if impossible.
{.dispatch: perfect_hash}
func process(x: any) -> string;

// Generate an inline cache for this highly polymorphic call site.
{.dispatch: inline_cache}
func render(obj: Drawable) -> void;
```

This makes stub generation an explicit, auditable engineering decision, in accordance with the **Revealed Complexity** doctrine.

-----

## **4. Deliverables**

  - **Code:**
      - `compiler/codegen/llvm_dispatch.zig` (or equivalent)
      - `compiler/ir/dispatch_nodes.zig`
  - **Tooling:**
      - `janus query dispatch-ir` command implementation.
      - `janus trace dispatch` command implementation.
  - **CI:**
      - New GitHub Actions/Buildkite jobs for cross-platform builds, IR golden tests, and performance benchmarks.
  - **Documentation:**
      - `docs/dev/dispatch-codegen.md` (developer guide for working on the codegen).
      - Updated RPC schema and CLI documentation.

-----

## **5. Milestones**

  - **M1:** IR node definitions and LLVM binding for `static_call` are merged.
  - **M2:** IR stub generation (`dynamic_stub`) for `switch_table` is merged.
  - **M3:** `janus query dispatch-ir` and `janus trace dispatch` CLI commands are operational.
  - **M4:** All `C1xxx` error codes and structured diagnostics are integrated.
  - **M5:** Cross-platform CI is green with IR golden tests enforced.
  - **M6:** Performance benchmarks are stable and enforced as a build requirement.

-----

## **6. Risks & Mitigations**

  - **Risk:** Stub generation complexity slows down the compiler.
      - **Mitigation:** Heavy use of the CAS cache for serialized dispatch tables. Incremental compilation means we only generate code for what changed.
  - **Risk:** LLVM backend changes break our IR.
      - **Mitigation:** The canonical IR layer is our abstraction boundary. We adapt the LLVM emitter, not the core logic.
  - **Risk:** Performance on one architecture is not representative of others.
      - **Mitigation:** CI enforces benchmarks across all mandatory targets. A regression on *any* target is a build failure.

-----

## **7. Success Criteria & Doctrinal Compliance**

  - All tasks are complete and all deliverables are merged.
  - The system works flawlessly for all patterns in `examples.md` and `advanced-patterns.md`.
  - Tooling provides full transparency into the generated code, upholding **Revealed Complexity**.
  - The clear distinction between static and dynamic costs upholds **Performance Predictability**.
  - The absence of implicit behavior upholds **Syntactic Honesty**.
  - Error codes are stable and documented.
  - Cross-platform builds are green, with no performance regressions.

-----

## **8. Implementation Contract**

This specification is immutable. Deviations require a formal RFC amendment. CI will enforce compliance. Performance regressions are build failures. Accountability is total.
