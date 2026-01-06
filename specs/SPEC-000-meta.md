<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — Meta-Specification (SPEC-000)

**Version:** 1.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  

## 1. Introduction

This document defines the normative infrastructure and conventions used across all Janus Language Specifications. It ensures precision, traceability, and consistency in how language rules are defined and verified.

## 2. Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

- **MUST / SHALL / REQUIRED**: These terms indicate absolute requirements of the specification.
- **MUST NOT / SHALL NOT**: These terms indicate absolute prohibitions of the specification.
- **SHOULD / RECOMMENDED**: These terms indicate that there may exist valid reasons in particular circumstances to ignore a particular item, but the full implications must be understood and weighed before choosing a different course.
- **MAY / OPTIONAL**: These terms indicate that an item is truly optional. An implementation that does not include a particular option MUST be prepared to interoperate with another implementation which does include the option.

## 3. Paragraph Indexing

To facilitate traceability and precise citation, key normative paragraphs SHOULD be indexed using the format `[FILE-ID:SECTION.PARA]`.

Example: `[SEMA:2.1.4]` refers to Semantics Spec, Section 2.1, Paragraph 4.

## 4. Symbol Taxonomy

The following symbols are used in specifications to denote specific semantic domains or safety properties:

| Symbol | Name | Semantic Role |
| :--- | :--- | :--- |
| **☍** | **The Janus** | Represents Identity and Dualism (Safe/Unsafe, Script/System). |
| **🜏** | **The Antimony** | Represents Invariants and Law (Immutable Core). |
| **⟁** | **The Delta** | Represents Transformation (Codegen, Lowering, Desugaring). |
| **⊢** | **The Turnstile** | Represents Judgment and Truth (Compiler Proofs, Type Checking). |
| **∅** | **The Void** | Represents Forbidden paths (Anti-patterns, Banned features). |
| **⚠** | **The Hazard** | Represents Raw or Unsafe operations. |
| **⧉** | **The Box** | Represents Boundaries (Capabilities, Module Interfaces, FFI). |

## 5. Specification Priority

In the event of a conflict between the compiler implementation and the specification, the **Specification SHALL reign supreme**. Any behavior in the compiler that deviates from the specification without a corresponding and ratified RFC is considered a bug and MUST be corrected.

---

**Ratified:** 2026-01-06  
**Authority:** Markus Maiwald + Voxis Forge
