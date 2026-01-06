<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — Desugar Debugging Features
**Version:** 0.1.0
**Status:** Draft
**Author:** Voxis Forge
**Date:** 2025-11-13
**License:** LSL-1.0
**Epic:** :script Profile Honest Sugar
**Depends on:** SPEC-profiles-script.md, SPEC-query-engine.md, SPEC-astdb-query.md
**Compatible engines:** `janus query`, `janus desugar`, `janus migrate`

---

## 0. Purpose

The **Desugar Debugging System** is the cornerstone of Honest Sugar in the `:script` profile. It provides transparent, queryable access to the "lengthy verbose" code that lies beneath every convenience feature. Every implicit default, every type inference, every allocator injection can be examined, traced, and understood.

This document defines the complete debugging pipeline that enables the **Julia/Ruby/Python Parity** without sacrificing **Systems Language Honesty**.

---

## 1. The Core Principle: Transparent Revelation

### 1.1 What is Desugaring?

**Desugaring** is the process of revealing the explicit, verbose code that results from applying Honest Sugar defaults. It's not compilation - it's *transformation* that shows the truth beneath the haiku.

```bash
# The Haiku (script profile)
fn insert(map, key, value) { map.put(key, value)? }

# The Truth (desugared)
fn insert(alloc: Allocator, map: &mut HashMap[Any, Any], key: Any, value: Any) -> Result[Void, Error] {
    using std.mem.thread_local_arena {
        map.put(std.mem.thread_local_arena.allocator(), key, value)?;
    }
}
```

### 1.2 The Never-Lie Principle

**Every :script convenience is debuggable, overrideable, and traceable.** If you can't desugar it and see the truth, it violates the Honest Sugar doctrine.

- **Default Inference**: Every implicit type, mutability, allocator choice is queryable
- **Performance Analysis**: Every convenience feature has an explicit cost
- **Migration Paths**: Every haiku can be converted to explicit syntax
- **No Black Boxes**: No "magic" that can't be examined

---

## 2. Desugar Query Engine

### 2.1 Core Commands

```bash
# Desugar any function to show explicit costs
janus query desugar function_name

# Desugar with performance analysis
janus query desugar --performance function_name

# Desugar with migration suggestions
janus query desugar --migrate function_name

# Desugar entire file
janus query desugar --file script_file.jan
```

### 2.2 Output Formats

**Verbose Format (Default):**
```janus
# Input: :script
fn insert(map, key, value) { map.put(key, value)? }

# Desugared: :core equivalent
fn insert(alloc: Allocator, map: &mut HashMap[Any, Any], key: Any, value: Any) -> Result[Void, Error] {
    using std.mem.thread_local_arena {
        map.put(std.mem.thread_local_arena.allocator(), key, value)?;
    }
}

# Analysis:
# - Allocator: implicit thread-local arena injection
# - Types: Any variants (performance warning)
# - Mutability: inferred mutable (&mut)
# - Errors: inferred Result[Void, Error]
```

**JSON Format (API Integration):**
```json
{
  "function": "insert",
  "input": {
    "profile": "script",
    "source": "fn insert(map, key, value) { map.put(key, value)? }"
  },
  "desugared": {
    "profile": "min",
    "parameters": [
      { "name": "alloc", "type": "Allocator", "injected": true },
      { "name": "map", "type": "HashMap[Any, Any]", "inferred": true },
      { "name": "key", "type": "Any", "inferred": true },
      { "name": "value", "type": "Any", "inferred": true }
    ],
    "return_type": "Result[Void, Error]",
    "arena_injection": true
  },
  "analysis": {
    "performance_warnings": [
      {
        "code": "E4101",
        "message": "HashMap[Any, Any] variant overhead - consider explicit types",
        "suggestion": "HashMap[Str, I64] for key, I64 for value"
      }
    ],
    "safety_issues": [],
    "migration_suggestions": [
      {
        "priority": 1,
        "message": "Consider explicit HashMap[Str, I64]",
        "reason": "Eliminate Any variant overhead"
      }
    ]
  }
}
```

---

## 3. Category-Specific Debugging

### 3.1 Type Inference Analysis

**Query:** `janus query desugar --types variable_name`

