<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — :core Profile (SPEC-P-CORE)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-profile-min v0.1.0

## 1. Profile Purpose

The `:core` profile is Janus's **teaching and fundamental subset** — a carefully curated monastic language that maintains all Janus principles while being simple enough for education, scripting, and formal verification of basic logic.

## 2. Capability Set 🜏

[PCORE:2.1.1] The `:core` profile MUST support the following fundamental keywords:
`func`, `let`, `var`, `if`, `else`, `for`, `while`, `match`, `when`, `return`, `break`, `continue`, `do`, `end`.

[PCORE:2.1.2] The `:core` profile SHALL support the following primitive types:
`i64`, `f64`, `bool`, `String`, `void`, `never`.

[PCORE:2.1.3] **No Indirect Authority ∅:** The `:core` profile SHALL NOT support concurrency (actors/nurseries), effects tracking, or arbitrary generics.

## 3. Execution Mode: Strict ⊢

[PCORE:3.1.1] The `:core` profile SHALL operate in **Strict Mode** (Monastery). This REQUIRES:
1.  Explicit type annotations at function boundaries.
2.  Explicit memory management (stack or unique linear types).
3.  No hidden control flow or implicit type conversions.

## 4. Feature Highlights

### 4.1 Honest Sugar (`when`)
[PCORE:4.1.1] The `when` keyword SHALL be supported for both match guards and postfix conditional returns.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge
