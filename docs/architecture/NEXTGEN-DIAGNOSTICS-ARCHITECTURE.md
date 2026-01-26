<!--
---
title: "Next-Generation Diagnostics Architecture"
description: "Implementation architecture for the probabilistic multi-hypothesis diagnostic system"
author: "Janus Compiler Team"
date: 2026-01-25
license: |
  SPDX-License-Identifier: LCL-1.0
  Copyright (c) 2026 Self Sovereign Society Foundation
version: 1.0.0
---
-->

# Next-Generation Diagnostics Architecture

## Overview

This document describes the implementation architecture of the Janus Next-Generation Error Handling System, a diagnostic infrastructure that treats errors as probabilistic hypotheses within a semantic web.

---

## System Architecture

```
+---------------------------------------------------------------------+
|                     DIAGNOSTIC ORCHESTRATOR                         |
|                   (NextGenDiagnosticEngine)                         |
+---------------------------------------------------------------------+
         |              |              |              |
         v              v              v              v
+----------------+ +----------------+ +----------------+ +----------------+
|  HYPOTHESIS    | |  TYPE FLOW     | |  SEMANTIC      | |  FIX LEARNING  |
|  ENGINE        | |  ANALYZER      | |  CORRELATOR    | |  ENGINE        |
|                | |                | |                | |                |
| Multi-cause    | | Inference      | | CID-based      | | Track accepted |
| probability    | | chain viz      | | change detect  | | fixes, improve |
+----------------+ +----------------+ +----------------+ +----------------+
         |              |              |              |
         v              v              v              v
+---------------------------------------------------------------------+
|                 UNIFIED DIAGNOSTIC DATA MODEL                       |
|  (NextGenDiagnostic with hypotheses, type flow, correlations)       |
+---------------------------------------------------------------------+
         |                                            |
         v                                            v
+---------------------------+          +---------------------------+
|    HUMAN OUTPUT LAYER     |          |   MACHINE OUTPUT LAYER    |
|                           |          |                           |
| - Terminal formatting     |          | - JSON serialization      |
| - Multi-hypothesis view   |          | - AI-native schema        |
| - Type flow visualization |          | - Structured data         |
+---------------------------+          +---------------------------+
```

---

## Component Details

### 1. NextGenDiagnosticEngine

**File:** `compiler/libjanus/diagnostic_engine.zig`

The orchestrator that integrates all diagnostic subsystems:

```zig
pub const NextGenDiagnosticEngine = struct {
    allocator: Allocator,
    config: NextGenConfig,

    // Sub-engines
    hypothesis_engine: HypothesisEngine,
    type_flow_analyzer: TypeFlowAnalyzer,
    type_flow_recorder: TypeFlowRecorder,
    semantic_correlator: SemanticCorrelator,
    fix_learning_engine: FixLearningEngine,

    // Legacy engine for fallback
    legacy_engine: DiagnosticEngine,

    // Diagnostic counter
    next_diagnostic_id: u64,
};
```

**Key Methods:**
- `generateFromResolveResult()` - Main entry point for resolution errors
- `generateTypeMismatchDiagnostic()` - Type error with full flow
- `recordFixAcceptance()` - Feed learning system
- `reset()` - Clear state for new compilation

### 2. Hypothesis Engine

**File:** `compiler/libjanus/hypothesis_engine.zig`

Generates multiple probabilistic explanations for errors:

```zig
pub const HypothesisEngine = struct {
    allocator: Allocator,
    config: HypothesisConfig,
    next_hypothesis_id: u32,
};
```

**Hypothesis Generation Pipeline:**

1. **Typo Detection** - Levenshtein distance against available symbols
2. **Conversion Analysis** - Check for available type conversions
3. **Import Suggestions** - Speculative missing imports
4. **Argument Reordering** - Detect swapped arguments
5. **Undefined Detection** - Suggest defining new symbols

