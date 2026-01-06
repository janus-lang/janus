<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Context System

**Status:** Implementation
**Version:** 0.1.0
**Profiles:** `:service`, `:sovereign`

## Overview

The Context system is the **doctrinal enforcer** of Janus's Syntactic Honesty principle. It makes all implicit dependencies explicit by bundling them into a single injectable struct.

## The Problem It Solves

Without Context, code has hidden dependencies:

```zig
// BAD: Hidden allocator, no cancellation, no capability checks
fn fetchData(url: []const u8) ![]u8 {
    // Where does memory come from?
    // How do we cancel if user navigates away?
    // Who authorized network access?
}
```

With Context, dependencies are visible:

```zig
// GOOD: All dependencies explicit
fn fetchData(url: []const u8, ctx: *Context) ![]u8 {
    if (ctx.isDone()) return error.Cancelled;
    if (!ctx.capabilities.net_connect) return error.CapabilityDenied;
    
    const data = try allocator.alloc(u8, size);
    ctx.logInfo("Fetched {d} bytes", .{size});
    return data;
}
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                      Context                            │
├─────────────────────────────────────────────────────────┤
│  allocator: *Allocator     ← Memory allocation          │
│  logger: ?*Logger          ← Structured logging         │
│  capabilities: *CapabilitySet  ← Security tokens        │
│  deadline: ?i64            ← Cancellation timeout       │
│  values: HashMap           ← Request-scoped data        │
│  cancelled: bool           ← Manual cancellation        │
└─────────────────────────────────────────────────────────┘
```

## Profile Usage

### `:core` Profile (No Context)

Functions take allocator directly. Simplest API, no overhead.

```zig
// :core - Direct allocator
pub fn readFile(path: []const u8, allocator: Allocator) ![]u8 {
    // ...
}
```

### `:service` Profile (Context for Lifecycle)

Functions take Context for deadline/cancellation/values.

```zig
// :service - Context-aware
pub fn readFile(path: []const u8, ctx: *Context) ![]u8 {
    if (ctx.isDone()) return error.Cancelled;
    
    const data = try foo(ctx.allocator);
    ctx.logInfo("Read {d} bytes", .{data.len});
    return data;
}
```

### `:sovereign` Profile (Context + Explicit Capability)

Functions take Context AND explicit capability token.

```zig
// :sovereign - Capability-gated
pub fn readFile(path: []const u8, cap: CapFsRead, ctx: *Context) ![]u8 {
    if (!cap.validate()) return error.CapabilityDenied;
    if (!ctx.isPathAllowed(path)) return error.PathDenied;
    if (ctx.isDone()) return error.Cancelled;
    
    // ...
}
```

## CapabilitySet

The `CapabilitySet` controls what operations are allowed:

```zig
var caps = CapabilitySet.init(allocator);
defer caps.deinit();

// Grant specific permissions
caps.grantFsRead();
caps.grantFsWrite();
caps.grantNetConnect();
caps.grantAccelerator();

// Restrict to specific paths
try caps.allowPath("/home/user/safe/");
```

## Logger

Structured logging that respects log levels:

```zig
var logger = Logger.init(allocator);
logger.level = .debug;  // Set minimum level

logger.trace("Very verbose", .{});   // Filtered out
logger.debug("Debug info", .{});     // Shown
logger.info("User action", .{});     // Shown
logger.warn("Potential issue", .{}); // Shown
logger.err("Error occurred", .{});   // Shown
logger.fatal("System crash", .{});   // Shown
```

## Context Creation

```zig
const allocator = std.heap.page_allocator;

var caps = CapabilitySet.init(allocator);
defer caps.deinit();

caps.grantFsRead();

var ctx = Context.init(allocator, &caps);
defer ctx.deinit();

// Add timeout
var ctx_with_timeout = ctx.withTimeout(5000); // 5 seconds

// Add logger
var logger = Logger.init(allocator);
var ctx_with_logger = ctx.withLogger(&logger);

// Add request-scoped value
var ctx_with_trace = try ctx.withValue("trace_id", "abc-123");
```

## Doctrinal Compliance

- **Syntactic Honesty**: All dependencies visible in function signature
- **IO Sovereignty**: Allocators and loggers explicitly passed
- **Capability-Based Security**: No operation without matching token
- **Progressive Disclosure**: `:core` simple, `:sovereign` explicit

## Testing

```bash
cd std/core
zig test context.zig
```
