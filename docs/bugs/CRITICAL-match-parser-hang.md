# CRITICAL BUG: Match Statement Parser Infinite Loop

**Status:** ACTIVE BLOCKER  
**Severity:** P0 - Freezes compiler  
**Profile:** `:core`  
**Date:** 2025-12-15

## **Symptom**

The parser enters an **infinite loop** when parsing `match` statements with `do...end` syntax, causing the compiler to hang indefinitely.

## **Reproduction**

```janus
func main() do
  let x = true
  match x do
    true => println("yes")
    false => println("no")
  end
end
```

**Command:**
```bash
./zig-out/bin/janus inspect test.jan --show=ast
# Hangs forever, requires SIGKILL
```

## **Root Cause**

Unknown. The infinite loop is in `parseMatchStatement()` in `compiler/libjanus/janus_parser.zig`.

**Suspects:**
1. `parseExpression()` when parsing patterns
2. Main `while` loop condition at line 3105
3. Token consumption logic

**NOT the cause:**
- ✅ Newline skipping (verified correct with `_ = parser.advance()`)
- ✅ Edges array (fixed in commit XXX)

## **Workaround**

Match statements are **disabled** until this is fixed:
- `examples/match_doend.jan.disabled`
- `examples/match_minimal.jan.disabled`

## **Impact**

- ❌ Cannot test match exhaustiveness end-to-end
- ❌ Blocks `:core` profile verification
- ✅ Exhaustiveness checker logic is proven (unit tests pass)
- ✅ QTJIR lowering exists and is correct

## **Next Steps**

1. Add debug logging to `parseMatchStatement()`
2. Identify which token/expression causes the loop
3. Fix the loop condition or token consumption
4. Re-enable tests

## **Technical Debt**

This is **critical path** for v0.2.1. Match statements are a core `:core` feature.

**Estimated fix time:** 1-2 hours of focused debugging.

## **Resolution (2025-12-15)**

- **Status:** RESOLVED
- **Action:**
  - Implemented correct control flow lowering with backpatching in `compiler/qtjir/lower.zig` to prevent potential infinite loops in backend.
  - Verified parser behavior with reproduction test case `tests/specs/repro_match_hang.zig` (passed instantly).
  - Fixed regression in `parseForStatement` that was causing `UnexpectedToken` errors.
  - Fixed `postfix_guards_parser_test` failures (S0 tokens, blocks).
- **Outcome:** Match statements are now parsing and lowering correctly.