```bash
# Input: :script
let x = 42
let pi = 3.14
let bucket = hashmap()

# Type Analysis Output:
Variable: x
  Inferred: I64 (from literal 42)
  Rationale: sane default for integers (90% coverage)
  
Variable: pi
  Inferred: F64 (from literal 3.14)  
  Rationale: sane default for floats (scientific computing)
  
Variable: bucket
  Inferred: HashMap[Any, Any]
  Rationale: "whatever" bucket for dynamic content
  Overrides: HashMap[Str, I64], HashMap[Str, String], etc.
```

### 3.2 Mutability Inference Analysis

**Query:** `janus query desugar --mutability function_name`

```bash
Function: process_data(items)
  Parameters: items: [Any] (inferred)
  Variables:
    result = [] (inferred mutable)
    bucket = hashmap() (inferred mutable)
  
  Mutation Analysis:
    result.append(item) -> Mutable inference
    bucket[key] = value -> Mutable inference
    
  Desugared:
    var result: [Any] = [] // explicit mutability
    var bucket: HashMap[Any, Any] = hashmap() // explicit mutability
```

### 3.3 Allocator Injection Analysis

**Query:** `janus query desugar --allocators function_name`

```bash
Function: process_data(items)
  Allocator Strategy: Thread-Local Arena
  Injection Points:
    - Top-level entry function
    - Implicit per-call-site
    
  Desugared Form:
  fn process_data(alloc: Allocator, items: [Any]) -> HashMap[Any, Any] {
    using alloc {
      var result = hashmap() // uses alloc
      for item in items {
        result[key] = value
      }
      return result
    }
  }
  
  Alternative Strategies:
    - Custom allocator: using custom_alloc
    - Explicit arena: using ArenaAllocator
    - Stack allocation: @stackAllocate
```

### 3.4 Error Handling Analysis

**Query:** `janus query desugar --errors function_name`

```bash
Function: insert(map, key, value)
  Error Strategy: Inferred Result
  Desugared:
    fn insert(alloc: Allocator, map: &mut HashMap[Any, Any], key: Any, value: Any) -> Result[Void, Error] {
      using alloc { map.put(key, value)? }
    }
  
  Alternative Strategies:
    - Explicit try/catch: try { ... } catch { ... }
    - Error propagation: return error.IoError
    - Panic on error: @panic("map.put failed")
```

---

## 4. Performance Impact Analysis

### 4.1 Automatic Performance Profiling

**Query:** `janus query performance function_name`

```bash
Function: process_data(items) -> HashMap[Any, Any]

Performance Breakdown:
┌─────────────────────────┬──────────────┬─────────────┐
│ Operation               │ Overhead     │ Alternative │
├─────────────────────────┼──────────────┼─────────────┤
│ HashMap[Any, Any]       │ 15-25%       │ HashMap[Str, I64] │
│ Thread-local arena      │ 5-10%        │ Custom allocator  │
│ I64->Any conversion     │ 3-5%         │ Explicit typing   │
│ Runtime type dispatch   │ 10-20%       │ Static dispatch   │
├─────────────────────────┼──────────────┼─────────────┤
│ Total estimated overhead│ 33-60%       │ Baseline      │
└─────────────────────────┴──────────────┴─────────────┘

Optimization Suggestions:
1. HashMap[Str, I64] → Eliminate Any variants
2. Custom allocator → Reduce thread-local overhead  
3. Explicit typing → Eliminate runtime dispatch
```

### 4.2 Memory Usage Analysis

**Query:** `janus query memory function_name`

```bash
Function: insert(map, key, value)
Memory Analysis:
  Stack allocation: 0 bytes (arena injected)
  Heap allocation: 128-256 bytes per call
  Type tags: 8-16 bytes per value
  Allocator metadata: 24-32 bytes per call

Memory Breakdown:
  ┌─────────────────┬──────────────┬─────────────┐
  │ Component       │ Per Element  │ Total (1000)│
  ├─────────────────┼──────────────┼─────────────┤
  │ Any variant tag │ 1 byte       │ 1 KB        │
  │ HashMap entry   │ 32 bytes     │ 32 KB       │
  │ Key/value pair  │ 32 bytes     │ 32 KB       │
  │ Arena metadata  │ 32 bytes     │ 32 KB       │
  ├─────────────────┼──────────────┼─────────────┤
  │ Total           │ 97 bytes     │ 97 KB       │
  └─────────────────┴──────────────┴─────────────┘

Alternative: HashMap[Str, I64] would use 24 bytes per entry
Savings: 75% reduction in memory overhead
```

---

## 5. Migration Intelligence

### 5.1 Automated Migration Planning

