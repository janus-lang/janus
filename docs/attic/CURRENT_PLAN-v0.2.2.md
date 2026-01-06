<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus v0.2.2 Execution Plan: Language Server Protocol

**Target:** v0.2.2-0  
**Status:** ⏳ Planning Phase  
**Focus:** Foundational Developer Tooling  
**Timeline:** 1-2 weeks

---

## 🎯 Mission Objective

**Deliver a fully functional Language Server Protocol (LSP) implementation** that provides essential IDE features for Janus development. This establishes the foundation for the "Smalltalk Experience" - live introspection and seamless developer feedback.

---

## 📋 Prerequisites (✅ COMPLETE)

From v0.2.1:
- ✅ **:core Profile Complete** - All core language features operational
- ✅ **ASTDB Stable** - Node storage, token ranges, symbol tracking
- ✅ **Type System Operational** - Inference, constraints, type checking
- ✅ **Test Suite Passing** - 133/135 tests (99.2%)
- ✅ **LSP Architecture Designed** - Standalone "thick client" model chosen

---

## 🚧 Current Blocker: Zig 0.15 I/O API Migration

### The Problem

Zig 0.15 introduced breaking changes to the standard library I/O API:

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

**Current Error:**
```
cmd/janus-lsp/main.zig:35:43: error: member function expected 1 argument(s), found 0
    const StdinReader = @TypeOf(stdin_file.reader());
```

### The Solution

Implement buffered I/O wrapper using `std.io.bufferedReader/Writer`:

```zig
// cmd/janus-lsp/main.zig
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){}; 
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Initialize ASTDB
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

**Estimated Fix Time:** 30-60 minutes

---

## 🏗️ Implementation Phases

### **Phase 1: Fix I/O and Handshake** (Day 1)
**Priority:** CRITICAL • **Effort:** 2-4 hours

**Tasks:**
- [x] Architecture complete (standalone LSP)
- [x] `cmd/janus-lsp/main.zig` created
- [x] Build integration (`build.zig`)
- [ ] Fix Zig 0.15 I/O API (buffered readers/writers)
- [ ] Verify LSP initialize handshake
- [ ] Verify capability negotiation
- [ ] Test with VS Code (basic connection)

**Verification:**
```bash
# Build LSP server
zig build -Ddaemon=true

# Test handshake manually
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}' | ./zig-out/bin/janus-lsp

# Expected: Valid JSON-RPC response with capabilities
```

---

### **Phase 2: Document Synchronization** (Day 2)
**Priority:** HIGH • **Effort:** 4-6 hours

**Already Implemented in `daemon/lsp_server.zig`:**
- ✅ `textDocument/didOpen` - Document opened in editor
- ✅ `textDocument/didChange` - Document modified
- ✅ `textDocument/didClose` - Document closed

**Remaining Work:**
- [ ] Parse file content into ASTDB on `didOpen`
- [ ] Update ASTDB on `didChange` (incremental updates)
- [ ] Clear ASTDB state on `didClose`
- [ ] Return diagnostics (parse errors, type errors)
- [ ] Test with VS Code (live error reporting)

**Implementation:**
```zig
// daemon/lsp_server.zig
fn handleDidOpen(self: *Self, params: DidOpenParams) !void {
    const uri = params.textDocument.uri;
    const text = params.textDocument.text;
    
    // Parse into ASTDB
    const unit_id = try self.astdb.createUnit(uri);
    const parse_result = try janus_parser.parse(self.allocator, text, unit_id);
    
    // Generate diagnostics
    var diagnostics = try self.generateDiagnostics(parse_result);
    try self.sendDiagnostics(uri, diagnostics);
}

