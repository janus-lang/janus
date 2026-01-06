<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Dispatch Map RPC Schema (Draft v0)

**Purpose:** Provide machine-readable access to Janus dispatch resolution via `janusd` RPC.
**Format:** JSON by default; CBOR as binary transport for performance.
**Transport:** Same RPC mechanism as other `janusd` services (gRPC/JSON-RPC/WebSocket – TBD).

---

## **Endpoint 1: Query Canonical Dispatch Tables**

### Request
```json
{
  "method": "dispatch.query",
  "params": {
    "symbol": "add",
    "module": "std.math"
  }
}
```

### Response
```json
{
  "symbol": "add",
  "module": "std.math",
  "family": [
    {
      "signature": "add(i32, i32) -> i32",
      "location": "src/std/math.jan:12",
      "specificity": ["i32", "i32"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "location": "src/std/math.jan:18",
      "specificity": ["f64", "f64"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    },
    {
      "signature": "add(string, string) -> string",
      "location": "src/std/string.jan:44",
      "specificity": ["string", "string"],
      "dispatch_strategy": "runtime",
      "performance_cost": "sub_10ns"
    }
  ]
}
```

---

## **Endpoint 2: Trace Resolution Paths**

### Request
```json
{
  "method": "dispatch.trace",
  "params": {
    "call": {
      "symbol": "add",
      "args": ["i32", "f64"]
    },
    "context": {
      "module": "user.main",
      "location": "src/main.jan:25"
    }
  }
}
```

### Response (Corrected - No Implicit Coercions)
```json
{
  "call": "add(i32, f64)",
  "resolution_strategy": "compile_time_error",
  "candidates": [
    {
      "signature": "add(i32, i32) -> i32",
      "status": "rejected",
      "reason": "second argument type mismatch: expected i32, got f64"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "status": "rejected",
      "reason": "first argument type mismatch: expected f64, got i32"
    },
    {
      "signature": "add(string, string) -> string",
      "status": "rejected",
      "reason": "all argument types mismatch"
    }
  ],
  "error": {
    "code": "E0020",
    "message": "No matching implementation for call to 'add'",
    "suggestion": "Add explicit type conversion or define add(i32, f64) -> T"
  }
}
```

**Doctrinal Note:** The original example showing `"coercions": ["i32 → f64"]` has been **REMOVED**. Janus performs **no implicit coercions** during dispatch resolution. This maintains our doctrine of Syntactic Honesty - all type conversions must be explicit in the source code.

---

## **Endpoint 3: What-If Analysis**

### Request
```json
{
  "method": "dispatch.whatif",
  "params": {
    "call": {
      "symbol": "collide",
      "args": ["PlayerShip", "Asteroid"]
    }
  }
}
```

### Response
```json
{
  "call": "collide(PlayerShip, Asteroid)",
  "outcome": {
    "status": "resolved",
    "selected": "collide(PlayerShip, Asteroid) -> CollisionResult",
    "location": "src/game/physics.jan:210",
    "dispatch_strategy": "static",
    "performance_cost": "zero_overhead",
    "specificity_analysis": "exact_match"
  }
}
```

### Example: Ambiguity
```json
{
  "call": "add(MyVector, f64)",
  "outcome": {
    "status": "ambiguous",
    "candidates": [
      {
        "signature": "add(Vector2, f64) -> Vector2",
        "specificity_reason": "MyVector is subtype of Vector2"
      },
      {
        "signature": "add(Vector3, f64) -> Vector3",
        "specificity_reason": "MyVector is subtype of Vector3"
      }
    ],
    "error": {
      "code": "E0021",
      "message": "Ambiguous dispatch: multiple equally specific implementations",
      "suggestion": "Add more specific implementation for MyVector or use explicit type annotation"
    }
  }
}
```

---

## **Schema Data Models**

### Core Types
```json
{
  "DispatchSignature": {
    "signature": "string",
    "location": "SourceLocation",
    "specificity": ["TypeName"],
    "dispatch_strategy": "DispatchStrategy",
    "performance_cost": "PerformanceCost"
  },

  "DispatchStrategy": "static | runtime | hybrid",

  "PerformanceCost": "zero_overhead | sub_10ns | bounded_log_n",

  "SourceLocation": {
    "file": "string",
    "line": "number",
    "column": "number"
  },

  "ResolutionCandidate": {
    "signature": "string",
    "status": "accepted | rejected | ambiguous",
    "reason": "string",
    "specificity_reason": "string"
  }
}
```

---

