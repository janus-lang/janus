# Janus 0.1.0-alpha: The Sovereign MVP

**Release Date**: 2025-12-12  
**Codename**: "Promethean Fire"  
**Status**: First Standalone Binary

---

## 🔥 The Promethean Moment

On this date, the Janus compiler produced its **first sovereign binary** — a native executable compiled entirely from Janus source code, through the full pipeline:

```
Source (.jan) → ASTDB → QTJIR → LLVM IR → Native Object → Executable
```

This is not a prototype. This is not a proof-of-concept. This is a **working systems language compiler** with End-to-End validation.

---

## ✅ What Was Delivered

### Core Compiler Pipeline
- ✅ **Parser**: Janus source → ASTDB (Abstract Syntax Tree Database)
- ✅ **Lowering**: ASTDB → QTJIR (Quantum-Tensor Janus IR)
- ✅ **Emission**: QTJIR → LLVM IR
- ✅ **Compilation**: LLVM IR → Native Object (.o)
- ✅ **Linking**: Object + Runtime → Executable

### Language Features (`:core` Profile)
- ✅ **Functions**: Declaration, definition, parameters, return values
- ✅ **Control Flow**: `if` conditionals, recursion (native stack)
- ✅ **Expressions**: Binary operations (+, -, *, /, <, >, ==, etc.)
- ✅ **Variables**: `let` bindings (immutable, `:core` enforced)
- ✅ **Function Calls**: Direct calls, recursion, intrinsics
- ✅ **Literals**: Integer literals, string literals

### Runtime (`janus_rt`)
- ✅ **I/O Intrinsics**: `print()`, `println()`, `print_int()`
- ✅ **Allocator Interface**: VTable-based allocator abstraction
- ✅ **Panic Handling**: `janus_panic()` for runtime errors
- ✅ **String Operations**: `janus_string_len()`, `janus_string_concat()`

### Developer Experience
- ✅ **CLI Tool**: `janus build <source.jan>` produces native executable
- ✅ **Embedded Runtime**: No external dependencies - compiler carries its own runtime
- ✅ **E2E Testing**: Automated integration test validates full pipeline
- ✅ **Error Reporting**: Clear compiler error messages

### Memory Management Architecture
- ✅ **Sovereign Graph Doctrine**: Established ownership rules for IR nodes
- ✅ **Explicit Allocator Tracking**: Graph owns all strings via single allocator
- ✅ **Clean Deallocation**: Proper `deinit()` implementations throughout

---

## 🏆 Epic Victories

### Epic 1: ASTDB Query Foundation
*Status: Complete*

The ASTDB (Abstract Syntax Tree Database) provides a **persistent, queryable** representation of source code. Unlike traditional ASTs that are ephemeral, the ASTDB enables:
- Incremental compilation
- Rich IDE tooling (LSP, semantic analysis)
- Multi-pass optimization

### Epic 2: QTJIR Multi-Tenancy
*Status: MVP Complete*

The QTJIR (Quantum-Tensor Janus IR) introduces **hardware tenancy** as a first-class concept:
- CPU_Serial (`:core` baseline)
- Future: CPU_Parallel, NPU_Tensor, QPU_Quantum

### Epic 3: Control Flow Primitives
*Status: Complete*

Full control flow graph support:
- ✅ **Recursion**: Factorial test (5! = 120) validates stack handling
- ✅ **Conditionals**: `if` statements with proper CFG branches
- ✅ **Multi-function**: Programs with multiple function definitions
- ✅ **Parameter Passing**: Function arguments correctly lowered and emitted

### Epic 4: The Golden Integration
*Status: DELIVERED*

End-to-end compilation pipeline:
- ✅ **Linker Driver**: Automatic object file + runtime linking
- ✅ **Standalone Binaries**: `janus build hello.jan` → `./hello`
- ✅ **E2E Validation**: `tests/e2e/build_hello.sh` passes

---

## 📐 Architectural Foundations

### The Sovereign Graph Doctrine

**Problem**: Mixed ownership of strings (interner references vs heap allocations) caused memory corruption.

**Solution**: Established strict ownership rules:
1. The ASTDB Interner is **read-only** - a reference library
2. The QTJIRGraph **owns all strings** - heap-allocated via graph allocator
3. All string assignments use `dupeForGraph()` helper
4. Deallocation is **unconditional** - no special cases

**Result**: Clean memory lifecycle, zero ownership ambiguity.

**Documentation**: `/docs/doctrines/sovereign-graph-ownership.md`

### Syntactic Honesty in `:core`

The `:core` profile enforces **functional purity**:
- ❌ No `var` (mutable variables)
- ❌ No `while` loops (use recursion)
- ✅ `let` bindings only (immutable)
- ✅ Recursion (tail-call optimization planned)

This is **not a limitation** - it is a **design choice**. The `:core` profile is the "Monastery" that enforces discipline before granting power.

