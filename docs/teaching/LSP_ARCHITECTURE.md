# The Nervous System: Inside the Janus LSP

> "The language server is not a tool. It is the language itself, listening."

This walkthrough explains the architecture of the Janus Language Server (`janus-lsp`), how it connects to the compiler's brain (`astdb`), and how to extend it.

---

## 🏗️ Architecture: The "Thick Client"

Most language servers are "Thin Clients" that talk to a separate daemon. Janus takes a **"Thick Client"** approach (similar to `rust-analyzer` or `zls`).

The `janus-lsp` binary **IS** the compiler. It embeds the `AstDB` (Abstract Syntax Tree Database) directly.

```ascii
+-----------------------+                    +-------------------------+
|      VS Code          | -- (JSON-RPC) -->  |      janus-lsp          |
| (Thin UI Layer)       | <--(Stdin/Out)--   |  (The Compiler Brain)   |
+-----------------------+                    +-------------------------+
                                                       |
                                             [ In-Memory AstDB ]
                                             [   Source Code   ]
                                             [   Token Stream  ]
                                             [   Symbol Table  ]
```

### Why this way?
1.  **Speed:** Zero IPC latency. Queries run directly against in-memory structs.
2.  **Simplicity:** No need to manage a background `janusd` process for basic editing.
3.  **Resilience:** If the LSP crashes, it restarts instantly (stateless).

---

## 🧬 Anatomy of a Request

Let's trace a **Hover** request (`textDocument/hover`).

### 1. The Trigger
You move your mouse over `my_var`. VS Code sends:
```json
{"method": "textDocument/hover", "params": { "position": { "line": 10, "character": 5 } ... }}
```

### 2. The Handler (`daemon/lsp_server.zig`)
The `LspServer` event loop catches the message and dispatches it:
```zig
fn handleMessage(...) {
    if (std.mem.eql(u8, method, "textDocument/hover")) {
        try self.handleHover(id, params);
    }
}
```

### 3. The Query (`compiler/astdb/query.zig`)
The handler asks the `AstDB`: *"What relies at this coordinate?"*
```zig
const node_id = query.findNodeAtPosition(db, unit_id, line, char);
```
*   **Mechanism:** The `AstDB` stores tokens with byte ranges. We binary search the tokens to find which one covers the cursor. Then we find the AST Node that owns that token.

### 4. The Intelligence
Once we have the `NodeId`, we extract intelligence:
*   **Kind:** Is it a Function? Variable?
*   **Name:** What is it called?
*   **Type:** (Coming Soon) What is its inferred type?

### 5. The Response
We construct Markdown and send it back:
```markdown
### Variable: `my_var`
```
VS Code renders this in a pop-up.

---

## 🛠️ Adding a New Feature

Want to add **"Signature Help"**? Follow this mental model:

1.  **LSP Layer (`daemon/lsp_server.zig`):**
    *   Add `handleSignatureHelp`.
    *   Parse the JSON params.
2.  **Query Layer (`compiler/astdb/query.zig`):**
    *   Write `findFunctionCallAtPosition`.
    *   Need to traverse *up* the AST from the cursor to find the active `CallExpr`.
3.  **Intelligence:**
    *   Look up the function definition in `AstDB`.
    *   Extract parameter names and types.

---

## 🧠 The "Living" Graph

The LSP relies on the **"Living Graph"** principle.
*   **`textDocument/didChange`:** We do not patch the AST. We **re-parse** the modified file immediately.
*   **Performance:** The Janus parser is designed to be fast enough (<50ms) to re-parse entire files on every keystroke.
*   **Future:** We will implement incremental parsing for massive files, but for now, "Brute Force Speed" is our strategy.

---

## 🚨 Diagnostics (The Feedback Loop)

When you type, we produce diagnostics (Red Squiggles).
Currently pipeline:
1.  **Parse:** `janus_parser.parseIntoAstDB`
2.  **Error?** -> Publish `Diagnostic` -> Done.
3.  **Success?** -> Publish `[]` (Clear errors) -> Run Binder.

**Next Step (Stabilization):** We need to report Binder errors (e.g., "Unknown Identifier") as diagnostics too.

---
*Voxis Forge Teaching Series*
