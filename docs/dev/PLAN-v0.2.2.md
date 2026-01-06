# PLAN: v0.2.2 LSP Stabilization

**Status:** 🏗️ **IN PROGRESS**
**Focus:** Reliability, Semantic Intelligence, and Teaching
**Previous:** v0.2.1-0 (Min Profile)
**Next:** v0.2.3 (Code Completion)

---

## 🏛️ Strategic Context

The "Nervous System" (LSP) is functional. We have a working `janus-lsp` binary that speaks JSON-RPC over stdin/stdout. It parses code and provides basic navigation (Go to Definition, Find References).

**The Stabilization Mandate:**
1.  **From "Syntax" to "Semantics":** Move beyond green squiggles (parsing). Show red squiggles for type errors. Hover should show types (`i32`), not just AST kinds (`IntegerLiteral`).
2.  **Teaching:** Document the "How" for future contributors.
3.  **Zero Artifacts:** Ensure the LSP is stateless and crash-proof.

---

## 📋 Features & Roadmap

### 1. Semantic Diagnostics (The "Red Squiggle" Upgrade)
*Currently, we only report syntax errors from the parser.*
- [x] **SymbolResolver Integration:** Report "Undeclared identifier" and "Duplicate declaration" errors.
- [ ] **Type Checker Integration:** Report "Type mismatch" errors.
- [ ] **Unified Diagnostic Pipeline:** Merge Parse + Bind + TypeCheck diagnostics before publishing.

### 2. Intelligent Hover (The "Type Reveal")
*Currently, Hover shows "Variable Declaration". Usefulness: Low.*
- [x] **Type Query:** Implement `query.inferTypeAtPosition` (Completed via SymbolResolver).
- [x] **Hover Polish:** Show `x: i32` instead of `Variable x`.
- [x] **UFCS Support:** Enable method-style syntax (`obj.method()`) with semantic resolution.
- [ ] **Doc Comments:** Extract and render `///` comments in Markdown.

### 3. Verification & Robustness
- [ ] **Crash Proofing:** Fuzz `textDocument/didChange` with partial edits.
- [ ] **Test Coverage:** Add integration tests for the VS Code extension flow.

### 4. Teaching Documentation
- [ ] **Walkthrough:** `docs/teaching/LSP_ARCHITECTURE.md` - How the "Thick Client" LSP works.

---

## 🗓️ Execution Order

1.  **Teaching First:** Write the `LSP_ARCHITECTURE.md` walkthrough to solidify understanding.
2.  **Semantic Diagnostics:** Wire up Binder errors.
3.  **Type Hover:** Wire up Type Inference.
4.  **Polish:** Release v0.2.2-0.

---

## 🛑 Definition of Done

- VS Code shows type errors (e.g., `let x: i32 = "string"`).
- Hovering `x` shows `i32`.
- `docs/teaching/LSP_ARCHITECTURE.md` explains how to add the *next* feature.
