<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# RFC 025: Sovereign Documentation System

**Status:** PROPOSED
**Version:** 0.1.0
**Author:** Janus Language Architecture Team
**Target Profile:** `:core` (Foundation), `:sovereign` (Full Integration)
**Doctrines:** Syntactic Honesty, Mechanism > Policy, Revealed Complexity
**Created:** 2026-02-22

---

## 1. Abstract

This RFC proposes a **Sovereign Documentation System** for Janus — a paradigm where documentation is not opaque text attached to code, but **structured, queryable data stored as first-class ASTDB rows**. Every doc comment is parsed into columnar arrays, linked to its target declaration via content-addressed identifiers (CIDs), annotated with compiler-extracted capabilities and effects, and queryable through the same predicate engine used for code analysis. The result is documentation that survives renames, prevents drift, powers AI agents via UTCP, and treats doctests as first-class compilation artifacts — not regex-extracted string blobs.

---

## 2. Motivation

### The Problem

Every existing documentation system — ExDoc, rustdoc, godoc, zig doc — treats documentation as **opaque text**. Comments are string blobs scraped from source files, rendered to HTML, and divorced from the semantic graph they describe. This creates three systemic failures:

1. **Documentation Drift:** Manual `@capability` or `@effect` annotations rot as code evolves. The compiler knows the truth; the docs lie.
2. **Fragile Identity:** Rename a function and its documentation link breaks. Name-based references are positional, not semantic.
3. **Machine Opacity:** AI agents must scrape rendered HTML to understand APIs. There is no structured query path from "what capabilities does this function require?" to a machine-readable answer.

### The Janus Solution

Janus already has the infrastructure to solve all three:

- **ASTDB** stores code as columnar arrays with CID-based identity (`compiler/astdb/core.zig`)
- **`doc_comment`** is already a token type (`core.zig:229`) and trivia kind (`core.zig:248`)
- **The lexer** already captures `///` as doc_comment trivia (`astdb/lexer.zig:159`)
- **`EffectsInfo`** tracks `capabilities_required` and `capabilities_granted` (`schema.zig:95`)
- **`HoverInfo`** has a `documentation` field ready for structured content (`schema.zig:138`)
- **`Predicate`** supports `effect_contains` and `requires_capability` queries (`query.zig:67-68`)
- **`utcpManual()`** is implemented across 16+ standard library modules

We propose adding a **DocEntry** table (the 10th columnar array in CompilationUnit) that transforms doc comments from trivia into structured, queryable, CID-linked documentation artifacts.

### Strategic Value

1. **AI-Native:** Agents query documentation via UTCP manuals and predicate queries — no scraping.
2. **Compiler-Truthful:** Capabilities and effects are auto-extracted, not manually tagged.
3. **Rename-Proof:** CID-based identity means documentation survives refactoring.
4. **Capsule Integration:** `janus publish` can auto-include structured docs in capsule manifests.
5. **LSP-Rich:** `HoverInfo.documentation` populated from structured DocEntry, not raw text.

---

## 3. Design

### 3.1 Doc Comment Syntax

Doc comments use the existing `///` token. The body is Markdown with optional structured tags.

```janus
/// Open a file at the given path with the specified mode.
///
/// Returns a handle to the opened file, or an error if the path
/// is inaccessible or the capability token is insufficient.
///
/// @param path      Filesystem path to open
/// @param mode      Access mode (read, write, read_write)
/// @param cap       Capability token granting filesystem access
/// @returns         File handle bound to the caller's arena
/// @error FsError.NotFound       Path does not exist
/// @error FsError.PermissionDenied  Capability insufficient
/// @capability CapFsRead         Required for read/read_write mode
/// @capability CapFsWrite        Required for write/read_write mode
/// @since 0.3.0
/// @see close_file
/// @safety Caller must ensure the capability token outlives the handle.
/// @complexity O(1) amortized, O(n) on first access to uncached path
///
/// ## Examples
/// ```janus
/// let f = open_file("/data/config.kdl", .read, ctx.cap_fs) catch |err| do
///     log.err("open failed: {}", err)
///     return err
/// end
/// defer close_file(f)
/// let content = read_all(f, allocator)
/// ```
func open_file(path: String, mode: Mode, cap: CapFsRead) -> File ! FsError do
    // ...
