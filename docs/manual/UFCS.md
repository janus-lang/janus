# UFCS: Unified Function Call Syntax

**Status:** ✅ **Implemented** (v0.2.1-2)

---

## 🎯 **The Problem**

Traditional OOP forces you to define methods *inside* classes:

```java
class Player {
    void move(float dx, float dy) { ... }
}
```

This creates several issues:
1. **Closed for Extension:** You can't add methods to types you don't own.
2. **Namespace Pollution:** All methods live in the type's namespace.
3. **Hidden Complexity:** Method dispatch can involve v-tables and dynamic dispatch.

---

## 💡 **The Janus Solution: UFCS**

In Janus, **everything is a function**. There are no "methods" in the traditional sense.

However, you can call functions using method syntax:

```janus
func move(p: *Player, dx: f64, dy: f64) do
    p.x = p.x + dx
    p.y = p.y + dy
end

// Both work identically:
move(player, 10.0, 5.0)    // Procedural
player.move(10.0, 5.0)     // Method-style (UFCS)
```

---

## 🔧 **How It Works**

When the compiler sees `obj.method(args)`:

1. **First:** Check if `obj` has a field named `method`
2. **Fallback:** Look for a function `method(self: TypeOf(obj), args...)`
3. **Rewrite:** Transform `obj.method(args)` → `method(obj, args)`

This is **pure syntactic sugar**. No runtime overhead. No hidden magic.

---

## ✨ **Benefits**

### 1. **Extension Methods**

Add "methods" to any type, even standard library types:

```janus
// Extend the built-in Vector type
func sum(v: Vector) -> f64 do
    let total = 0.0
    for i in 0..v.len() do
        total = total + v.get(i)
    end
    return total
end

// Now you can call it like a method:
let numbers = vector_create()
numbers.push(1.0)
numbers.push(2.0)
println(numbers.sum())  // 3.0
```

### 2. **IDE Autocomplete**

Type `player.` and your IDE shows all functions where `player` is the first argument.

This is **the killer feature** for discoverability.

### 3. **Method Chaining**

```janus
player
    .move(10.0, 5.0)
    .damage(20)
    .heal(50)
```

Reads naturally, compiles to simple function calls.

### 4. **Honest Abstraction**

Unlike OOP, there's no hidden `this` pointer or implicit state. The first argument is **explicit**.

---

## 📋 **Rules**

1. **First Argument Matters:** For `obj.method(...)` to work, there must be a function `method(self: TypeOf(obj), ...)`.
2. **No Overloading (Yet):** If multiple functions match, the first one found wins.
3. **Explicit is Better:** You can always use procedural syntax if UFCS feels unclear.

---

## 🚀 **LSP Support**

The Janus LSP server fully supports UFCS:

- **Hover:** Shows function signature when hovering over `player.move`
- **Go to Definition (F12):** Jumps to the `move` function definition
- **Find References:** Finds all uses of `move`, whether called procedurally or as a method

---

## 🎓 **Inspiration**

UFCS is stolen from:
- **Nim:** Pioneered this approach
- **D:** Popularized it in systems programming
- **Rust:** Uses traits for similar ergonomics (but with more ceremony)

Janus takes the simplest, most pragmatic approach: **just rewrite the call**.

---

## 📝 **Example**

See `examples/ufcs_demo.jan` for a complete demonstration.

---

**Voxis Forge Verdict:** ⚡ **Pragmatic Evolution.**

We give you the ergonomics of OOP without the complexity of OOP.
