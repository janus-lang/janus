<!--
SPDX-License-Identifier: LCL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

# Context Switch Invariants

**Status:** Canonical
**Specification:** SPEC-021 Section 5.3 (Continuation)
**Date:** 2026-01-29

---

## Purpose

This document defines the **non-negotiable invariants** for the fiber context switch primitive. Any implementation (assembly, external `.s`, or future stackless) MUST satisfy these constraints.

---

## 1. What MUST Be Preserved

### Callee-Saved Registers (System V AMD64 ABI)

| Register | Purpose | MUST Preserve |
|----------|---------|---------------|
| `rbx` | General purpose | YES |
| `rbp` | Frame pointer | YES |
| `r12` | General purpose | YES |
| `r13` | General purpose | YES |
| `r14` | General purpose | YES |
| `r15` | General purpose | YES |
| `rsp` | Stack pointer | YES (explicit) |

### Fiber State

| State | Location | MUST Preserve |
|-------|----------|---------------|
| Stack pointer | `Context.sp` | YES |
| Saved registers | `Context.regs` | YES |
| Return address | Top of stack | YES |

---

## 2. What MAY Be Clobbered

### Caller-Saved Registers (Scratch)

| Register | Purpose | May Clobber |
|----------|---------|-------------|
| `rax` | Return value | YES |
| `rcx` | 4th argument | YES |
| `rdx` | 3rd argument | YES |
| `rsi` | 2nd argument | YES |
| `rdi` | 1st argument | YES |
| `r8`  | 5th argument | YES |
| `r9`  | 6th argument | YES |
| `r10` | Scratch | YES |
| `r11` | Scratch | YES |

### Flags

| Flag | May Clobber |
|------|-------------|
| `RFLAGS` | YES (condition codes) |
| Direction flag | MUST be clear on return |

### Floating Point / SIMD

