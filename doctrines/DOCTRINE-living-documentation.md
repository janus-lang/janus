<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# The Doctrine of Living Documentation

**Status:** CANONICAL
**Supersedes:** None (extends `metadata-comments.md`)
**Classification:** DOCTRINE // ARCHITECTURE

---

## The Problem: Documentation is Dead on Arrival

Traditional documentation suffers from three fatal flaws:

1. **Detachment** — JSDoc, Javadoc, and similar systems treat documentation as *comments*, separate from code semantics. They are ignored by compilers and easily drift from reality.

2. **Unverified** — Documentation examples are never executed. They lie the moment they are written and grow more dishonest with every refactor.

3. **Opaque to AI** — LLM agents cannot distinguish verified usage patterns from hallucinated examples in comment graffiti. This leads to synthesized code that doesn't compile.

**JSDoc is dead. We bury it here.**

---

## The Solution: Documentation IS Code

In Janus, documentation is not "attached" to code. **Documentation IS Code.**

### The Three Pillars

| Pillar | Mechanism | Enforcement |
|--------|-----------|-------------|
| **Semantic** | `///` is parsed as AST metadata, not discarded comments | Compiler stores in ASTDB |
| **Executable** | Code blocks in docs are extracted and run as tests | `janus test` verifies all examples |
| **Queryable** | Docs are accessible via `janus query` and MCP tools | AI agents get verified context |

---

## The Mechanism: Docs as AST Nodes

### Rule 1: Triple Slash (`///`) is Canonical

The `///` prefix is **not a comment**. It is a **string literal** attached to the following AST node's metadata.

```janus
/// Calculates the frequency of graphemes in a string.
///
/// # Examples
///
/// ```janus
/// assert("Janus" |> frequencies() == {"J": 1, "a": 1, "n": 1, "u": 1, "s": 1})
/// ```
func frequencies(input: String) -> Map<String, i64> do
    // Implementation...
end
```

**Storage:** The ASTDB stores documentation as structured metadata:

```zig
pub const DocMetadata = struct {
    summary: []const u8,           // First paragraph
    body: []const u8,              // Full markdown content
    examples: []const Example,     // Extracted code blocks
    sections: []const Section,     // # headers and content
    source_span: SourceSpan,       // Location in source file
};

pub const Example = struct {
    code: []const u8,              // The code block content
    language: []const u8,          // "janus", "text", etc.
    verified: bool,                // Was this executed?
    result: ?ExampleResult,        // Test outcome if verified
};
```

### Rule 2: Implementation Comments are Invisible

- `//` is for implementation details — **ignored by ASTDB**
- `///` is for interface contracts — **stored in ASTDB**

The compiler sees implementation comments and discards them. Documentation comments become first-class metadata.

---

## The Killer Feature: Doctests (Truth Tests)

### The Guarantee

If your documentation example does not compile and pass, **the build fails**.

### The Mechanism

When you run `janus test`, the compiler:

1. Extracts all code blocks marked ` ```janus ` from `///` documentation
2. Wraps each in a test harness with the documented function in scope
3. Executes and verifies assertions
4. Reports failures as documentation errors, not test failures

### Example

```janus
/// Reverses a string, preserving grapheme clusters.
///
/// This handles Unicode correctly, reversing visible characters
/// rather than raw bytes.
///
/// # Examples
///
/// ```janus
/// assert("hello" |> reverse() == "olleh")
/// assert("cafe" |> reverse() == "efac")
/// ```
///
/// # Edge Cases
///
/// ```janus
/// assert("" |> reverse() == "")
/// assert("a" |> reverse() == "a")
/// ```
pub func reverse(input: String) -> String do
    // Implementation...
end
```

**Test Output:**

```
Running doctests...
  std.string.reverse: 4 examples, 4 passed
```

### Doctest Modifiers

Code blocks can have modifiers for special handling:

```janus
/// # Examples
///
/// ```janus,should_panic
/// let _ = divide(1, 0)  // This should panic
/// ```
///
/// ```janus,compile_fail
/// let x: i32 = "not a number"  // This should not compile
/// ```
///
/// ```janus,ignore
/// // This example is illustrative only, not executed
/// let expensive = compute_for_hours()
/// ```
```

| Modifier | Behavior |
|----------|----------|
| (none) | Must compile and pass |
| `should_panic` | Must compile and panic |
| `compile_fail` | Must fail to compile |
| `ignore` | Not executed, documentation only |
| `no_run` | Must compile, but not executed |

---

## The Structure: Markdown with Sections

Documentation uses **Markdown** with semantic sections:

```janus
/// Brief one-line summary.
///
/// Longer description that explains the purpose, behavior,
/// and design rationale. This can span multiple paragraphs.
///
/// # Arguments
///
/// - `input` — The string to process
/// - `options` — Configuration options (optional)
///
/// # Returns
///
/// The processed result, or an error if processing fails.
///
/// # Examples
///
/// ```janus
/// let result = process("hello", .{})
/// assert(result.ok?)
/// ```
///
/// # Errors
///
/// Returns `ProcessError.InvalidInput` if the input is empty.
///
/// # Panics
///
/// Panics if the allocator is exhausted.
///
/// # Safety
///
/// This function is safe for all inputs.
///
/// # See Also
///
/// - `process_batch` — For processing multiple inputs
/// - `validate` — For input validation without processing
pub func process(input: String, options: Options) -> Result<Output, ProcessError> do
    // ...
