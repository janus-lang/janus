# SPDX-License-Identifier: LCL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation
#
# x86_64 Context Switch for CBC-MN Scheduler
#
# System V AMD64 ABI compliant fiber context switch.
# See: CONTEXT-SWITCH-INVARIANTS.md for specification.
#
# Callee-saved registers (must preserve): rbx, rbp, r12-r15
# Arguments: rdi = from (Context*), rsi = to (const Context*)
#
# Context layout (must match task.zig SavedRegisters + sp):
#   offset 0:  sp   (stack pointer)
#   offset 8:  rbx
#   offset 16: rbp
#   offset 24: r12
#   offset 32: r13
#   offset 40: r14
#   offset 48: r15

.text
.global janus_context_switch
.type janus_context_switch, @function

janus_context_switch:
    # ============================================
    # Save current context to 'from' (rdi)
    # ============================================

    # Save callee-saved registers
    movq %rbx, 8(%rdi)
    movq %rbp, 16(%rdi)
    movq %r12, 24(%rdi)
    movq %r13, 32(%rdi)
    movq %r14, 40(%rdi)
    movq %r15, 48(%rdi)

    # Save stack pointer
    movq %rsp, 0(%rdi)

    # ============================================
    # Restore context from 'to' (rsi)
    # ============================================

    # Restore stack pointer first
    movq 0(%rsi), %rsp

    # Restore callee-saved registers
    movq 8(%rsi), %rbx
    movq 16(%rsi), %rbp
    movq 24(%rsi), %r12
    movq 32(%rsi), %r13
    movq 40(%rsi), %r14
    movq 48(%rsi), %r15

    # Return to new context
    # (return address is on the new stack)
    ret

.size janus_context_switch, .-janus_context_switch

# ============================================
# Fiber entry trampoline
# ============================================
# Called when a new fiber starts for the first time.
# Registers set up by initFiberContext:
#   r12 = entry function pointer
#   r13 = argument pointer
#   r14 = cleanup function pointer
#
# This trampoline calls entry_fn(arg) and then calls
# cleanup_fn(result) with the return value.

.global janus_fiber_entry
.type janus_fiber_entry, @function

janus_fiber_entry:
    # Call entry_fn(arg)
    movq %r13, %rdi          # arg -> first parameter
    callq *%r12              # call entry_fn, result in rax

    # entry_fn returned, result in rax
    # Call cleanup_fn(result) to properly yield back
    movq %rax, %rdi          # result -> first parameter
    callq *%r14              # call cleanup_fn(result)

    # Should never reach here - cleanup_fn yields to scheduler
    # Safety: infinite loop if cleanup returns
.Lspin:
    pause
    jmp .Lspin

.size janus_fiber_entry, .-janus_fiber_entry