end
```

**Tag Reference:**

| Tag | Syntax | Semantic |
|:----|:-------|:---------|
| `@param` | `@param name Description` | Document a parameter |
| `@returns` | `@returns Description` | Document the return value |
| `@error` | `@error ErrorType When condition` | Document an error variant |
| `@capability` | `@capability CapName Description` | Declare required capability (supplementary) |
| `@since` | `@since version` | Version when introduced |
| `@see` | `@see identifier` | Cross-reference another declaration |
| `@deprecated` | `@deprecated Reason or replacement` | Mark as deprecated |
| `@safety` | `@safety Explanation` | Document safety invariants |
| `@complexity` | `@complexity O(...)` | Algorithmic complexity |

**Design Note:** `@capability` tags are **supplementary**. The compiler auto-extracts capabilities from `EffectsInfo.capabilities_required`. Manual tags exist only for human-readable context or to document capabilities that are transitively required but not directly visible in the function signature.

### 3.2 ASTDB Integration

The CompilationUnit currently stores 9 columnar arrays:

```
tokens, trivia, nodes, edges, scopes, decls, refs, diags, cids
```

This RFC adds a 10th: **`docs`**, containing `DocEntry` structs.

#### DocEntry

```zig
pub const DocEntry = struct {
    /// The DeclId this documentation targets
    target_decl: DeclId,
    /// The NodeId of the target declaration's AST node
    target_node: NodeId,
    /// Content-addressed identifier of the target (survives renames)
    target_cid: [32]u8,
    /// Raw text of the doc comment block (/// prefixes stripped)
    raw_text: StrId,
    /// First line / summary sentence
    summary: StrId,
    /// Source span covering the entire doc comment block
    span: SourceSpan,
    /// Kind of documented item
    kind: DocKind,
    /// Range into the DocTag array [tag_lo..tag_hi)
    tag_lo: u32,
    tag_hi: u32,
    /// Range into the DocTest array [test_lo..test_hi)
    test_lo: u32,
    test_hi: u32,
};

pub const DocKind = enum {
    function,
    variable,
    constant,
    type_alias,
    struct_type,
    enum_type,
    trait_type,
    impl_block,
    module,
};
```

#### DocTag

```zig
pub const DocTag = struct {
    kind: TagKind,
    /// For @param: the parameter name. For @error: the error type. Else null.
    name: ?StrId,
    /// The tag's content text
    content: StrId,
    /// Source span of this tag within the doc comment
    span: SourceSpan,

    pub const TagKind = enum {
        param,
        returns,
        err,
        capability,
        since,
        see,
        deprecated,
        safety,
        complexity,
        example,
    };
};
```

#### DocTest

```zig
pub const DocTest = struct {
    /// If from an adjacent test block: the NodeId of the test_decl
    test_node: ?NodeId,
    /// The source text of the test/example
    source_text: StrId,
    /// Origin of this doctest
    origin: Origin,
    /// Source span
    span: SourceSpan,

    pub const Origin = enum {
        /// A `test` block immediately following the documented declaration
        adjacent_test,
        /// A fenced ```janus code block inside the doc comment
        embedded_example,
    };
};
```

### 3.3 Doc Extraction Pass

Documentation extraction is a new compilation phase: **post-parse, pre-semantic-analysis**.

**Algorithm:**

1. Iterate the `trivia` array. Identify contiguous runs of `TriviaKind.doc_comment` trivia entries.
2. For each contiguous block:
   a. Strip the `///` prefix from each line.
   b. Join into a single raw text string.
   c. Extract the summary (first non-empty line or first sentence).
   d. Parse structured `@tag` lines into `DocTag` entries.
   e. Extract fenced `` ```janus `` code blocks as implicit `DocTest` entries with `origin = .embedded_example`.
3. Link each doc block to the **nearest subsequent `DeclId`** by span proximity (the declaration immediately following the doc comment).
4. Resolve `target_cid` from the existing `cids` array for the target declaration.
5. Scan for adjacent `test` blocks (a `test_decl` node whose span starts within 2 lines of the documented declaration's closing span) and link them as `DocTest` entries with `origin = .adjacent_test`.
6. Append all entries to the `docs`, doc_tags, and doc_tests columnar arrays.

**Why post-parse, pre-sema:** The parser has already built the AST and trivia arrays. We need DeclIds (available after parse) but not type information (which comes from sema). This keeps doc extraction isolated and non-blocking for semantic analysis.

### 3.4 Doctest Model

Janus has two doctest origins:

#### Origin 1: Adjacent Test Blocks

Janus already has `test` as a first-class keyword. A test block placed immediately after a function declaration is treated as that function's doctest:

```janus
/// Clamp a value to the given range.
func clamp(val: i32, lo: i32, hi: i32) -> i32 do
    if val < lo do return lo end
    if val > hi do return hi end
    return val