**Probability Calculation:**
```
probability = base + (evidence_weight * 0.3) - (counter_evidence_weight * 0.3)
```

### 3. Type Flow Analyzer

**File:** `compiler/libjanus/type_flow_analyzer.zig`

Tracks and visualizes the complete type inference chain:

```zig
pub const TypeFlowAnalyzer = struct {
    allocator: Allocator,
    config: TypeFlowConfig,
};

pub const TypeFlowRecorder = struct {
    allocator: Allocator,
    events: ArrayList(TypeFlowEvent),
    config: TypeFlowConfig,
    next_timestamp: u64,
    enabled: bool,
};
```

**Integration Pattern:**

```zig
// During type inference, record each step
try ctx.recordInference(
    line,
    column,
    node_cid,
    type_before,
    type_after,
    .function_return,
    "process(data)",
);

// When error occurs, build chain
var chain = try analyzer.buildChain(&recorder, expected, actual);
```

**Divergence Detection:**
The analyzer identifies where the inference chain diverged from the expected type, enabling precise error localization.

### 4. Semantic Correlator

**File:** `compiler/libjanus/semantic_correlator.zig`

Uses BLAKE3 CIDs to detect semantic changes:

```zig
pub const SemanticCorrelator = struct {
    allocator: Allocator,
    config: CorrelationConfig,
    history: CIDHistory,
    active_diagnostics: ArrayList(ActiveDiagnostic),
    cascades: AutoHashMap(DiagnosticId, ArrayList(DiagnosticId)),
};
```

**Change Detection Flow:**

```
┌─────────────────┐     ┌─────────────────┐
│  Previous CID   │     │   Current CID   │
│  7f3a...2b1c    │ --> │   9d4e...8f2a   │
└─────────────────┘     └─────────────────┘
         │                       │
         v                       v
┌─────────────────────────────────────────┐
│           CID Comparison                │
│     (BLAKE3 deterministic hash)         │
└─────────────────────────────────────────┘
                    │
                    v
┌─────────────────────────────────────────┐
│         SemanticChange Detected         │
│  - entity_name: UserProfile             │
│  - change_type: signature_changed       │
│  - old_signature: { name, age }         │
│  - new_signature: { name, age, email }  │
└─────────────────────────────────────────┘
```

**Cascade Detection Algorithm:**
1. Track affected entities for each diagnostic
2. When new diagnostic registered, check for entity overlap
3. If overlap exists, mark as potential cascade
4. Identify root cause by finding earliest/most-causing diagnostic

### 5. Fix Learning Engine

**File:** `compiler/libjanus/fix_learning.zig`

Tracks user preferences to improve suggestions:

```zig
pub const FixLearningEngine = struct {
    allocator: Allocator,
    config: LearningConfig,
    error_patterns: AutoHashMap(u64, ErrorPatternStats),
    preferences: UserPreferences,
    recent_acceptances: ArrayList(FixAcceptance),
    total_suggestions: u64,
    total_acceptances: u64,
};
```

**Learning Flow:**

```
                ┌─────────────────────┐
                │   Error Occurs      │
                └──────────┬──────────┘
                           │
                           v
                ┌─────────────────────┐
                │  Generate Fixes     │
                │  (with base conf.)  │
                └──────────┬──────────┘
                           │
         ┌─────────────────┼─────────────────┐
         v                 v                 v
   ┌───────────┐    ┌───────────┐    ┌───────────┐
   │  Fix A    │    │  Fix B    │    │  Fix C    │
   │  conf=0.7 │    │  conf=0.5 │    │  conf=0.3 │
   └─────┬─────┘    └─────┬─────┘    └─────┬─────┘
         │                │                │
         v                v                v
   ┌─────────────────────────────────────────────┐
   │        Apply Historical Adjustment          │
   │   adjusted = base + (acceptance_rate * 0.2) │
   └─────────────────────────────────────────────┘
         │                │                │
         v                v                v
   ┌───────────┐    ┌───────────┐    ┌───────────┐
   │  Fix A    │    │  Fix B    │    │  Fix C    │
   │  adj=0.7  │    │  adj=0.7  │    │  adj=0.3  │
   │  (no hist)│    │  (+0.2)   │    │  (no hist)│
   └───────────┘    └───────────┘    └───────────┘
```