fn handleDidChange(self: *Self, params: DidChangeParams) !void {
    // For now: full re-parse (incremental parsing in v0.2.3+)
    const uri = params.textDocument.uri;
    const text = params.contentChanges[0].text;
    
    // Clear and re-parse
    try self.astdb.clearUnit(uri);
    const unit_id = try self.astdb.createUnit(uri);
    const parse_result = try janus_parser.parse(self.allocator, text, unit_id);
    
    // Update diagnostics
    var diagnostics = try self.generateDiagnostics(parse_result);
    try self.sendDiagnostics(uri, diagnostics);
}
```

**Verification:**
- Open `.jan` file in VS Code
- Introduce syntax error → Red squiggle appears
- Fix syntax error → Squiggle disappears
- Close file → No errors

---

### **Phase 3: ASTDB Query Infrastructure** (Day 3-4)
**Priority:** HIGH • **Effort:** 6-8 hours

**New File:** `compiler/astdb/query.zig`

**Required APIs:**

#### 3.1 Position → NodeId Mapping
```zig
pub fn queryNodeAtPosition(
    astdb: *AstDB,
    unit_id: UnitId,
    line: u32,
    character: u32
) !?NodeId {
    // Binary search through nodes by token range
    const nodes = astdb.getNodesInUnit(unit_id);
    
    for (nodes) |node_id| {
        const range = astdb.getNodeRange(node_id);
        if (range.contains(line, character)) {
            return node_id;
        }
    }
    
    return null;
}
```

#### 3.2 Symbol Resolution
```zig
pub fn queryDefinition(
    astdb: *AstDB,
    symbol_table: *SymbolTable,
    node_id: NodeId
) !?NodeId {
    // Get symbol at position
    const symbol_name = astdb.getNodeSymbol(node_id) orelse return null;
    
    // Lookup in symbol table
    const def_id = symbol_table.lookup(symbol_name) orelse return null;
    
    return def_id;
}
```

#### 3.3 Find All References
```zig
pub fn querySymbolReferences(
    astdb: *AstDB,
    symbol_table: *SymbolTable,
    symbol_name: []const u8
) ![]NodeId {
    var refs = std.ArrayList(NodeId).init(astdb.allocator);
    
    // Scan all units for references
    for (astdb.units.items) |unit| {
        const nodes = astdb.getNodesInUnit(unit.id);
        for (nodes) |node_id| {
            const sym = astdb.getNodeSymbol(node_id) orelse continue;
            if (std.mem.eql(u8, sym, symbol_name)) {
                try refs.append(node_id);
            }
        }
    }
    
    return refs.toOwnedSlice();
}
```

#### 3.4 Type Hover Information
```zig
pub fn queryNodeType(
    astdb: *AstDB,
    type_system: *TypeSystem,
    node_id: NodeId
) !?TypeId {
    // Get inferred type from type system
    return type_system.getNodeType(node_id);
}
```

**Verification:**
```bash
# Unit tests
zig build test-astdb-query

# Integration test
janus query node --file=examples/hello.jan --line=5 --col=10
# Expected: NodeId, type, definition location
```

---

### **Phase 4: LSP Feature Implementation** (Day 5-6)
**Priority:** HIGH • **Effort:** 8-12 hours

#### 4.1 Hover (`textDocument/hover`)
**Feature:** Show type and documentation on hover

```zig
fn handleHover(self: *Self, params: HoverParams) !?Hover {
    const uri = params.textDocument.uri;
    const line = params.position.line;
    const char = params.position.character;
    
    // Find node at position
    const unit_id = try self.astdb.getUnitByUri(uri);
    const node_id = try query.queryNodeAtPosition(
        self.astdb, 
        unit_id, 
        line, 
        char
    ) orelse return null;
    
    // Get type information
    const type_id = try query.queryNodeType(
        self.astdb,
        self.type_system,
        node_id
    ) orelse return null;
    
    const type_name = self.type_system.getTypeName(type_id);
    
    return Hover{
        .contents = .{ .value = type_name },
        .range = self.astdb.getNodeRange(node_id),
    };
}
```

**Test:**
- Hover over variable → See type (e.g., `i32`, `string`)
- Hover over function → See signature
- Hover over type → See definition

#### 4.2 Go To Definition (`textDocument/definition`)
**Feature:** Jump to symbol definition

```zig
fn handleDefinition(self: *Self, params: DefinitionParams) !?Location {
    const uri = params.textDocument.uri;
    const line = params.position.line;
    const char = params.position.character;
    
    // Find node at position
    const unit_id = try self.astdb.getUnitByUri(uri);
    const node_id = try query.queryNodeAtPosition(
        self.astdb,
        unit_id,
        line,
        char
    ) orelse return null;
    
    // Resolve definition
    const def_id = try query.queryDefinition(
        self.astdb,
        self.symbol_table,
        node_id
    ) orelse return null;
    
    // Get definition location
    const def_range = self.astdb.getNodeRange(def_id);
    const def_uri = self.astdb.getNodeUri(def_id);
    
    return Location{
        .uri = def_uri,
        .range = def_range,
    };
}
```

**Test:**
- Ctrl+Click variable → Jump to declaration
- Ctrl+Click function call → Jump to function definition
- Ctrl+Click type → Jump to type definition

#### 4.3 Find References (`textDocument/references`)
**Feature:** Find all usages of a symbol

```zig
fn handleReferences(self: *Self, params: ReferenceParams) ![]Location {
    const uri = params.textDocument.uri;
    const line = params.position.line;
    const char = params.position.character;
    
    // Find symbol at position
    const unit_id = try self.astdb.getUnitByUri(uri);
    const node_id = try query.queryNodeAtPosition(
        self.astdb,
        unit_id,
        line,
        char
    ) orelse return &[_]Location{};
    
    const symbol_name = self.astdb.getNodeSymbol(node_id) orelse return &[_]Location{};
    
    // Find all references
    const ref_nodes = try query.querySymbolReferences(
        self.astdb,
        self.symbol_table,
        symbol_name
    );
    
    // Convert to locations
    var locations = std.ArrayList(Location).init(self.allocator);
    for (ref_nodes) |ref_id| {
        try locations.append(.{
            .uri = self.astdb.getNodeUri(ref_id),
            .range = self.astdb.getNodeRange(ref_id),
        });
    }
    
    return locations.toOwnedSlice();
}
```

**Test:**
- Right-click variable → "Find All References"
- See all usages highlighted
- Navigate between references

---

### **Phase 5: VS Code Extension Integration** (Day 7)
**Priority:** HIGH • **Effort:** 2-4 hours

**File:** `tools/vscode/src/extension.ts`

**Changes:**
```typescript
import * as path from 'path';
import { workspace, ExtensionContext } from 'vscode';
import {
    LanguageClient,
    LanguageClientOptions,
    ServerOptions,
    TransportKind
} from 'vscode-languageclient/node';

