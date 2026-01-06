<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Standard Library Consistency Across Profiles

## The Tri-Signature Pattern

Janus maintains API consistency across profiles through the **tri-signature pattern**: same function names with profile-specific capabilities.

### Core Principle

**Same name, rising honesty** - function names remain constant, but parameter requirements become more explicit as profiles advance.

## HTTP Module Example

### Function: `http_get`

| Profile | Signature | Capabilities |
|---------|-----------|--------------|
| `:core` | `http_get(url: String) -> Bytes` | Simple, synchronous |
| `:service` | `http_get(url: String, ctx: Context) -> Bytes` | Timeout, cancellation |
| `:sovereign` | `http_get(url: String, cap: Cap[NetHttp]) -> Bytes` | Security, audit trails |

### Code Examples

#### :core Profile - Learning & Scripts
```janus
// Simple, no ceremony
let response = http_get("https://api.example.com/users")
print(response)
```

#### :service Profile - Production Backend
```janus
// Context-aware with timeout
let ctx = context.with_timeout(parent_ctx, 5000)  // 5 second timeout
let response = http_get("https://api.example.com/users", ctx)
print(response)
```

#### :sovereign Profile - Secure Systems
```janus
// Capability-gated with explicit permissions
let cap = NetHttp.init("api-client")
cap.allow_host("api.example.com")
let response = http_get("https://api.example.com/users", cap)
print(response)
```

## Migration Path

### No Breaking Changes
Code written in a lower profile continues to work when upgrading:

```janus
// This code works in :core, :service, and :sovereign profiles
func fetch_user_data() {
    let response = http_get("https://api.example.com/users")
    return parse_json(response)
}
```

### Progressive Enhancement
Add capabilities when ready:

```janus
// Upgrade to :service profile - add context
func fetch_user_data(ctx: Context) {
    let response = http_get("https://api.example.com/users", ctx)
    return parse_json(response)
}

// Upgrade to :sovereign profile - add capability
func fetch_user_data(cap: Cap[NetHttp]) {
    let response = http_get("https://api.example.com/users", cap)
    return parse_json(response)
}
```

## Context Module (:service+ profiles)

### Features
- **Deadline management**: Automatic timeout handling
- **Cancellation propagation**: Structured cancellation across call stack
- **Value passing**: Request ID, user context, tracing information
- **Integration**: Works with structured concurrency (nurseries)

### API
```janus
// Create contexts
let ctx = context.background()
let timeout_ctx = context.with_timeout(ctx, 5000)
let cancel_ctx = context.with_cancel(ctx)

// Check context state
if ctx.is_done() {
    // Handle cancellation or timeout
}

// Pass values
let user_ctx = ctx.with_value("user_id", "12345")
let user_id = user_ctx.get_value("user_id")
```

## Capability System (:sovereign profile)

### Features
- **Explicit permissions**: No ambient authority
- **Host/scheme restrictions**: Fine-grained access control
- **Audit trails**: All capability usage logged
- **Compile-time verification**: Type system enforces capabilities

### API
```janus
// Create capabilities
let http_cap = NetHttp.init("service-client")
http_cap.allow_host("api.example.com")
http_cap.allow_scheme("https")

let fs_cap = FileSystem.init("config-reader")
fs_cap.allow_path("/etc/myapp")
fs_cap.set_read_only(true)

// Use capabilities
let response = http_get(url, http_cap)
let config = file_read("/etc/myapp/config.json", fs_cap)
```

## Benefits

### For Developers
- **Familiar names**: No need to learn new APIs when upgrading profiles
- **Progressive complexity**: Add capabilities when needed, not before
- **Type safety**: Compiler enforces capability requirements
- **Clear costs**: Parameter requirements make costs explicit

### For Teams
- **Gradual adoption**: Start simple, scale complexity over time
- **No rewrites**: Existing code continues to work
- **Security by design**: Capabilities required for sensitive operations
- **Audit compliance**: All access explicitly granted and tracked

### For Systems
- **Principle of least privilege**: Only required capabilities granted
- **Defense in depth**: Multiple layers of access control
- **Observability**: All capability usage auditable
- **Correctness**: Type system prevents capability violations

## Implementation Status

- ✅ **HTTP module**: Tri-signature pattern implemented
- ✅ **Context module**: Deadline, cancellation, values
- ✅ **Capability system**: NetHttp, FileSystem, Database capabilities
- ✅ **Profile integration**: Feature gating and availability
- ✅ **Documentation**: API consistency patterns documented

This establishes the foundation for stdlib consistency that enables Janus's progressive adoption strategy.