end

test "clamp basics" do
    assert(clamp(5, 0, 10) == 5)
    assert(clamp(-1, 0, 10) == 0)
    assert(clamp(99, 0, 10) == 10)
end
```

The test block is a first-class AST node — not a regex-extracted string. It participates in compilation, type checking, and CID computation.

#### Origin 2: Embedded Examples

Fenced `janus` code blocks inside doc comments are extracted as implicit test blocks:

```janus
/// Format a greeting.
///
/// ## Examples
/// ```janus
/// let msg = greet("Markus")
/// assert(msg == "Hello, Markus!")
/// ```
func greet(name: String) -> String do
    return "Hello, " ++ name ++ "!"
end
```

The fenced block is extracted during the doc extraction pass and compiled as a test with an auto-generated name derived from the parent declaration's CID.

#### Execution

```bash
janus test --doc          # Run all doctests (adjacent + embedded)
janus test --doc --check  # Verify doctests compile without running
```

#### CID Caching

Doctests are keyed by the CID of their parent declaration. If the CID has not changed since the last test run, the doctest result is cached and skipped. This makes `janus test --doc` incremental by default.

### 3.5 Query Interface

Extend the existing `Predicate` union (`query.zig`) with documentation predicates:

```zig
// New predicate variants
has_doc: void,                    // Declaration has a DocEntry
doc_contains: []const u8,         // Doc raw_text contains substring
is_deprecated: void,              // Has @deprecated tag
has_doctest: void,                // Has at least one DocTest
doctest_passing: void,            // All doctests pass (cached result)
missing_param_doc: void,          // Has params without @param tags
```

**CLI Usage:**

```bash
# Find all undocumented public functions
janus query "pub and func and not has_doc"

# Find all deprecated items
janus query "is_deprecated"

# Find functions with doctests
janus query "func and has_doctest"

# Lint: functions with parameters but missing @param docs
janus query "func and missing_param_doc"

