<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Specification — Bootstrapping & Capability Management (SPEC-012)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-boot-and-capabilities v0.1.0-foundational

## 1. Scope

This spec defines how a Janus program starts (“boot”), how **capabilities** (IO, Clock, Logger, RNG, Runtime) are constructed and made available to user code, and the lifecycle guarantees around initialization and shutdown. It locks the **call-site shape** of the boot API for 0.1.15 while leaving room for richer runtimes in 0.2.0.

Out of scope: detailed IO stream contracts, scheduler internals, and logging wire formats (covered by their own specs).

**Allocators are not part of Boot/AppContext; they are a lower-level facility, configured independently.**

## 2. Goals

* **Caller sovereignty.** Side effects are explicit; the caller chooses implementations.
* **Stable seam from 0.1.15 → 0.2.0.** Blocking runtime today; schedulers/supervision later, **without** API breakage.
* **Deterministic testing.** First-class knobs for seeded RNG and deterministic scheduling.
* **Target agnostic.** Works on native, WASM/WASI, and within BEAM boundaries (Ports/NIFs).
* **Least global state.** No hidden singletons; everything is reachable from an explicit context.

## 3. Terms

* **Capability**: An abstract handle to a privileged function set (IO/Clock/Logger/RNG/Runtime).
* **Provider/Backend**: A concrete implementation of a capability (e.g., POSIX IO, WASI IO).
* **AppContext**: The aggregate of capabilities handed to main; immutable root of side effects.
* **ChildContext**: A derived context with scoped adjustments (fields on logger, deadlines on clock, etc.).

## 4. Entrypoint shapes

Janus defines two entrypoint forms. Tooling (`janus run`, `janus test`) wires them identically.

```zig
// Minimal
pub fn main() !void { /* may call Janus.boot() manually */ }

// Juicy main (preferred)
pub fn main(init: BootInit) !void {
    const ctx = Janus.boot(init)?;
    defer Janus.shutdown(&ctx); // always run, even on error paths
    // … app code …
}
```

**Rules**

* If `main` has a `BootInit` parameter, the host provides it. Otherwise, call `Janus.boot(Janus.defaultInit())`.
* `Janus.shutdown` must be safe to call exactly once; it is idempotent if called again.
* In debug builds, unhandled panics print stack + (if available) error traces before process exit.

## 5. Boot API

### 5.1 Types

```zig
pub const BootInit = struct {
    // Capability selection
    io:       ?*const IOProvider,       // null => platform default
    clock:    ?*const ClockProvider,
    rng:      ?*const RngProvider,
    logger:   ?*const LoggerProvider,
    runtime:  ?*const RuntimeProvider,  // may be Blocking in 0.1.15

    // Configuration knobs
    log_level:       ?LogLevel,         // default INFO
    log_fields:      ?[][2][]const u8,  // k/v pairs to stamp on root logger
    rng_seed:        ?u64,              // default: non-deterministic
    sched_seed:      ?u64,              // default: non-deterministic (ignored by Blocking)
    time_origin:     ?TimeOrigin,       // Monotonic/Steady/Realtime policy
    diag_capacity:   ?u32,              // per-context diagnostics ring size

    // Platform/host hints
    argv:    ?[][]const u8,
    env:     ?[][2][]const u8,
    cwd:     ?[]const u8,
};

pub const AppContext = struct {
    io:      *IO;
    clock:   *Clock;
    rng:     *Rng;
    logger:  *Logger;
    runtime: *Runtime;
    // internal: provider lifetimes, shutdown hooks…
};
```

Providers are factories. They construct the concrete capability objects during boot.

```zig
pub const IOProvider = struct { create: fn(*BootInit) !*IO };
pub const ClockProvider = struct { create: fn(*BootInit) !*Clock };
pub const RngProvider = struct { create: fn(*BootInit) !*Rng };
pub const LoggerProvider = struct { create: fn(*BootInit) !*Logger };
pub const RuntimeProvider = struct { create: fn(*BootInit) !*Runtime };
```

### 5.2 Functions

```zig
pub fn defaultInit() BootInit;

pub fn boot(init: BootInit) !AppContext;

pub fn shutdown(ctx: *const AppContext) void;
```

**Behavior**

* `defaultInit()` composes platform defaults (POSIX/Winsock/WASI; Blocking runtime; INFO logs).
* `boot()` validates the graph, creates capabilities in dependency order, and registers shutdown hooks.
* `shutdown()` flushes logs/IO buffers, signals runtime quiescence, waits bounded time for tasks to exit, and releases resources.

### 5.3 Environment/CLI override

Tooling translates environment and CLI flags into `BootInit` unless the program provides its own `BootInit`.

**Suggested environment keys (non-breaking to add):**

