<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# RFC: Path Join Operator `/` for std.fs Path Types

- Status: Draft
- Owner: std-fs working group
- Affects: Language semantics (narrow), std.fs Path API

## Summary

Introduce a narrowly-scoped, non-user-extensible Path Join operator using `/` for `Path`/`PathBuf` to enable readable, allocation-efficient path construction:

- Required syntax: `let config = base / "conf" / "app.json"`
- Returns: `PathBuf`
- Zero- or single-allocation join (amortized), no I/O, platform-aware separators
- Strictly limited to std.fs path types; not a general-purpose operator overloading facility

This RFC preserves the “no ad‑hoc operator overloading” doctrine while unlocking a high-leverage ergonomic and performance win for filesystem code by standardizing a single, blessed operator mapping for path joins.

## Motivation

1) Ergonomics & Readability
- Operator form (desired): `base / "dir" / "file"`
- Current placeholder: `join_all(base, vec!["dir".to_string(), "file".to_string()])`
- Placeholder problems:
  - Verbose and noisy in real code
  - Requires heap allocation for the `Vec`
  - Littered with `.to_string()` conversions

2) Performance & Allocation
- Operator design: perform size prediction and single reserve on a `PathBuf`, or push segments incrementally with minimal allocations; no intermediate `Vec`.
- Placeholder design: allocates a `Vec`, pushes N items, then joins, incurring additional allocations and copies.

3) Precedent & Competitive Edge
- Python `pathlib.Path` uses `/` for join; widely used and loved.
- Many ecosystems converge on object paths with fluent, readable joins.
- Adopting a principled `/` aligns Janus with ergonomic excellence expected from a modern systems language while retaining strict safety/explicitness.

## Doctrine Compatibility (No Ad‑Hoc Operator Overloading)

This proposal is a constrained, standard-library bound operator specialization, not a user-extensible overload system.

- Scope: Only for std.fs `Path`/`PathBuf` operands with RHS `Path | PathBuf | String` (language-appropriate string type).
- Resolution: If LHS is Path/PathBuf and operator token is `/`, dispatch to path-join semantics. Otherwise, preserve numeric division.
- Extensibility: No user-defined operator hooks; no traits; no macros. A single, blessed mapping in the standard library domain.
- Profiles: Enabled where std.fs is available. If needed, gate under advanced profiles to preserve teaching simplicity.

Thus we maintain the doctrine’s intent (no general operator overloading) while providing a targeted, high-value exception encoded as a language builtin mapping to std.fs.

## Design

- Operands
  - `Path / String` → `PathBuf`
  - `Path / Path` → `PathBuf`
  - `PathBuf / String` → `PathBuf`
  - `PathBuf / Path` → `PathBuf`
- Semantics
  - Absolute RHS: result is RHS (ignores LHS), normalized to platform separators.
  - Single-separator invariant between segments.
  - No filesystem access; purely syntactic join.
- Allocation strategy
  - Pre-compute length growth (best-effort) and reserve once in `PathBuf`.
  - Push segments while normalizing separators; avoid intermediate containers.
- Return type rationale
  - Borrowed `Path` remains immutable; joining yields owned `PathBuf` for fluent composition.
- Cross‑platform
  - Respect platform separators and root forms (Unix `/`, Windows drive letters/UNC handled by Path types).

## Alternatives Considered

- `join_all(path, parts...)`: function or builder API. Still noisier than `/` and often allocates more.
- Macros or string interpolation: not aligned with doctrine; hides semantics; hampers tooling.
- Do nothing: retains ergonomic and performance debt; inconsistent with a best‑in‑class std.fs.

## Backwards Compatibility

- Parser: no grammar change; `/` already exists. Semantic disambiguation based on LHS type.
- Numeric division: unaffected when LHS is numeric or non‑Path types.
- Source: existing code continues to work; new code may adopt `/` incrementally.

## Security & Capabilities

- Operator performs no I/O; no capability involvement.
- Capability checks remain at I/O boundaries (open/read/write) per platform security model.

## Testing Strategy

- Unit tests for join semantics: absolute RHS override, single-separator invariant, mixed Path/PathBuf/string.
- Property tests over random segment sequences to verify normalization invariants and panic-freedom.
- Cross‑platform matrix for Windows/Unix path forms.

## Tooling & IDE Support

- Semantic highlighter: treat `/` with Path LHS as a path-join operator for better hints.
- Lint rule: prefer `/` over ad‑hoc `join_all` or string concatenation.

## Rollout Plan

- Phase 1: Implement operator semantics in standard library integration; add tests.
- Phase 2: Migrate std.fs and examples to `/`; add deprecation lint (soft) for placeholder helpers.
- Phase 3: Document in std.fs and language guide with a clear doctrine caveat (“standard-library bound operator; not user-extensible”).

## Open Questions

- Profile gating: Should `/` be available in minimal profiles or reserved for advanced ones to reduce syntactic magic where teaching simplicity is paramount?
- Windows semantics: exact rules for drive letters and UNC in the presence of LHS/RHS combinations.

---

Appendix: Side‑by‑side Ergonomics

- Operator: `let cfg = base / "conf" / "app.json"`
- Placeholder: `let cfg = join_all(base, vec!["conf".to_string(), "app.json".to_string()])`

Operator form is shorter, clearer, and reliably cheaper to execute.
