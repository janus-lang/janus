<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — :sovereign Profile (SPEC-P-SOVEREIGN)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-profile-full v0.1.0

## 1. Profile Purpose

The `:sovereign` profile is the **complete, unrestricted Janus feature set**, optimized for **self-sovereign systems programming**, operating systems, and kernel development. It enables the full effects system, advanced metaprogramming, and raw memory access (gated by hazard symbols ⚠).

## 2. Capability Set ☍

[PSOV:2.1.1] The `:sovereign` profile SHALL possess **Ambient Capability** over all language features, including those defined in the `:core`, `:service`, `:cluster`, and `:compute` profiles.

[PSOV:2.1.2] **Advanced Metaprogramming:** The profile SHALL support full `comptime` execution with reflection and AST generation capabilities.

[PSOV:2.1.3] **Hazardous Operations ⚠:** The profile SHALL permit raw pointer arithmetic and FFI, provided they are encapsulated within `unsafe` or `unchecked` blocks.

## 3. Execution Mode: Strict ⊢

[PSOV:3.1.1] The `:sovereign` profile SHALL operate in **Strict Mode**, requiring total transparency and manual control over all system resources.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge
