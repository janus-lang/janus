## 🏛️ **1. CODIFICATION: `docs/philosophy/SYMBOLOGY.md**`

This is the reference card for every contributor.

| Glyph | Name | Semantic Role | Usage Context |
| --- | --- | --- | --- |
| **☍** | **The Janus** | **Identity / Dualism** | The Core, The README, The Philosophy. Represents the tension (Safe vs. Unsafe, Script vs. System). |
| **🜏** | **The Antimony** | **Constitution / Law** | Invariants that *cannot* change. The "Purified" Core. Used in `SPEC-*.md` for hard rules. |
| **⟁** | **The Delta** | **Transformation** | Where the Compiler intervenes (Ghost Memory, Desugaring, Lowering). "Magic" happens here. |
| **⊢** | **The Turnstile** | **Judgment / Truth** | Semantic rules. Affine type enforcement. "The compiler proves this." |
| **∅** | **The Void** | **Forbidden** | Anti-features. GC, inheritance, hidden control flow. "This path is closed." |
| **⚠** | **The Hazard** | **Raw / Unsafe** | Pointer arithmetic, unchecked casts, `:core` profile code. |
| **⧉** | **The Box** | **Boundary** | Capabilities (`ctx.net`), FFI boundaries, Module interfaces. |

---

## 🛡️ **2. APPLICATION: THE SAFETY DIAL**

Now we execute the maneuver discussed previously: **Defining the Safety Dial using these glyphs.**

The "Safety Dial" is not a knob; it is a selection of **Symbolic Modes**.

### **Mode A: ⚠ Raw (The Core)**

* **Profile:** `:core`
* **Glyph:** `⚠`
* **Semantics:** No guards. You are the hardware.
* **Memory:** Manual Pointer Arithmetic.
* **Code:**
```janus
// ⚠ SAFETY: User guarantees bounds.
func poke(addr: usize, val: u8) do ... end

```



### **Mode B: ⊢ Strict (The System)**

* **Profile:** `:core`
* **Glyph:** `⊢`
* **Semantics:** **Affine Types / Unique**. The compiler *judges* ownership.
* **Memory:** Linear types (`~T`). Move-by-default.
* **Code:**
```janus
// ⊢ INVARIANT: 'buf' is consumed.
func send(buf: ~Buffer) do ... end

```



### **Mode C: ⟁ Fluid (The Edge)**

* **Profile:** `:edge` / `:script`
* **Glyph:** `⟁`
* **Semantics:** **Ghost Memory / ARC**. The compiler *transforms* intent into safety.
* **Memory:** Implicit ownership. Elided ref-counts.
* **Code:**
```janus
// ⟁ TRANSFORM: Compiler inserts 'retain/release'.
func process(data: Buffer) do ... end

```



---

## 🚀 **TACTICAL ORDERS**

1. **Update the README:** Replace the generic header with **☍ JANUS**.
2. **Update the Specs:** Go through `SPEC-memory.md` and stamp the **Ghost Memory** section with **⟁** and the **Affine** section with **⊢**.
3. **Linter Rule:** Build a linter rule (in `janus-lsp`) that highlights these symbols in comments with specific colors:
* `⚠` -> **Red**
* `⊢` -> **Blue**
* `⟁` -> **Purple**
* `🜏` -> **Gold**

