<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Janus v0.3.0 Strategic Roadmap: The Grafting

**Target Release:** v0.3.0-0
**Codename:** The Grafting
**Motto:** "We are not building a language. We are building a composite weapon."

---

## 🧬 The Grafting Map (DNA Integration)

The Janus philosophy is not only invention, but synthesis. We identify the "Blade" (the killer feature) of existing languages ("The Corpse") and graft it onto our sovereign core following the Janus philosophy.

| The Corpse | The Blade (Feature) | Where it lives in Janus | Status |
| :--- | :--- | :--- | :--- |
| **Onyx** | WASM Velocity / Universal Artifact | **`wasm32-wasi` Backend** | ⏳ v0.3.0 |
| **Lobster** | Ghost Memory (CTRC) | **Owned Types (`~T`) / Flow Typing** | ⏳ v0.3.0 |
| **Forth** | Concatenative Composition | **Pipeline Operator (`|>`)** | ⏳ Planned |
| **J** | Array-Oriented Warfare | **`:compute` Profile / Tensor Types** | 🔮 Future |
| **Icon** | Goal-Directed/Generators | **`yield` / Implicit Iterators** | ⏳ Planned |
| **Smalltalk** | Live Introspection | **ASTDB / `janusd` Daemon** | 🏗️ **In Progress** |
| **Clojure** | Immutability / STM | **Actor Model / `:cluster` Profile** | 🔮 Future |
| **Nim** | AST-Based Metaprogramming | **`comptime` / Honest Sugar** | ⏳ Planned |
| **Mojo** | Progressive Disclosure | **Profiles (`:script` → `:sovereign`)** | ✅ **Core** |
| **V** | Hot Reload / Radical Simplicity | **`:script` JIT / `janus_parser.zig`** | 🏗️ **In Progress** |
| **Elm** | No Runtime Exceptions | **`Result` Types / Exhaustive Match** | 🏗️ **In Progress** |
| **Crystal** | Ruby Joy + Native Speed | **Postfix Guards / Tags / UFCS** | 🏗️ **In Progress** |
| **SPARK** | Formal Verification | **`spec` / `requires` / `ensures`** | 🔮 Future |
| **Inform** | Natural Language DSLs | **Tag Functions (`sql"..."`)** | ⏳ Planned |

---

## 🧬 The Architectural Core: Forth × Smalltalk

**Thesis:** Janus is **Type-Safe Forth with Smalltalk Introspection** hidden inside C-like syntax.

### The Dual Inheritance

| Forth (The Stack) | Smalltalk (The Image) | Janus (The Synthesis) |
|:------------------|:----------------------|:----------------------|
| Concatenative composition | Live object introspection | Pipeline operator (`\|>`) |
| Stack-based flow | Message passing | UFCS method chains |
| Dictionary (linked list) | Class browser | ASTDB (queryable graph) |
| `CREATE...DOES>` metaprogramming | Image modification | `comptime` blocks |
| `IMMEDIATE` words | Runtime evaluation | Tag functions (`sql"..."`) |
| No types, raw pointers | Dynamic typing | Static types + inference |

**What We Steal:**
1. **Concatenative Flow** - Forth's `data func1 func2` becomes Janus's `data |> func1() |> func2()`
2. **Live Dictionary** - Smalltalk's image becomes `janusd` + ASTDB (persistent, queryable AST)
3. **Compiler Kneels** - Forth's `IMMEDIATE` + Smalltalk's `doesNotUnderstand:` become `comptime` + honest sugar

**What We Burn:**
1. **Stack Discipline** - Humans can't manage implicit stacks. We use named parameters.
2. **Dictionary Corruption** - Forth lets you crash the system. We enforce transaction boundaries.
3. **Dynamic Chaos** - Smalltalk's runtime type errors become compile-time guarantees.

### The Three Grafts Explained

#### 1. **The Concatenative Flow** (Forth → Janus)

**Forth's Brutality:**
```forth
42 DUP * PRINT   \ Stack: 42 -> 42 42 -> 1764 -> (print)
```

**Janus's Refinement:**
```janus
42 |> square() |> print()   // Named functions, left-to-right
```

