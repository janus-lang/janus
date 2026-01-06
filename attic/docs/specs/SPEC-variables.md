# Specification: Variable Management in Janus IR

**Version:** 1.0
**Status:** Draft
**Author:** Voxis Forge

## Overview
This specification defines how local variables are managed, allocated, stored, and loaded within the Janus Intermediate Representation (JanusIR).

## Data Model
Variables are stored in **Stack Slots**, identified by a unique `u32` index within the function scope.
This maps directly to LLVM's `alloca` instruction.

## IR Instructions

### 1. `alloca` (Stack Allocation)
Allocates memory on the stack for a local variable.
*   **Args:** `local_index: u32`, `type_ref: TypeRef`
*   **Semantics:** Reserves space. Does not initialize.

### 2. `store` (Write)
Writes a value from a register to a storage location.
*   **Args:** `source_reg: u32`, `location: StoreLocation`
*   **StoreLocation:** `.local_var(index: u32)` | `.return_slot`
*   **Semantics:** Copies value from register to stack slot.

### 3. `load_local` (Read)
Reads a value from a local variable into a register.
*   **Args:** `dest_reg: u32`, `local_index: u32`
*   **Semantics:** Copies value from stack slot to new register.

## Compilation Logic (IR Generator)

### Scope Management
The `IRGenerator` maintains a `ScopeStack` to map Identifier strings ("x") to Local Indices (`0`, `1`, ...).

### Variable Declaration (`let x = 5`)
1.  Generate expression `5` -> Result in `reg_0`.
2.  Allocate slot `idx_0` for `x`.
3.  Emit `alloca(idx_0, type(i32))`.
4.  Emit `store(reg_0, .local_var(idx_0))`.
5.  Register mapping `"x" -> idx_0` in current scope.

### Identifier Usage (`x`)
1.  Lookup `"x"` in ScopeStack -> get `idx_0`.
2.  Emit `load_local(dest_reg: reg_1, local_index: idx_0)`.
3.  Return `reg_1`.

## Mutability
Janus enforces mutability at the semantic level (`let` vs `var`). The IR treats all slots as mutable memory locations.