**Query:** `janus migrate suggest --script --target=go`

```bash
Migration Analysis: script → go
Current Function:
  fn insert(map, key, value) {
    map.put(key, value)?
  }

Migration Suggestions:
┌──────┬──────────────────────────┬─────────────┐
│ Prio │ Suggestion               │ Impact      │
├──────┼──────────────────────────┼─────────────┤
│ HIGH │ Add allocator parameter  │ Required    │
│ HIGH │ Explicit types on HashMap│ Recommended │
│ MED  │ Error handling strategy  │ Required    │
│ LOW  │ Mutability annotations   │ Optional    │
└──────┴──────────────────────────┴─────────────┘

Generated Migration:
┌─────────────────┬─────────────────────────────────┐
│ Input (script)  │ fn insert(map, key, value) {    │
│                 │   map.put(key, value)? }        │
├─────────────────┼─────────────────────────────────┤
│ Output (go)     │ fn insert(alloc: Allocator,     │
│                 │   map: &mut HashMap[Str, I64],  │
│                 │   key: Str, value: I64) ->      │
│                 │   !void {                        │
│                 │   map.put(alloc, key, value)?    │
│                 │ }                                │
└─────────────────┴─────────────────────────────────┘

Performance Impact: 40-60% faster, zero runtime overhead
```

### 5.2 Incremental Migration Support

**Query:** `janus migrate apply --suggestions=1,2 --dry-run`

```bash
Incremental Migration Plan:
┌──────┬────────────┬─────────────────────────────────┐
│ Step │ Change     │ Description                     │
├──────┼────────────┼─────────────────────────────────┤
│ 1    │ Add types  │ HashMap[Str, I64] explicitly    │
│ 2    │ Add alloc  │ First parameter becomes explicit│
│ 3    │ Error sig  │ Return type becomes explicit    │
│ 4    │ Mutability │ Mutability annotations added    │
└──────┴────────────┴─────────────────────────────────┘

Preview:
Before:
  fn insert(map, key, value) { map.put(key, value)? }

After Step 1:
  fn insert(map: HashMap[Str, I64], key: Str, value: I64) { map.put(key, value)? }

After Step 2:
  fn insert(alloc: Allocator, map: HashMap[Str, I64], key: Str, value: I64) { 
    map.put(alloc, key, value)? 
  }

All steps preserve semantic equivalence
```

---

## 6. Error Code Integration

### 6.1 Desugar-Specific Error Codes

| Code | Description | Desugar Revelation |
|------|-------------|-------------------|
| **E4101** | Any variant performance warning | `janus query desugar --types` reveals specific Any overhead |
| **E4102** | Inferred mutability ambiguity | `janus query desugar --mutability` shows usage analysis |
| **E4103** | Thread-local arena injection limit | `janus query desugar --allocators` reveals scope depth |
| **E4104** | Implicit type coercion warning | `janus query desugar --types` shows coercion chain |
| **E4105** | Migration target incompatibility | `janus migrate suggest` shows profile-specific issues |

### 6.2 Diagnostic Integration

```bash
# Compiler error with desugar hints
E4101: Any variant overhead detected in HashMap[Any, Any]
  → run `janus query desugar --performance hashmap_operation`
  → consider `HashMap[Str, I64]` for better performance
  → see migration: `janus migrate suggest --target=go`

# Help integration
$ janus help E4101
E4101: Any variant performance overhead

This warning appears when using HashMap[Any, Any] or Any variants
in performance-critical code. The Any type requires runtime type
tagging which adds 15-25% overhead.

Examples:
  Bad:   let bucket = hashmap()
  Good:  let bucket = HashMap[Str, I64]()

Debug Commands:
  janus query desugar --types bucket
  janus query performance bucket
  janus migrate suggest --target=go
```

---

## 7. Integration with ASTDB

### 7.1 Query Engine Integration

The Desugar Debugging System is built on top of the ASTDB architecture, enabling efficient queries and caching:

```sql
-- Find all functions with Any variants
SELECT function, symbol, type 
FROM astdb 
WHERE type CONTAINS 'Any' AND profile = 'script';

-- Find all thread-local arena injections
SELECT function, allocator_strategy, injection_point
FROM astdb 
WHERE allocator_strategy = 'thread_local_arena';

-- Performance-critical Any usage
SELECT function, overhead_estimate, suggestion
FROM astdb 
WHERE performance_warning = 'E4101'
ORDER BY overhead_estimate DESC;
```