# Find docs mentioning "allocator"
janus query "has_doc and doc_contains('allocator')"
```

### 3.6 Output Targets

The `janus doc` command generates documentation from the structured DocEntry table:

| Command | Output | Format |
|:--------|:-------|:-------|
| `janus doc` | Static site | HTML + CSS |
| `janus doc --format=json` | Canonical JSON | RFC 8785 (deterministic) |
| `janus doc --format=utcp` | UTCP Manual JSON | For AI agent consumption |
| `janus doc --format=capsule` | Capsule manifest | Doc metadata for `janus publish` |
| `janus doc --check` | Lint report | Warnings on undocumented pub items |

**HTML Generation** builds a navigable documentation site with:
- Module hierarchy navigation
- Rendered Markdown bodies
- Capability and effect badges per function
- Symbolic markers (see 3.8)
- Embedded doctest source with pass/fail indicators
- Cross-reference links resolved from `@see` tags

**Canonical JSON** (RFC 8785) output is deterministic and signable, consistent with the Law of Representation doctrine.

### 3.7 UTCP Manual Integration

The existing `utcpManual()` pattern (implemented across 16+ std/ modules) returns handwritten multiline strings. The Sovereign Documentation System enriches this:

1. **Auto-generation:** `janus doc --format=utcp` generates UTCP manual JSON from DocEntry data, replacing the need for hand-maintained `utcpManual()` functions.
2. **Structured Fields:** UTCP output includes parsed parameters, return types, capabilities, effects, and examples — not just prose.
3. **Backward Compatibility:** Hand-written `utcpManual()` functions continue to work. Auto-generated manuals supplement them. When both exist, auto-generated data takes precedence for structured fields; hand-written prose is preserved for overview sections.

**UTCP Manual JSON Schema (per module):**

```json
{
    "module": "std/fs",
    "cid": "b3a4f7...",
    "summary": "Tri-signature file system operations.",
    "capabilities": ["CapFsRead", "CapFsWrite"],
    "functions": [
        {
            "name": "open_file",
            "cid": "8e2c1a...",
            "summary": "Open a file at the given path.",
            "params": [
                {"name": "path", "type": "String", "doc": "Filesystem path to open"},
                {"name": "mode", "type": "Mode", "doc": "Access mode"}
            ],
            "returns": {"type": "File", "doc": "File handle bound to caller's arena"},
            "errors": [
                {"type": "FsError.NotFound", "doc": "Path does not exist"}
            ],
            "capabilities_required": ["CapFsRead"],
            "effects": {"io": "read_write", "memory": "read"},
            "examples": ["let f = open_file(\"/data/config.kdl\", .read, ctx.cap_fs)"],
            "doctest_status": "passing",
            "since": "0.3.0"
        }
    ]
}
```

### 3.8 Symbolic Markers

Documentation output includes auto-inserted glyphs from the Janus Symbology (`SYMBOLOGY.md`):

| Glyph | Name | Condition | Meaning |
|:------|:-----|:----------|:--------|
| `⊢` | Turnstile | All doctests pass | **Proven** — compiler verifies this declaration |
| `⚠` | Hazard | `capabilities_required` is non-empty | **Unsafe capabilities** — requires explicit tokens |
| `⟁` | Delta | Compiler transforms applied (desugar, ghost memory) | **Transformed** — what you write is not what runs |
| `⧉` | Box | Function crosses a capability boundary | **Boundary** — capability context changes here |

These markers appear in HTML output as badges, in terminal output as Unicode glyphs, and in JSON/UTCP output as boolean flags.

### 3.9 Auto-Extracted Metadata

The critical differentiator: **capabilities and effects come from the compiler, not from the developer**.

The existing `EffectsInfo` struct already tracks:
- `capabilities_required: [][]const u8`
- `capabilities_granted: [][]const u8`
- `is_pure: bool`
- `is_deterministic: bool`
- `memory_effects: MemoryEffects`
- `io_effects: IOEffects`

During the doc extraction pass (or as a post-sema enrichment step), each DocEntry is annotated with compiler-derived metadata:

1. **Capabilities** from `EffectsInfo.capabilities_required` — always authoritative.
2. **Effects** from `EffectsInfo.memory_effects` and `io_effects` — always authoritative.
3. **Purity** from `EffectsInfo.is_pure` — displayed as a badge.
4. **Manual `@capability` tags** — supplementary context only. If a manual tag contradicts the compiler, a diagnostic warning is emitted.

**This prevents documentation drift by design.** The compiler is the single source of truth for what a function does. Documentation adds human-readable context for *why*.

---

## 4. Competitive Analysis

| Dimension | ExDoc (Elixir) | rustdoc | zig doc | godoc | **Janus Sovereign** |
|:----------|:---------------|:--------|:--------|:------|:--------------------|
| **Storage** | String blobs | String blobs | String blobs | String blobs | **ASTDB rows (columnar)** |
| **Identity** | Name-based | Name-based | Name-based | Name-based | **CID-based (rename-proof)** |
| **Capabilities** | None | None | None | None | **Auto-extracted from compiler** |
| **Effects** | None | None | None | None | **Auto-extracted from effect system** |
| **Doctests** | Regex from comments | Regex from comments | None | Testable examples (convention) | **First-class AST nodes** |
| **Machine-Readable** | Partial JSON | Partial JSON | None | None | **Native UTCP + query predicates** |
| **Type Integration** | `@spec` (separate) | Inferred + `///` | `///` | Signature only | **Single source, compiler-derived** |
| **Incremental** | Full rebuild | Full rebuild | Full rebuild | Full rebuild | **CID-invalidated (incremental)** |
| **AI-Queryable** | Scraping required | Scraping required | Scraping required | Scraping required | **Native UTCP Manuals + query API** |
| **Proof Integration** | None | None | None | None | **Embedded proof certificates** |
| **Lint / Coverage** | Credo (separate tool) | `#[warn(missing_docs)]` | None | `go vet` (basic) | **`janus doc --check` + predicates** |
| **Symbolic Safety** | None | None | None | None | **Symbology markers (⊢ ⚠ ⟁ ⧉)** |

