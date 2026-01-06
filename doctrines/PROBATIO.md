<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# DOCTRINE: The Scientific Method (Integrated Proof & Forensics)

**Codename:** `PROBATIO`
**Status:** CONSTITUTIONAL (Effective Immediately)
**Scope:** All Profiles (`:core` to `:sovereign`)

---

## 1. The Axiom of Existence

> *"A feature that is not proven does not exist."*

Code without verification is merely text. It becomes software only when it withstands falsification. Therefore, the mechanism of proof must be **inseparable** from the mechanism of creation.

---

## 2. Integrated Verification (The "Colocation" Law)

We reject the separation of "Source" and "Test."

- **Zig-Style Unit Tests:** Tests live inside the module they verify. They have access to private state.
- **Proof blocks:** Compiled only in `:test` mode. Stripped in `:release`.

**Syntax (Immutable):**

```janus
func add(a: i32, b: i32) -> i32 do
    return a + b
end

// The Proof lives with the Code.
test "addition holds basic arithmetic truth" do
    assert(add(2, 2) == 4)
    assert(add(-1, 1) == 0)
end
```

---

## 3. First-Class BDD (The "Specification" Law)

We do not use external Gherkin files parsed by regex. We embed **Executable Specifications** directly into the grammar.

**Syntax (The "Spec" Block):**

```janus
spec "Fibonacci Sequence" do
    // State setup (The 'Given')
    let n = 10
    
    // Action (The 'When')
    let result = fib(n)
    
    // Verification (The 'Then')
    expect(result) == 55
    expect(fib(0)) == 0
    expect(fib(1)) == 1
end
```

*Implementation Note:* `spec` blocks desugar to `test` blocks but enforce a "Given/When/Then" structure via helper functions.

---

## 4. Forensic Debugging (The "Black Box" Law)

Debugging is not "printing and guessing." It is **Forensics**.

When a test fails, the System must produce a **Snapshot**—a content-addressed, replayable artifact containing:

1. The ASTDB node ID of the failure.
2. The stack trace with source locations.
3. The exact inputs (arguments) that caused the crash.

**Developer Experience:**

```bash
$ janus test
❌ FAIL: "Fibonacci Sequence"
   --> src/math.jan:45:5
   Snapshot saved to: .janus/trace/failure_28a9f4.json

$ janus debug .janus/trace/failure_28a9f4.json
# Replays the exact failure instantly without re-running the full suite.
```

---

## 5. Ecosystem Sovereignty (The "Capsule" Law)

A library is not just code. It is a **Capsule** containing:

1. **Source** (Logic)
2. **Proofs** (Tests/Specs)
3. **Docs** (AI Hints + Human Text)

The Package Manager (`hinge`) rejects any package with < 90% coverage or failing proofs. **Zero Trust Integration.**

---

## 6. Assertion Intrinsics

These are **compiler intrinsics**, not standard library functions.

| Intrinsic | Behavior |
|:----------|:---------|
| `assert(condition)` | If false: print `FILE:LINE`, stack trace, and `exit(1)` |
| `assert(condition, message)` | Same, with custom message |
| `expect(value)` | Structural matcher for BDD (returns matcher object) |
| `@unreachable` | Panic if reached (code path should be impossible) |

---

## 7. Test Isolation (Stack Hygiene)

Each `test` or `spec` block executes in a **fresh stack frame**. Variables from one test cannot leak into another.

```janus
test "scope A" do
    let x = 10
    assert(x == 10)
end

test "scope B" do
    let x = 20 // Does not conflict with A
    assert(x == 20)
end
```

---

## 8. Compilation Modes

| Mode | `test` blocks | `assert` behavior |
|:-----|:--------------|:------------------|
| `:test` | Compiled & Executed | Runtime check, panic on failure |
| `:debug` | Stripped (dead code) | Runtime check, panic on failure |
| `:release` | Stripped (dead code) | Compiled out (zero overhead) |

---

## 9. The Test Runner Protocol

```bash
$ janus test [file.jan]
```

1. Parse file(s).
2. Query ASTDB for all `TestDecl` and `SpecDecl` nodes.
3. For each test:
   - Reset interpreter state (fresh stack).
   - Execute the test block.
   - Catch failures; record snapshot.
4. Print Summary: `Ran N tests. X passed, Y failed in Z ms.`
5. Exit code: 0 if all pass, 1 otherwise.

---

## 10. Cross-References

- **Syntax:** `test_decl`, `spec_decl` in [SPEC-syntax.md](../specs/SPEC-syntax.md)
- **Semantics:** Verification in [SPEC-semantics.md](../specs/SPEC-semantics.md)
- **Package Sovereignty:** [SPEC-capsule.md](../specs/SPEC-capsule.md) (future)