* `JANUS_LOG=trace|debug|info|warn|error`
* `JANUS_LOG_FIELDS=app=foo,env=dev`
* `JANUS_RNG_SEED=<u64>`
* `JANUS_SCHED_SEED=<u64>`
* `JANUS_RUNTIME=blocking|green|coroutine`
* `JANUS_IO=posix|wasi|memory`
* `JANUS_TIME=monotonic|realtime`

**Precedence:** explicit `BootInit` > CLI > env > defaults.

## 6. Capability interfaces (method sets)

The method sets below are **frozen for 0.1.15**. Implementations may add methods under feature flags, but call sites must not break.

### 6.1 IO

`IO` is the root for **stream** creation and basic filesystem/network handles. (Stream details in SPEC—IO Streams.)

```zig
pub const IO = struct {
    // Filesystem
    openFile:   fn(*IO, path: []const u8, opts: OpenOpts) !File;
    createFile: fn(*IO, path: []const u8, opts: CreateOpts) !File;
    remove:     fn(*IO, path: []const u8) !void;
    stat:       fn(*IO, path: []const u8) !Stat;

    // Networking (optional on some targets; return !Error.NotSupported)
    tcpConnect: fn(*IO, addr: SockAddr, opts: NetOpts) !TcpStream;
    tcpListen:  fn(*IO, addr: SockAddr, opts: NetOpts) !TcpListener;

    // Standard streams (always available, may be in-memory on WASM)
    stdout:     fn(*IO) Writer;
    stderr:     fn(*IO) Writer;
    stdin:      fn(*IO) Reader;

    // Timers, signals and other extensions are provided via separate traits/specs.
};
```

**Notes**

* All handles (File, TcpStream, Reader/Writer) are **capability-bound** (they carry a reference to their `IO` for internal buffering/polling).
* Methods that are not meaningful on a target **compile** but return `Error.NotSupported`.

### 6.2 Clock

```zig
pub const Clock = struct {
    now:        fn(*Clock) Instant;         // monotonic by default
    toRealtime: fn(*Clock, Instant) Time;   // may fail if unsupported
    sleep:      fn(*Clock, Duration) void;  // blocking runtime: sleeps thread
    deadline:   fn(*Clock, Duration) Deadline;
};
```

### 6.3 RNG

```zig
pub const Rng = struct {
    fill:   fn(*Rng, buf: []u8) void;
    u32:    fn(*Rng) u32;
    u64:    fn(*Rng) u64;
    choose: fn(*Rng, n: u64) u64; // [0, n)
};
```

Determinism: When `BootInit.rng_seed` is provided, RNG is reproducible (same seed → same sequence). Security-grade randomness is obtained via a separate `CryptoRng` capability (future spec).

### 6.4 Logger

Structured logging; implementation decides sinks/format.

```zig
pub const Logger = struct {
    log:     fn(*Logger, level: LogLevel, msg: []const u8, fields: ?[][2][]const u8) void;
    with:    fn(*Logger, fields: ?[][2][]const u8) Logger; // returns a child logger (cheap)
    level:   fn(*Logger) LogLevel;
    setLevel:fn(*Logger, LogLevel) void; // optional, may be a no-op in some deployments
};

pub const LogLevel = enum { Trace, Debug, Info, Warn, Error };
```

### 6.5 Runtime (scheduling/supervision seam)

The **method set is frozen;** the blocking implementation satisfies it with constrained behavior.

```zig
pub const Runtime = struct {
    // Fire-and-forget. In blocking runtime this runs inline.
    runAsync: fn(*Runtime, task: fn() !void) void;

    // Requires a scheduler. Blocking runtime returns Error.NotSupported.
    runConcurrent: fn(*Runtime, task: fn() !void) !TaskHandle;

    // Supervision boundary. Blocking runtime executes child inline and returns a report.
    supervise: fn(*Runtime, child: fn(*AppContext) void, policy: *const Policy) ExitReport;
};
```

Policy, TaskHandle, ExitReport are defined in the Runtime spec; their **presence here is to stabilize names**.

## 7. Lifecycle

### 7.1 Initialization order

`boot()` constructs providers in this order, with dependency guarantees:

1. Clock (needed by others for timestamps/backoff).
2. RNG (needed for scheduler seeding).
3. Runtime (may need RNG/Clock).
4. IO (some runtimes depend on IO polling).
5. Logger (needs Clock/IO for timestamps/sinks).

Providers may internally construct additional sub-capabilities. Failures during boot return `!Error` up to `main`.

### 7.2 Shutdown

`shutdown()`:

1. Signals the runtime to stop accepting new tasks.
2. Waits for a bounded grace period (implementation-defined; future flag) for tasks to quiesce.
3. Flushes Logger sinks and IO buffers.
4. Releases resources in reverse creation order.

On abnormal termination (panic/crash of root), `shutdown()` still runs via a process-level guard where supported.