end
```

### Required Sections for Public API

| Profile | Required Sections |
|---------|-------------------|
| `:core` | Summary, Examples |
| `:script` | Summary, Examples |
| `:service` | Summary, Arguments, Returns, Examples, Errors |
| `:cluster` | Summary, Arguments, Returns, Examples, Errors, Safety |
| `:sovereign` | Summary, Arguments, Returns, Examples, Errors, Panics, Safety |

---

## AI-First Context: The Query API

Because docs are AST nodes, AI agents can query structured documentation.

### Command Line

```bash
janus query docs std.string.frequencies
```

**Output:**

```json
{
  "module": "std.string",
  "name": "frequencies",
  "kind": "function",
  "signature": "func frequencies(input: String) -> Map<String, i64>",
  "doc": {
    "summary": "Calculates the frequency of graphemes in a string.",
    "body": "...",
    "verified_examples": [
      {
        "code": "assert(\"Janus\" |> frequencies() == {\"J\": 1, ...})",
        "verified": true,
        "last_run": "2026-01-28T12:00:00Z"
      }
    ]
  },
  "effects": ["pure"],
  "complexity": "O(n)"
}
```

### MCP Tool Integration

The `janusd` daemon exposes documentation via MCP:

```json
{
  "tool": "janus_query_docs",
  "arguments": {
    "path": "std.string.frequencies"
  }
}
```

This enables AI agents to:
- Get verified usage examples (not hallucinated patterns)
- Understand function signatures with full context
- Access cross-references and related functions

---

## Enforcement: The Build Guard

### Configurable Enforcement Levels

In `janus.pkg`:

```kdl
[doctest]
enforce = "strict"  // "none", "warn", "strict"
coverage = 0.8      // 80% of public API must have examples
```

| Level | Behavior |
|-------|----------|
| `none` | Doctests run but failures don't block build |
| `warn` | Failures produce warnings |
| `strict` | Failures block the build |

### Profile-Based Requirements

```kdl
[doctest.profiles]
sovereign = "strict"  // `:sovereign` profile requires docs
service = "strict"    // `:service` profile requires docs
script = "warn"       // `:script` profile warns on missing docs
core = "warn"         // `:core` profile warns on missing docs
```

### Missing Documentation Diagnostics

```
error[E3001]: missing documentation for public function
  --> src/lib.jan:42:1
   |
42 | pub func important_function(x: i32) -> i32 {
   | ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   |
   = help: add `///` documentation before this function
   = note: profile `:service` requires documentation for public API
```

---

## The Diagnostic Codes

| Code | Name | Description |
|------|------|-------------|
| E3001 | DOC_MISSING | Public item lacks required documentation |
| E3002 | DOC_EXAMPLE_MISSING | Documentation lacks required examples |
| E3003 | DOCTEST_COMPILE_FAIL | Example code failed to compile |
| E3004 | DOCTEST_ASSERTION_FAIL | Example assertion failed |
| E3005 | DOCTEST_PANIC_EXPECTED | Example should have panicked but didn't |
| E3006 | DOCTEST_UNEXPECTED_PANIC | Example panicked unexpectedly |
| W3001 | DOC_SECTION_MISSING | Recommended section missing |
| W3002 | DOC_EXAMPLE_OUTDATED | Example hasn't been verified recently |

---

## Implementation in ASTDB

The ASTDB stores documentation as columnar data:

```zig
// In astdb/columns.zig
pub const DocColumns = struct {
    /// Summary text (first paragraph)
    summaries: StringPool,

    /// Full markdown body
    bodies: StringPool,

    /// Extracted example code blocks
    examples: PackedArray(ExampleRef),

    /// Section headers and content
    sections: PackedArray(SectionRef),

    /// Source spans for error reporting
    spans: PackedArray(SourceSpan),

    /// Doctest verification status
    verified: BitSet,

    /// Last verification timestamp
    verified_at: PackedArray(u64),
};
```

---

## The Promise

1. **Every example compiles** — Doctests are verified on every build
2. **Every example runs** — Unless explicitly marked `ignore` or `no_run`
3. **Every assertion holds** — Failed assertions fail the build
4. **Every query returns truth** — AI agents get verified, structured documentation

**Documentation is not a comment. Documentation is a contract.**

---

## References

- `metadata-comments.md` — Comment type hierarchy
- `SPEC-024-doctest-system` — Implementation specification
- `ai-alignment.md` — AI-first design principles

---

*"If the documentation lies, the build dies."*