**Superiority Verdict:** Janus is the first language where documentation is a **queryable semantic artifact** rather than a rendering pipeline. Other systems transform text to HTML. Janus transforms text to structured data that powers AI agents, linters, capsule manifests, and the compiler itself.

---

## 5. Implementation Plan

Implementation is deferred to a dedicated sprint. The five phases are ordered by dependency:

### Phase 1: Data Structures (Foundation)

- Define `DocEntry`, `DocTag`, `DocTest` structs in `compiler/astdb/core.zig`
- Add `docs: []DocEntry`, `doc_tags: []DocTag`, `doc_tests: []DocTest` to `CompilationUnit`
- Add `DocKind` enum aligned with existing `DeclKind`
- Wire up arena allocation for doc arrays

**Deliverable:** ASTDB can store documentation. No extraction yet.

### Phase 2: Doc Extraction Pass

- Implement `doc_extract.zig` in `compiler/astdb/` (or `compiler/libjanus/passes/`)
- Iterate trivia array, identify contiguous `doc_comment` runs
- Strip `///` prefixes, parse Markdown body and `@tag` lines
- Link to nearest subsequent DeclId by span proximity
- Extract fenced `janus` blocks as DocTest entries
- Detect adjacent `test` blocks and link as DocTest entries

**Deliverable:** `janus build` populates DocEntry table. `janus query "not has_doc"` works.

### Phase 3: Query Predicates + Lint

- Add `has_doc`, `doc_contains`, `is_deprecated`, `has_doctest`, `doctest_passing`, `missing_param_doc` to `Predicate` union in `query.zig`
- Implement `janus doc --check` as sugar for `janus query "pub and not has_doc"`
- Emit diagnostics for `@capability` tags that contradict `EffectsInfo`

**Deliverable:** Documentation coverage lint. CI can gate on undocumented pub items.

### Phase 4: Output Generators

- HTML generator with Markdown rendering, navigation, symbolic markers
- Canonical JSON (RFC 8785) output
- UTCP Manual JSON output (replaces hand-written `utcpManual()` where present)
- Capsule manifest doc metadata for `janus publish`

**Deliverable:** `janus doc`, `janus doc --format=json`, `janus doc --format=utcp`.

### Phase 5: Doctest Execution + Auto-Extraction

- Compile and execute embedded examples and adjacent test blocks via `janus test --doc`
- CID-based caching (skip unchanged doctests)
- Post-sema enrichment: populate DocEntry with compiler-derived capabilities, effects, purity
- Generate proof certificates (⊢ marker) for declarations with passing doctests
- Enrich `HoverInfo.documentation` in LSP from structured DocEntry

**Deliverable:** Full sovereign documentation pipeline. AI agents get structured, truthful, queryable docs.

---

## 6. Doctrinal Compliance

| Doctrine | Compliance |
|:---------|:-----------|
| **Syntactic Honesty** | Doc comments use existing `///` syntax — no hidden annotation magic. Structured tags are plaintext, not compiler directives. All extraction is queryable via `janus query`. |
| **Mechanism > Policy** | The system provides doc extraction, tagging, and querying as **mechanisms**. It does not enforce documentation — `janus doc --check` is opt-in. Developers choose their doc coverage policy. |
| **Revealed Complexity** | Capabilities and effects are auto-extracted from the compiler, revealing the true cost of each function. Manual `@capability` tags cannot hide or override compiler truth — contradictions emit warnings. |
| **Zero Lies** | CID-based identity means documentation never points to the wrong target. Compiler-derived metadata means docs never claim a function is pure when it isn't. Doctests are compiled AST nodes, not regex-extracted strings that might not parse. |