let client: LanguageClient;

export function activate(context: ExtensionContext) {
    // Get LSP server path from configuration
    const config = workspace.getConfiguration('janus');
    const serverPath = config.get<string>('lsp.serverPath', './zig-out/bin/janus-lsp');

    const serverOptions: ServerOptions = {
        command: serverPath,
        args: [],
        options: {
            env: process.env
        }
    };

    const clientOptions: LanguageClientOptions = {
        documentSelector: [{ scheme: 'file', language: 'janus' }],
        synchronize: {
            fileEvents: workspace.createFileSystemWatcher('**/*.jan')
        }
    };

    client = new LanguageClient(
        'janusLsp',
        'Janus Language Server',
        serverOptions,
        clientOptions
    );

    client.start();
}

export function deactivate(): Thenable<void> | undefined {
    if (!client) {
        return undefined;
    }
    return client.stop();
}
```

**File:** `tools/vscode/package.json` (Update)
```json
{
  "contributes": {
    "configuration": {
      "type": "object",
      "title": "Janus",
      "properties": {
        "janus.lsp.serverPath": {
          "type": "string",
          "default": "./zig-out/bin/janus-lsp",
          "description": "Path to the Janus LSP server executable"
        }
      }
    }
  },
  "activationEvents": [
    "onLanguage:janus"
  ]
}
```

**Build & Install:**
```bash
# Build extension
cd tools/vscode
npm install
npm run compile
vsce package

# Install locally
code --install-extension janus-lang-0.2.2.vsix
```

**Verification:**
- Open `.jan` file
- Verify syntax highlighting works
- Hover over identifier → See type
- Ctrl+Click → Go to definition
- Right-click → Find references
- Introduce error → See diagnostic

---

## 📊 Success Criteria

### Minimum Viable LSP (v0.2.2-0 Release)

- [ ] **Handshake:** LSP server starts and responds to `initialize`
- [ ] **Diagnostics:** Parse errors shown in VS Code
- [ ] **Hover:** Type information displayed on hover
- [ ] **Go To Definition:** Navigate to symbol definitions
- [ ] **Find References:** Locate all symbol usages
- [ ] **Document Sync:** Changes reflected in real-time

### Performance Targets

- **Initialization:** < 500ms for typical project
- **Hover Response:** < 50ms
- **Go To Definition:** < 100ms
- **Diagnostics Update:** < 200ms after edit

---

## 🔬 Testing Strategy

### Unit Tests
```bash
zig build test-lsp          # LSP protocol handling
zig build test-astdb-query  # Query infrastructure
```

### Integration Tests
```bash
# Manual LSP protocol test
./scripts/test_lsp_handshake.sh

