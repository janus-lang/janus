<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus Specification — Panic Taxonomy & Failure Modes (SPEC-011)

**Version:** 1.0.0  

## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).

**Status:** DRAFT  
**Authority:** Constitutional  

## 1. Introduction

This document defines the taxonomy of panic codes and failure modes in the Janus programming language. It establishes a consistent vocabulary for unrecoverable errors and defines how they MUST be handled across different profile tiers.

### 1.1 Normative References
All definitions in this document SHALL follow the normative language defined in [SPEC-000: Meta-Specification](meta.md).

## 2. The Nature of Panic ∅

[PAN:2.1.1] A **Panic** is an unrecoverable state where the application cannot safely continue execution.

[PAN:2.1.2] Panics SHALL NOT be used for expected error conditions (e.g., file not found, network timeout). These MUST use the `!Error` result mechanism.

[PAN:2.1.3] **No Recovery:** In the `:core` and `:sovereign` profiles, there is no language-level mechanism to catch a panic once triggered.

## 3. Panic Categories (Taxonomy)

[PAN:3.1.1] All panics SHALL belong to one of the following categories:

| Category | Description | Common Codes |
| :--- | :--- | :--- |
| **MEM** | Memory Safety violations | `MEM:OUT_OF_BOUNDS`, `MEM:NULL_DEREF` |
| **SYS** | Internal System/Runtime failures | `SYS:RESOURCE_EXHAUSTED`, `SYS:HW_FAULT` |
| **LOG** | Logical invariants or contract violations | `LOG:ASSERT_FAIL`, `LOG:UNREACHABLE` |
| **CAP** | Capability or security violations | `CAP:AUTHORITY_EXCEEDED` |

## 4. Profile-Specific Behavior

[PAN:4.1.1] **:core / :sovereign (The Monastery)**
- [PAN:4.1.2] Behavior: **Immediate Abort**.
- [PAN:4.1.3] Output: Minimal crash dump or LED status.

[PAN:4.1.4] **:service / :cluster (The Bazaar)**
- [PAN:4.1.5] Behavior: **Actor/Process Crash**. The supervisor SHALL decide the restart strategy.
- [PAN:4.1.6] Output: Detailed structured log with trace data.

## 5. Standard Panic Codes

| Code | Meaning |
| :--- | :--- |
| `P001` | Index Out of Bounds |
| `P002` | Integer Overflow (in checked mode) |
| `P003` | Division by Zero |
| `P004` | Assertion Failure |
| `P005` | Unreachable Path Hit |
| `P006` | Out of Memory |

---

**Ratified:** [PENDING]  
**Authority:** Markus Maiwald + Voxis Forge