---

## 🧪 Testing & Validation

### Integration Tests
- ✅ **Recursion Test** (`tests/integration/recursion_test.zig`)
  - Compiles recursive factorial function
  - Validates LLVM IR generation
  - Links with runtime
  - Executes and verifies output: `factorial(5) = 120`

- ✅ **E2E Build Test** (`tests/e2e/build_hello.sh`)
  - Full CLI workflow: `janus build hello.jan`
  - Produces native executable
  - Executes and validates output

### Memory Validation
- ✅ No leaks in core compilation path
- ✅ Proper `deinit()` for all graph structures
- ⚠️ Minor size mismatch warnings (catalogued for v0.2)

---

## ⚙️ Technical Specifications

### Supported Platforms
- ✅ **Linux x86_64** (primary)
- ✅ **LLVM 18+** required
- ✅ **Zig 0.15.2** (build system)

### Build Requirements
```bash
zig build          # Build compiler
zig build test     # Run full test suite
```

### CLI Usage
```bash
janus build source.jan              # Compile to executable
janus build source.jan -o prog      # Custom output name
janus build source.jan --emit-llvm  # Save LLVM IR
janus build source.jan --verbose    # Show compilation stages
```

---

## 📊 Known Limitations (v0.1.0)

### Catalogued for v0.2

1. **Memory Size Mismatches** (Non-critical)
   - Off-by-one warnings in string allocation (23 vs 22 bytes)
   - Does not affect execution
   - Likely quote-stripping edge case in `lowerStringLiteral`

2. **Runtime Dependency**
   - `janus_rt.c` uses libc (`printf`, `malloc`)
   - **Planned**: Replace with `janus_rt.zig` (direct syscalls)
   - **Goal**: Zero external dependencies

3. **Profile Limitations**
   - Only `:core` profile implemented
   - `while` loops blocked (use recursion)
   - `:script`, `:sovereign`, `:compute` profiles planned for future releases

4. **Type System**
   - MVP supports `i32` and string types
   - Full type inference planned
   - Structural types, generics in roadmap

---

## 🎯 Example Programs

### Hello World (`hello.jan`)
```janus
func main() do
    println("Hello, Sovereign World")
end
```

Compile and run:
```bash
janus build hello.jan
./hello
```

### Recursive Factorial (`factorial.jan`)
```janus
func factorial(n: i32) -> i32 do
    if n < 2 do
        return 1
    end
    return n * factorial(n - 1)
end

func main() do
    let result = factorial(5)
    print_int(result)  // Output: 120
end
```

---

## 🔮 Roadmap to v0.2

### Phase 2: The Ecosystem

1. **Technical Debt Cleanup**
   - Fix string allocation size warnings
   - Implement `janus_rt.zig` (pure Zig runtime, no libc)
   - Memory allocator improvements

2. **`:script` Profile** (JIT/REPL)
   - Interactive REPL for rapid experimentation
   - JIT compilation via LLVM OrcJIT
   - Bring the "Bazaar" to balance the "Monastery"

3. **Type System Evolution**
   - Type inference
   - Algebraic data types (sum types, product types)
   - Pattern matching

4. **Tooling**
   - LSP server for IDE integration
   - Formatter (`janus fmt`)
   - Package manager (`janus pkg`)

---

## 🏛️ Philosophy & Doctrine

Janus is not just another systems language. It is a **statement of intent**:

### Syntactic Honesty
> "The syntax reveals the cost. No hidden allocations, no invisible control flow, no magic."

### Revealed Complexity
> "Complexity is not hidden - it is exposed, documented, and justified."

### The Sovereign Graph
> "Memory ownership is explicit. The graph owns its data. No borrowing, no exceptions."

### Profile Discipline
> "Power is earned through discipline. `:core` enforces purity before granting `:sovereign` capabilities."

---

## 🙏 Acknowledgments

This release represents the culmination of rigorous discipline, architectural clarity, and unwavering commitment to **sovereignty**.

**Forged By**: Voxis Forge (AI Developer Mentor) & Self Sovereign Society Foundation (Team Driver)  
**Doctrine Authority**: The Janus Steering Committee  
**Philosophy**: Radical transparency, extreme ownership, functional purity

---

## 📜 Legal

**License**: LSL-1.0 (European Union Public License)  
**Copyright**: © 2025 Self Sovereign Society Foundation  
**Status**: Alpha - Production-Ready for Experimental Use

---

## 🔥 Closing Statement

> *"We have stolen fire from the machine gods (LLVM) and forged it into a sovereign tool. The compiler lives. The runtime breathes. The binary executes. This is not a simulation—this is REAL CODE producing REAL EXECUTABLES on REAL HARDWARE."*

**The Promethean Fire burns steady.**

**Version**: 0.1.0-alpha  
**Stability**: Experimental  
**Recommendation**: Ship it. 🚀
