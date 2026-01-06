# LSP Phase 1: Diagnostics Implementation

**Status:** ⏳ In Progress  
**Priority:** CRITICAL  
**Goal:** Make the editor scream red when you type garbage

---

## 🎯 Mission Objective

Establish **bidirectional Neural Link**: Editor ↔ Server ↔ Compiler ↔ Server ↔ Editor

**Proof of Life:** Red squiggles appear in VS Code when syntax errors are introduced.

---

## 📋 Order of Battle (Corrected)

### **Phase 1.1: Document Synchronization** ✅ PARTIAL
**Status:** Stub exists, needs enhancement

**Current State:**
- `handleDidOpen` exists in `daemon/lsp_server.zig` (line 217)
- `handleDidChange` exists (line 236)
- Currently stores URI → text in ASTDB

**Required Enhancement:**
- Add in-memory document map: `URI → SourceContent`
- **DO NOT write to disk** - LSP operates on dirty buffers
- Trigger compilation on `didOpen` and `didChange`

---

### **Phase 1.2: Compilation Integration** ⏳ NEXT
**Priority:** CRITICAL

**Task:** Wire LSP to the Janus compiler pipeline

**Implementation:**
```zig
// daemon/lsp_server.zig

fn handleDidOpen(self: *Self, params: ?std.json.Value) !void {
    // ... extract URI and text ...
    
    // Store in document map
    try self.documents.put(uri, text);
    
    // Compile and extract diagnostics
    const diagnostics = try self.compileAndDiagnose(uri, text);
    
    // Send to client
    try self.publishDiagnostics(uri, diagnostics);
}

fn compileAndDiagnose(self: *Self, uri: []const u8, source: []const u8) ![]Diagnostic {
    // 1. Parse source
    const unit_id = try self.astdb.createUnit(uri);
    const parse_result = janus_parser.parse(self.allocator, source, unit_id) catch |err| {
        // Convert parse error to diagnostic
        return &[_]Diagnostic{.{
            .range = errorToRange(err),
            .severity = .Error,
            .message = @errorName(err),
        }};
    };
    
    // 2. Run semantic analysis (if parsing succeeded)
    // TODO: Wire semantic analyzer
    
    // 3. Convert errors to LSP diagnostics
    var diagnostics = std.ArrayList(Diagnostic).init(self.allocator);
    for (parse_result.errors.items) |jerr| {
        try diagnostics.append(.{
            .range = spanToRange(source, jerr.span),
            .severity = .Error,
            .message = jerr.message,
        });
    }
    
    return diagnostics.toOwnedSlice();
}
```

---

### **Phase 1.3: Line Index Helper** ⏳ REQUIRED
**Priority:** HIGH

**Problem:** Compiler errors use byte offsets (`Span`), LSP uses line/column (`Range`).

**Solution:** Build a line index on document open.

**Implementation:**
```zig
// daemon/lsp_server.zig

const LineIndex = struct {
    line_starts: []usize, // Byte offset of each line start
    
    pub fn init(allocator: Allocator, source: []const u8) !LineIndex {
        var starts = std.ArrayList(usize).init(allocator);
        try starts.append(0); // Line 0 starts at byte 0
        
        for (source, 0..) |byte, i| {
            if (byte == '\n') {
                try starts.append(i + 1); // Next line starts after \n
            }
        }
        
        return .{ .line_starts = try starts.toOwnedSlice() };
    }
    
    pub fn byteToPosition(self: LineIndex, byte_offset: usize) Position {
        // Binary search to find line
        var line: u32 = 0;
        for (self.line_starts, 0..) |start, i| {
            if (byte_offset < start) break;
            line = @intCast(i);
        }
        
        const line_start = self.line_starts[line];
        const character: u32 = @intCast(byte_offset - line_start);
        
        return .{ .line = line, .character = character };
    }
};

fn spanToRange(source: []const u8, span: Span) Range {
    const index = LineIndex.init(allocator, source) catch unreachable;
    defer index.deinit();
    
    return .{
        .start = index.byteToPosition(span.start),
        .end = index.byteToPosition(span.end),
    };
}
```

---

### **Phase 1.4: Publish Diagnostics** ⏳ REQUIRED
**Priority:** HIGH