## **Schema Notes**

- **`symbol`**: Function family name.
- **`signature`**: Full canonical type signature.
- **`location`**: Source file + line reference.
- **`specificity`**: Ordered type list, used for specificity graph.
- **`status`**: `accepted`, `rejected`, `ambiguous`.
- **`reason`**: For rejections, compiler diagnostic reason.
- **`dispatch_strategy`**: How the call will be resolved (static/runtime/hybrid).
- **`performance_cost`**: Expected performance characteristics.

**REMOVED**: `coercions` field - violates Janus doctrine of no implicit conversions.

---

## **Success Criteria**

1. AI agent can enumerate all overloads of a family.
2. AI agent can replay the compiler's resolution trace.
3. AI agent can predict resolution outcome for hypothetical calls.
4. **All dispatch behavior is explicit** - no hidden coercions or conversions.

---

## **Encoding Strategy**

### **Phase 1: JSON-First Approach**
- **Default encoding:** JSON (`application/json`)
- **Transport:** HTTP/JSON-RPC via `janusd` daemon
- **Tooling:** Standard tools (curl, jq, browser dev tools)
- **Debugging:** Human-readable payloads for development and testing

### **Phase 2: Performance Extension**
- **Binary encoding:** CBOR (`application/cbor`) for high-throughput scenarios
- **Schema stability:** Field names and structures identical across encodings
- **Content negotiation:** Clients specify preferred encoding via HTTP `Accept` header
- **Backward compatibility:** JSON remains supported indefinitely

### **Rationale**
JSON provides immediate accessibility for developers and AI agents during Phase 1 (Core Language Integration). CBOR will be introduced in Phase 2 (Performance & Scale) once dispatch maps become heavy (thousands of overloads) and performance becomes a bottleneck, without changing schema semantics.

**Example Content Negotiation:**
```http
Accept: application/json          # Default, human-readable
Accept: application/cbor          # Binary, high-performance
Accept: application/json, application/cbor;q=0.9  # Preference order
```

---

🔥 This schema turns Janus dispatch into a **transparent, queryable semantic substrate** — not just for human developers, but for **AI copilots, refactoring bots, and verification systems** — while maintaining **doctrinal purity** with no hidden behavior.

---

## **Doctrinal Compliance Statement**

This RPC schema maintains Janus's core principles:

- ✅ **Syntactic Honesty**: No implicit coercions or hidden conversions
- ✅ **Revealed Complexity**: All dispatch decisions are transparent and queryable
- ✅ **Mechanism over Policy**: Provides tools for AI agents to understand dispatch without imposing decisions
- ✅ **Honest Sugar**: All convenience features desugar to visible, documented mechanisms

The schema enables powerful AI tooling while ensuring that **what you query is what you get** - no surprises, no magic, no hidden costs.
---


## **📦 CBOR Encodings for Dispatch Map RPC**

*Note: CBOR encoding is **schema-preserving** — same fields, same structure, only serialized in compact binary. We use CBOR diagnostic notation to show raw hex plus readable breakdown.*

### **1. `dispatch.query`**

**JSON (Canonical):**
```json
{
  "symbol": "add",
  "family": [
    {
      "signature": "add(i32, i32) -> i32",
      "location": "src/std/math.jan:12",
      "specificity": ["i32", "i32"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "location": "src/std/math.jan:18",
      "specificity": ["f64", "f64"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    }
  ]
}
```

**CBOR Diagnostic:**
```
{
  "symbol": "add",
  "family": [
    {
      "signature": "add(i32, i32) -> i32",
      "location": "src/std/math.jan:12",
      "specificity": ["i32", "i32"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "location": "src/std/math.jan:18",
      "specificity": ["f64", "f64"],
      "dispatch_strategy": "static",
      "performance_cost": "zero_overhead"
    }
  ]
}
```

**CBOR Hex:**
```
a2                                      # map(2)
  66                                    # text(6)
    73796d626f6c                        # "symbol"
  63                                    # text(3)
    616464                              # "add"
  66                                    # text(6)
    66616d696c79                        # "family"
  82                                    # array(2)
    a5                                  # map(5) - first overload
      69                                # text(9)
        7369676e6174757265              # "signature"
      74                                # text(20)
        616464286933322c2069333229202d3e20693332  # "add(i32, i32) -> i32"
      68                                # text(8)
        6c6f636174696f6e                # "location"
      71                                # text(17)
        7372632f7374642f6d6174682e6a616e3a3132    # "src/std/math.jan:12"
      6b                                # text(11)
        7370656369666963697479          # "specificity"
      82                                # array(2)
        63                              # text(3)
          693332                        # "i32"
        63                              # text(3)
          693332                        # "i32"
      71                                # text(17)
        64697370617463685f737472617465677920      # "dispatch_strategy"
      66                                # text(6)
        737461746963                    # "static"
      70                                # text(16)
        706572666f726d616e63655f636f7374          # "performance_cost"
      6d                                # text(13)
        7a65726f5f6f766572686561640      # "zero_overhead"
    # ... second overload (similar structure)
```