**Preference Detection:**
- `prefers_explicit_casts` - User tends to accept cast fixes
- `prefers_qualified_names` - User prefers qualified over imports
- `prefers_inline_fixes` - User prefers single-file changes

---

## Data Flow

### Error Generation Pipeline

```
┌─────────────────────────────────────────────────────────────────────┐
│                      COMPILATION PHASE                              │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                                v
┌─────────────────────────────────────────────────────────────────────┐
│                    SEMANTIC RESOLUTION                              │
│  - Record type flow events                                          │
│  - Track CID changes                                                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ (error occurs)
                                v
┌─────────────────────────────────────────────────────────────────────┐
│               NextGenDiagnosticEngine.generate*()                   │
└───────────────────────────────┬─────────────────────────────────────┘
        ┌───────────────────────┼───────────────────────┐
        v                       v                       v
┌───────────────┐    ┌───────────────────┐    ┌─────────────────┐
│  Hypothesis   │    │   Type Flow       │    │   Semantic      │
│  Engine       │    │   Analyzer        │    │   Correlator    │
└───────┬───────┘    └─────────┬─────────┘    └────────┬────────┘
        │                      │                       │
        v                      v                       v
┌─────────────────────────────────────────────────────────────────────┐
│                    NextGenDiagnostic Assembly                       │
│  - Combine hypotheses, type flow, correlations                      │
│  - Rank fix suggestions with learning adjustment                    │
│  - Generate human and machine output                                │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
        ┌───────────────────────┼───────────────────────┐
        v                       v                       v
┌───────────────┐    ┌───────────────────┐    ┌─────────────────┐
│    Human      │    │      JSON         │    │   Learning      │
│    Output     │    │      Export       │    │   Recording     │
└───────────────┘    └───────────────────┘    └─────────────────┘
```

---

## Integration Points

### With Semantic Resolver

```zig
// In semantic_resolver.zig
pub fn resolve(self: *SemanticResolver, call_site: CallSite) ResolveResult {
    // ... resolution logic ...

    // Record type flow during resolution
    if (self.type_flow_context) |ctx| {
        try ctx.recordInference(...);
    }

    return result;
}
```

### With ASTDB CID System

```zig
// In semantic_correlator.zig
pub fn recordChange(self: *SemanticCorrelator, snapshot: CIDSnapshot) !void {
    // Uses BLAKE3 CIDs from astdb/libjanus_cid.zig
    try self.history.recordCID(snapshot);
}
```

### With Type Registry

```zig
// In hypothesis_engine.zig
fn generateTypeMismatchHypotheses(
    self: *HypothesisEngine,
    expected: TypeId,  // From type_registry.zig
    actual: TypeId,
    context: ErrorContext,
) ![]Hypothesis
```

---

## Configuration

### NextGenConfig

```zig
pub const NextGenConfig = struct {
    /// Enable multi-hypothesis analysis
    enable_hypotheses: bool = true,
    /// Enable type flow visualization
    enable_type_flow: bool = true,
    /// Enable semantic correlation (CID-based)
    enable_correlation: bool = true,
    /// Enable fix learning
    enable_learning: bool = true,
    /// Maximum hypotheses to generate
    max_hypotheses: u32 = 5,
};
```

### Component Configs

Each subsystem has its own configuration:

- `HypothesisConfig` - Typo detection, max edit distance
- `TypeFlowConfig` - Max chain length, simplification
- `CorrelationConfig` - Time window, cascade detection
- `LearningConfig` - Persistence, pattern limits