## 8. Child contexts & scoping

Any component may derive a **ChildContext** for scoped behavior:

```zig
pub fn withScope(parent: *const AppContext, cfg: ScopeCfg) AppContext;

pub const ScopeCfg = struct {
    add_log_fields: ?[][2][]const u8,
    deadline:       ?Deadline,
    rng_fork:       ?bool,      // derive a substream from RNG
    io_override:    ?*IO,       // rare; e.g., memory FS for a submodule
};
```

Rules:

* Child contexts **borrow** underlying providers; lifetime ≤ parent.
* Scoped deadlines propagate to runtime timers/sleeps.
* `rng_fork=true` derives a deterministic substream from parent seed (stable across runs given same seeds).

## 9. Determinism & testing

* `rng_seed` and `sched_seed` in `BootInit` control reproducibility.
* The **blocking** runtime ignores `sched_seed`; the **deterministic** runtime (0.2.0) must use it to drive interleavings.
* `janus test` sets defaults:

  * `rng_seed`: test case hash (overridable).
  * `diag_capacity`: increased.
  * Logger: captures to test harness by default.

## 10. Target notes

### 10.1 WASM/WASI

* `IO` defaults to a WASI provider. Networking methods may return `Error.NotSupported`.
* `stdout/stderr/stdin` map to host streams.
* `Runtime` defaults to **Blocking** (no threads). Future: green threads/stackless coroutines where available.
* `Clock.toRealtime` may be unsupported in some embeddings.

### 10.2 BEAM boundary

* When embedded via Port/NIF:

  * `Logger` writes structured events suitable for BEAM logging pipelines.
  * `Runtime.supervise` maps exit reasons to Port exits or NIF return tuples (adapter layer; separate spec).
  * `shutdown()` must not block BEAM schedulers indefinitely; use bounded waits.

### 10.3 C/Rust FFI

* The `AppContext` pointer is passed into exported entrypoints; no global singletons.
* Capability handles are opaque; FFI helpers expose a narrow C ABI for the minimal surface (open/read/write, log, time, rng).

## 11. Safety & security

* Capability handles are **opaque, non-forgeable**. Only providers construct them.
* Default providers follow **least privilege**: e.g., memory FS for `janus test` sandboxes; WASI caps gate resources.
* No allocations are performed implicitly on hot error paths (see Diagnostics in RFC-0001). Diagnostics capacity is bounded and configurable.

## 12. Compatibility guarantees

* The **names** and **shapes** of:

  * `BootInit`, `AppContext`, `Janus.boot`, `Janus.shutdown`,
  * capability interfaces (`IO`, `Clock`, `Rng`, `Logger`, `Runtime`),
  * and `Runtime.runAsync/runConcurrent/supervise`

  are **frozen for 0.1.15**.

* 0.2.0 may introduce additional methods via feature-gated traits or new providers, but existing call sites compile unchanged. `runConcurrent` will transition from `Error.NotSupported` to working semantics automatically when a non-blocking runtime is provided.

## 13. Examples

### 13.1 Typical CLI

```zig
pub fn main(init: BootInit) !void {
    var ctx = try Janus.boot(init);
    defer Janus.shutdown(&ctx);

    ctx.logger.log(.Info, "starting up", null);

    const out = ctx.io.stdout();
    try out.print("Hello, Janus!\n");

    // Deterministic choice if rng_seed set:
    const idx = ctx.rng.choose(10);
    ctx.logger.log(.Debug, "picked index", &.{.{ "idx", itoa(idx) }});
}
```

### 13.2 Service with supervision (works on 0.1.15 blocking runtime; semantics improve in 0.2.0)

```zig
fn serve(ctx: *AppContext) void {
    // ... use ctx.io, ctx.clock, ctx.logger ...
}

pub fn main(init: BootInit) !void {
    var ctx = try Janus.boot(init);
    defer Janus.shutdown(&ctx);

    const policy = Policy{ .max_restarts = 10, .backoff = .exponential(50_ms, 5_s) };
    _ = ctx.runtime.supervise(serve, &policy);
}
```

### 13.3 Test with deterministic seeds

```zig
test "parser fuzz shard" {
    var init = Janus.defaultInit();
    init.rng_seed = 42;
    init.sched_seed = 99;
    var ctx = try Janus.boot(init);
    defer Janus.shutdown(&ctx);

    // run fuzz harness; behavior is reproducible across runs
}
```

---

## 14. Open items

* Specify IO stream contracts (buffer sizes, flush semantics, zero-copy).
* Define `Policy`, `TaskHandle`, `ExitReport` precisely (Runtime spec).
* Logging sink selection and wire formats (Console/JSON/OTLP).
* Explicit cancellation tokens and deadlines in `Runtime` API.

---

**End of SPEC — Boot & Capabilities**
