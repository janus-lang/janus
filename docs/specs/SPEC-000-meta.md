# SPEC-000: Specification Meta-Document

**Status:** Normative  
**Version:** 0.2.5  
**Classification:** 🜏 Constitution

---

## 1. Scope

[META-01] This document defines the rules for reading and writing Janus language specifications.

[META-02] All normative Janus specifications MUST conform to the requirements in this document.

---

## 2. Normative Language (RFC 2119)

[META-03] This specification uses terminology from RFC 2119:

| Keyword | Meaning |
|---------|---------|
| **MUST** / **SHALL** | Absolute requirement |
| **MUST NOT** / **SHALL NOT** | Absolute prohibition |
| **SHOULD** / **RECOMMENDED** | Valid reasons to ignore, but implications MUST be understood |
| **SHOULD NOT** / **NOT RECOMMENDED** | Valid reasons to accept, but implications MUST be understood |
| **MAY** / **OPTIONAL** | Truly optional |

[META-04] These keywords **MUST** appear in bold when used normatively.

---

## 3. Paragraph Indexing

[META-05] All normative paragraphs **MUST** have a unique identifier in format `[PREFIX-NN]`.

[META-06] Prefixes by domain:

| Prefix | Domain |
|--------|--------|
| `META` | Spec meta-rules |
| `SYN` | Syntax/Grammar |
| `SEM` | Semantics |
| `MEM` | Memory |
| `TYPE` | Type system |
| `CAP` | Capabilities |
| `PANIC` | Panic conditions |
| `PROF` | Profiles |

[META-07] Test cases **SHOULD** reference the spec ID they verify.

---

## 4. Category Taxonomy

[META-08] Paragraphs **MUST** be categorized:

| Category | Description |
|----------|-------------|
| `legality-rule` | Compile-time requirement |
| `syntax` | Grammar rule |
| `dynamic-semantics` | Runtime behavior |
| `informative` | Non-normative explanation |

---

## 5. Symbol Taxonomy

[META-09] Glyphs mark semantic weight:

| Glyph | Name | Role |
|-------|------|------|
| 🜏 | Antimony | Constitutional invariant |
| ⊢ | Turnstile | Legality rule |
| ⟁ | Delta | Compiler transformation |
| ⚠ | Hazard | Unsafe operation |
| ∅ | Void | Forbidden pattern |
| ⧉ | Box | Capability boundary |

---

## 6. Authority Hierarchy

[META-10] The Specification is the Constitution. The Compiler is the Enforcer.

[META-11] If the Compiler contradicts the Specification, the Compiler is **wrong**.

[META-12] The Specification **MUST NOT** be defined by "reference compiler behavior."

---

## 7. Panic Taxonomy

[META-13] All panic conditions **MUST** be documented with:
- Panic code (e.g., `P001`)
- Condition that triggers it
- Profile-specific behavior

[META-14] Profile-specific failure modes:

| Profile | Failure Mode |
|---------|--------------|
| `:edge` | Result propagation (safe) |
| `:core` | Panic (deterministic) |
| `:core` | Undefined behavior (in `⚠ unsafe` only) |

---

**Last Updated:** 2026-01-06
