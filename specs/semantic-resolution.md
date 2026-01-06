<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Semantic Resolution System

## Overview

The Janus Semantic Resolution System is the core engine that determines which function to call for any given call site. It embodies the doctrines of **Syntactic Honesty**, **Revealed Complexity**, and **Mechanism over Policy** by making all resolution decisions explicit and providing weaponized diagnostics for both humans and AI agents.

## Architecture

The system consists of four main components working in a pipeline:

```
CallSite → CandidateCollection → CompatibilityAnalysis → Disambiguation → ResolvedCall/Diagnostic
```

### Core Components

1. **TypeRegistry** (`type_registry.zig`)
   - Efficient type identification and comparison
   - Zero implicit coercion behavior
   - O(1) type operations with proper hashing

2. **ConversionRegistry** (`conversion_registry.zig`)
   - Explicit conversion trait system
   - Cost tracking and lossiness flags
   - Support for built-in and user-defined conversions

3. **ScopeManager** (`scope_manager.zig`)
   - Hierarchical scope management
   - Explicit import tracking
   - Visibility enforcement (private, module, public)

4. **CandidateCollector** (`candidate_collector.zig`)
   - Function discovery by name and arity
   - Visibility rule application
   - Comprehensive rejection reason tracking

5. **SemanticResolver** (`semantic_resolver.zig`)
   - Main orchestrator coordinating all phases
   - Four-phase resolution pipeline
   - Performance tracking and caching

6. **DiagnosticEngine** (`diagnostic_engine.zig`)
   - Dual-layer diagnostic generation
   - Socratic human explanations
   - Machine-readable JSON for AI agents

7. **FixSuggestionEngine** (`fix_suggestion_engine.zig`)
   - Automated fix generation
   - Confidence scoring
   - Precise edit operations

## Key Principles

### Zero Implicit Behavior
- No implicit type coercions during resolution
- All conversions must be explicitly requested
- Conversion costs are visible and documented

### Weaponized Diagnostics
- Human diagnostics teach and guide (Socratic method)
- Machine diagnostics provide actionable edit operations
- Structured error codes (S1xxx series) for programmatic handling

### Performance Guarantees
- <1ms average resolution time
- <10ms diagnostic generation time
- Memory usage proportional to candidate set size

## Usage Examples

### Basic Function Resolution

```janus
// Exact match - zero overhead
func add(a: i32, b: i32) -> i32 { return a + b; }
let result = add(2, 3); // Resolves to add(i32, i32)
```

### Explicit Conversion Required

```janus
func sqrt(x: f64) -> f64 { /* ... */ }

// This fails - no implicit conversion
let result = sqrt(4); // ERROR S1102: No matching function

// This succeeds - explicit conversion
let result = sqrt(4 as f64); // Resolves with conversion cost=5
```

### Ambiguous Resolution

```janus
func add(a: i32, b: f64) -> f64 { /* ... */ }
func add(a: f64, b: i32) -> f64 { /* ... */ }

// This fails - ambiguous
let result = add(2, 3); // ERROR S1101: Ambiguous call

// Fix suggestions provided:
// 1. add(2, 3 as f64)     // Selects first overload
// 2. add(2 as f64, 3)     // Selects second overload
```

## Diagnostic System

### Human-Friendly Diagnostics

```
Error S1101: Ambiguous call to `add` with arguments (i32, i32)

> The compiler found multiple valid functions and cannot choose between them.
> This happens when multiple functions match your call but none is more specific.

Candidates:
  (A) func add(a: i32, b: f64) -> f64  [from std.math]
  (B) func add(a: f64, b: i32) -> f64  [from std.math]

Why this is ambiguous:
  • Both functions could accept your arguments (i32, i32)
  • Function A would convert the second argument: i32 → f64
  • Function B would convert the first argument: i32 → f64
  • Both conversions have equal cost, so the compiler cannot choose

How to resolve:
  1. Cast one argument to make your intent explicit:
     add(2, 3 as f64)     // Selects candidate A
     add(2 as f64, 3)     // Selects candidate B
```

### Machine-Readable Diagnostics

```json
{
  "diagnostic": {
    "code": "S1101",
    "severity": "error",
    "message": "Ambiguous call to `add` with arguments (i32, i32)",
    "span": {
      "file": "main.jan",
      "start_line": 15,
      "start_col": 12,
      "end_line": 15,
      "end_col": 23,
      "start_byte": 342,
      "end_byte": 353
    },
    "fix_suggestions": [
      {
        "id": "cast_arg_1",
        "description": "Cast second argument to f64 (selects candidate A)",
        "confidence": 0.9,
        "edits": [
          {
            "span": { "start_byte": 350, "end_byte": 351 },
            "replacement": "3 as f64"
          }
        ]
      }
    ]
  }
}
```

## Performance Characteristics

### Resolution Performance
- **Exact Match**: O(1) lookup in function table
- **With Conversions**: O(C × P × T) where C=candidates, P=parameters, T=conversions
- **Disambiguation**: O(C log C) for sorting by specificity

### Memory Usage
- **TypeRegistry**: O(T) where T=number of types
- **ConversionRegistry**: O(C) where C=number of conversions
- **Resolution Cache**: O(R) where R=number of cached resolutions

### Diagnostic Generation
- **Human Diagnostics**: <10ms including explanation generation
- **Fix Suggestions**: <5ms for common patterns
- **JSON Serialization**: <1ms for structured output

## Integration Points

### Parser Integration
- Functions grouped into dispatch families during parsing
- AST nodes enhanced with resolution metadata
- Source location tracking for precise diagnostics

### Code Generation
- Static resolution: Direct function calls (zero overhead)
- Dynamic resolution: Optimized dispatch tables
- Conversion insertion at call sites

### IDE Integration
- Real-time diagnostic updates
- Hover information with resolution details
- Code completion using resolution context

### AI Agent API
- Batch analysis endpoints
- Fix application API with confidence thresholds
- Learning feedback mechanisms

## Testing Strategy

### Unit Tests
- Each component tested independently
- All error conditions and edge cases covered
- Performance regression tests

### Integration Tests
- Complete pipeline from parsing to diagnostics
- Cross-module resolution scenarios
- Memory leak detection

### Property-Based Tests
- Resolution determinism
- Diagnostic consistency
- Performance invariants

## Future Enhancements

### Phase 2: Advanced Features
- Cross-module dispatch optimization
- Profile-guided resolution caching
- Advanced specificity rules

### Phase 3: AI Integration
- Machine learning for fix suggestion ranking
- Automated refactoring based on resolution patterns
- Semantic search across codebases

## References

- [Semantic Resolution Specification](.kiro/specs/semantic-resolution/)
- [Dispatch Language Integration](.kiro/specs/dispatch-language-integration/)
- [Multiple Dispatch System](docs/multiple-dispatch-guide.md)
- [Development Log](.kiro/logbook.md)

The Janus Semantic Resolution System represents a new paradigm in compiler design: one that serves both human developers and AI agents with equal precision, making every error a teaching moment and every resolution decision transparent and traceable.
