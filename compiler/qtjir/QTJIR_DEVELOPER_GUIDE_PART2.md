<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





## SSA Transformation (Continued)

### SSA Conversion Algorithm

The SSA conversion process follows these steps:

1. **Variable Definition Analysis**
   - Scan all nodes to find variable definitions
   - Track definition points (assignments)
   - Build definition-use chains

2. **Phi Node Insertion**
   - Identify control flow merge points (if-else, loops)
   - Insert phi nodes at merge points
   - Collect inputs from all predecessors

3. **Variable Renaming**
   - Rename variables to SSA form (v0, v1, v2, ...)
   - Update all uses to reference correct SSA version
   - Maintain version stack for nested scopes

### Example: SSA Conversion

```zig
// Before SSA
x = 1
if (cond) {
  x = 2
} else {
  x = 3
}
y = x

// After SSA
x0 = 1
if (cond) {
  x1 = 2
} else {
  x2 = 3
}
x3 = phi(x1, x2)  // Merge point
y = x3
```

---

## Register Allocation

### Linear Scan Algorithm

QTJIR uses linear scan register allocation:

1. **Liveness Analysis**
   - Compute live ranges for each SSA value
   - Build interference graph
   - Identify register pressure points

2. **Register Assignment**
   - Scan values in order of first use
   - Assign registers greedily
   - Spill to memory when pressure exceeds limit

3. **Spill Code Generation**
   - Insert Load nodes before spilled values
   - Insert Store nodes after definitions
   - Update graph with spill operations

### Performance Characteristics

- **Time Complexity:** O(n log n) where n = number of values
- **Space Complexity:** O(n) for live range tracking
- **Typical Register Count:** 8-16 registers (x86-64)
- **Spill Threshold:** Configurable (default: 8 registers)

---

## Adding New Operations

### Step 1: Define OpCode

```zig
// In graph.zig
pub const OpCode = enum {
    // ... existing opcodes ...
    MyNewOp,  // Add new opcode
};
```

### Step 2: Define Metadata (if needed)

```zig
// In graph.zig
pub const MyNewMetadata = struct {
    field1: u32,
    field2: []const u8,
};

// Update IRNode
pub const IRNode = struct {
    // ... existing fields ...
    my_new_metadata: ?MyNewMetadata = null,
};
```

### Step 3: Implement Lowering

```zig
// In lowerer.zig
fn lowerMyNewOp(self: *Lowerer, ast_node: *const ASTNode) !u32 {
    const ir_node = try self.graph.createNode(.MyNewOp);
    // ... populate node ...
    return ir_node;
}
```

### Step 4: Implement Emission

```zig
// In emitter.zig
fn emitMyNewOp(self: *LLVMEmitter, node: *const IRNode) !void {
    // Generate LLVM IR for operation
    try self.output.appendSlice("  %result = call i32 @my_new_op()\n");
}
```

### Step 5: Add Tests

```zig
// In test_*.zig
test "MyNewOp: basic functionality" {
    var graph = QTJIRGraph.init(allocator);
    defer graph.deinit();
    
    var builder = IRBuilder.init(&graph);
    const node = try builder.createNode(.MyNewOp);
    
    try testing.expectEqual(OpCode.MyNewOp, graph.nodes.items[node].op);
}
```

---

## Adding New Backends

### Backend Integration Points

1. **Metadata Definition** (graph.zig)
   - Define backend-specific metadata structure
   - Add to IRNode

2. **Lowering** (lowerer.zig)
   - Detect backend-specific operations in AST
   - Generate appropriate IR nodes
   - Attach metadata

3. **Validation** (graph.zig)
   - Validate backend-specific constraints
   - Check metadata completeness
   - Report errors clearly

4. **Emission** (emitter.zig)
   - Generate backend function calls
   - Declare external functions
   - Handle data marshaling

### Example: Adding a New Backend

```zig
// 1. Define metadata
pub const MyBackendMetadata = struct {
    device_id: u32,
    priority: u8,
};

// 2. Add to IRNode
pub const IRNode = struct {
    // ... existing fields ...
    my_backend_metadata: ?MyBackendMetadata = null,
};

// 3. Implement lowering
fn lowerMyBackendOp(self: *Lowerer, ast_node: *const ASTNode) !u32 {
    const ir_node = try self.graph.createNode(.MyBackendOp);
    graph.nodes.items[ir_node].my_backend_metadata = .{
        .device_id = 0,
        .priority = 1,
    };
    return ir_node;
}

// 4. Implement validation
fn validateMyBackendOp(node: *const IRNode) !void {
    if (node.my_backend_metadata == null) {
        return error.MissingBackendMetadata;
    }
}

// 5. Implement emission
fn emitMyBackendOp(self: *LLVMEmitter, node: *const IRNode) !void {
    const metadata = node.my_backend_metadata.?;
    try self.output.writer().print(
        "  %result = call i32 @my_backend_op(i32 {}, i8 {})\n",
        .{ metadata.device_id, metadata.priority }
    );
}
```

