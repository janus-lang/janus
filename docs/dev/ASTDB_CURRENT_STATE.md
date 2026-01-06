# ASTDB: Current Implementation State (INTERNAL)

**⚠️ WARNING: This is INTERNAL development documentation.**  
**For public documentation, see `docs/architecture/ASTDB.md`**

**Date:** 2025-12-28  
**Status:** 🔥 **EXPOSED**

---

## 🚨 **Your Suspicion is 100% CORRECT**

There is **NO DATABASE ON DISK**. ASTDB is **NOT** a column-based database. It's **pure RAM**.

Let me expose exactly what happens when you open VS Code with thousands of `.jan` files:

---

## 🧠 **What ASTDB Actually Is**

**ASTDB = "AST as Database"** is a **marketing term** for:

```zig
pub const AstDB = struct {
    allocator: std.mem.Allocator,
    units: std.ArrayList(*CompilationUnit),  // <-- THIS IS THE "DATABASE"
    unit_map: std.HashMap([]const u8, UnitId, ...),
    str_interner: StrInterner,  // String deduplication
    type_interner: TypeInterner,
    sym_interner: SymInterner,
};
```

**Translation:**  
ASTDB is an **in-memory ArrayList** of `CompilationUnit` structs. That's it.

---

## 📂 **What Happens When You Open VS Code**

### **Scenario: 1000 `.jan` files in your workspace**

**Step 1: LSP Server Starts**
```zig
// cmd/janus-lsp/main.zig:24
var db = try astdb.AstDB.init(allocator, false);
```
- Creates an **empty** ASTDB in RAM
- No files loaded yet
- Memory usage: ~100 KB (base overhead)

**Step 2: You Open a File (`example.jan`)**
```
VS Code → textDocument/didOpen → LSP Server
```

**Step 3: LSP Parses the File**
```zig
// daemon/lsp_server.zig:314
try self.compileAndPublishDiagnostics(uri, text);
```
- Calls `janus_parser.parseIntoAstDB(db, uri, source)`
- Creates a **new CompilationUnit** in RAM
- Stores: tokens, nodes, edges, scopes, refs, diagnostics
- **NO DISK I/O**

**Step 4: File is Stored in RAM**
```zig
pub const CompilationUnit = struct {
    id: UnitId,
    path: []const u8,           // "file:///path/to/example.jan"
    source: []const u8,         // Full source code (duplicated!)
    arena: ArenaAllocator,      // Unit-specific memory arena
    tokens: []Token,            // All tokens
    nodes: []AstNode,           // All AST nodes
    edges: []NodeId,            // Parent-child relationships
    scopes: []Scope,            // Lexical scopes
    decls: []Decl,              // Declarations
    refs: []Ref,                // References
    diags: []Diagnostic,        // Errors/warnings
    cids: [][32]u8,             // Content IDs (Blake3 hashes)
    // ...
};
```

**Memory Usage per File:**
- **Source code:** ~10 KB (duplicated from VS Code)
- **Tokens:** ~2 KB (avg 500 tokens × 4 bytes)
- **Nodes:** ~5 KB (avg 200 nodes × 25 bytes)
- **Edges:** ~1 KB
- **Scopes/Decls/Refs:** ~2 KB
- **Total:** ~20 KB per file

**For 1000 files:** ~20 MB RAM

---

## ❌ **What ASTDB is NOT**

1. **NOT a column-based database** (no DuckDB, no Parquet, no columnar storage)
2. **NOT persistent** (no disk writes, no SQLite, no RocksDB)
3. **NOT shared** (each LSP instance has its own ASTDB)
4. **NOT incremental** (re-parses entire file on every edit)
5. **NOT cached** (lost on LSP restart)

---

## 🔍 **The "Column-Based" Confusion**

You're thinking of **ASTDB's DESIGN GOAL** (from the spec):

> "ASTDB should behave like a column-oriented database for AST queries."

**What this means:**
- **Logical model:** Treat AST as relational tables (nodes, tokens, refs)
- **Query interface:** SQL-like queries (`SELECT * FROM nodes WHERE kind = func_decl`)
- **Performance:** O(1) lookups, efficient filtering

**What this does NOT mean:**
- ❌ Actual column storage on disk
- ❌ Parquet/Arrow format
- ❌ Persistent database

