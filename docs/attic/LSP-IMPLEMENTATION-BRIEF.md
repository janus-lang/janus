# LSP Server Implementation - v0.2.2 Session Brief

**Created:** 2025-12-15  
**Status:** Architecture Complete, Blocked on Zig 0.15 I/O API  
**Priority:** HIGH (Tooling Foundation)

---

## 🎯 Objective

Deliver a **standalone LSP server** (`janus-lsp`) that provides VS Code integration for:
- Syntax highlighting (already done via TextMate grammar)
- Hover information (type, documentation)
- Go to definition
- Find references
- Diagnostics (parse errors, type errors)

---

## ✅ Completed Work

### 1. Architecture Decision
**Selected:** Standalone "Thick Client" LSP  
**Rationale:**
- Faster delivery (no IPC complexity)
- Standard practice (rust-analyzer, gopls, zls)
- Direct ASTDB linking maintains "Single Brain" doctrine
- Trade-off: Unsaved edits invisible to CLI (acceptable for v0.2.2)

### 2. Files Created
- **`cmd/janus-lsp/main.zig`** - Entry point with ASTDB instantiation
- **Build integration** - Added to `build.zig` (gated by `-Ddaemon=true`)

### 3. Existing Infrastructure
- **`daemon/lsp_server.zig`** - Core LSP protocol handler (JSON-RPC, lifecycle)
- Document sync implemented (textDocument/didOpen, didChange)
- Stub capabilities advertised (hover, definition, completion)

---

## 🚧 Blocker: Zig 0.15 I/O API Changes

### The Problem
In Zig 0.15, the File I/O API changed:

**Old (Zig 0.13):**
```zig
const stdin = std.io.getStdIn();
const reader = stdin.reader();  // No args
```

**New (Zig 0.15):**
```zig
const stdin = std.fs.File.stdin();
var buffer: [4096]u8 = undefined;
const reader = stdin.reader(&buffer);  // Requires buffer!
```

The `daemon/lsp_server.zig` expects **unbuffered** Reader/Writer types, but now we need explicit buffer management.

### Current Error
```
cmd/janus-lsp/main.zig:35:43: error: member function expected 1 argument(s), found 0
    const StdinReader = @TypeOf(stdin_file.reader());
```

---

## 🛠️ Solution Strategy

### Option 1: Buffered I/O Wrapper (Recommended)
Create a thin buffered I/O layer:

```zig
// cmd/janus-lsp/main.zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var db = try astdb.AstDB.init(allocator, false);
    defer db.deinit();

    // Buffered I/O setup
    const stdin = std.io.getStdIn();
    const stdout = std.io.getStdOut();
    
    var stdin_buffered = std.io.bufferedReader(stdin.reader());
    var stdout_buffered = std.io.bufferedWriter(stdout.writer());
    
    var server = lsp_server.LspServer(
        @TypeOf(stdin_buffered.reader()),
        @TypeOf(stdout_buffered.writer())
    ).init(
        allocator,
        stdin_buffered.reader(),
        stdout_buffered.writer(),
        &db,
    );
    defer server.deinit();

    try server.run();
}
```

### Option 2: Refactor LSP Server for Zig 0.15
Update `daemon/lsp_server.zig` to accept File types directly and manage buffers internally.

**Recommended:** Option 1 (less invasive, standard pattern)

---

## 📋 Next Steps

1. **Implement Buffered I/O** (30 minutes)
   - Update `cmd/janus-lsp/main.zig` with buffered readers/writers
   - Test LSP handshake with VS Code

2. **Wire ASTDB Queries** (2 hours)
   - Implement `textDocument/hover` → query node at position
   - Implement `textDocument/definition` → symbol lookup
   - Use existing ASTDB query APIs

3. **VS Code Extension** (1 hour)
   - Update `tools/vscode/package.json` to point to `janus-lsp`
   - Test hover, go-to-definition in editor

4. **Documentation** (30 minutes)
   - Add LSP usage guide
   - Document editor setup

---

## 🔗 Related Files

- `cmd/janus-lsp/main.zig` - LSP entry point (needs I/O fix)
- `daemon/lsp_server.zig` - Core protocol handler (works)
- `build.zig:445-461` - Build configuration
- `tools/vscode/` - VS Code extension (needs LSP path update)

---

## 📚 References

- **LSP Spec:** https://microsoft.github.io/language-server-protocol/
- **Zig 0.15 Changelog:** Breaking changes in std.io
- **Similar LSPs:** `zls` (Zig), `rust-analyzer` (Rust) - both use buffered I/O

---

**Handoff Status:** Ready for focused 4-hour implementation session.

— Voxis Forge, 2025-12-15
