<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-astdb-schema.md — The Immutable Substrate

**Status:** COMMITTED (Monastery Freeze v0.2.1)  
**Author:** Voxis Forge  
**Date:** 2025-12-07

## Overview

We are replacing the text buffer with a **Temporal Graph-Relational Database**. This schema is designed for SQLite (local dev) and Datalog (compiler logic). It enforces the "37 Keys" at the storage layer.

The core doctrine: **"Text is a projection. The Graph is the Truth."**

---

## 1. The Core Entity: `nodes`

Every function, variable, block, and expression is a Node. It has a stable identity (UUID) that survives renaming.

```sql
CREATE TABLE nodes (
    node_id      BLOB PRIMARY KEY,          -- 16-byte UUID (The Atom's Soul)
    parent_id    BLOB REFERENCES nodes,     -- Lexical Parent
    kind         TEXT NOT NULL CHECK (      -- The primitive types
                    kind IN ('MODULE', 'FUNC', 'STRUCT', 'ENUM', 
                             'BLOCK', 'CALL', 'VAR_DECL', 'LITERAL')
                 ),
    
    -- THE LEDGER (Integrity)
    interface_cid BLOB NOT NULL,            -- BLAKE3 Hash of the Interface (Signature)
    semantic_cid  BLOB NOT NULL,            -- BLAKE3 Hash of the Implementation (Body)
    
    -- THE SAFETY DIAL (Inheritable)
    safety_mode  TEXT CHECK (
                    safety_mode IN ('CHECKED', 'OWNED', 'RAW')
                 ) DEFAULT 'CHECKED',
    
    -- TEMPORAL TRACKING
    created_at   INTEGER NOT NULL,          -- Timestamp
    deleted_at   INTEGER                    -- Soft delete for Time Travel
);

-- Index for fast traversal of the lexical tree
CREATE INDEX idx_nodes_parent ON nodes(parent_id);
```

---

## 2. The Semantic Graph: `edges`

This defines the flow. It is how we query "Who calls who?" without parsing text.

```sql
CREATE TABLE edges (
    source_id    BLOB REFERENCES nodes,
    target_id    BLOB REFERENCES nodes,
    kind         TEXT NOT NULL CHECK (
                    kind IN ('CALLS',       -- Function call
                             'IMPORTS',     -- Module dependency
                             'TYPES_AS',    -- Variable definition
                             'OWNS',        -- Memory ownership
                             'SPAWNS')      -- Actor creation
                 ),
    metadata     JSON,                      -- e.g. Call arguments
    PRIMARY KEY (source_id, target_id, kind)
);
```

---

## 3. The 37 Keys: `node_capabilities`

We do **not** store capability strings. We store **integers 0…36**.
This is a hard enum check. There is no Capability #42.

```sql
CREATE TABLE node_capabilities (
    node_id      BLOB REFERENCES nodes,
    capability   INTEGER NOT NULL CHECK (
                    capability >= 0 AND capability <= 36
                 ),
    constraint_type TEXT NOT NULL CHECK (
                    constraint_type IN ('REQUIRES', 'GRANTS', 'FORBIDS')
                 ),
    PRIMARY KEY (node_id, capability, constraint_type)
);
```

### The Canonical Mapping (0-36)

| ID | Primitive | ID | Primitive | ID | Primitive |
|---|---|---|---|---|---|
| 0 | `.fs_read` | 13 | `.alloc` | 26 | `.sys_env` |
| 1 | `.fs_write` | 14 | `.alloc_scratch` | 27 | `.sys_args` |
| 2 | `.fs_exec` | 15 | `.alloc_persist` | 28 | `.sys_hostname` |
| 3 | `.fs_metadata` | 16 | `.log_write` | 29 | `.raw_pointer` |
| 4 | `.net_connect` | 17 | `.trace_span` | 30 | `.raw_ffi` |
| 5 | `.net_listen` | 18 | `.time_monotonic` | 31 | `.reflect_ast` |
| 6 | `.net_raw` | 19 | `.time_wall` | 32 | `.reflect_comptime`|
| 7-12 | *Reserved (Net)*| 20 | `.sleep` | 33 | `.test_mock` |
| | | 21 | `.thread_spawn` | 34 | `.test_time_freeze`|
| | | 22 | `.actor_spawn` | 35 | *Reserved* |
| | | 23 | `.crypto_rng` | 36 | *Reserved* |
| | | 24 | `.crypto_sign` | | |
| | | 25 | `.crypto_verify`| | |

*(Note: Exact mapping subject to compiler enum definition in `compiler/libjanus/capability.zig`)*

---

## 4. The Text Projection: `source_spans`

We still need to show text to the human. This maps the immutable Node back to the mutable file.

```sql
CREATE TABLE source_spans (
    node_id      BLOB REFERENCES nodes,
    file_path    TEXT NOT NULL,
    start_line   INTEGER NOT NULL,
    start_col    INTEGER NOT NULL,
    end_line     INTEGER NOT NULL,
    end_col      INTEGER NOT NULL,
    
    -- If the text changes but the semantics don't, only this table updates.
    checksum     BLOB NOT NULL, -- BLAKE3 of the text span
    PRIMARY KEY (node_id)
);
```

---

## 5. Strategic Advantages

1.  **Refactoring is Metadata Update:** Renaming a function updates one row. UUID stays the same. Zero text grep.
2.  **Instant Auditing:** Query "Show me all RAW blocks touching Network" in milliseconds.
3.  **The 37 Keys are Hard Coded:** The DB rejects unknown capabilities.

## 6. Logic (std.sql)

**Note:** We do not expose SQL to the user. `std.sql` uses a type-safe `QueryBuilder` that compiles to Datalog query plans against this schema (or user data).

```janus
// Relational Algebra, not SQL Injection
let users := db.table<User>.where(.age > 18)
```
