<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-defer: Explicit Resource Management

**Epic:** 2.4 Resource Management
**Status:** DRAFT
**Profile:** `:core` (Block Scoped)

## 1. The Doctrine
Janus uses **Block-Scoped Defer**.
- A `defer` statement schedules a call to be executed when the **immediately enclosing block** exits.
- Exiting a block includes: reaching the closing brace `}`, `return`, `break`, or `continue`.
- **LIFO Order:** Within a single scope, defers run in reverse order of declaration.
- **Argument Evaluation:** Arguments are evaluated **at the point of the defer statement**, not at execution time (to prevent lifetime confusion in `:core`).

## 2. Scenarios (AC-BDD)

### Scenario 2.4.1: Basic LIFO Execution
**Given** a function `main`
**When** I execute:
```janus
func main() do
    defer println(10)
    defer println(20)
    println(30)
end
```

**Then** the output MUST be:

```
30
20
10
```

### Scenario 2.4.2: Block Scope Cleanup (The RAII Check)

**Given** a block inside `main`
**When** I execute:

```janus
func main() do
    print("A")
    {
        defer print("B")
        print("C")
    }
    print("D")
end
```

**Then** the output MUST be:

```
A
C
B
D
```

*(Note: Go would print A C D B. Janus prints A C B D because memory pressure should be released ASAP.)*

### Scenario 2.4.3: Early Return

**Given** a function with an early return
**When** I execute:

```janus
func main() do
    defer println("cleanup")
    if true do
        return
    end
    println("unreachable")
end
```

**Then** the output MUST be:

```
cleanup
```

### Scenario 2.4.4: Loop Break Cleanup

**Given** a `while` loop with a `break`
**When** I execute:

```janus
func main() do
    var i = 0
    while i < 1 do
        defer println("loop_exit")
        println("loop_start")
        break
    end
    println("after_loop")
end
```

**Then** the output MUST be:

```
loop_start
loop_exit
after_loop
```

## 3. Implementation Plan (The Forge Cycle)

### 3.1 Parser (`compiler/astdb/parser.zig`)

  - Add `TokenKind.Keyword_Defer`.
  - Add `defer_stmt` node type to ASTDB.
  - Parse grammar: `defer_stmt ::= 'defer' call_expr | block`.

### 3.2 Lowering Strategy (`compiler/qtjir/lower.zig`)

  - **Scope Tracking:** The Lowerer must maintain a stack of `DeferStack` frames (one per block).
  - **Registration:** When lowering `defer`, emit the code for the call but **capture it** into a separate instruction list (or specialized `Defer` block) rather than the main instruction stream.
  - **Synthesizing Exits:**
      - On `Return`: Walk up ALL scopes from current to function root, emitting their defer chains.
      - On `Break`: Walk up scopes from current to the loop's target scope, emitting their defer chains.
      - On `Block End`: Emit the defer chain for the current scope.
