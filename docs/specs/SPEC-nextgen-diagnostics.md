<!--
---
title: "SPEC: Next-Generation Error Handling System"
description: "Probabilistic multi-hypothesis diagnostic system with type flow visualization and semantic correlation"
author: "Janus Compiler Team"
date: 2026-01-25
license: |
  SPDX-License-Identifier: LCL-1.0
  Copyright (c) 2026 Self Sovereign Society Foundation
version: 1.0.0
---
-->

# SPEC-nextgen-diagnostics: Next-Generation Error Handling System

**Status:** Normative
**Version:** 1.0.0
**Classification:** 🜏 Constitution
**Authority:** Janus Compiler Team
**Profile:** :core

---

## 1. Abstract

[DIAG-01] **informative** This specification defines a diagnostic system that treats errors as **probabilistic hypotheses within a semantic web**. Unlike traditional compilers that report single error causes, this system generates multiple ranked hypotheses, visualizes type inference chains, correlates errors with semantic changes, and learns from user fix acceptance patterns.

[DIAG-02] **informative** The system surpasses current state-of-the-art (including Rust's diagnostic system) through:
- Multi-hypothesis diagnosis with probability scoring
- Complete type flow visualization with divergence detection
- CID-based semantic change correlation
- Cascade error grouping with root cause identification
- AI-native structured output for automated fixing
- Fix learning system that improves over time

---

## 2. Normative References

[DIAG-03] **informative** This specification references:
- RFC 2119 for normative language (MUST, SHOULD, MAY)
- SPEC-semantics for core semantic definitions
- SPEC-profiles for profile-specific behavior
- BLAKE3 specification for content-addressed hashing

---

## 3. Terminology

[DIAG-04] **informative** The following terms have specific meanings in this specification:

| Term | Definition |
|------|------------|
| **Hypothesis** | A probabilistic explanation for an error cause |
| **CID** | Content Identifier - 32-byte BLAKE3 hash of semantic content |
| **Type Flow Chain** | Sequence of inference steps leading to a type |
| **Divergence Point** | Location where inferred type differs from expected |
| **Cascade Error** | Error caused by another error (not a root cause) |
| **Evidence** | Supporting or refuting information for a hypothesis |

---

## 4. Diagnostic Code Taxonomy

### 4.1 Phase Prefixes

[DIAG-05] **legality-rule** All diagnostic codes MUST use the following phase prefixes:

| Prefix | Phase | Description |
|--------|-------|-------------|
| L | Lexer | Tokenization errors (L0xxx) |
| P | Parser | Syntax errors (P0xxx) |
| S | Semantic | Semantic analysis errors (S0xxx) |
| C | CodeGen | Code generation errors (C0xxx) |
| K | Linker | Linking errors (K0xxx) |
| W | Warning | Non-fatal warnings (W0xxx) |
| I | Info | Informational hints (I0xxx) |

### 4.2 Semantic Error Subcategories

[DIAG-06] **legality-rule** Semantic errors (S prefix) MUST be organized into subcategories:

| Range | Category | Description |
|-------|----------|-------------|
| S1xxx | Dispatch & Resolution | Function overload resolution |
| S2xxx | Type Inference | Type system errors |
| S3xxx | Effect System | Capability violations |
| S4xxx | Module & Import | Module system errors |
| S5xxx | Pattern Matching | Match expression errors |
| S6xxx | Lifetime & Memory | Resource management errors |

### 4.3 Core Error Codes

[DIAG-07] **legality-rule** The following error codes are defined:

**Dispatch & Resolution (S1xxx):**
- S1101: Ambiguous function dispatch
- S1102: No matching function
- S1103: Internal resolution error
- S1104: Visibility violation in dispatch

**Type Inference (S2xxx):**
- S2001: Type mismatch
- S2002: Type inference failed
- S2003: Generic constraint violated
- S2004: Type flow diverged

**Effect System (S3xxx):**
- S3001: Required capability not available
- S3002: Effect escapes handler
- S3003: Purity violation
- S3004: Unhandled effect

---

## 5. Multi-Hypothesis System

### 5.1 Hypothesis Structure

[DIAG-08] **legality-rule** Each hypothesis MUST contain:

```
Hypothesis := {
    id:               HypothesisId,
    cause_category:   CauseCategory,
    probability:      Float32,        // 0.0 to 1.0
    explanation:      String,
    evidence:         []Evidence,
    counter_evidence: []Evidence,
    targeted_fixes:   []FixSuggestion
}
```

[DIAG-09] **dynamic-semantics** The probability field represents the system's confidence that this hypothesis explains the error. Probabilities across all hypotheses for a single error SHOULD sum to 1.0.

### 5.2 Cause Categories

[DIAG-10] **legality-rule** The following cause categories are defined:

| Category | Description |
|----------|-------------|
| type_mismatch | Type does not match expected |
| missing_conversion | No conversion path exists |
| generic_constraint_violation | Generic constraint not satisfied |
| typo | Possible typo in identifier |
| wrong_import | Wrong module imported |
| visibility_error | Symbol not visible in scope |
| missing_argument | Required argument not provided |
| wrong_argument_order | Arguments in wrong order |
| missing_capability | Required capability not available |
| effect_leak | Effect escapes its handler |
| ambiguous_dispatch | Multiple candidates match equally |
| changed_dependency | Dependency signature changed |

### 5.3 Evidence System

[DIAG-11] **legality-rule** Evidence MUST include:
- `evidence_type`: Supporting or refuting classification
- `description`: Human-readable explanation
- `location`: Optional source location
- `strength`: Float32 weight (0.0 to 1.0)

[DIAG-12] **dynamic-semantics** Supporting evidence types:
- `signature_match`: Function signature matches
- `name_similarity`: Name is similar (edit distance)
- `conversion_available`: Type conversion exists
- `pattern_match`: Pattern recognized
- `historical_fix`: Previously accepted fix pattern

[DIAG-13] **dynamic-semantics** Refuting evidence types:
- `type_incompatible`: Types cannot be converted
- `visibility_blocked`: Symbol not accessible
- `constraint_violated`: Generic constraint fails
- `arity_wrong`: Wrong number of arguments

### 5.4 Probability Calculation

[DIAG-14] **dynamic-semantics** Hypothesis probability MUST be calculated as:

```
probability = clamp(0.01, 0.99,
    base_probability
    + sum(evidence.strength * 0.3)
    - sum(counter_evidence.strength * 0.3)
)
```

[DIAG-15] **legality-rule** After calculation, probabilities MUST be normalized so they sum to 1.0.

---

## 6. Type Flow Visualization

### 6.1 Inference Step Structure

[DIAG-16] **legality-rule** Each inference step MUST record:

```
InferenceStep := {
    location:          SourceSpan,
    node_cid:          CID,          // 32-byte BLAKE3 hash
    type_before:       ?TypeId,
    type_after:        TypeId,
    reason:            InferenceReason,
    constraint_source: ?SourceSpan,
    expression_text:   String
}
```

### 6.2 Inference Reasons

[DIAG-17] **legality-rule** The following inference reasons are defined:

| Reason | Description |
|--------|-------------|
| literal_value | Type from literal (42 -> i32) |
| explicit_annotation | User annotation (x: i32) |
| function_parameter | From function signature |
| function_return | Return type of called function |
| variable_binding | From let binding |
| generic_instantiation | Generic parameter bound |
| expected_type | Type expected by context |
| coercion | Implicit coercion applied |

### 6.3 Type Flow Chain

[DIAG-18] **legality-rule** A type flow chain MUST include:
- `steps`: Ordered sequence of inference steps
- `divergence_point`: Index where inference diverged (if any)
- `expected_type`: The type expected at error site
- `actual_type`: The type actually inferred

[DIAG-19] **dynamic-semantics** The divergence point is the first step where `type_after` differs from `expected_type`.

### 6.4 Example Output

[DIAG-20] **informative** Type flow visualization example:

```
error[S2001]: Type mismatch - expected i32, found f64
  --> process.jan:55:20

   Type flow chain:

   1. data: [f64; 10]        (literal at line 50)
   2. process(data) -> f64   (return type, lib.jan:120)
   3. result: f64            (inferred)
   4. use_result(result)     (expects i32)  <-- DIVERGENCE

   Suggestion: Cast result, use f64 version, or change data type
```

---

## 7. Semantic Correlation System

### 7.1 CID-Based Change Detection

[DIAG-21] **legality-rule** The semantic correlator MUST:
1. Maintain historical CID snapshots for tracked entities
2. Detect when entity CIDs change between compilations
3. Correlate errors with recent semantic changes

[DIAG-22] **dynamic-semantics** A semantic change is detected when:
- An entity's current CID differs from its previous CID
- The change occurred within the configured time window

### 7.2 Change Types

[DIAG-23] **legality-rule** The following change types are recognized:

| Type | Description |
|------|-------------|
| signature_changed | Function/method signature modified |
| type_changed | Type definition modified |
| removed | Symbol was removed |
| renamed | Symbol was renamed |
| visibility_changed | Access level changed |
| moved | Symbol relocated to different module |

### 7.3 Cascade Detection

[DIAG-24] **dynamic-semantics** Cascade errors are identified when:
- Multiple errors share affected entities
- One error's affected entities overlap with another's
- Temporal ordering suggests causation

[DIAG-25] **legality-rule** The diagnostic system MUST identify root cause errors and mark cascade effects, presenting root causes first.

### 7.4 Example Output

[DIAG-26] **informative** Semantic correlation example:

```
error[S1102]: No matching overload for `serialize` with (UserProfile)
  --> api.jan:88:5

   Correlated changes detected:

   CHANGED: UserProfile struct (2026-01-25 14:32:05)
     - Before: { name: string, age: i32 }
     - After:  { name: string, age: i32, email: Option<string> }
     - CID: 7f3a...2b1c -> 9d4e...8f2a

   UNCHANGED: serialize(UserProfile) implementation
     - This expects the OLD UserProfile shape
```

---

## 8. Fix Suggestion System

### 8.1 Fix Suggestion Structure

[DIAG-27] **legality-rule** Each fix suggestion MUST contain:

```
FixSuggestion := {
    id:                 String,
    description:        String,
    confidence:         Float32,      // 0.0 to 1.0
    edits:              []TextEdit,
    hypothesis_id:      ?HypothesisId,
    acceptance_rate:    Float32,      // Historical rate
    requires_user_input: Bool
}
```

### 8.2 Ranked Suggestions

[DIAG-28] **dynamic-semantics** Fix suggestions MUST be ranked by:
```
score = confidence * hypothesis_probability * (1 + acceptance_rate * 0.2)
```

[DIAG-29] **legality-rule** Suggestions MUST be presented in descending score order.

---

## 9. Fix Learning System

### 9.1 Acceptance Tracking

[DIAG-30] **dynamic-semantics** The learning system MUST track:
- Error patterns (hashed by code + cause + context)
- Fix patterns (hashed by category + description)
- Acceptance events (error + fix + verbatim flag)

### 9.2 Confidence Adjustment

[DIAG-31] **dynamic-semantics** Historical acceptance rates MUST adjust confidence:
```
adjusted_confidence = base_confidence + (acceptance_rate * 0.2)
```

### 9.3 User Preferences

[DIAG-32] **dynamic-semantics** The system MUST detect preferences for:
- Explicit casts vs implicit conversions
- Qualified names vs imports
- Inline fixes vs multi-file changes

---

## 10. AI-Native Output

### 10.1 JSON Schema

[DIAG-33] **legality-rule** Machine-readable output MUST include:

```json
{
  "schema_version": 1,
  "code": "S1102",
  "severity": "error",
  "location": {
    "file": "math.jan",
    "line": 42,
    "column": 15
  },
  "summary": "No matching function...",
  "hypothesis_count": 3,
  "primary_hypothesis": {
    "probability": 0.78,
    "category": "missing_conversion"
  },
  "is_cascade_effect": false
}
```

### 10.2 Schema Versioning

[DIAG-34] **legality-rule** The `schema_version` field MUST be incremented when breaking changes are made to the JSON structure.

---

## 11. NextGenDiagnostic Structure

### 11.1 Complete Structure

[DIAG-35] **legality-rule** The NextGenDiagnostic type MUST contain:

```
NextGenDiagnostic := {
    // Core
    id:                    DiagnosticId,
    code:                  DiagnosticCode,
    severity:              Severity,
    primary_span:          SourceSpan,

    // Multi-Hypothesis
    hypotheses:            []Hypothesis,
    confidence_distribution: []Float32,

    // Type Flow
    type_flow_chain:       ?TypeFlowChain,

    // Semantic Correlation
    semantic_context:      ?SemanticContext,
    correlated_errors:     []CorrelatedError,
    cascade_root:          ?DiagnosticId,

    // Effect System
    effect_violations:     []EffectViolation,

    // Human Layer
    human_message:         EnhancedHumanMessage,

    // Machine Layer
    machine_data:          MachineReadableData,

    // Fix Suggestions
    fix_suggestions:       []RankedFixSuggestion,

    // Context
    related_info:          []RelatedInfo,

    // Learning
    learning_context:      ?LearningContext
}
```

---

## 12. Acceptance Criteria

### Scenario DIAG-AC-01: Multi-Hypothesis Generation
**Profile:** :core | **Capability:** none
- **Given:** A function call with no exact match
- **When:** The diagnostic engine processes the error
- **Then:** Multiple hypotheses are generated with probabilities
- **Invariant:** Probabilities sum to 1.0

### Scenario DIAG-AC-02: Type Flow Divergence
**Profile:** :core | **Capability:** none
- **Given:** A type mismatch error
- **When:** Type flow analysis is enabled
- **Then:** A complete inference chain with divergence point is produced
- **Invariant:** Divergence point identifies where expected != actual

### Scenario DIAG-AC-03: Semantic Change Correlation
**Profile:** :core | **Capability:** none
- **Given:** An error occurring after a dependency changed
- **When:** Semantic correlation is enabled
- **Then:** The change is detected and reported with before/after signatures
- **Invariant:** CID comparison is deterministic

### Scenario DIAG-AC-04: Cascade Detection
**Profile:** :core | **Capability:** none
- **Given:** Multiple errors with shared affected entities
- **When:** Cascade detection is enabled
- **Then:** Root cause is identified and presented first
- **Invariant:** Cascade errors reference their root cause

### Scenario DIAG-AC-05: Fix Learning
**Profile:** :core | **Capability:** none
- **Given:** A user accepts a fix suggestion
- **When:** The acceptance is recorded
- **Then:** Future similar errors rank that fix type higher
- **Invariant:** Confidence boost is bounded to prevent runaway



---

## 13. Implementation Files

[DIAG-36] **informative** Reference implementation is provided in:

| File | Purpose |
|------|---------|
| `compiler/libjanus/nextgen_diagnostic.zig` | Core data structures |
| `compiler/libjanus/hypothesis_engine.zig` | Multi-hypothesis generation |
| `compiler/libjanus/type_flow_analyzer.zig` | Type inference tracking |
| `compiler/libjanus/semantic_correlator.zig` | CID-based change detection |
| `compiler/libjanus/fix_learning.zig` | Fix acceptance tracking |
| `compiler/libjanus/diagnostic_engine.zig` | Integration engine |

---

## 14. Comparison with Prior Art

[DIAG-37] **informative** Feature comparison with Rust's diagnostic system:

| Feature | Rust | Janus NextGen |
|---------|------|---------------|
| Error cause | Single | Multiple hypotheses with probabilities |
| Type errors | Expected vs Found | Full inference chain visualization |
| Change tracking | None | CID-based semantic diff correlation |
| Error grouping | Independent | Cascade detection, root cause first |
| Machine output | Limited JSON | Complete AI-native structured data |
| Effect system | N/A (borrow checker) | Capability chain visualization |
| Learning | None | Track accepted fixes, improve suggestions |

---

## Appendix A: Symbolic Taxonomy

| Symbol | Meaning |
|--------|---------|
| 🜏 | Constitutional invariant |
| ⊢ | Legality rule |
| ⟁ | Compiler transformation |
| ⚠ | Hazard/Warning |
| ∅ | Forbidden pattern |
| ⧉ | Capability boundary |

---

## Appendix B: Revision History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-01-25 | Initial specification |