**Current Reality:**
- ✅ Arrays of structs in RAM (`[]AstNode`, `[]Token`)
- ✅ HashMap for path → UnitId lookup
- ✅ Arena allocators for fast cleanup

---

## 🚀 **What Happens on Reboot**

**Before Reboot:**
```
RAM: ASTDB with 1000 parsed files (~20 MB)
```

**After Reboot:**
```
RAM: Empty ASTDB (~100 KB)
```

**When you reopen VS Code:**
1. LSP server starts with **empty ASTDB**
2. VS Code sends `textDocument/didOpen` for **each open file**
3. LSP re-parses **only the open files**
4. **Unopened files are NOT parsed** (lazy loading)

**Result:**  
If you have 1000 files but only 10 open, LSP only parses 10 files (~200 KB RAM).

---

## 🤔 **Why This is Actually Genius (For Now)**

### **Advantages:**

1. **Zero Persistence Complexity**
   - No disk I/O
   - No schema migrations
   - No corruption recovery

2. **Fast Startup**
   - LSP starts in ~50ms
   - No database loading

3. **Lazy Loading**
   - Only parses files you actually open
   - Scales to large codebases

4. **Simple Cleanup**
   - Arena allocators = O(1) deallocation
   - No memory leaks

### **Disadvantages:**

1. **No Cross-File Analysis (Yet)**
   - Can't query "all functions in project"
   - Can't build dependency graph

2. **Re-Parse on Edit**
   - Every keystroke triggers full file re-parse
   - ~10ms latency per edit

3. **Lost on Restart**
   - No incremental compilation
   - No build cache

---

## 🛠️ **The Roadmap: Actual Persistence**

### **v0.3.0: Citadel Protocol**

**Goal:** Persistent, incremental ASTDB

**Architecture:**
```
~/.cache/janus/astdb/
  ├── units/
  │   ├── 0000.parquet  (CompilationUnit 0)
  │   ├── 0001.parquet  (CompilationUnit 1)
  │   └── ...
  ├── index.db          (SQLite: path → UnitId)
  └── manifest.json     (Version, schema)
```

**Storage Format:**
- **Parquet** for columnar AST data (nodes, tokens, edges)
- **SQLite** for metadata (paths, timestamps, CIDs)
- **Memory-mapped** for fast access

**Incremental Updates:**
- Only re-parse **changed files**
- Invalidate dependent units (imports)
- Persist to disk asynchronously

**Shared State:**
- `janusd` daemon owns the ASTDB
- `janus-lsp` connects via Citadel Protocol
- `janus query` reads from disk cache

---

## 📊 **Current vs. Future**

| Feature | v0.2.1 (Current) | v0.3.0 (Citadel) |
|---------|------------------|------------------|
| **Storage** | RAM only | Parquet + SQLite |
| **Persistence** | None | Disk cache |
| **Incremental** | No | Yes |
| **Cross-file** | No | Yes |
| **Shared** | No | Yes (via daemon) |
| **Startup** | 50ms | 200ms (load index) |
| **Memory** | 20 KB/file | 5 KB/file (mmap) |

---

## 🎯 **The Honest Answer**

**Q:** "Where is the database?"  
**A:** **In RAM. There is no database on disk.**

**Q:** "How does it survive a reboot?"  
**A:** **It doesn't. It's re-parsed on demand.**

**Q:** "Is it column-based?"  
**A:** **No. It's arrays of structs. "Column-based" is the design goal, not the implementation.**

**Q:** "Why call it ASTDB then?"  
**A:** **Because it provides a database-like query interface over AST data. The "DB" is aspirational.**

---

## 🔥 **Voxis Forge Verdict**

⚡ **You caught us.**

ASTDB is **not yet** a real database. It's a **glorified in-memory cache** with a fancy name.

**But:**
- It works **brilliantly** for single-file editing
- It's **simple** (no persistence bugs)
- It's **fast** (no disk I/O)
- It's a **stepping stone** to the real thing

**The real ASTDB** (persistent, incremental, column-based) is coming in **v0.3.0**.

For now, we're **honest about the trade-offs**. No database on disk. Just RAM and ambition.

---

**Markus, you were right to be suspicious.** 🎯