### 7.2 Live Debugging Support

```bash
# Live session with desugar feedback
$ janus script --repl
> fn insert(map, key, value) { map.put(key, value)? }

[Desugar Analysis Available]
> desugar insert
# Shows: explicit allocator, HashMap[Any, Any], etc.

> performance insert  
# Shows: 40-60% overhead due to Any variants

> migrate suggest --target=go
# Shows: migration path with explicit types
```

---

## 8. IDE Integration

### 8.1 VSCode Extension Features

- **Hover Analysis**: Hover over functions to see desugar preview
- **Quick Actions**: "Desugar This Function" → opens detailed view
- **Migration Suggestions**: Inline suggestions with migration previews
- **Performance Warnings**: Real-time Any variant detection

### 8.2 LSP Protocol Extensions

```json
{
  "capabilities": {
    "desugarProvider": true,
    "performanceProvider": true,
    "migrationProvider": true
  },
  "customRequests": {
    "janus/desugar": {
      "params": {
        "function": "string",
        "format": "verbose|json|compact",
        "analysis": "types|mutability|allocators|errors|performance"
      }
    },
    "janus/performance": {
      "params": {
        "target": "function|file|module",
        "depth": "basic|detailed|exhaustive"
      }
    },
    "janus/migrate": {
      "params": {
        "source_profile": "script|min",
        "target_profile": "go|elixir|full",
        "strategy": "minimal|safe|aggressive"
      }
    }
  }
}
```

---

## 9. Implementation Architecture

### 9.1 Desugar Pipeline

```
Source (:script) → Parse → Type Inference → Desugar → Analyze → Format

                    ↓
┌─────────────────────────────────────────────────┐
│  Honest Sugar Defaults Applied:                  │
│  • I64/F64 for literals                         │
│  • HashMap[Any, Any] for dynamic containers     │
│  • Thread-local arena injection                 │
│  • Inferred mutability                          │
│  • Implicit error handling                      │
└─────────────────────────────────────────────────┘
                    ↓
              Output (:core equivalent)
```

### 9.2 Query Optimization

- **Memoization**: Cache desugar results for identical code
- **Incremental Updates**: Only re-desugar changed functions
- **ASTDB Integration**: Store desugar results in semantic database
- **Lazy Analysis**: Only compute expensive analysis when requested

### 9.3 Performance Considerations

- **Desugar Cache**: Sub-millisecond response for cached functions
- **Background Analysis**: Performance analysis runs asynchronously
- **Incremental Updates**: Only analyze changed AST nodes
- **Streaming Output**: Large analyses stream results progressively

---

## 10. Success Criteria

### 10.1 Core Functionality

✅ **Desugar Transparency**: Every convenience feature reveals explicit truth
✅ **Performance Analysis**: Accurate overhead estimation with actionable suggestions  
✅ **Migration Intelligence**: Clear paths from :script to production profiles
✅ **Zero Black Boxes**: No "magic" that can't be debugged or understood

### 10.2 Developer Experience

✅ **Intuitive Commands**: `janus query desugar function_name` feels natural
✅ **Rich Output**: Verbose, JSON, and compact formats for different use cases
✅ **IDE Integration**: Hover, quick actions, and inline suggestions
✅ **Educational Value**: Learn systems programming through transparent revelation

### 10.3 Performance Targets

- **Desugar Query**: <10ms for 90% of functions
- **Performance Analysis**: <100ms for complex functions  
- **Migration Suggestions**: <50ms generation time
- **IDE Hover**: <5ms for inline previews

---

## 11. Philosophical Integration

### 11.1 The Gateway Drug Respect

The Desugar Debugging System honors the **Honest Sugar** philosophy:

> **"We lure with haiku, respect with truth, and empower with choice."**

- **Lure**: :script feels like Julia/Ruby/Python
- **Respect**: Every convenience shows its explicit cost
- **Empower**: Developers can choose to optimize or accept trade-offs

### 11.2 Systems Language Integrity

No compromise on **Systems Language Honesty**:

- Every allocation is visible
- Every type is explicable
- Every performance impact is measurable
- Every migration path is clear

**The Promise**: Dynamic language developers get the comfort they want with the honesty they need. Systems language developers get the transparency they demand.

---

**THE DESUGAR DEBUGGING SYSTEM IS THE GUARANTEE THAT HONEST SUGAR IS NEVER DISHONEST.**