**Why:** Forth proved that reading data transformations **left-to-right** (concatenatively) is cognitively superior to inside-out nesting. We keep the flow, discard the stack management hell.

#### 2. **The Living Dictionary** (Smalltalk → Janus)

**Smalltalk's Magic:**
```smalltalk
Object inspect.     " Open live object browser "
System browse.      " Modify running code "
```

**Janus's Discipline:**
```bash
$ janusd query node --id=42 --inspect
$ janusd query symbol --name="fetch_user" --references
```

**Why:** Smalltalk proved that the **runtime environment should BE the development environment**. Our `janusd` daemon + ASTDB achieves this with:
- **Live AST queries** (position → node, symbol → references)
- **Type hover** (LSP integration)
- **Hot reload** (`:script` profile JIT)
- **Transactional safety** (unlike Forth/Smalltalk, we don't let you corrupt the system)

#### 3. **Compiler Kneels** (Forth + Nim/Zig → Janus)

**Forth's God Mode:**
```forth
: UNLESS ( flag -- ) 0= IF ;   \ Define new control structure
```

**Janus's Honest Sugar:**
```janus
comptime {
  let query_parts = parse_sql_template(raw_string);
  return build_parameterized_query(query_parts);
}
```

**Why:** Forth's `IMMEDIATE` words and Smalltalk's metaclasses prove that **the language should be extensible from within**. We achieve this via:
- `comptime` blocks (Nim/Zig-style)
- Tag functions (`sql"..."` desugars at compile time)
- Honest desugaring (`janus query desugar` shows the transformation)

### The Verdict

**We are building** a language with Forth's **compositional flow**, Smalltalk's **live introspection**, and modern type safety.

**Strategic formula:**
```
Janus = (Forth - Stack Hell) + (Smalltalk - Dynamic Chaos) + Static Types
```

This is not imitation. This is **surgical extraction of battle-tested principles** from 50 years of language evolution.

---

## 🏛️ The Strategic Verdict

**Current Intelligence:**
Our reconnaissance confirms we are hunting the right beasts. The goal is to maximize leverage by leveraging decades of R&D from specialized ecosystems and unifying them under a single, disciplined banner.

---

## ⚡ The Onyx Graft: Universal Artifact (v0.3.0)

**Stolen From:** [Onyx Lang](https://onyxlang.io/)  
**Strategic Value:** "Write Once, Run Everywhere" was Java's lie. WASM/WASI is the truth.

### 1. WASM as First-Class Metal

Janus currently emits LLVM IR → native binaries. We will prioritize `wasm32-wasi` as a first-class target.

**Architecture:**
```
Janus Source (.jan)
    ↓
QTJIR (Quantum-Typed IR)
    ↓
LLVM IR
    ↓ ↙ ↘
Native   WASM32-WASI   (Future: QPU)
```

**Implementation Milestones:**

| Version | Feature | Description |
|---------|---------|-------------|
| **v0.3.0** | WASM Target | Add `wasm32-wasi` LLVM backend target |
| **v0.3.2** | WASM Optimization | Compact encoding, no stack unwinding |
| **v0.3.5** | WASI Preview2 | Async I/O, component model |

**Deployment Targets:**
- **Server:** Wasmtime/WasmEdge sandboxed microservices
- **Edge:** Cloudflare Workers, Fastly Compute
- **Browser:** Direct execution (no transpilation)
- **Embedded:** WASM on ESP32, Raspberry Pi

### 2. The Velocity Mandate

Onyx compiles in **47ms**. We must match this for `:script` profile.

**Action Items:**
- Profile semantic analyzer passes
- Strip "academic purity" checks that don't serve safety
- Target: `:script` < 100ms, `:core` < 500ms for 10k LOC

### 3. Dynamic Loading Escape Hatch (v0.3.5)

```janus
// Runtime plugin loading
let lib = std.os.dl.open("libplugin.so") catch return error.PluginNotFound
defer lib.close()

let process_fn = lib.symbol("process_data", fn([]u8) -> i32)
let result = process_fn(data)
```

**Capability Gated:** Requires `.dynamic_link` permission in profile.

---

## 🧠 The Lobster Graft: Ghost Memory (v0.3.0-v0.4.0)

**Stolen From:** [Lobster](http://strlen.com/lobster/)  
**Strategic Value:** Memory safety without GC pauses or borrow checker pain.

### 1. Compile-Time Reference Counting (CTRC)

The Holy Grail: automatic memory management with zero runtime overhead.

**Phase 1: Owned Types (v0.3.0)**
```janus
profile :sovereign

// Owned type (heap-allocated, ref-counted)
type ~Buffer = struct {
    data: []u8
    capacity: usize
}

func process(buf: ~Buffer) -> ~Buffer do
    // Compiler inserts retain/release automatically
    return buf
end
```

**Phase 2: Flow Analysis (v0.3.5)**
```janus
func borrow_only(buf: ~Buffer) -> i32 do
    // Compiler detects: buf not stored, not returned
    // Optimization: Elide retain/release (95% of ops)
    return buf.data.len
end
```

**Implementation:**
1. Type System: Add `~T` owned type constructor
2. Lowering: Insert `@retain(ptr)` / `@release(ptr)` intrinsics  
3. Optimizer: Escape analysis to elide redundant ops
4. Runtime: Atomic ref-count in object header

### 2. Flow-Sensitive Type Narrowing (v0.3.0)

Extend existing null-safety to all type checks:

```janus
func process(x: ?File) do
    if x != null do
        x.read()  // x narrowed to File in this block
    end
end

func handle(value: any) do
    if value is i32 do
        let n = value * 2  // value is i32 here
    else if value is string do
        println(value)     // value is string here
    end
end
```

**Implementation:**
- Semantic Analyzer: Track type constraints per basic block
- SSA Integration: Phi nodes carry refined types
- Scope Rules: Narrowing valid until mutation or scope exit

### 3. Vector Primitives Foundation (v0.4.0)

Native SIMD types for scientific computing:

```janus
let v = <1.0, 2.0, 3.0>      // Vec3
let r = v * 2.0               // SIMD multiply
let dot = v · <0.0, 1.0, 0.0> // Dot product

// Swizzling
let xy = v.xy
let bgr = color.bgr
```

**LLVM Mapping:** `<4 x float>` vector types with SSE/AVX/NEON intrinsics.

---

### Phase 1: The Surgeon's Knife (Active - v0.2.x)
**Objective:** Ergonomics & Stability
We are currently implementing **Crystal's** joy and **Rust's** discipline.
- **Postfix Guards:** Reduce indentation nesting (RFC-018).
- **Shadowing (Rebinding):** Reduce naming fatigue (RFC-017).
- **Exhaustive Matching:** Eliminate unhandled states (Elm/Rust).
- **LSP `janusd`:** The nervous system (Smalltalk).

#### The Elm Guarantees (Compiler as Executioner)

**Thesis:** We are enforcing **Total Functional Programming** constraints in a systems language.

| The Elm Guarantee | The Janus Implementation | Status |
|:------------------|:-------------------------|:-------|
| **No Null/Undefined** | `Option<T>` (sugar `T?`) is the *only* way to express absence. Null pointers illegal in safe code. | ✅ **Core** |
| **Exhaustive Matching** | `match` expressions MUST cover every variant. Missing cases = compile error. | 🏗️ **Active (v0.2.1)** |
| **Errors as Data** | `Result<T, E>` (sugar `T ! E`). No exceptions. No stack unwinding. Errors are values. | ✅ **Core** |
| **No Partial Functions** | Stdlib functions return `T?` or `Result<T, E>`. Division by zero, array bounds violations handled explicitly. | ⏳ **Enforcement (v0.2.2)** |

**The Enforcement Mechanism:**

```zig
// compiler/semantic/exhaustiveness.zig (v0.2.1)

fn checkMatchExhaustiveness(self: *SemanticAnalyzer, match_node: NodeId) !void {
    const scrutinee_type = self.getNodeType(match_node);
    const arms = self.getMatchArms(match_node);
    
    // 1. Collect all patterns
    var covered_patterns = PatternSet.init(self.allocator);
    defer covered_patterns.deinit();
    
    for (arms) |arm| {
        const pattern = self.getPattern(arm);
        try covered_patterns.insert(pattern);
    }
    
    // 2. Check coverage (Elm-style rigor)
    const missing = try self.findMissingPatterns(scrutinee_type, covered_patterns);
    
    // 3. **EXECUTIONER MODE**
    if (missing.len > 0) {
        return self.raiseError(.{
            .kind = .NonExhaustiveMatch,
            .message = "Match is not exhaustive. Missing patterns:",
            .patterns = missing,
            .hint = "Add a wildcard `_` arm or handle all cases."
        });
    }
}
```

**Stdlib Doctrine: Total Functions Only**

```janus
// ❌ BANNED in :core/:script profiles
fn head(list: [T]) -> T {
    return list[0]  // Crash on empty! Partial function!
}

// ✅ REQUIRED
fn head(list: [T]) -> T? do
    return if list.len > 0 then Some(list[0]) else None
end

// ✅ ALTERNATIVE (explicit panic in raw mode)
fn head_unchecked(list: [T]) -> T do
    requires list.len > 0;  // Runtime assertion (only in {.safety: raw})
    return list[0]
end
```

**Profile-Gated Safety:**

| Profile | Null Pointers | Partial Functions | Exhaustiveness | Panic Behavior |
|:--------|:--------------|:------------------|:---------------|:---------------|
| `:core` | ❌ Forbidden | ❌ Forbidden | ✅ Enforced | Compile error |
| `:script` | ❌ Forbidden | ❌ Forbidden | ✅ Enforced | Compile error |
| `:service` | ❌ Forbidden | ⚠️ Allowed with `{.safety: raw}` | ✅ Enforced | Runtime panic |
| `:sovereign` | ⚠️ Allowed in `unsafe` blocks | ⚠️ Allowed with contracts | ⚠️ Warnings only | Manual control |

**Active Tasks (v0.2.1):**
- [ ] Implement exhaustiveness checker for `match` expressions
- [ ] Add pattern coverage analysis
- [ ] Generate missing pattern hints
- [ ] Enforce `Result<T, E>` propagation in error paths

**Future Enforcement (v0.2.2):**
- [ ] Audit stdlib for partial functions
- [ ] Replace `array[i]` with `array.get(i) -> T?` or require bounds checks
- [ ] Add `requires` preconditions for `_unchecked` variants
- [ ] Document total vs partial function split

---

### Phase 2: Flow & Plasticity (Next - v0.3.0)
**Objective:** Expressiveness
We are implementing **Nim/D's** flow, **Inform/JS's** DSL capability, and **J's** tacit programming style.
- **UFCS (Uniform Function Call Syntax):** Method chains without objects (RFC-016).
- **Pipeline Operator (`|>`):** Functional composition (Forth/Elixir/J).
- **Tag Functions:** Type-safe DSL embeddings (RFC-015).
- **Iterators (`yield`):** Custom traversal logic (Icon).
- **Function Composition:** Point-free style (J/Haskell).

#### J-Inspired: Tacit Flow (v0.3.0-v0.3.5)

**Thesis:** Kill the intermediate variable. Data should flow like a river, not pool in lakes.

**Graft Source:** J/APL (Tacit Programming), Elixir (Pipeline), Forth (Concatenative)

**The Style Split:**
We graft J's **syntax** (tacit/point-free) in Phase 2, but defer the **engine** (array warfare) to Phase 3.

**Implementation Stages:**

**v0.3.0-v0.3.1: Pipeline Operator**
```janus
// Left-to-right data flow (Forth/Elixir/J)
let result = data
    |> parse()
    |> validate()
    |> process()

// Desugars to: process(validate(parse(data)))
```

**v0.3.2: Function Composition**
```janus
// Point-free style (J/Haskell)
let processor = compose(save, enrich, validate, parse)
files.map(processor)  // No lambda needed!
```

**v0.3.3-v0.3.5: Advanced Composition**
- Threading macros (Clojure `->` and `->>`)
- Partial application with `_` placeholder
- Composition operators

**Why This First?**
UFCS + Pipeline enables readable array chaining. Without it, array operations become unreadable nested calls. This is the prerequisite for J-style array warfare in Phase 3.

**See:** [`docs/dev/j-inspired-tacit-arrays.md`](./j-inspired-tacit-arrays.md) for complete implementation plan.

#### Icon-Inspired: Lazy Generators

**Voxis Forge** executing analysis.

**Icon** is a beautiful, dangerous creature. It replaces "Boolean Success" with "Success/Failure + State." In Icon, `if i := find("s", "mississippi")` finds the first "s". If you later say `& i > 3`, it automatically *backtracks* into `find`, resumes execution, finds the *next* "s", and tries again.

It is **"Elegance in Nondeterminism."**
It is also **"The Debugger's Nightmare"** for systems code.

If `user.save()` fails, we do *not* want the system to silently backtrack into `user.create()` and try generating a new UUID. That is chaos.

However, the **Blade** of Icon—**Generators**—is essential. We will graft it, but we will sheath it in **Explicit Control Flow**.

##### The Graft: From "Implicit Backtracking" to "Lazy Pipelines"

We strip the "Implicit" magic and keep the "Stream" power.

| Icon (The Magic) | Janus (The Discipline) | Mechanism |
| :--- | :--- | :--- |
| **Generators** | **`yield` Iterators** | Functions that define state machines. |
| **Backtracking** | **Lazy Pipelines** | Pull-based execution. `iter.next()` drives the flow. |
| **Goal-Directed** | **Combinators** | `.filter()`, `.first()`, `.any()` define the "Goal." |

###### 1. The Weapon: `yield` (Resumable Functions)

We add `yield` to the language. It transforms a function into a **State Machine** struct at compile time (Zero Allocation).

**Icon Style (Implicit):**
```icon
procedure to(i, j)
    while i <= j do { suspend i; i +:= 1 }
end
```

**Janus Style (Explicit):**
```janus
func to(i: i32, j: i32) -> Iterator[i32] do
    while i <= j do
        yield i
        i += 1
    end
end
```

###### 2. The Tactic: "Pull" Backtracking

In Janus, backtracking happens only when you *ask* for it via a pipeline. This preserves **Local Reasoning**.

**The Logic:**
`find_candidates() |> check_validity() |> take(1)`

1.  `take(1)` asks `check_validity` for a value.
2.  `check_validity` asks `find_candidates`.
3.  `find` yields `A`.
4.  `check` tests `A`. **Fail.** (Backtracks locally).
5.  `check` asks `find` again.
6.  `find` yields `B`.
7.  `check` tests `B`. **Success.**
8.  `take` returns `B`.

This *is* Icon's goal-directed execution, but structurally visible.

##### Strategic Fit

This feature is already identified in our Roadmap under **Phase 2: Flow & Plasticity**.

* **Blade:** "Goal-Directed/Generators"
* **Source:** Icon
* **Implementation:** `yield` / Implicit Iterators

##### The Verdict

**Verdict:** **APPROVED for Phase 2.**

We do not implement "Global Backtracking." We implement **First-Class Generators**.
This satisfies the "Search" use case (Parsing, Combinatorics) without destroying the "Systems" use case (Predictable Control Flow).

**Action Item:**
This moves **Sticky Feature #10 (Lazy Iterators)** and **Sticky Feature #9 (Implicit Chaining)** up the priority list.

**Current Context:**
We are currently executing **Phase 1** (Guards/Shadowing). `yield` requires complex state-machine lowering in the compiler (`janus_lower.zig`), which is a heavier lift.

**Command:**
Maintain course on **v0.2.1 (Phase 1)**. Once the parser and simple semantics are solid, we will forge the **Generator State Machine** logic in v0.3.0.

#### Nim-Inspired: Honest Metaprogramming

**Voxis Forge** executing synthesis.

You are absolutely correct. **Nim** is the chameleon. It proves you can have the skin of a script (Python) with the skeleton of a titan (C++).

We have already heavily grafted Nim’s DNA into Janus, but we are doing it with **strict discipline**. Nim allows you to rewrite the AST so aggressively that the code becomes unrecognizable. Janus demands that every transformation be **Honest** (reversible and visible).

Here is how we graft the **"Ultimate Customization Engine"** without creating the "Ultimate Debugging Nightmare."

##### 1. The Graft: Nim's Power, Janus's Rules

| Nim Feature (The Blade) | Janus Implementation (The Hilt) | Doctrine |
| :--- | :--- | :--- |
| **Macros** | **`comptime` Blocks** | We execute Janus code at compile time to generate logic. No separate macro language. |
| **Term Rewriting** | **Honest Sugar (Desugaring)** | Transformations like `tag"..."` -> `tag()` are fixed by the compiler, not the user. |
| **UFCS (Method Call)** | **UFCS (RFC-016)** | We steal this directly. `x.f()` is just `f(x)`. It makes the language extensible without classes. |
| **Templates** | **Generics `[T]` + Comptime** | We use monomorphization (like Nim/C++) to generate specialized code for every type. |

##### 2. The "Malleability" Mechanism

You want Janus to be malleable. We achieve this via **Comptime Introspection** (Reflection), which we stole from **Smalltalk** but implemented like **Nim**.

**Nim Style:**
`macro check(x: typed): untyped = ...` (Manipulate AST nodes directly).

**Janus Style:**
```janus
func serialize(x: any) -> string do
    comptime {
        // Query the ASTDB for the type structure
        let type_info = reflection.type_of(x)
        for field in type_info.fields do
             // Generate serialization code
        end
    }
end
```

This gives you the power to "extend the language" (e.g., auto-serialization, ORM mapping) without breaking the grammar.

##### 3. The Distinction: "Honest Sugar"

Nim lets you define operators that look like line noise (`*>`, `|?`). Janus restricts this.

* **The Rule:** You can define **Tag Functions** (`sql"..."`) and **Pipelines** (`|>`), but you cannot invent new operator precedence tables.
* **The Reason:** **Revealed Complexity.** An AI (or human) must be able to read a line of Janus and know the parse tree without seeing the imports.

##### The Verdict

**Nim is already in the blood.**

* **Phase 1 (Active):** We are implementing **UFCS** (Nim's #1 ergonomic feature).
* **Phase 2 (Active):** We are implementing **Tag Functions** (A disciplined version of Nim's string macros).
* **Phase 3 (Future):** We will enable `comptime` to query the **ASTDB** to generate boilerplate (Nim's template power).

**Strategic Alignment:**
This fits perfectly into **Phase 2: Flow & Plasticity**.

### Phase 3: Heavy Artillery (Future - v0.4.0+)
**Objective:** Raw Power & Scale
We are implementing **J/Mojo's** array firepower, **Erlang's** resilience, and **SPARK's** verification.
- **`:compute` Profile:** SIMD/Tensor native types for AI.
- **Array Warfare:** Dot broadcasting (`.+`, `.*`) for element-wise operations.
- **`:cluster` Profile:** Actor model concurrency.
- **Formal Verification:** SPARK-like contracts.

#### J-Inspired: Array Engine (v0.4.0+)

**Thesis:** Manipulate million-element arrays with single characters. Kill loops entirely.

**Graft Source:** J/APL (Array Programming), Mojo (Tensor Performance), NumPy (Broadcasting)

**The Problem With Early Implementation:**
If we implement array operations before QTJIR backend matures, we get slow library wrappers (NumPy without C). We need **native** fusion.

**Prerequisites:**
1. ✅ QTJIR can represent tensor operations
2. ⏳ Backend abstraction (CPU/GPU/NPU dispatch)
3. ⏳ Kernel fusion optimizer
4. ⏳ Shape tracking in type system

**Implementation Stages:**

**v0.4.0: Tensor Types Foundation**
```janus
profile :compute

let matrix: Tensor[f64, (3, 4)] = ...  // Shape-tracked type
let vector: Tensor[i32, 100] = ...     // Compile-time shapes
```

**v0.4.1: Dot Broadcasting (RFC-023)**
```janus
profile :compute

let a = tensor([1, 2, 3, 4, 5])
let b = tensor([10, 20, 30, 40, 50])

// Element-wise operations (fused kernels)
let sum = a .+ b      // [11, 22, 33, 44, 55]
let product = a .* 2  // [2, 4, 6, 8, 10]
let mask = a .> 3     // [false, false, false, true, true]
```

**v0.4.2: Reduction Operations (J's Insert)**
```janus
profile :compute

// J's +/ (plus insert) → Janus .reduce(.add)
let sum = a.reduce(.add)      // 15
let product = a.reduce(.mul)  // 120
let max_val = a.reduce(.max)  // 5
```

**v0.4.3-v0.4.5: Advanced Array Ops**
- Map/Filter/Scan on tensors
- Matrix operations (`@` for matmul)
- Multi-backend runtime (CPU SIMD, CUDA, NPU)

**Performance Targets:**
- CPU SIMD: Within 2x of hand-written C
- CUDA: Within 10% of cuBLAS
- NPU: Memory-bandwidth limited

**The "Honest Sugar" Philosophy:**
Unlike J's cryptic `+/`, Janus uses explicit `.reduce(.add)`. Readable for newcomers, LSP-discoverable, but equally dense.

**See:** [`docs/dev/j-inspired-tacit-arrays.md`](./j-inspired-tacit-arrays.md) for complete array warfare roadmap.

#### Inform-Inspired: Narrative DSLs

**Voxis Forge** executing final analysis.

**Inform** is the ultimate example of **"Code as Narrative."** It proves that if you constrain the domain enough (Interactive Fiction), code can read like a novel.

However, **English is a terrible systems programming language.** It is ambiguous, verbose, and imprecise. If we try to make Janus core syntax look like Inform, we recreate COBOL. We will not do that.

Instead, we steal the **Fluency** and the **Rule Engine**, but we confine them to **DSLs (Domain Specific Languages)**.

##### 1. The Graft: The "Narrative" Tag

We do not make the compiler understand English. We make **Tag Functions** understand English.

**Inform 7:**
`The Gazebo is a room. "A white gazebo stands here."`

**Janus (via RFC-015 Tag Functions):**
```janus
let world = story"
    The Gazebo is a room. 
    'A white gazebo stands here.'
    North of the Gazebo is the Garden.
"
```
* **Mechanism:** The `story` function is a `comptime` parser. It parses the natural language, builds the Entity-Component graph, and returns a type-safe `World` struct.
* **Benefit:** Game designers can write prose; Systems engineers get compiled, optimized structs.

##### 2. The Engine: Declarative Rules vs. ECS

Inform's "World Modeling" is essentially a database of **Rules** that fire on events.

* **Inform:** "Instead of eating the rock: say 'It is too hard.'"
* **Janus:** This maps perfectly to the **`:game` Profile** (ECS / Actors).

We graft the **Declarative Style** into the **ECS (Entity Component System)** syntax.

```janus
// Janus :game profile
system Physics {
    on(Collision) when entity.is_rock {
        reject("Too hard")
    }
}
```

This preserves the "Rule-based" logic of Inform without the verbosity of English.

##### The Verdict

**Verdict:** **Containment Strategy.**
We steal the *idea* (Natural Language DSLs), but we keep it strictly inside **Tag Functions**. It is a tool for specific domains (Game Design, Business Rules), not for the kernel.

#### Project Aegis: The High-Assurance Protocol

**Thesis:** Replace "Runtime Checks" with "Compile-Time Proofs" for critical domains (aerospace, medical, HFT).

**Graft Source:** SPARK (Ada), Dafny, F*

**The Doctrine:**
When `{.verify: true.}` is active in `:sovereign` profile:
1.  **Design by Contract:** `requires` / `ensures` become **Proof Obligations**, not runtime checks.
2.  **No Exceptions:** If a pre-condition *can* be violated, the code does not compile.
3.  **Solver Integration:** `janusd` lowers AST to SMT logic (Z3/CVC5) to prove invariants.

**The Transformation:**
```janus
// Standard Mode (:core/:script) -> Panics at runtime
func divide(x: i32, y: i32) -> i32 do
    requires y != 0
    return x / y
end

// Aegis Mode (:sovereign + verify) -> Compiler Error
// "Error: Caller 'main' fails precondition 'y != 0' (y could be 0 here)"
func divide(x: i32, y: i32) -> i32 do
    requires y != 0
    return x / y
end
```

**The Straitjacket (Verification Subset):**
To make mathematical proof possible, chaos is banned:
*   ❌ No Dynamic Allocation (Stack/Pools only)
*   ❌ No Unbounded Recursion (Must prove termination)
*   ❌ No Aliasing (Rust borrow checker becomes Proof logic)
*   ✅ Ghost Code (`ghost var`) allowed for proof state tracking

**Implementation Strategy:**
*   **Step 1 (Now):** Solidify `requires`/`ensures` syntax in Parser.
*   **Step 2 (v0.3.0):** Runtime checks (Development Mode).
*   **Step 3 (v0.4.0):** SMT Solver integration (`janusd` + Z3).

#### Clojure vs Janus: The Concurrency Verdict

**Voxis Forge** executing architectural comparison.

You have hit the nail on the head. They are fundamentally different religions.

**Clojure's STM (Software Transactional Memory)** essentially treats memory like a **ACID Database**.
* **Philosophy:** "State is shared, but access is coordinated."
* **Mechanism:** Multiple threads read/write the same data. If they conflict, the system **retries** the transaction.
* **Cost:** High memory churn (persistent structures) and unpredictable latency (retries).

**Janus's Actor Model (`:game` / `:cluster`)** treats memory like **Sovereign Islands**.
* **Philosophy:** "State is private. Communication is explicit."
* **Mechanism:** An Actor (or Grain) owns its data exclusively. No one else can touch it. To change it, you send a message.
* **Cost:** Serialization (if remote) or message passing overhead.

##### Why Janus Chooses Actors for `:game`

For a Game Engine or Metaverse (the target of `:game` profile), **Clojure's model fails** in two critical ways:

1.  **Latency Spikes:** In a twitch-reaction shooter, you cannot have the physics engine "retry" a transaction because a bullet update conflicted. You need **linear, predictable execution**. Actors process messages one-by-one, guaranteeing order and determinism.
2.  **Distribution:** Clojure's STM works great on *one* 64-core machine. It fails when you need *100* machines. You cannot coordinate atomic transactions across a network without massive slowness (Distributed Locking).
    * **Janus Grains** are **Location Transparent**. An Actor can live on the CPU, move to another server, or hibernate to disk. The code doesn't change.

##### The Graft: What We Steal From Clojure

We reject the STM (the mechanism), but we steal the **Immutability (the guarantee)**.

Janus uses **Mutable Value Semantics** (inspired by Hylo/Swift) to achieve Clojure's safety without its cost.

| Feature | Clojure (Persistent Data) | Janus (Mutable Value Semantics) |
| :--- | :--- | :--- |
| **Sharing** | Reference sharing (cheap read, expensive write) | **Copy-on-Write (COW)** (logical copy, physical sharing until write) |
| **Modification** | Returns new tree (allocates) | **In-Place Mutation** (if unique) OR Clone (if shared) |
| **Safety** | Guaranteed by immutability | Guaranteed by **Uniqueness Types** |
| **Performance** | O(log n) overhead | **O(1) / Raw Memory Speed** |

##### The Verdict

**We stick to Actors/Grains for `:game`.**

* **Threads** are for the hardware (M:N scheduling).
* **Actors** are for the logic (Entities/NPCs).
* **STM** is rejected because we value **Distribution** (Scale) and **Real-Time** (Performance) over Shared State convenience.

The `:game` profile is explicitly defined as a composite of `:cluster` (Actors) and `:compute` (NPU/Tensors). This allows an Actor (Logic) to dispatch work to the NPU (Physics) without locking the world.

#### The V Blade: Sovereign Memory Model

**Thesis:** "Safety without the Nanny." Deterministic cleanup. No GC. No borrow checker wars.

**Graft Source:** V (Autofree), Hylo (Mutable Value Semantics), Zig (Explicit Allocators)

**The Doctrine:**
1.  **Values, Not Objects:** Structs are passed by value (logically). The compiler optimizes copies to pointers (COW).
2.  **Region Allocators:** Short-lived data lives in the **Scratchpad** (Arena). It frees instantly per frame/request.
3.  **Prophetic JIT:** `janusd` hot-patches the Living Graph. No rebuilds. Live code injection.

**The "C Escape Hatch":**
Janus structs are `repr(C)` by default in systems profiles. We don't "export"; we just *are* C-compatible.

---

**Directive:**
This roadmap is not a wish list. It is a manifesto. Implement with surgical precision.
