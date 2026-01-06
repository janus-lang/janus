# PLAN: v0.3.0 Release — "The Graft & The Crown"

**Target:** June 2026
**Codename:** "Chimera"
**Focus:** Grafting, Standard Library Crowns, and Core Stability.

---

## 🏛️ Strategic Vision

v0.3.0 is the release where Janus stops being an island. It becomes an empire.
We assume the substrate (Core Language v0.2.x) is stable. Now we build the bridges and the palaces.

**The Three Pillars:**
1.  **The Crown Jewels:** High-level, "Standard Library as a Service" modules (`std.compute`, `std.service`).
2.  **The Grafting:** Seamless, zero-overhead FFI to the world's ecosystem (Onyx syntax, Lobster memory model, C/Rust/Julia bindings).
3.  **The Graph Revolution:** Specialized heavy artillery for decentralized networks.

---

## 🗺️ The Roadmap (Consolidated)

### 1. The Foundation (v0.2.x Cleanup)
*Before we conquer, we must secure the base.*

#### A. The Nervous System (LSP)
*Source: `CURRENT_PLAN-v0.2.2.md`*
- [ ] **ASTDB Query API:** Position-based lookups.
- [ ] **LSP Features:** Hover, Go-To-Def, References.
- [ ] **VS Code Integration:** Full extension support.

#### B. The Sovereign Memory Model
*Source: `memory-model-v0.2.5-v0.2.15.md`*
- [ ] **Region Allocators (v0.2.5):** `with_scratchpad` for frame-scoped memory.
- [ ] **Mutable Value Semantics (v0.2.6):** Logical copies, physical COW.
- [ ] **Hot Reloading (v0.2.8):** JIT infrastructure for `:script` profile.
- [ ] **C Interop (v0.2.9):** Native `import c` support.

---

### 2. The Grafting Revolution (Integration)
*Spec: `18-GRAFTING-REVOLUTION`*
*Source: `FUTURE_PLAN-v0.3.0.md`, `GRAFT-onyx-lobster.md`*

#### A. Syntax & Flow (The Onyx/Forth/J Graft)
- [ ] **UFCS (Uniform Function Call Syntax):** `x.f()` -> `f(x)`.
- [ ] **Pipeline Operator (`|>`):** `data |> parse |> validate`.
- [ ] **Tacit Composition:** `compose(process, validate)`.

#### B. Memory & Safety (The Lobster Graft)
- [ ] **Owned Types (`~T`):** Compile-time ref counting (Ghost Memory).
- [ ] **Flow Typing:** Null narrowing (`if x != null`).

#### C. The World Grafts (FFI)
- [ ] **C:** Direct shared object loading (`graft libc = c "..."`).
- [ ] **Rust:** Cargo crate grafting (`graft rocket = cargo "..."`).
- [ ] **Julia:** Foreign blocks for scientific supremacy.
- [ ] **Zig:** Native substrate extension.

#### D. The Universal Artifact
- [ ] **WASM Backend:** Target `wasm32-wasi` via LLVM.

---

### 3. The Crown Jewels (Applications)
*Spec: `16-CROWN-JEWELS`*

- [ ] **`std.compute` (Tensor Forge):** PyTorch/LibTorch graft. Native tensors.
- [ ] **`std.service` (High-Velocity Gate):** FastAPI-inspired, compiled web service layer.

---

### 4. The Graph Revolution (Performance)
*Spec: `17-GRAPH-THEORY-REVOLUTION`*

- [ ] **`std.graph.sparse_sssp`:** arXiv:2504.17033v2 implementation.
- Breaking the sorting barrier for massive, sparse decentralized topologies.

---

## 🗓️ Execution Order

### Phase 1: Stabilization (Immediate)
1.  **LSP & Tooling (v0.2.2):** Complete ASTDB query engine and VS Code extension.
2.  **Memory Model (v0.2.5-v0.2.9):** Implement scratchpads, COW, and basic C FFI.

### Phase 2: The Syntax Grafts (v0.3.0-alpha)
1.  **Parser Upgrades:** Implement UFCS and `|>` pipe operator.
2.  **WASM Backend:** Initial `wasm32-wasi` target support.

### Phase 3: The Crown & Graph (v0.3.0-beta)
1.  **Crown Jewels:** Prototype `std.compute` and `std.service`.
2.  **Graph:** Implement Sparse SSSP algorithm.

### Phase 4: Release (v0.3.0-RC)
1.  **Integration:** Verify all grafts work together.
2.  **Documentation:** Complete "Grafting Guide" and "Standard Library" docs.

---

## ⏩ Defended to Future (Backlog)

These features are critical but deferred to maintain v0.3.0 velocity:
- `9-io-revolution` (Async IO is complex, rely on `std.service` graft for now).
- `14-PROPHETIC_JIT` (Full Hot Reload deferred, basic JIT in v0.2.8).
- `11-bsd-anarchy` (OS Sovereignty is v1.0).
- `j-inspired-tacit-arrays.md` (Array Engine/NPU Profile deferred to v0.4.0).

---

**Voxis Forge Directive:**
"We are not building a language. We are building a composite weapon."
