<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





## Normative Language (RFC 2119)

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD", "SHOULD NOT", "RECOMMENDED", "MAY", and "OPTIONAL" in this document are to be interpreted as described in [RFC 2119](https://tools.ietf.org/html/rfc2119).


# Janus Specification — Canonical Program Representation (SPEC-013)

**Version:** 2.0.0  
**Status:** CANONICAL  
**Authority:** Constitutional  
**Supersedes:** SPEC-canonical-program v0.2.1

## Overview

This program demonstrates the **One True Form**. It uses:
1.  **Explicit Capability Constraints** (`with ctx where ctx.has(...)`)
2.  **The 37 Keys** (`.net_connect`, `.log_write`)
3.  **Honest Sugar** (`$"{...}"`, `try ...`)
4.  **Implicit Context Passing** (Call-site `with ctx`)

It is exactly 30 lines of logic (excluding comments). It is the definition of Janus.

---

## The Canon

```janus
module "keeper" { requires capabilities { .net_connect, .log_write, .alloc } }

import std.net.http
import std.json

// A pure data structure (Structural Typing)
struct StatusReport { uptime: u64, healthy: bool, region: String }

// The Sovereign Function: Explicit privileges, no hidden side effects
func publish_status(endpoint: String, report: StatusReport) -> void ! Error
with ctx where ctx.has(.net_connect, .log_write, .alloc)
do
    // Honest Logging: We declare we need .log_write, so we can use it
    ctx.log.info($"Broadcasting status to {endpoint}")

    // Honest Serialization: Allocating JSON string requires .alloc
    let payload := json.serialize(report) with ctx

    // Honest I/O: Networking requires .net_connect
    // 'or do' block handles errors inline (Honest Control Flow)
    let response := http.post(endpoint, payload) with ctx 
        or do |err|
            ctx.log.error($"Failed to publish: {err}")
            return err
        end

    ctx.log.info($"Success: {response.status}")
end

// The Entry Point: The root of authority
func main(args: []String) -> void ! Error
with ctx where ctx.has(.net_connect, .log_write, .alloc, .time_monotonic)
do
    let report := StatusReport { 
        uptime: ctx.clock.monotonic(), 
        healthy: true, 
        region: "eu-central-1" 
    }

    // Call-site checking: Compiler proves main's ctx has required keys
    publish_status("https://api.monastery.io/heartbeat", report) with ctx
end
```

## Analysis

1.  **Line 1**: Module manifest declares the maximum ambient authority.
2.  **Line 13**: `with ctx where ctx.has(...)`. The signature is a contract. It demands 3 specific keys from the 37.
3.  **Line 20**: `json.serialize(...) with ctx`. Explicit allocation. No hidden `malloc`.
4.  **Line 25**: `http.post(...) with ctx`. Explicit network usage.
5.  **Line 26**: `or do |err|`. No `try/catch` jumping. Local, visible error handling.
6.  **Line 46**: `with ctx`. The context flows. The compiler verifies that `main` (which has 4 keys) satisfies `publish_status` (which needs 3).

**This is safe.**
**This is honest.**
**This is Janus.**
