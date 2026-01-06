<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC: Grafting & Foreign Interop (`foreign` blocks, std.graft) — v0

**Profiles:** `:core` ✅ (IPC only), `:service` ✅ (IPC only, pool allowed), `:sovereign` ✅ (IPC or embedded VM with capability)

------

## 0. Purpose

Janus interoperates with external runtimes (e.g., Python) via an **explicit foreign boundary**. There is **no magical import**. Every cross-boundary action is visible in code, capability-gated, and effect-tracked.

This spec defines the surface syntax, semantics, capabilities, determinism rules, marshalling, diagnostics, and minimal APIs for Python interop using `foreign` blocks that desugar to std.graft APIs. It also establishes std.graft as the explicit, auditable namespace for foreign modules (Python, Zig/C, etc.).

------

## 1. Surface Syntax

### 1.1 Foreign Block (declaration + bootstrap)

```janus
foreign "python" as py do
  # Raw Python source (verbatim)
  import numpy as np

  def add(a, b):
      return a + b
end
```

- `"python"` is the foreign **language tag** (string literal).
- `as py` binds a **handle variable** in the surrounding scope.
- Block contents are **verbatim source** for the foreign runtime (not Janus).
- A foreign block **does not** run at comptime; it generates runtime bootstrap calls (see desugar).

### 1.2 Host API (explicit, honest)

Operations occur **through the handle** returned/bound by the block:

```janus
// Execute raw code in that interpreter (string)
py.exec("import math")

// Get/Set attributes on the foreign global/module objects
let math := py.get_attr("math")             // handle to python object
let tau  := math.get_attr("tau").to_number()

math.set_attr("tau", 6.28318)

// Call a foreign function with values converted explicitly
let s := py.call("add", [40, 2]).to_number()

// Evaluate an expression and get result
let res := py.eval("sorted([3,1,2])").to_array()
```

**Honesty rules apply:**

- `py.attr` (bare field) is **not** permitted; use `get_attr`.
- `.call` performs a foreign call; conversions are explicit via `to_*()`.

------

## 2. Normative Desugaring

A `foreign` block lowers to explicit runtime calls.

```janus
foreign "python" as py do
  <PYTHON_SOURCE>
end
```

**Desugars to (conceptual core, via std.graft.python):**

```janus
let py := std.graft.python.open(ctx, policy: default) or { |err| return err }
defer std.graft.python.close(py)

try py.exec(<PYTHON_SOURCE as string>)
```

> Where `ctx` must provide the appropriate **capability** (see §4) and the function acquires **effects** (§3).

------

## 3. Effects & Signatures

Foreign operations **taint** call sites with effects:

- `foreign.python.exec` — executing/evaluating Python code in a process/VM.
- `foreign.python.embed` — embedding a Python VM in-process (only in `:sovereign`).
- `foreign.ipc` — spawning/IPC to a foreign worker (subsumed by `foreign.python.exec` but may be exposed for policy).

A function that performs any of the above must declare effects, e.g.:

```janus
func build_report(py_path: string, ctx: Context, log: Logger)
  {.effects: "foreign.python.exec", "io.fs.read".}
do
  let py := try std.graft.python.open(ctx)
  defer std.graft.python.close(py)
  ...
end
```

------

## 4. Capabilities & Profiles

### 4.1 Capabilities (runtime)

- `CapForeignPythonIpc` — permission to start/use a sandboxed Python **worker process** (IPC).
- `CapForeignPythonEmbed` — permission to **embed** CPython **in-process** (only `:sovereign`).

These are passed via `Context` and **required** by `std.graft.python.open(...)`:

```janus
let py := std.graft.python.open(ctx, cap: ctx.foreign.python.ipc) ...
// or (full profile only)
let py := std.graft.python.open(ctx, cap: ctx.foreign.python.embed) ...
```

### 4.2 Profiles

| Profile | Allowed transport                                | Notes                                                        |
| ------- | ------------------------------------------------ | ------------------------------------------------------------ |
| `:core`  | **IPC only** (`CapForeignPythonIpc`)             | Timeouts **required**, minimal marshalling, no NumPy adapters |
| `:service`   | **IPC only** (pooling allowed)                   | Same semantics as `:core`, plus worker pool stdlib helper     |
| `:sovereign` | IPC or **embedded VM** (`CapForeignPythonEmbed`) | Optional zero-copy adapters (guarded), richer marshalling    |

**Comptime:** Foreign code **cannot run at comptime** by default. A build policy must explicitly grant it (and only for pure, vendored inputs). See §6.4.

------

## 5. Determinism & Sandboxing

- `--deterministic` disables foreign execution **unless**:
  - A policy explicitly allows it **and**
  - The call provides a **timeout** and **resource limits**, **and**
  - The operation is declared **pure** (no net/fs, deterministic seed from `ctx`).
- The sandbox denies `net/fs/env` by default. Any access must be declared and recorded in `JANUS.lock` (capabilities delta audit).

------

## 6. Runtime API (MVP)

Namespace: `std.graft.python`.

```janus
// Handle is a unique resource; must be closed
type ForeignHandle = unique _ForeignPython

// Open & close
func open(ctx: Context, cap?: Cap, opts: ForeignOpts = {}) -> ForeignHandle!Error

func close(h: ForeignHandle) -> void

// Execute module/function/expr
func exec(h: ForeignHandle, code: string, timeout_ms: i32 = 0) -> unit!Error
func eval(h: ForeignHandle, expr: string, timeout_ms: i32 = 0) -> ForeignValue!Error
func call(h: ForeignHandle, name: string, args: array, kwargs: table = {}, timeout_ms: i32 = 0)
  -> ForeignValue!Error

// Attribute access
func get_attr(h: ForeignHandle, path: string) -> ForeignValue!Error
func set_attr(h: ForeignHandle, name: string, v: ForeignValue) -> unit!Error

// Conversion (explicit & fallible)
type ForeignValue = unique _ForeignValue
func to_number(v: ForeignValue) -> number!Error
func to_string(v: ForeignValue) -> string!Error
func to_bool(v: ForeignValue) -> bool!Error
func to_array(v: ForeignValue) -> array!Error
func to_table(v: ForeignValue) -> table!Error

// Zero-copy ndarray (full only; gated)
func to_ndarray(v: ForeignValue, want_dtype: string) -> NdArrayView!Error {.effects: "foreign.python.embed".}
```

**Resources:** `ForeignHandle` and `ForeignValue` are **unique**. Use `using` or `defer foreign.close(...)` to avoid leaks.

------

## 7. Marshalling (MVP)

| Janus        | Python            | Notes                                                  |
| ------------ | ----------------- | ------------------------------------------------------ |
| `number`     | `int`/`float`     | MIN unifies numeric; rounded/truncated per value       |
| `string`     | `str`             | UTF-8                                                  |
| `bool`       | `bool`            | 1:1                                                    |
| `null`       | `None`            | 1:1                                                    |
| `array`      | `list`            | Homogeneity **not** enforced by Python                 |
| `table`      | `dict` (str keys) | Only **string keys** in MVP (honest limitation)        |
| foreign view | `numpy.ndarray`   | **FULL** profile only; `to_ndarray` gated by embed cap |

Unsupported shapes/types raise **E2404 ForeignMarshallingError**.

------

## 8. Diagnostics (IDs reserved E2400–E2407)

- **E2400 ForeignLanguageUnsupported**
   `"foreign" language 'ruby' is not supported; supported: "python".`
- **E2401 ForeignFeatureDisabledInProfile**
   `Embedding Python VM is disabled in :core/:service. Use IPC or switch to :sovereign.`
- **E2402 ForeignCapabilityMissing**
   `Missing CapForeignPythonIpc/Embed in Context.` (Fix-it: add to function params and pass `ctx.foreign.python.ipc`.)
- **E2403 ForeignTimeout**
   `Foreign call exceeded timeout N ms.`
- **E2404 ForeignMarshallingError**
   `Cannot convert Janus table with non-string keys to Python dict.`
- **E2405 ForeignExecError**
   `Python exception: <TypeError ...>` (propagate message + sanitized traceback)
- **E2406 ForeignDeterminismViolation**
   `Foreign exec forbidden under --deterministic without approved policy.`
- **E2407 ForeignResourceLeak**
   `ForeignHandle/ForeignValue leaked past scope; wrap in 'using' or 'defer close()'.`

**LSP Fix-its:**

- Wrap block with `using py := std.graft.python.open(ctx, ...) do … end`
- Insert `timeout_ms:` arg where missing under deterministic mode
- Convert sugar to core calls (see below)

------

## 9. Honest Sugar (optional, off by default in `:core`)

To ease ergonomics without lying:

- **Attribute path sugar (FULL only):**

  ```
  py.attr("numpy.random").call("rand", [1024])
  // sugar (off in :core/:service):
  py.attr("numpy.random").rand(1024)
  ```

  **Desugar:** `X.Y(...)` → `X.get_attr("Y").call(... )`

- **Inline foreign literal (FULL, gated by caps; disabled under deterministic):**

  ```janus
  let xs := py.eval("""[i*i for i in range(10)]""").to_array()
  ```

  **Desugar:** `eval(...)` call.

If sugar is used where disabled, emit **E2401** with fix-it to the explicit API.

------

## 10. Comptime (build-time) rules

Foreign execution at compile time is **off by default**. To allow:

- `docs/packages.md` policy **must** grant:
  - `comptime.foreign.python = "exec"` (no embed at comptime)
  - `fs_read` limited to vendored inputs (no network)
- The `comptime` block must declare **effects: "foreign.python.exec"** and may only produce **CAS-addressed** artifacts (hash recorded in `JANUS.lock`).

Violations → **E2406**.

------

## 11. Examples

### 11.1 Basic use (IPC, `:core`)

```janus
func main(ctx: Context) {.effects: "foreign.python.exec".} do
  using py := try std.graft.python.open(ctx, cap: ctx.foreign.python.ipc) do
    try py.exec("def add(a,b): return a+b")
    let r := try py.call("add", [40, 2], {}, timeout_ms: 500)
    print $"sum={try r.to_number()}"
  end
end
```

### 11.2 NumPy (embed, `:sovereign`)

```janus
func dot(a: NdArrayView, b: NdArrayView, ctx: Context)
  {.effects: "foreign.python.embed".}
do
  using py := try std.graft.python.open(ctx, cap: ctx.foreign.python.embed) do
    try py.exec("import numpy as np")
    let res := try py.eval("np.dot(a,b)")        // a/b pre-bound via `foreign.bind` (future)
    return try res.to_ndarray("float64")
  end
end
```

------

## 12. Testing & Security

- **Unit tests:** mock worker returning canned responses; assert marshalling/diagnostics.
- **Integration:** spawn a real Python worker in a jailed env (no net/fs unless granted).
- **Fuzzing:** fuzz marshalling tables both directions.
- **Leak checks:** ensure `ForeignHandle`/`ForeignValue` are unique and closed.
- **Deterministic CI:** run with `--deterministic`; expect **E2406** where policy is absent.

------

## 13. Rationale (why this design)

- **No lies:** The syntax makes foreign boundaries unmistakable. No silent GIL, no implicit conversions.
- **Mechanisms only:** We provide `open/close/exec/call/get/set`. You choose IPC vs embed via capabilities/policy.
- **Auditable:** Effects and caps make supply-chain and runtime use inspectable (`JANUS.lock` records grants).
- **Deterministic by default:** Foreign exec is gated under `--deterministic`, preserving reproducibility.
- **Progressive disclosure:** Works in `:core` today; scales up to high-performance adapters in `:sovereign`.

------

## 14. Open v1.1 items (tracked)

- `foreign.bind(h, "a", NdArrayView)` to inject host values by handle
- Streamed I/O (stdin/stdout) for long-running foreign services (IPC channels)
- Additional runtimes (`"lua"`, `"js"`, `"R"`) behind the same contract

------

## 15. std.graft Model (Zig/C overview)

In addition to Python, Janus exposes foreign modules via std.graft under an explicit, auditable namespace:

- `std.graft.*` containment prevents pollution of core std modules and enables transparent replacement by native code later.
- Bridges enforce capability tokens and allocator discipline, converting foreign errors to structured Janus errors.
- Grafted modules must provide `.utcpManual()` so discovery can enumerate endpoints/capabilities.

Zig/C prototype intent:
- Minimal Zig library linked and surfaced as `std.graft.<module>` with wrappers enforcing allocator/capability contracts.
- Future syntax may include: `graft gui = zig "dvui";` which binds `std.graft.dvui` under alias `gui`.

------

**End of SPEC**
