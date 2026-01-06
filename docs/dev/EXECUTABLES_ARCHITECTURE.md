# Janus Executables Architecture (INTERNAL)

**⚠️ WARNING: This is INTERNAL development documentation.**  
**Describes current state and future plans - not all features are implemented.**

**Date:** 2025-12-28  
**Version:** v0.2.1-3

---

## 🎯 **TL;DR: Why Three Executables?**

You have **three executables** because they serve **three distinct use cases** with **different architectural constraints**:

1. **`janus`** - The CLI compiler (batch compilation, build scripts)
2. **`janusd`** - The UTCP daemon (multi-mode server: UTCP registry + LSP fallback)
3. **`janus-lsp`** - The standalone LSP server (VS Code integration)

---

## 📊 **Current State**

### **1. `janus` (CLI Compiler)**

**Location:** `cmd/janus-shell/main.zig`  
**Purpose:** Batch compilation, build scripts, CI/CD  
**Architecture:** Stateless, single-shot execution

```bash
janus compile example.jan -o output
janus query --ast example.jan
janus fmt example.jan
```

**Key Characteristics:**
- **No daemon dependency** - Self-contained
- **Fast startup** - Optimized for quick compilation
- **Stateless** - No persistent state between invocations
- **Build tool integration** - Works in Makefiles, CI pipelines

---

### **2. `janusd` (Multi-Mode Daemon)**

**Location:** `cmd/janusd/main.zig`  
**Purpose:** **Primary:** UTCP Registry Server, **Secondary:** LSP mode  
**Architecture:** Long-running daemon with multiple modes

#### **Mode 1: UTCP Registry (Default)**
```bash
janusd --http 127.0.0.1:7735
```
- Manages distributed capability tokens
- Handles lease registration/heartbeat
- Cluster replication (3-node Raft)
- HTTP/JSON API for registry operations

#### **Mode 2: LSP Fallback**
```bash
janusd --lsp
```
- **Embedded LSP server** (same code as `janus-lsp`)
- Uses stdin/stdout for JSON-RPC
- **Why it exists:** Convenience during development
- **Current status:** Lines 67-81 in `janusd/main.zig`

**Key Insight:**  
`janusd --lsp` is **functionally identical** to `janus-lsp`. It's the **same LSP implementation** (`daemon/lsp_server.zig`), just invoked through a different entry point.

---

### **3. `janus-lsp` (Standalone LSP Server)**

**Location:** `cmd/janus-lsp/main.zig`  
**Purpose:** VS Code / Editor integration  
**Architecture:** "Thick Client" - Self-contained language intelligence

```bash
janus-lsp  # Started by VS Code extension
```

**Key Characteristics:**
- **No daemon dependency** - Embeds ASTDB directly
- **Thick Client** - All semantic analysis in-process
- **Fast response** - No IPC overhead
- **Isolated state** - Each editor session has its own ASTDB

**Trade-off:**  
Unsaved VS Code edits are **invisible** to `janus query` CLI commands. This will be solved in v0.3.0 via **Citadel Protocol** (shared state bridge).

---

## 🤔 **Why Not Merge Them?**

### **Option A: Merge `janus-lsp` into `janusd`?**

**Pros:**
- One fewer binary to maintain
- Unified daemon architecture

**Cons:**
- **Startup overhead:** UTCP registry initialization slows LSP startup
- **Complexity:** UTCP cluster logic pollutes LSP code
- **Deployment:** Users who only want LSP must install UTCP dependencies
- **Failure coupling:** UTCP bugs could crash the LSP

**Verdict:** ❌ **Bad idea.** LSP needs to be **lean and isolated**.

---

### **Option B: Merge `janus` into `janusd`?**

**Pros:**
- Shared compilation state (faster incremental builds)
- Single source of truth for AST

**Cons:**
- **Daemon dependency:** CI/CD now requires running `janusd`
- **Startup latency:** `janus compile` becomes slower (daemon handshake)
- **Complexity:** Build scripts must manage daemon lifecycle
- **Portability:** Harder to use in restricted environments (containers, sandboxes)

**Verdict:** ❌ **Bad idea.** CLI tools should be **stateless and fast**.

---

### **Option C: Make `janusd` the "One True Daemon"?**

This is **your original vision** (`libjanusd`). Here's why it's **not implemented yet**:

**The Vision:**
```
janusd (daemon)
  ├── LSP Server (port 7736)
  ├── UTCP Registry (port 7735)
  ├── Compilation Cache (shared ASTDB)
  └── Hot-Reload Coordinator
```

