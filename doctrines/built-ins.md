<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





### The Janus Doctrine for "Built-ins"

Our strategy is three-pronged, moving from the standard library inward to the compiler only when absolutely necessary.



#### 1. Standard Library First

The vast majority of operations that are built-ins in other languages will be **regular, generic functions in the Janus standard library.** A checked integer cast is not a magical compiler intrinsic that requires an `@` symbol; it is a generic library function with a clear signature.

**Example:**

Code snippet

```
// A regular, generic function in `std.conv`, not a special compiler built-in.
let y: u8 = try std.conv.toInt[u8](x)
```

This upholds our doctrine of **No Second Semantics**. The rules of function calls, generics, and error handling are the same for library code as they are for user code.



#### 2. The `std.meta` Conduit

For operations that require true compiler introspection—like examining a function's effects, reflecting on a type, or manipulating the AST at compile time—we provide **one, unified, and powerful conduit**: the `std.meta` module, used within a `comptime` block.

This is our single, secure airlock to the compiler's omniscient knowledge stored in the ASTDB.

**Example:**

Code snippet

```
comptime {
    // Accessing compiler knowledge through a standard module, not a special built-in.
    let func_ref := std.meta.get_function("my_func")
    assert(func_ref.effects.is_pure())
}
```



#### 3. Reserved `@[keyword]` for Irreducible Primitives

A special `@` syntax will be reserved **only for the most fundamental, irreducible primitives** that cannot possibly be expressed as a library function because they are deeply tied to the compiler's state or code generation.

The list of these true built-ins will be deliberately and ruthlessly kept small.

**Potential Candidates:**

Code snippet

```
@sizeOf(T)      // Memory layout is the compiler's domain.
@alignOf(T)     // Memory layout is the compiler's domain.
@errorName(err) // Accessing the name of an error from an error set.
```

------



### Philosophical Comparison

| Feature / Task         | Zig's Approach      | **Janus's Doctrinal Approach**                  |
| ---------------------- | ------------------- | ----------------------------------------------- |
| Checked Integer Cast   | `@intCast(value)`   | `std.conv.toInt[T](value)` (Library Function)   |
| Type Information       | `@TypeOf(value)`    | `std.meta.typeOf(value)` (in `comptime`)        |
| Function Introspection | (various built-ins) | `std.meta.get_function("name")` (in `comptime`) |
| Memory Layout          | `@sizeOf(T)`        | `@sizeOf(T)` (True Built-in)                    |

In summary, Zig provides a large toolbox of specialized, magical tools. Janus provides a clean room with a few powerful, general-purpose machines (`comptime`, generics) and a single, secure interface to the compiler's core (`std.meta`). Our approach is more scalable, more maintainable, and more doctrinally pure.
