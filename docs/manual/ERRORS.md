<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# The Janus Doctrine of Error Handling

## Philosophy: Errors as Forensic Data

In Janus, we reject the chaos of traditional exceptions. An error is not an exceptional, disruptive event that hijacks control flow. It is a predictable, expected outcome for any non-trivial operation.

Our approach is to treat an error not as a simple message, but as a **first-class citizen** and a **forensic data package**. A function's signature must be honest about its potential for failure. The error value itself must be rich with context. And for the most difficult cases, the entire program's execution leading to the error must be perfectly replayable.

This document explains the three layers of the Janus error handling strategy, from basic interaction to our most revolutionary debugging capabilities.

-----

## Layer 1: The Core Mechanism (Errors as Values)

The foundation of Janus error handling is the **error union**, a type-safe sum type that explicitly represents either a successful outcome or an error.

### The `Error!Success` Union

A function that can fail **must confess this in its signature**. It does this by returning an error union, written as `ErrorType!SuccessType`.

```janus
// This function can fail with an 'IoError' or succeed with a 'string'.
func read_file(path: string, cap: CapFsRead) -> IoError!string do
    // ... implementation
end
```

This compile-time contract makes it impossible to ignore the possibility of failure.

### Interacting with Errors: `try` and `or`

You have two primary, disciplined ways to interact with a function that returns an error union.

#### 1\. Propagation (`try`)

To propagate an error up the call stack, use the `try` keyword. This is the most common case. If the called function returns an error, your function will immediately return that same error. The compiler automatically and safely wraps the error with contextual information (file, line, function name) at each step.

```janus
func load_config(cap: CapFsRead) -> Config!Error do
    // If fs.read fails, try propagates the error out of load_config immediately.
    let text := try fs.read("config.jan", cap)

    // If parse_config fails, its error is propagated.
    let cfg := try parse_config(text)

    return cfg
end
```

#### 2\. Handling (`or`)

To handle an error immediately and locally, use an `or` block. This allows you to provide fallback logic or recover from the failure.

```janus
// Try to read the config, but use a default if it fails.
let config := fs.read("config.jan", cap) or |err| {
    log.warn("Config not found, using default.", error: err)
    return default_config()
}
```

-----

## Layer 2: The Janus Advantage: The Semantic Trace

A traditional stack trace is a primitive tool. It tells you *where* the code broke, but rarely *why*. A Janus error report is a **Semantic Trace**—a rich, intelligent, forensic document built from the compiler's perfect understanding of your code in the ASTDB.

For every frame in the trace, Janus provides deep semantic context:

  - The **effects** the function was declared with.
  - The **capabilities** it was expected to hold.
  - The **types** of the variables in scope.

This transforms a simple error message into a powerful **causal analysis**.

**Example Janus Error Report:**

```
🔥 KERNEL PANIC: Unhandled 'PermissionDenied'
   at 'save_user_profile' (user.jan:112)

   [Frame 1] save_user_profile(user: User)
   - Effects: { io.fs.write, db.write }
   - Capabilities: { CapDbWrite }
   - Insight: This function attempted an 'io.fs.write' effect but was not granted the 'CapFsWrite' capability.

   [Frame 2] http.handler(req: Request)
   - Effects: { io.net.read, io.net.write, db.write }
   - Capabilities: { CapNet, CapDbWrite }
   - Insight: This handler correctly holds 'CapDbWrite' but did not hold or grant 'CapFsWrite' to its callee.

   [Root Cause] fs.write() called without 'CapFsWrite'
```

-----

## Layer 3: The Final Weapon: Deterministic Replay

For the most catastrophic and elusive bugs, a static report is not enough. Janus provides a **time machine.**

When a program is run with the `--deterministic` flag, any crash will also produce a compact **replay log**. This log captures all non-deterministic inputs (e.g., network traffic, user input) that led to the failure.

You can feed this log back into the Janus debugger:

```bash
janus debug --replay=crash-log-123.bin
```

This launches a time-travel debugging session at the exact moment of the crash. You can then step **backwards** through your program's execution, inspecting the full application state at every point in time to see precisely where your logic went wrong.

-----

## Reporting Compiler Errors

The Janus compiler itself is a teaching instrument, and we strive to make its diagnostics perfect. If you encounter a confusing, incorrect, or unhelpful error message from the compiler, we consider that a high-priority bug.

When reporting a compiler diagnostic issue on our [Git Issues](https://git.maiwald.work/markus/janus/issues), please provide:

1.  A **minimal, reproducible code sample** that triggers the error.
2.  The **full, uncut error output** from the Janus compiler. The semantic trace is critical for our analysis.
3.  The version of the Janus compiler you are using (`janus --version`).

In Janus, an error is not the end of the program; it is the beginning of a precise, data-rich investigation.