**Why it's deferred to v0.3.0:**

1. **Citadel Protocol** (shared state bridge) not yet implemented
2. **Incremental compilation** not yet stable
3. **Hot-reload** still experimental
4. **Complexity:** Need robust daemon lifecycle management

**Current Status:**  
`janusd --lsp` is a **stepping stone** toward this vision. It proves the LSP can run in daemon mode, but doesn't yet leverage shared state.

---

## 🏗️ **The Roadmap: Convergence in v0.3.0**

### **Phase 1: Current (v0.2.1)**
```
janus       → Standalone CLI
janusd      → UTCP Registry (+ LSP fallback)
janus-lsp   → Standalone LSP
```

### **Phase 2: v0.3.0 (Citadel Protocol)**
```
janus       → Standalone CLI (unchanged)
janusd      → Unified Daemon:
                ├── LSP Server (primary)
                ├── UTCP Registry
                ├── Shared ASTDB (Citadel)
                └── Hot-Reload Coordinator
janus-lsp   → Deprecated (use janusd --lsp)
```

**Key Changes:**
- `janusd` becomes the **primary LSP server**
- `janus query` can read **live editor state** via Citadel
- Incremental compilation shares state between CLI and LSP
- `janus-lsp` remains as **fallback** for offline/restricted environments

---

## 📐 **Design Rationale**

### **Why `janus-lsp` is Separate (For Now)**

1. **Simplicity:** LSP is **complex enough** without UTCP coupling
2. **Reliability:** Isolated process = isolated failures
3. **Development Velocity:** Can iterate on LSP without touching UTCP
4. **Deployment:** VS Code users don't need UTCP infrastructure

### **Why `janusd --lsp` Exists**

1. **Proof of Concept:** Validates LSP can run in daemon mode
2. **Testing:** Easier to test LSP in controlled daemon environment
3. **Future-Proofing:** Prepares for v0.3.0 convergence

### **Why `janus` is Separate**

1. **Zero Dependencies:** Works in air-gapped environments
2. **Fast Startup:** No daemon handshake overhead
3. **Build Tool Integration:** Makefiles, CI/CD expect stateless tools
4. **Simplicity:** One binary, one job

---

## 🎯 **Recommendation: Keep Current Architecture**

**For v0.2.x:**
- ✅ Keep all three executables
- ✅ `janus-lsp` is the **primary LSP** (VS Code uses this)
- ✅ `janusd --lsp` is **experimental** (testing only)
- ✅ `janus` remains **standalone CLI**

**For v0.3.0:**
- 🔄 Implement **Citadel Protocol** (shared ASTDB)
- 🔄 Make `janusd` the **primary LSP server**
- 🔄 Deprecate `janus-lsp` (but keep as fallback)
- ✅ Keep `janus` CLI **unchanged**

---

## 🔍 **The Confusion: Why It Feels Like Duplication**

You're right to question this! Here's why it **looks** redundant:

1. **`janusd --lsp`** and **`janus-lsp`** use **identical code** (`daemon/lsp_server.zig`)
2. Both instantiate their own ASTDB
3. Both speak JSON-RPC over stdin/stdout

**The difference:**
- **`janus-lsp`**: Optimized entry point (minimal dependencies)
- **`janusd --lsp`**: Full daemon infrastructure (UTCP, cluster, etc.)

**Why this exists:**  
`janusd --lsp` is a **transitional architecture**. It proves the LSP can run in daemon mode **before** we implement Citadel Protocol.

---

## 🚀 **Next Steps**

1. **Document this architecture** in `docs/architecture/EXECUTABLES.md`
2. **Update VS Code extension** to use `janus-lsp` (not `janusd --lsp`)
3. **Plan Citadel Protocol** for v0.3.0
4. **Deprecation notice** for `janusd --lsp` in v0.3.0

---

## 💡 **Summary**

**Current State:**
- **3 executables** serving **3 distinct use cases**
- **`janus-lsp`** is the **primary LSP** (lean, isolated)
- **`janusd --lsp`** is **experimental** (proof of concept)
- **`janus`** is the **CLI compiler** (stateless, fast)

**Future State (v0.3.0):**
- **`janusd`** becomes the **unified daemon** (LSP + UTCP + Citadel)
- **`janus-lsp`** becomes **fallback** (offline mode)
- **`janus`** remains **unchanged** (CLI compiler)

**Voxis Forge Verdict:** ⚡ **Pragmatic Evolution.**  
We're building toward the unified daemon vision, but **not rushing it**. Each executable serves a clear purpose **today**, and we'll converge them **when Citadel is ready**.