### **2. `dispatch.trace` (Corrected - No Implicit Coercions)**

**JSON (Canonical):**
```json
{
  "call": "add(i32, f64)",
  "resolution_strategy": "compile_time_error",
  "candidates": [
    {
      "signature": "add(i32, i32) -> i32",
      "status": "rejected",
      "reason": "second argument type mismatch: expected i32, got f64"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "status": "rejected",
      "reason": "first argument type mismatch: expected f64, got i32"
    }
  ],
  "error": {
    "code": "E0020",
    "message": "No matching implementation for call to 'add'",
    "suggestion": "Add explicit type conversion or define add(i32, f64) -> T"
  }
}
```

**CBOR Diagnostic:**
```
{
  "call": "add(i32, f64)",
  "resolution_strategy": "compile_time_error",
  "candidates": [
    {
      "signature": "add(i32, i32) -> i32",
      "status": "rejected",
      "reason": "second argument type mismatch: expected i32, got f64"
    },
    {
      "signature": "add(f64, f64) -> f64",
      "status": "rejected",
      "reason": "first argument type mismatch: expected f64, got i32"
    }
  ],
  "error": {
    "code": "E0020",
    "message": "No matching implementation for call to 'add'",
    "suggestion": "Add explicit type conversion or define add(i32, f64) -> T"
  }
}
```

**CBOR Hex (truncated):**
```
a4                                      # map(4)
  64                                    # text(4)
    63616c6c                            # "call"
  6d                                    # text(13)
    616464286933322c20663634290        # "add(i32, f64)"
  72                                    # text(18)
    7265736f6c7574696f6e5f737472617465677920  # "resolution_strategy"
  72                                    # text(18)
    636f6d70696c655f74696d655f6572726f72      # "compile_time_error"
  6a                                    # text(10)
    63616e64696461746573                # "candidates"
  82                                    # array(2)
    a3                                  # map(3) - first candidate
      69                                # text(9)
        7369676e6174757265              # "signature"
      74                                # text(20)
        616464286933322c2069333229202d3e20693332  # "add(i32, i32) -> i32"
      66                                # text(6)
        737461747573                    # "status"
      68                                # text(8)
        72656a6563746564                # "rejected"
      66                                # text(6)
        726561736f6e                    # "reason"
      78 2b                             # text(43)
        7365636f6e6420617267756d656e74207479706520...  # "second argument type mismatch..."
    # ... second candidate
  65                                    # text(5)
    6572726f72                          # "error"
  a3                                    # map(3)
    # ... error details
```

### **3. `dispatch.whatif`**

**JSON (Canonical):**
```json
{
  "call": "collide(PlayerShip, Asteroid)",
  "outcome": {
    "status": "resolved",
    "selected": "collide(PlayerShip, Asteroid) -> CollisionResult",
    "location": "src/game/physics.jan:210",
    "dispatch_strategy": "static",
    "performance_cost": "zero_overhead"
  }
}
```

**CBOR Diagnostic:**
```
{
  "call": "collide(PlayerShip, Asteroid)",
  "outcome": {
    "status": "resolved",
    "selected": "collide(PlayerShip, Asteroid) -> CollisionResult",
    "location": "src/game/physics.jan:210",
    "dispatch_strategy": "static",
    "performance_cost": "zero_overhead"
  }
}
```

