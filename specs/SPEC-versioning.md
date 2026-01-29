# SPEC-versioning.md — Janus Versioning Strategy

**Status:** Normative  
**Version:** 1.0.0  
**Classification:** 🜏 Constitution

---

## 1. Scope

[VER-01] This specification defines the Janus versioning and release strategy.

[VER-02] Janus uses **Calendar Versioning (CalVer)** with the "Mars Cycle" doctrine.

---

## 2. Version Format

[VER-03] **syntax** Version format is `YYYY.Q.PATCH`:

- `YYYY` — Year (e.g., 2026)
- `Q` — Quarter (1-4)
- `PATCH` — Patch number (0-indexed)

[VER-04] **informative** Examples:
- `2026.1.0` — Q1 2026, first release
- `2026.1.1` — Q1 2026, first patch
- `2026.4.0` — Q4 2026 (LTS candidate)

---

## 3. The Mars Cycle (2-Year LTS)

[VER-05] **legality-rule** Janus releases follow two tracks:

| Track | Schedule | Support Duration |
|-------|----------|------------------|
| **Standard** | Quarterly (Q1-Q4) | 6 months |
| **LTS (Citadel)** | Q4 Even Years | 4 years |

[VER-06] **legality-rule** LTS releases **MUST** occur only in Q4 of even years.

[VER-07] **informative** Examples:
- `2026.4.0` — Citadel Alpha (LTS, supported until 2030)
- `2027.1-4` — Standard releases (experimental phase)
- `2028.4.0` — Citadel Beta (LTS, supported until 2032)

---

## 4. Support Windows

[VER-08] **legality-rule** Support overlap provides upgrade flexibility:

```
2026.4 (LTS) ──────────────────────────> 2030
                    2028.4 (LTS) ──────────────────────────> 2032
```

[VER-09] **informative** This allows skipping one LTS release (e.g., 2026.4 → 2030.4).

---

## 5. The Frozen Factory

[VER-10] **legality-rule** Every release **MUST** be reproducible via container:

```bash
docker run ghcr.io/janus-lang/compiler:2026.1.0
```

[VER-11] **dynamic-semantics** Old code compiles with old compilers:
- Source code frozen in time
- Compiler provided as hermetic container
- No backward compatibility burden on `main` branch

---

## 6. The JIR Bridge

[VER-12] **legality-rule** While source syntax may break between versions, compiled artifacts (JIR/libraries) **MUST** be forward-compatible within the same **Epoch** (year).

[VER-13] **dynamic-semantics** Example:
- Library compiled with `2026.1.0` → links with `2026.2.0`
- Source migration → use `janus migrate` (ASTDB-powered)

---

## 7. Version Bumping

[VER-14] **legality-rule** Version increments follow these rules:

| Bump Type | Rule | Example |
|-----------|------|---------|
| `quarter` | Increment Q, reset PATCH | `2026.1.0` → `2026.2.0` |
| `patch` | Increment PATCH | `2026.1.0` → `2026.1.1` |
| `year` | New year, reset to Q1 | `2026.4.0` → `2027.1.0` |

---

## 8. Release Codenames

[VER-15] **informative** LTS releases have codenames:

| Version | Codename | Type |
|---------|----------|------|
| 2026.4.0 | Citadel Alpha | LTS |
| 2028.4.0 | Citadel Beta | LTS |
| 2030.4.0 | Citadel Gamma | LTS |

---

## 9. Rationale

[VER-16] **informative** Why CalVer?
- **Honesty:** A compiler is a product of its time
- **Alignment:** Matches parser epochs (`// janus: 2026.1`)
- **Enterprise Planning:** Banks/Defense plan in calendar years

[VER-17] **informative** Why 2-year LTS?
- **Stability:** Slow enough for compliance-heavy industries
- **Relevance:** Fast enough to support new hardware (NPU/GPU)
- **Overlap:** 4-year support allows skipping one LTS

---

**Last Updated:** 2026-01-06