---

## Memory Management

### Allocation Strategy

All components use explicit allocator passing:

```zig
pub fn init(allocator: Allocator) NextGenDiagnosticEngine {
    return .{
        .allocator = allocator,
        .hypothesis_engine = HypothesisEngine.init(allocator),
        .type_flow_analyzer = TypeFlowAnalyzer.init(allocator),
        // ...
    };
}
```

### Cleanup Pattern

```zig
pub fn deinit(self: *NextGenDiagnosticEngine) void {
    self.hypothesis_engine.deinit();
    self.type_flow_analyzer.deinit();
    self.type_flow_recorder.deinit();
    self.semantic_correlator.deinit();
    self.fix_learning_engine.deinit();
}
```

### Diagnostic Lifetime

Diagnostics own their data and must be deinitialized:

```zig
var diag = try engine.generateTypeMismatchDiagnostic(...);
defer diag.deinit();

// Use diagnostic...
```

---

## Output Formats

### Terminal Output

```
error[S1102]: No matching function for `calculate` with arguments (i32, f64)
  --> math.jan:42:15

  Most likely causes:

  [78%] Missing conversion: Argument 2 needs explicit cast
        Evidence: Function signature at math.jan:10:1
        Fix: calculate(x, y as i32)

  [15%] Wrong function: Did you mean `calculateF`?
        Evidence: Similar name, matching second argument type
        Fix: calculateF(x as f32, y)

  [7%]  Missing import: calculate(i32, f64) may exist in std.math
```

### JSON Output

```json
{
  "schema_version": 1,
  "code": "S1102",
  "severity": "error",
  "location": {"file": "math.jan", "line": 42, "column": 15},
  "summary": "No matching function for `calculate` with arguments (i32, f64)",
  "hypothesis_count": 3,
  "primary_hypothesis": {
    "probability": 0.78,
    "category": "missing_conversion"
  },
  "is_cascade_effect": false
}
```

---

## Performance Considerations

### Lazy Evaluation

- Type flow recording only when enabled
- Hypotheses generated on-demand
- Correlation checks batched

### Caching

- CID computation cached in CIDCache
- Error pattern hashes memoized
- Fix pattern statistics persisted

### Memory Limits

- Max hypothesis count: 5 (configurable)
- Max chain length: 20 steps
- Max patterns: 10,000

---

## Testing Strategy

### Unit Tests

Each component has comprehensive unit tests:

```zig
test "HypothesisEngine generates typo hypotheses" { ... }
test "TypeFlowAnalyzer detects divergence" { ... }
test "SemanticCorrelator detects cascades" { ... }
test "FixLearningEngine adjusts confidence" { ... }
```

### Integration Tests

Test the full pipeline:

```zig
test "NextGenDiagnosticEngine type mismatch diagnostic" {
    var engine = NextGenDiagnosticEngine.init(allocator);
    defer engine.deinit();

    var diag = try engine.generateTypeMismatchDiagnostic(...);
    defer diag.deinit();

    try testing.expect(diag.hypotheses.len > 0);
}
```

---

## Future Enhancements

### Planned Features

1. **Interactive Explorer** - REPL interface for debugging errors
2. **Cross-File Correlation** - Track changes across module boundaries
3. **Machine Learning** - Neural network for pattern recognition
4. **IDE Integration** - Language server protocol support
5. **Historical Analysis** - Project-wide error trending

### Extension Points

- Custom hypothesis generators
- Pluggable evidence providers
- Custom fix suggestion strategies
- Alternative output formatters

---

## References

- [SPEC-nextgen-diagnostics](../specs/SPEC-nextgen-diagnostics.md) - Formal specification
- [ASTDB Architecture](./ASTDB-ARCHITECTURE.md) - CID system details
- [Rust Diagnostics](https://doc.rust-lang.org/nightly/nightly-rustc/rustc_errors/) - Prior art comparison