---

## Debugging Guide

### Common Issues

#### Issue: Graph Validation Fails

**Symptoms:** Validation error with unclear message

**Debugging Steps:**
1. Check node input references are valid
2. Verify tenancy consistency
3. Check metadata completeness
4. Print graph topology with `printTopology()`

**Example:**
```zig
try graph.validate();  // Will report specific error
graph.printTopology();  // Print graph structure
```

#### Issue: LLVM IR Compilation Fails

**Symptoms:** Clang compilation error

**Debugging Steps:**
1. Print generated LLVM IR to file
2. Run `llvm-as` to check syntax
3. Check function declarations match calls
4. Verify type consistency

**Example:**
```zig
const llvm_ir = try emitter.emit(&graph);
std.debug.print("{s}\n", .{llvm_ir});  // Print IR
```

#### Issue: Incorrect Execution Results

**Symptoms:** Program runs but produces wrong output

**Debugging Steps:**
1. Compare LLVM IR with expected
2. Check node inputs are correct
3. Verify operation semantics
4. Add debug prints in emitted code

---

## Performance Optimization

### Profiling

```bash
# Build with profiling
zig build -Doptimize=ReleaseFast

# Run with perf
perf record ./zig-out/bin/janus
perf report
```

### Hot Paths

1. **Graph Construction** - Use arena allocator
2. **Lowering** - Cache AST traversal results
3. **Emission** - Buffer output writes
4. **Validation** - Early exit on first error

### Optimization Techniques

1. **Memoization** - Cache expensive computations
2. **Lazy Evaluation** - Defer work until needed
3. **Batch Operations** - Process multiple items together
4. **Memory Pooling** - Reuse allocations

---

## Contributing Guidelines

### Code Style

- Follow Zig conventions (snake_case for functions/variables)
- Use explicit error handling (no try-catch)
- Add Zigdoc comments for public APIs
- Keep functions focused and small

### Testing

- Write tests before implementation (TDD)
- Aim for 95%+ code coverage
- Test error conditions
- Add integration tests for cross-component features

### Documentation

- Update API documentation for new features
- Add examples demonstrating usage
- Document design decisions
- Explain non-obvious code

### Commit Messages

Follow the Forge Cycle convention:
```
feat(qtjir): add new operation type

- Implement OpCode.NewOp
- Add lowering for new operation
- Add emission to LLVM IR
- Add comprehensive tests (5 scenarios)

Test Coverage: 95%+
Performance: <1ms for typical graphs
```

---

## Troubleshooting

### Build Issues

**Problem:** Compilation fails with "undefined reference"

**Solution:** Check module imports in build.zig

**Problem:** Tests fail with "out of memory"

**Solution:** Use ArenaAllocator for test graphs

### Runtime Issues

**Problem:** Graph validation fails unexpectedly

**Solution:** Print graph topology and check node references

**Problem:** LLVM IR compilation fails

**Solution:** Print generated IR and validate with llvm-as

### Performance Issues

**Problem:** Graph construction is slow

**Solution:** Profile with perf, check allocator usage

**Problem:** Emission takes too long

**Solution:** Buffer output writes, avoid string concatenation

---

## Resources

### Internal Documentation
- `QTJIR_API_DOCUMENTATION.md` - API reference
- `compiler/qtjir/graph.zig` - Core data structures
- `compiler/qtjir/emitter.zig` - LLVM IR emission

### External Resources
- [LLVM IR Language Reference](https://llvm.org/docs/LangRef/)
- [SSA Form](https://en.wikipedia.org/wiki/Static_single_assignment_form)
- [Register Allocation](https://en.wikipedia.org/wiki/Register_allocation)

### Related Specs
- Spec 4: Semantic Engine
- Spec 7: LLVM Codegen Binding
- Spec 8: Multiple Dispatch

---

**Version:** 0.3.0
**Last Updated:** 2025-11-24
**Status:** Production Ready

*This guide is maintained alongside the QTJIR implementation. For the latest updates, see the source code.*