| State | Policy |
|-------|--------|
| x87 FPU | Not used (tasks don't use x87) |
| SSE/AVX | Caller-saved (clobber OK) |
| MXCSR | Caller-saved |

**Note:** If tasks use SIMD, we'd need to save/restore XMM registers. Current design assumes integer-only fibers.

---

## 3. Stack Ownership Rules

### Rule 1: Each Task Owns Its Stack

```
Task A: [stack_a ... sp_a]  ← Task A's exclusive memory
Task B: [stack_b ... sp_b]  ← Task B's exclusive memory
```

A task MUST NOT write to another task's stack.

### Rule 2: Stack Pointer Validity

Before switch:
- `from->sp` will be written (current stack pointer saved)
- `to->sp` MUST be valid (points into `to`'s stack)

After switch:
- Execution continues at `to->sp` with `to`'s registers

### Rule 3: Stack Alignment

- Stack pointer MUST be 16-byte aligned before `call`
- After switch, `rsp % 16 == 8` (return address pushed)

### Rule 4: Red Zone

- System V ABI reserves 128 bytes below `rsp` (red zone)
- Context switch MUST NOT clobber red zone of suspended task
- Solution: Save `rsp` before any stack operations

---

## 4. Who Is Allowed to Call switchContext

### ALLOWED

| Caller | Context | Notes |
|--------|---------|-------|
| `Worker.run()` | Worker loop | Switch to next task |
| `Task.yield()` | Inside task | Voluntary yield |
| `Nursery.awaitAll()` | Inside task | Blocking wait |
| `Channel.send/recv()` | Inside task | Blocking I/O |

### FORBIDDEN

| Caller | Why |
|--------|-----|
| Signal handlers | Unsafe (unknown stack state) |
| Interrupt context | No valid `from` context |
| Before Runtime init | No scheduler exists |
| After Runtime shutdown | Workers stopped |

### Call Site Invariant

```zig
// REQUIRED pattern
fn switchContext(from: *Context, to: *const Context) void;

// Caller MUST ensure:
assert(from != to);           // No self-switch
assert(to.sp != 0);           // Target has valid stack
assert(isAligned(to.sp, 16)); // Stack aligned
```

---

## 5. Initialization Invariants

### New Fiber Setup (initFiberContext)

```
Stack layout after init:
                        ┌─────────────────┐ High address
                        │   (red zone)    │
                        ├─────────────────┤
                        │  cleanup_fn     │ ← Return address after entry_fn returns
                        ├─────────────────┤
                        │  entry_wrapper  │ ← Initial "return" target
                        ├─────────────────┤
            sp ──────►  │  (16-aligned)   │
                        ├─────────────────┤
                        │      ...        │
                        └─────────────────┘ Low address (stack.ptr)

Registers after init:
    r12 = entry_fn      (task entry point)
    r13 = arg           (task argument)
    r14 = 0
    r15 = 0
    rbx = 0
    rbp = sp            (frame pointer)
```

### First Switch to New Fiber

1. `switchContext(worker_ctx, task_ctx)` called
2. Registers restored from `task_ctx.regs`
3. `rsp` loaded from `task_ctx.sp`
4. `ret` instruction pops `entry_wrapper` address
5. `entry_wrapper` reads `r12`/`r13`, calls `entry_fn(arg)`
6. When `entry_fn` returns, `ret` pops `cleanup_fn`
7. `cleanup_fn` marks task complete, yields to scheduler

---

## 6. Safety Guarantees

### Memory Safety

- Context switch does NOT allocate
- Context switch does NOT free
- Context switch does NOT access heap
- Only touches: registers, `from->regs`, `from->sp`, `to->regs`, `to->sp`

### Thread Safety

- Context switch is NOT thread-safe
- Each worker has exclusive access to its current task's context
- Cross-worker stealing copies task pointer, not context

### Reentrancy

- Context switch is NOT reentrant
- Recursive switch would corrupt saved state
- Worker loop ensures linear switch sequence

---

## 7. Error Conditions

| Condition | Detection | Response |
|-----------|-----------|----------|
| Null `from` | Assert | Panic (bug) |
| Null `to` | Assert | Panic (bug) |
| Invalid `to.sp` | Guard page | SIGSEGV → worker crash |
| Stack overflow | Guard page | SIGSEGV → task panic |
| Self-switch | Assert | Panic (bug) |

---

## 8. Implementation Options

### Option A: External Assembly File

```
# context_switch.s
.global janus_switch_context
janus_switch_context:
    # Save callee-saved to [rdi] (from)
    movq %rbx, 0(%rdi)
    movq %rbp, 8(%rdi)
    ...
    # Load from [rsi] (to)
    movq 0(%rsi), %rbx
    ...
    ret
```

**Pros:** Full control, standard AT&T syntax
**Cons:** Separate build step, platform-specific files

### Option B: Zig @call with Tail Call

```zig
fn switchContext(from: *Context, to: *const Context) void {
    saveRegs(from);
    @call(.always_tail, restoreAndJump, .{to});
}
```

**Pros:** Pure Zig
**Cons:** May not work for arbitrary switches

### Option C: setjmp/longjmp Wrapper

```zig
const jmp_buf = extern struct { ... };
extern fn setjmp(env: *jmp_buf) c_int;
extern fn longjmp(env: *jmp_buf, val: c_int) noreturn;
```

**Pros:** Portable, libc handles details
**Cons:** Overhead, doesn't match our Context layout

### Recommended: Option A

External `.s` file gives full control and matches the invariants exactly.

---

## 9. Verification Tests

Before any implementation is accepted:

```zig
test "switch preserves callee-saved registers" { ... }
test "switch restores correct stack pointer" { ... }
test "new fiber starts at entry_fn" { ... }
test "fiber return invokes cleanup" { ... }
test "nested switches unwind correctly" { ... }
test "switch under memory pressure" { ... }
```

---

## Signature

**Adopted:** 2026-01-29
**Authority:** Markus Maiwald

*"The context switch is the beating heart. Guard it with invariants."*