**CBOR Hex:**
```
a2                                      # map(2)
  64                                    # text(4)
    63616c6c                            # "call"
  78 1d                                 # text(29)
    636f6c6c69646528506c61796572536869702c2041737465726f696429  # "collide(PlayerShip, Asteroid)"
  67                                    # text(7)
    6f7574636f6d65                      # "outcome"
  a5                                    # map(5)
    66                                  # text(6)
      737461747573                      # "status"
    68                                  # text(8)
      7265736f6c766564                  # "resolved"
    68                                  # text(8)
      73656c6563746564                  # "selected"
    78 2f                               # text(47)
      636f6c6c69646528506c61796572536869702c2041737465726f696429202d3e20436f6c6c6973696f6e526573756c74  # "collide(PlayerShip, Asteroid) -> CollisionResult"
    68                                  # text(8)
      6c6f636174696f6e                  # "location"
    78 19                               # text(25)
      7372632f67616d652f706879736963732e6a616e3a323130  # "src/game/physics.jan:210"
    71                                  # text(17)
      64697370617463685f737472617465677920        # "dispatch_strategy"
    66                                  # text(6)
      737461746963                      # "static"
    70                                  # text(16)
      706572666f726d616e63655f636f7374            # "performance_cost"
    6d                                  # text(13)
      7a65726f5f6f766572686561640        # "zero_overhead"
```

### **✅ Encoding Strategy Recap**

- **Default:** JSON (`application/json`)
- **Optional (Phase 2):** CBOR (`application/cbor`)
- **Contract:** Schema stable across encodings (field names/values identical)
- **Negotiation:** Via RPC headers (`Accept: application/cbor`)

### **Performance Projections**

| Scenario | JSON Size | CBOR Size | Bandwidth Savings |
|----------|-----------|-----------|-------------------|
| Small query | ~100 bytes | ~65 bytes | 35% |
| Large family (50 overloads) | ~8KB | ~5KB | 37% |
| Bulk analysis (1000 queries) | ~800KB | ~520KB | 35% |
| Trace with error details | ~500 bytes | ~320 bytes | 36% |

### **Implementation Notes**

- **String interning** can provide additional 15-20% compression
- **Binary parsing** is 3-5x faster than JSON for large payloads
- **Schema remains identical** - only encoding changes
- **Content negotiation** allows gradual migration
- **No doctrinal violations** - CBOR examples maintain explicit error reporting

🔥 **With these CBOR examples on file, we guarantee a performance escape hatch is provisioned. No surprises later, no schema drift.**
---


## **📊 Benchmark Plan: JSON vs CBOR Performance**

*Strategic benchmarking to determine the optimal Phase 1 → Phase 2 transition point.*

### **Benchmark Scenarios**

| Scenario | Description | Dispatch Families | Overloads per Family | Expected JSON Size |
|----------|-------------|-------------------|---------------------|-------------------|
| **Small Project** | Basic math operations | 10 | 3-5 | ~2KB |
| **Medium Project** | Game engine core | 100 | 5-10 | ~50KB |
| **Large Project** | Full stdlib + user code | 1,000 | 10-20 | ~2MB |
| **Enterprise Scale** | Massive codebase | 10,000 | 20-50 | ~50MB |

### **Performance Metrics**

#### **Throughput Benchmarks**
- **Query Rate**: Queries per second for `dispatch.query`
- **Trace Rate**: Traces per second for `dispatch.trace`
- **Bulk Analysis**: Time to analyze 1000 dispatch calls
- **Memory Usage**: Peak memory during large query processing

#### **Latency Benchmarks**
- **Cold Start**: First query response time
- **Warm Cache**: Subsequent query response time
- **Network Overhead**: Serialization + transmission time
- **Parse Time**: Deserialization time on client side

### **Phase 2 Transition Triggers**

**Automatic CBOR Migration When:**
- JSON payload size > 1MB for single query
- Query throughput < 100 queries/second
- Network bandwidth > 10MB/minute for dispatch queries
- Parse time > 10ms for typical queries

**Manual Override:**
- High-frequency AI agents (>1000 queries/minute)
- Bandwidth-constrained environments
- Real-time analysis requirements

### **Benchmark Implementation**

```bash
# Benchmark suite commands (Phase 2)
janus benchmark dispatch --format=json --queries=1000 --families=100
janus benchmark dispatch --format=cbor --queries=1000 --families=100
janus benchmark dispatch --compare --threshold=1mb
```

**Expected Results:**
- **Small/Medium Projects**: JSON sufficient (human-readable wins)
- **Large Projects**: CBOR provides 35-40% improvement
- **Enterprise Scale**: CBOR essential for performance

### **Decision Matrix**

| Project Size | Recommended Format | Rationale |
|--------------|-------------------|-----------|
| < 100 families | JSON | Debugging and tooling ease |
| 100-1000 families | JSON with CBOR option | Content negotiation |
| > 1000 families | CBOR default | Performance critical |
| AI-heavy workloads | CBOR | High query frequency |

🎯 **This benchmark plan ensures we flip the switch to CBOR exactly when it matters, not before.**
