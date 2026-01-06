<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# ASTDB Architecture Guide

**Status:** Normative  
**Audience:** Compiler contributors, AI assistants, semantic analysis implementers  
**Purpose:** Define the architecturally pure way to interact with ASTDB

---

## 🎯 The Core Philosophy

> **The AST is not a tree you walk—it's a database you query.**

Traditional compilers use pointer-based trees with recursive traversal. Janus uses **columnar storage** with **pure, memoized queries**. This paradigm shift enables:

- **Perfect incremental compilation** (CID-based invalidation)
- **Sub-10ms IDE responses** (memoized queries)
- **Zero memory leaks** (arena allocation, O(1) teardown)
- **Deterministic builds** (immutable snapshots)

---

## 📐 The Three-Layer Architecture

```
┌─────────────────────────────────────┐
│   Query Engine (query.zig)          │  ← High-level semantic queries
│   Q.TypeOf, Q.IROf, Q.Dispatch      │     (Memoized, CID-based)
├─────────────────────────────────────┤
│   Accessor Layer (accessors.zig)    │  ← Schema/View abstraction
│   getBinaryOpLeft, getFunctionBody  │     (Pure functions, no state)
├─────────────────────────────────────┤
│   Storage Engine (core.zig)         │  ← Columnar tables, stable IDs
│   Table<NodeId>, Vec<NodeId>        │     (Arena-allocated, immutable)
└─────────────────────────────────────┘
```

### **Layer 1: Storage Engine (`compiler/astdb/core.zig`)**

**Responsibility:** Columnar data storage with stable IDs.

```zig
pub const AstDB = struct {
    tokens: ArrayList(Token),      // Table<TokenId, ...>
    nodes: ArrayList(AstNode),      // Table<NodeId, ...>
    edges: ArrayList(NodeId),       // Flattened children array
    scopes: ArrayList(Scope),       // Table<ScopeId, ...>
    decls: ArrayList(Decl),         // Table<DeclId, ...>
    refs: ArrayList(Ref),           // Table<RefId, ...>
};

pub const AstNode = struct {
    kind: NodeKind,
    first_token: TokenId,
    last_token: TokenId,
    child_lo: u32,  // Index into edges array
    child_hi: u32,
};
```

**Key Properties:**
- **Immutable:** Once created, never mutated
- **Columnar:** Data organized by column (all `kind` fields together)
- **Stable IDs:** NodeId remains valid within a snapshot
- **Arena-backed:** O(1) cleanup when snapshot released

**DO NOT:**
- ❌ Expose raw `children[0]` indexing to consumers
- ❌ Mutate nodes after creation
- ❌ Store pointers to nodes (use NodeId instead)

**DO:**
- ✅ Provide basic table access (`getNode`, `getChildren`)
- ✅ Maintain invariants (child_lo ≤ child_hi)
- ✅ Generate CIDs bottom-up during construction

---

### **Layer 2: Accessor Layer (`compiler/libjanus/astdb/accessors.zig`) ← YOU ARE HERE**

**Responsibility:** Map semantic structures to table queries.

This layer is **THE MISSING PIECE** in most ASTDB implementations. It defines the **schema** of how language constructs map to the columnar storage.

```zig
/// Get the left operand of a binary expression
pub fn getBinaryOpLeft(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .binary_expr) return null;
    
    const children = db.getChildren(unit_id, node_id);
    if (children.len < 2) return null;
    return children[0];  // Schema: left is child 0
}

/// Get the initializer of a variable declaration
pub fn getVariableInitializer(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .let_stmt and node.kind != .var_stmt) return null;
    
    const children = db.getChildren(unit_id, node_id);
    // Schema: [0] = name, [1] = type_annotation?, [2] = initializer?
    if (children.len >= 3) return children[2];
    if (children.len == 2) return children[1];  // No type annotation
    return null;
}
```

**Key Properties:**
- **Pure functions:** No side effects, fully deterministic
- **Schema-defining:** Encapsulates "layout knowledge"
- **Defensive:** Returns `?NodeId`, validates kinds
- **Documented:** Comments explain the schema

**DO NOT:**
- ❌ Put accessor logic in `type_inference.zig` or `symbol_resolver.zig`
- ❌ Hardcode `children[0]` in semantic analysis files
- ❌ Return raw array indices to consumers

**DO:**
- ✅ Create one accessor per semantic structure (getBinaryOpLeft, getFunctionParams, etc.)
- ✅ Validate node kinds before indexing
- ✅ Return `?NodeId` for optional children
- ✅ Document the schema (which child is what)

**Why This Matters:**
When the ASTDB schema changes (e.g., adding metadata to BinaryOp), you only update `accessors.zig`, not 47 files that hardcode `children[0]`.

---

### **Layer 3: Query Engine (`compiler/astdb/query.zig`)**

**Responsibility:** High-level semantic queries with memoization.