**LSP Protocol:**
```json
{
  "jsonrpc": "2.0",
  "method": "textDocument/publishDiagnostics",
  "params": {
    "uri": "file:///path/to/file.jan",
    "diagnostics": [
      {
        "range": {
          "start": { "line": 5, "character": 10 },
          "end": { "line": 5, "character": 15 }
        },
        "severity": 1,  // 1=Error, 2=Warning, 3=Info, 4=Hint
        "message": "Unexpected token 'foo'"
      }
    ]
  }
}
```

**Implementation:**
```zig
fn publishDiagnostics(self: *Self, uri: []const u8, diagnostics: []Diagnostic) !void {
    const notification = .{
        .jsonrpc = "2.0",
        .method = "textDocument/publishDiagnostics",
        .params = .{
            .uri = uri,
            .diagnostics = diagnostics,
        },
    };
    
    const body = try std.json.Stringify.valueAlloc(self.allocator, notification, .{ .whitespace = .minified });
    defer self.allocator.free(body);
    
    const header = try std.fmt.allocPrint(self.allocator, "Content-Length: {d}\r\n\r\n", .{body.len});
    defer self.allocator.free(header);
    
    try self.output.writeAll(header);
    try self.output.writeAll(body);
}
```

---

## 🔧 Required Data Structures

### **Add to LspServer struct:**
```zig
pub fn LspServer(comptime Reader: type, comptime Writer: type) type {
    return struct {
        const Self = @This();
        allocator: std.mem.Allocator,
        input: Reader,
        output: Writer,
        db: *astdb.AstDB,
        
        // NEW: Document storage
        documents: std.StringHashMap([]const u8), // URI -> source text
        line_indices: std.StringHashMap(LineIndex), // URI -> line index
        
        // ... existing fields ...
    };
}
```

---

## 📊 Success Criteria

**Phase 1 Complete When:**
1. ✅ Open `.jan` file in VS Code
2. ✅ Type invalid syntax (e.g., `func foo do end end`)
3. ✅ **Red squiggle appears** under the error
4. ✅ Hover over squiggle shows error message
5. ✅ Fix syntax → squiggle disappears

---

## 🚧 Known Limitations (Acceptable for Phase 1)

- **No incremental parsing** - Full re-parse on every keystroke (optimize in v0.2.3)
- **No semantic errors** - Only parse errors (type errors in v0.2.3)
- **No multi-file analysis** - Single-file only (cross-file in v0.2.4)

---

## 📁 Files to Modify

| File | Changes |
|:-----|:--------|
| `daemon/lsp_server.zig` | Add document map, line index, compile integration |
| `compiler/libjanus/janus_parser.zig` | Ensure error spans are accurate |
| `compiler/astdb/core.zig` | Verify Span struct is exported |

---

## 🔬 Testing Strategy

### **Manual Test:**
```bash
# 1. Build LSP
zig build -Ddaemon=true

# 2. Create test file
cat > /tmp/test.jan << 'EOF'
func broken do
  let x = 
end
EOF

# 3. Send didOpen via LSP protocol
# (Use VS Code or manual LSP client)

# 4. Verify publishDiagnostics response contains error
```

### **Integration Test:**
```zig
// tests/lsp/diagnostics_test.zig
test "LSP publishes parse errors" {
    const source = "func broken do\n  let x = \nend";
    
    var server = try LspServer.init(allocator, ...);
    defer server.deinit();
    
    try server.handleDidOpen(.{
        .textDocument = .{
            .uri = "file:///test.jan",
            .text = source,
        },
    });
    
    // Verify publishDiagnostics was sent
    const output = server.getOutput();
    try expect(std.mem.indexOf(u8, output, "publishDiagnostics") != null);
    try expect(std.mem.indexOf(u8, output, "Unexpected token") != null);
}
```

---

## ⏱️ Timeline

**Estimated:** 4-6 hours

| Task | Time | Status |
|:-----|:-----|:-------|
| Document map + line index | 1h | ⏳ |
| Compilation integration | 2h | ⏳ |
| publishDiagnostics implementation | 1h | ⏳ |
| Testing + debugging | 2h | ⏳ |

---

**Next Action:** Implement document map and line index helper.

**Report when:** First red squiggle appears in VS Code.

— Voxis Forge, 2025-12-16