# VS Code extension test
code --extensionDevelopmentPath=./tools/vscode tests/fixtures/
```

### Manual Verification
1. Install extension
2. Open `examples/hello.jan`
3. Test each LSP feature
4. Verify no crashes or hangs

---

## 📚 Documentation Tasks

- [ ] **LSP Usage Guide** (`docs/manual/tooling-lsp.md`)
  - Installation instructions
  - VS Code setup
  - Configuration options
  - Troubleshooting

- [ ] **Editor Setup** (`docs/manual/editor-setup.md`)
  - VS Code configuration
  - Neovim integration (future)
  - Emacs integration (future)

- [ ] **CHANGELOG Update**
  - Document LSP features
  - Migration notes (if any)

- [ ] **README Update**
  - Add LSP feature showcase
  - Update editor support section

---

## 🚨 Known Limitations (v0.2.2)

### Acceptable Trade-offs
- **No Incremental Parsing:** Full re-parse on every change (fast enough for v0.2.2)
- **Single-File Analysis:** Cross-file references limited (multi-file in v0.2.3+)
- **No Code Completion:** Autocomplete deferred to v0.2.3
- **No Signature Help:** Parameter hints deferred to v0.2.3
- **No Rename Refactoring:** Symbol renaming deferred to v0.2.3

### Deferred to v0.2.3+
- Incremental document parsing
- Multi-file project analysis
- Code completion (intellisense)
- Signature help
- Rename refactoring
- Code actions (quick fixes)
- Semantic tokens (semantic highlighting)

---

## 🔗 Related Files

### To Modify
- `cmd/janus-lsp/main.zig` - Fix I/O API, ASTDB integration
- `daemon/lsp_server.zig` - Implement feature handlers
- `tools/vscode/src/extension.ts` - LSP client configuration
- `tools/vscode/package.json` - Extension metadata

### To Create
- `compiler/astdb/query.zig` - Position-based query API
- `docs/manual/tooling-lsp.md` - LSP usage guide
- `docs/manual/editor-setup.md` - Editor configuration

### Dependencies
- ✅ `compiler/astdb/core.zig` - Node storage
- ✅ `compiler/semantic/symbol_table.zig` - Symbol tracking
- ✅ `compiler/semantic/type_system.zig` - Type information
- ✅ `compiler/libjanus/janus_parser.zig` - Parser

---

## 🧭 Strategic Context

### Why LSP Matters (The Smalltalk Vision)

The LSP server is **not just IDE support**. It embodies the **Smalltalk philosophy** adapted for modern systems programming:

| Smalltalk Image | Janus ASTDB + LSP | Benefit |
|:----------------|:------------------|:--------|
| Live object inspection | Hover type info | Instant feedback |
| Class browser | Workspace symbols | Navigable codebase |
| Method senders | Find references | Impact analysis |
| Debugger | DAP (future) | Interactive debugging |
| Image modification | Hot reload (future) | Live development |

**The Janus Advantage:** Unlike Smalltalk's binary image, our ASTDB is:
- ✅ **Git-friendly** (text-based project structure)
- ✅ **Corruption-proof** (transactional integrity)
- ✅ **AI-readable** (structured semantic queries)
- ✅ **Multi-language** (VS Code, Neovim, Emacs)

---

## 📅 Estimated Timeline

| Phase | Duration | Dependencies |
|:------|:---------|:-------------|
| **Phase 1:** I/O Fix + Handshake | 0.5 days | None |
| **Phase 2:** Document Sync | 1 day | Phase 1 |
| **Phase 3:** ASTDB Query API | 2 days | Phase 2 |
| **Phase 4:** LSP Features | 2 days | Phase 3 |
| **Phase 5:** VS Code Integration | 1 day | Phase 4 |
| **Documentation** | 0.5 days | Parallel |
| **Testing & Polish** | 1 day | Phase 5 |

**Total:** 7-8 days (1-2 weeks)

---

## ✅ Definition of Done

**v0.2.2-0 is complete when:**

1. ✅ VS Code extension installs without errors
2. ✅ LSP server starts and connects automatically
3. ✅ Parse errors show as red squiggles in real-time
4. ✅ Hover shows correct type information
5. ✅ Go To Definition navigates to correct location
6. ✅ Find References shows all usages
7. ✅ Documentation is complete and accurate
8. ✅ Test suite passes (LSP-specific tests)
9. ✅ VERSION bumped to `0.2.2-0`
10. ✅ CHANGELOG updated with LSP features

---

## 🎯 Post-v0.2.2 Roadmap

### v0.2.3: Advanced LSP Features
- Code completion (autocomplete)
- Signature help (parameter hints)
- Incremental parsing
- Multi-file analysis
- Rename refactoring

### v0.2.4: Debugger Integration
- Debug Adapter Protocol (DAP)
- Breakpoints
- Variable inspection
- Step debugging

### v0.3.0: Pipeline Syntax (The Grafting)
- UFCS (Uniform Function Call Syntax)
- Pipeline operator (`|>`)
- Tag functions
- See: `FUTURE_PLAN-v0.3.0.md`

---

**Status:** Ready for focused implementation session  
**Blocked By:** Zig 0.15 I/O API migration (30min fix)  
**Next Action:** Fix `cmd/janus-lsp/main.zig` buffered I/O

— Voxis Forge, 2025-12-16