---

## 7. Risks & Mitigations

| Risk | Impact | Mitigation |
|:-----|:-------|:-----------|
| **Doc extraction performance** | Additional compilation phase adds latency | Lazy extraction: only run when `--doc` flag or query predicate requires it. Skip in release builds. |
| **CID stability under refactoring** | CID changes when declaration body changes, invalidating doc links | CIDs are content-addressed — a body change *should* invalidate the cache. Only truly structural renames (no body change) preserve CID. Document this behavior. |
| **Tag syntax conflicts** | `@param` might collide with future language features | Tags are only recognized inside `///` doc comments, not in code. The `@` prefix is doc-context-only. |
| **Doctest compilation overhead** | Embedded examples add compilation units | CID-cached execution. Only recompile on CID change. `--check` mode compiles without running. |
| **UTCP backward compatibility** | Auto-generated manuals may differ from hand-written ones | Hand-written `utcpManual()` is preserved for overview prose. Auto-generated data supplements, does not replace. |
| **10th columnar array complexity** | Adding arrays to CompilationUnit increases memory and serialization surface | DocEntry is append-only and sparse (only populated for documented declarations). Memory cost is proportional to doc coverage, not codebase size. |

---

## 8. Future Work

- **Persistent ASTDB Docs:** Disk-backed doc storage via DuckDB, enabling cross-session queries and historical doc diffing.
- **`janus doc --serve`:** Live documentation server with hot-reload on source changes.
- **Cross-Capsule Doc Linking:** `@see` tags that resolve to declarations in dependency capsules via CID.
- **AI-Generated Doc Suggestions:** Use ASTDB structure + UTCP to suggest doc comment drafts for undocumented functions.
- **Doc Coverage Metrics:** `janus doc --coverage` reporting percentage of documented pub items, param coverage, and doctest coverage.
- **Proof Certificates in Capsule Manifests:** Published capsules include cryptographically signed proof that all doctests passed at publish time.
- **Interactive Doc Explorer:** `janus doc --interactive` TUI for browsing docs with predicate queries.

---

## 9. References

- [ASTDB Core Types](../../compiler/astdb/core.zig) — `doc_comment` token (line 229), `TriviaKind.doc_comment` (line 248), `CompilationUnit` columnar arrays
- [ASTDB Schema](../../compiler/libjanus/astdb/schema.zig) — `EffectsInfo` (line 95), `HoverInfo` (line 138)
- [ASTDB Query Engine](../../compiler/libjanus/astdb/query.zig) — `Predicate` union with `effect_contains`, `requires_capability` (lines 67-68)
- [ASTDB Lexer](../../compiler/astdb/lexer.zig) — `///` doc_comment capture (line 159)
- [Janus Symbology](../../docs/philosophy/SYMBOLOGY.md) — Glyph definitions (⊢ ⚠ ⟁ ⧉)
- [Grafting Doctrine](../../.claude/rules/grafting.md) — `utcpManual()` requirement for all grafted modules
- [Garden Wall Doctrine](../../.claude/rules/garden-wall.md) — Capsule standard (Source + Proof + Contract)
- [Law of Representation](../../docs/LAW_OF_REPRESENTATION.md) — KDL for intent, Canonical JSON (RFC 8785) for state
- [Elixir ExDoc](https://hexdocs.pm/ex_doc/) — Prior art (string-blob documentation)
- [rustdoc](https://doc.rust-lang.org/rustdoc/) — Prior art (attribute-based documentation)
- [RFC 8785 — JSON Canonicalization Scheme](https://datatracker.ietf.org/doc/html/rfc8785)

---

**Voting:**
- [ ] Accept
- [ ] Accept with modifications
- [ ] Defer
- [ ] Reject

---

*Forge Protocol: This RFC was forged in the fires of pragmatic language design.*
