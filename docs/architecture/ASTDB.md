# ASTDB: AST as Database

**Version:** v0.2.1  
**Status:** ✅ **Production Ready**

---

## 🎯 **What is ASTDB?**

ASTDB (Abstract Syntax Tree Database) is Janus's **in-memory AST query engine**. It provides a **database-like interface** for querying and analyzing parsed source code.

---

## 🏗️ **Architecture**

ASTDB treats your parsed code as a **queryable data structure**:

```
Source Code → Parser → ASTDB → Query Engine → Results
```

**Key Components:**

1. **Compilation Units** - Each `.jan` file is a unit
2. **Tokens** - Lexical tokens (keywords, identifiers, literals)
3. **Nodes** - AST nodes (expressions, statements, declarations)
4. **Edges** - Parent-child relationships between nodes
5. **Scopes** - Lexical scoping information
6. **References** - Symbol usage tracking

---

## 📊 **Data Model**

ASTDB organizes code into **columnar arrays**:

```zig
CompilationUnit {
    tokens: []Token,      // All tokens in the file
    nodes: []AstNode,     // All AST nodes
    edges: []NodeId,      // Parent-child links
    scopes: []Scope,      // Lexical scopes
    refs: []Ref,          // Symbol references
    diags: []Diagnostic,  // Errors and warnings
}
```

**Benefits:**
- **O(1) lookups** - Direct array indexing
- **Efficient filtering** - Scan specific columns
- **Type-safe IDs** - Strongly typed indices

---

## 🔍 **Query Interface**

ASTDB provides **type-safe queries** over AST data:

### **Example: Find all function declarations**

```zig
const nodes = unit.nodes;
for (nodes) |node| {
    if (node.kind == .func_decl) {
        // Process function
    }
}
```

### **Example: Find node at cursor position**

```zig
const node_id = query.findNodeAtPosition(db, unit_id, line, column, allocator);
```

### **Example: Resolve symbol definition**

```zig
const location = query.resolveDefinitionLocation(db, unit_id, node_id, allocator);
```

---

## ⚡ **Performance Characteristics**

| Operation | Complexity | Notes |
|-----------|------------|-------|
| **Parse file** | O(n) | n = file size |
| **Lookup node** | O(1) | Direct array access |
| **Find children** | O(1) | Edge array slice |
| **Query by kind** | O(n) | Linear scan (fast) |
| **Position lookup** | O(log n) | Binary search on spans |

**Memory Usage:**
- ~20 KB per 1000 lines of code
- Lazy loading (only parses open files)
- Arena allocators for fast cleanup

---

## 🛠️ **LSP Integration**

ASTDB powers the Janus Language Server:

- **Hover** - Show type and documentation
- **Go to Definition (F12)** - Jump to symbol declaration
- **Find References** - Find all symbol usages
- **Diagnostics** - Real-time error reporting
- **Semantic Highlighting** - Context-aware syntax coloring

---

## 📝 **API Examples**

### **Creating an ASTDB instance**

```zig
const std = @import("std");
const astdb = @import("astdb");

var db = try astdb.AstDB.init(allocator, false);
defer db.deinit();
```

### **Parsing a file**

```zig
const parser = @import("janus_parser");

const unit_id = try parser.parseIntoAstDB(
    &db,
    "example.jan",
    source_code
);
```

### **Querying nodes**

```zig
const unit = db.getUnit(unit_id).?;
for (unit.nodes) |node| {
    std.debug.print("Node: {s}\n", .{@tagName(node.kind)});
}
```

---

## 🎓 **Design Principles**

1. **Immutable Snapshots** - AST data is read-only after parsing
2. **Arena Allocation** - Fast O(1) cleanup per compilation unit
3. **Type Safety** - Strongly typed IDs prevent index errors
4. **Lazy Loading** - Only parse files when needed
5. **Query-Oriented** - Optimized for read-heavy workloads

---

## 🔗 **Related Documentation**

- **Parser Integration:** `docs/compiler/PARSER.md`
- **LSP Server:** `docs/lsp/LSP_SERVER.md`
- **Query API:** `docs/api/QUERY_API.md`

---

## 📊 **Current Capabilities**

✅ **Single-file analysis** - Full AST for each file  
✅ **Fast queries** - O(1) node lookups  
✅ **LSP features** - Hover, Go-to-Def, Find References  
✅ **Type inference** - Basic type resolution  
✅ **UFCS support** - Method-style syntax resolution  

---

## 🚀 **Future Enhancements**

See `docs/dev/ASTDB_ROADMAP.md` for planned features.

---

**ASTDB provides the foundation for intelligent code analysis in Janus.**