```zig
pub const QueryEngine = struct {
    astdb: *AstDB,
    cache: HashMap(QueryKey, CachedResult),
    
    /// Q.TypeOf - Get the type of a node
    pub fn queryTypeOf(self: *QueryEngine, node_id: NodeId) !TypeId {
        // Check memo cache
        const key = QueryKey{ .type_of = node_id };
        if (self.cache.get(key)) |cached| return cached.type_id;
        
        // Compute type (calls accessors, not raw children[])
        const type_id = try self.computeType(node_id);
        
        // Memoize result
        try self.cache.put(key, .{ .type_id = type_id });
        return type_id;
    }
};
```

**Key Properties:**
- **Memoized:** Results cached by CID tuples
- **CID-keyed:** Invalidates when semantic content changes
- **Pure:** No I/O, no mutation, fully deterministic
- **Dependency-tracking:** Salsa-style invalidation

**DO NOT:**
- ❌ Call `getChildren()` directly from queries (use accessors)
- ❌ Cache by NodeId (unstable across snapshots)
- ❌ Perform I/O or mutation in queries

**DO:**
- ✅ Cache by CID tuples
- ✅ Call accessor functions
- ✅ Track dependencies for invalidation
- ✅ Return `(result, diagnostics)` pairs

---

## 🛠️ Implementation Pattern for Semantic Analysis

### ❌ **WRONG** (Anti-pattern)

```zig
// symbol_resolver.zig - BAD!
fn resolveFunction(self: *SymbolResolver, node_id: NodeId) !void {
    const children = self.astdb.getChildren(node_id);
    const name_node = children[0];  // ← HARDCODED SCHEMA
    const params_node = children[1];  // ← BRITTLE
    // ...
}
```

**Problems:**
- Schema knowledge scattered across codebase
- Changing AST layout breaks 47 files
- No validation (index out of bounds if schema changes)
- Not query-able or memoizable

### ✅ **CORRECT** (Architecturally pure)

```zig
// accessors.zig - Schema definition
pub fn getFunctionName(db: *const AstDB, unit_id: UnitId, node_id: NodeId) ?NodeId {
    const node = db.getNode(unit_id, node_id) orelse return null;
    if (node.kind != .func_decl) return null;
    const children = db.getChildren(unit_id, node_id);
    return if (children.len > 0) children[0] else null;
}

// symbol_resolver.zig - Clean consumer
fn resolveFunction(self: *SymbolResolver, node_id: NodeId) !void {
    const name_node = accessors.getFunctionName(self.astdb, self.unit_id, node_id) 
        orelse return error.MalformedAST;
    // ...
}
```

**Benefits:**
- Schema isolated in one file
- Type-safe, validated access
- Can be upgraded to memoized query later
- Clear semantic intent

---

## 📋 Checklist for Adding New Semantic Analysis

When implementing a new semantic analysis module (type inference, borrow checking, etc.):

1. **✅ DO:** Create accessors in `compiler/astdb/accessors.zig` for all AST structures you need
2. **✅ DO:** Import accessors via `const accessors = @import("accessors.zig")`
3. **✅ DO:** Call `accessors.getFoo()` instead of `getChildren()[0]`
4. **✅ DO:** Document your accessor functions with schema comments
5. **❌ DON'T:** Hardcode `children[0]` in your semantic analysis file
6. **❌ DON'T:** Store `*AstNode` pointers (use NodeId)
7. **❌ DON'T:** Mutate the ASTDB
8. **❌ DON'T:** Cache by NodeId (use CID for memoization)

---

## 🔄 Migration Path for Existing Code

### Step 1: Audit for `getChildren()` calls
```bash
rg "getChildren\(" compiler/semantic/
```

### Step 2: Extract accessors
For each pattern like `getChildren()[0]`, create an accessor:
```zig
// Before (scattered):
const left = self.astdb.getChildren(node_id)[0];
const right = self.astdb.getChildren(node_id)[1];

// After (centralized):
const left = accessors.getBinaryOpLeft(self.astdb, self.unit_id, node_id)?;
const right = accessors.getBinaryOpRight(self.astdb, self.unit_id, node_id)?;
```

### Step 3: Replace call sites
```zig
// Old:
const children = self.astdb.getChildren(node_id);
const name = children[0];

// New:
const name = accessors.getFunctionName(self.astdb, self.unit_id, node_id) 
    orelse return error.MalformedAST;
```

---

## 🎓 For AI Assistants

When implementing semantic analysis for Janus:

1. **First:** Check if `compiler/astdb/accessors.zig` exists
2. **If not:** Create it following this guide
3. **Always:** Add accessors for new AST structures
4. **Never:** Hardcode `children[0]` outside `accessors.zig`
5. **Remember:** The ASTDB is a database, not a tree

**Common mistake:** Treating ASTDB like a traditional AST with pointer walking.  
**Correct approach:** Query the database through the accessor layer.

---

## 📚 Further Reading

- `docs/specs/SPEC-astdb-query.md` - Canonical ASTDB specification
- `docs/PARADIGM-SHIFT.md` - Perfect incremental compilation architecture
- `compiler/astdb/core.zig` - Storage engine implementation
- `compiler/astdb/query.zig` - Query engine implementation

---

**TL;DR:** Don't walk the AST. Query the database. Use accessors, not array indices.
