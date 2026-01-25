# ASTDB Query Language Reference

**Version:** 0.1.0
**Status:** Implemented (Task 6 - CLI Tooling)
**Date:** 2026-01-25

## Overview

The ASTDB Query Language provides a powerful way to search and filter AST nodes in Janus source code. It supports semantic queries with predicates, boolean combinators, and property access.

## CLI Usage

```bash
# Basic syntax
janus query --expr "<expression>" [files...] [options]

# Options
--json          Output results in JSON format
--stats         Show performance statistics
--limit <n>     Maximum number of results
--no-context    Don't show source context

# Examples
janus query --expr "func" src/*.jan
janus query --expr "func and child_count >= 2" --json
janus query --expr "struct or enum" --stats
```

## Query Expressions

### Node Kind Predicates

Match AST nodes by their kind:

| Predicate | Matches | NodeKind |
|-----------|---------|----------|
| `func` | Function declarations | `func_decl` |
| `var` | Variable statements | `var_stmt` |
| `const` | Constant statements | `const_stmt` |
| `struct` | Struct declarations | `struct_decl` |
| `enum` | Enum declarations | `enum_decl` |

**Examples:**
```bash
janus query --expr "func"           # All functions
janus query --expr "struct"         # All structs
janus query --expr "var"            # All variable declarations
```

### Boolean Combinators

Combine predicates with logical operators:

| Operator | Syntax | Description |
|----------|--------|-------------|
| AND | `p1 and p2` | Both predicates must match |
| OR | `p1 or p2` | Either predicate matches |
| NOT | `not p` | Predicate must not match |
| Grouping | `(p1 or p2) and p3` | Control precedence |

**Precedence** (lowest to highest): `or`, `and`, `not`

**Examples:**
```bash
janus query --expr "func and var"           # Functions containing vars
janus query --expr "struct or enum"         # Structs or enums
janus query --expr "not func"               # Anything except functions
janus query --expr "(func or struct) and not enum"
```

### Comparison Predicates

Compare node properties:

| Property | Operators | Description |
|----------|-----------|-------------|
| `child_count` | `==`, `!=`, `<`, `<=`, `>`, `>=` | Number of child nodes |

**Examples:**
```bash
janus query --expr "func and child_count >= 5"    # Complex functions
janus query --expr "child_count == 0"             # Leaf nodes
```

### Effect Predicates (Future)

Query nodes by their effects and capabilities:

```bash
# Find functions with file system effects
janus query --expr "func where effects.contains(\"io.fs.read\")"

# Find functions requiring specific capabilities
janus query --expr "func and requires_capability(\"CapFsWrite\")"
```

> **Note:** Effect and capability predicates require semantic analysis integration. Currently returns false for all nodes. Full implementation pending semantic engine completion.

## Query Results

### Text Output (default)

```
$ janus query --expr "func" src/main.jan
🧠 Janus ASTDB Semantic Query Engine
🎯 Expression: "func"
📁 Source files: 1
📄 Analyzing: src/main.jan
✅ src/main.jan: 3 matches in 42 nodes

🧠 SEMANTIC QUERY PERFORMANCE
========================================
🎯 Matches found: 3
🔍 Nodes analyzed: 42
⏱️  Query time: 0.45ms
📈 Nodes/sec: 93333

🚀 REVOLUTIONARY SEMANTIC ANALYSIS!
```

### JSON Output (`--json`)

```json
{
  "file": "src/main.jan",
  "node_id": 5,
  "type": "node"
}
```

### Statistics Output (`--stats`)

```
📊 DETAILED QUERY STATISTICS
==================================================
🎯 Total matches:     3
🔍 Nodes analyzed:    42
⏱️  Execution time:    0.450ms
📈 Throughput:        93333 nodes/sec
🧠 Memory estimate:   2.62 KB
==================================================
⚡ EXCELLENT: Query completed under 10ms target!
```

## Predicate Reference

### Core Predicate Types

```zig
pub const Predicate = union(enum) {
    // Basic node predicates
    node_kind: NodeKind,
    node_id: NodeId,
    has_child: NodeId,

    // Declaration predicates
    decl_kind: DeclKind,

    // Boolean combinators
    and_: struct { left: *const Predicate, right: *const Predicate },
    or_: struct { left: *const Predicate, right: *const Predicate },
    not_: *const Predicate,

    // Effect/capability predicates (semantic analysis required)
    effect_contains: []const u8,
    has_effect: []const u8,
    requires_capability: []const u8,

    // Numeric comparison predicates
    node_child_count: struct { op: CompareOp, value: u32 },

    // Match-all predicate
    any: void,
};
```

### Declaration Kinds

```zig
pub const DeclKind = enum {
    function,
    variable,
    constant,
    type_alias,
    struct_type,
    enum_type,
    trait_type,
    impl_block,
};
```

### Comparison Operators

```zig
pub const CompareOp = enum {
    eq,  // ==
    ne,  // !=
    lt,  // <
    le,  // <=
    gt,  // >
    ge,  // >=
};
```

## Grammar Specification

```ebnf
query       := or_expr
or_expr     := and_expr ('or' and_expr)*
and_expr    := not_expr ('and' not_expr)*
not_expr    := 'not' primary | primary
primary     := '(' or_expr ')' | node_pred | property_pred | comparison_pred

node_pred   := 'func' | 'var' | 'const' | 'struct' | 'enum'
property_pred := identifier '.' property ('.' method '(' string ')')?
comparison_pred := identifier comparison_op number

property    := 'effects' | 'capabilities'
method      := 'contains' | 'requires'
comparison_op := '==' | '!=' | '<' | '<=' | '>' | '>='

identifier  := [a-zA-Z_][a-zA-Z0-9_]*
string      := '"' [^"]* '"'
number      := [0-9]+
```

## Performance Targets

| Query Type | P50 Target | P99 Target |
|------------|------------|------------|
| Simple (node_kind) | < 1ms | < 5ms |
| Combined (and/or) | < 5ms | < 20ms |
| Complex (effects) | < 10ms | < 50ms |

## Integration with LSP

The query engine powers LSP features:

| LSP Feature | Query |
|-------------|-------|
| Hover | `NodeAt(position)` + `TypeOf(node_id)` |
| Go to Definition | `DefOf(symbol_at_pos)` |
| Find References | `RefsOf(node_id)` |
| Diagnostics | `Diag()` |

## Future Enhancements

- **Effect Tracking**: Full semantic integration for effect queries
- **Capability Analysis**: Static capability checking
- **Cross-file Queries**: Query across multiple compilation units
- **Query Caching**: Memoization with CID-based cache keys
- **Incremental Updates**: Invalidate only affected query results

## Related Documentation

- [ASTDB Architecture](ASTDB-ARCHITECTURE.md) - Core ASTDB design
- [ASTDB Overview](ASTDB.md) - System overview
- [LSP Architecture](../teaching/LSP_ARCHITECTURE.md) - LSP integration details
