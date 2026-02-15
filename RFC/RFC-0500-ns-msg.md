# **RFC-0500: ns-msg — Namespace Messaging**

## First-Class Distributed Communication for Janus

**Version:** 0.2.0 (with LTP Profile)  
**Status:** DRAFT  
**Profile:** :service  
**Layer:** L0-L4 (Transport to Federation)  
**Class:** FOUNDATIONAL  
**Author:** Markus Maiwald  
**Co-Author:** Claude (Anthropic)  
**Date:** 2026-02-15  

---

## 0. ABSTRACT

This document specifies **ns-msg**, the namespace messaging system for Janus' `:service` profile. It provides first-class distributed communication primitives that unify PUB/SUB, REQ/REP, and SURVEY patterns under a single semantic: **the namespace query.**

**Core Insight:** Just as Zenoh unifies messaging patterns through key-space queries, Janus unifies distributed communication through namespace types and effects.

**Design Goals:**
- **Zero-cost abstraction:** `ns-msg` compiles to efficient wire protocol
- **Type-safe namespaces:** Namespace paths are compile-time checked
- **Effect-transparent:** Communication effects are explicit and trackable
- **Kenya compliant:** Minimal runtime footprint (~50KB target)

---

## 1. MOTIVATION

### 1.1 The Gap
Janus `:core` provides systems programming. Janus `:service` needs distributed systems programming. Current approaches:
- **Raw sockets:** Too low-level, error-prone
- **gRPC/HTTP:** Heavy, broker-dependent, not sovereign
- **Actor frameworks:** Implicit message passing, hard to reason about

### 1.2 The Namespace Insight
In Janus, everything has a type. Namespaces should too.

```janus
// Instead of error-prone strings:
let topic = "sensor/berlin/pm25"  // Could be typo'd

// Type-safe namespaces:
let topic = Namespace.sensor.berlin.pm25  // Compile-time checked
```

### 1.3 Design Philosophy
> **Law: In ns-msg, everything is a namespace query. The pattern is in the path, not the API.**

| Traditional | ns-msg |
|-------------|--------|
| PUB/SUB | `publish(namespace)` / `subscribe(namespace)` |
| REQ/REP | `query(specific_namespace)` |
| SURVEY | `query(wildcard_namespace, timeout)` |
| PIPELINE | **Function calls** (not message passing) |

---

## 2. LANGUAGE INTEGRATION

### 2.1 Namespace Types

Namespaces are first-class types with compile-time path validation:

```janus
// Declaration
namespace Sensor {
    path: "sensor/{geohash}/{metric}"
    
    struct Reading {
        value: f64
        timestamp: u64
        unit: String
    }
}

namespace Feed {
    path: "feed/{chapter}/{channel}/{post_id}"
    
    struct Post {
        author: DID
        content: String
        entropy: EntropyStamp
    }
}

namespace Query {
    path: "query/{service}/{operation}"
    
    // Request/Response types
    struct TrustRequest {
        did: DID
        context: Context
    }
    
    struct TrustResponse {
        distance: f64
        path: Vec[DID]
    }
}
```

### 2.2 The Namespace Effect

All ns-msg operations are explicit effects:

```janus
// Effect signature
namespace NS {
    effect publish[T](path: Path, value: T) ! NetworkError
    effect subscribe[T](pattern: Pattern) ! NetworkError -> Stream[T]
    effect query[Q, R](path: Path, request: Q) ! NetworkError -> R
    effect respond[Q, R](pattern: Pattern, handler: fn(Q) ! R) ! NetworkError
}

// Usage with effect tracking
func monitor_sensors() ! NS.publish, NS.subscribe, Log do
    let sub = subscribe(Sensor.".".pm25)  // Wildcard: all geohashes
    
    for reading in sub do
        if reading.value > 50.0 then
            publish(Feed.berlin.alerts.alert_id, Alert {
                severity: High,
                message: "PM2.5 critical"
            })
        end
    end
end
```

### 2.3 Wildcard Patterns

Type-safe wildcards with compile-time validation:

```janus
// Single-level wildcard (+)
let all_pm25 = Sensor.+.pm25           // sensor/{any}/pm25

// Multi-level wildcard (*)
let all_sensors = Sensor.*              // sensor/{any}/{any}

// Specific geohash
let berlin_pm25 = Sensor.u33dc0.pm25    // sensor/u33dc0/pm25

// Query with wildcards (SURVEY pattern)
let health_results = query(Health.+, Timeout.ms(500))
```

---

## 3. API SPECIFICATION

### 3.1 Core Types

```janus
// Path represents a concrete namespace path
struct Path {
    segments: Vec[Segment]
    is_concrete: bool  // true if no wildcards
}

// Pattern represents a path with wildcards
struct Pattern {
    segments: Vec[PatternSegment]
    
    enum PatternSegment {
        Literal(String)
        SingleWildcard      // +
        MultiWildcard       // *
    }
}

// Message envelope
struct Envelope[T] {
    path: Path
    payload: T
    timestamp: u64
    sequence: u64
    // LWF encryption applied at transport layer
}

// Subscription handle
struct Subscription[T] {
    pattern: Pattern
    receiver: Channel[Envelope[T]]
    
    func next(self) ! TimeoutError -> ?Envelope[T]
    func cancel(self) ! do
        // Unsubscribe and cleanup
    end
}

// Query handle
struct QueryHandle[R] {
    responses: Vec[R]
    timeout: Duration
    
    func next(self) ! TimeoutError -> ?R
    func all(self) ! TimeoutError -> Vec[R]
end
```

### 3.2 Publish/Subscribe

```janus
// Publish a value to a namespace path
func publish[T](path: Path, value: T) ! NetworkError do
    let envelope = Envelope {
        path: path,
        payload: value,
        timestamp: now(),
        sequence: next_sequence()
    }
    
    // Route to local subscribers and network
    route_to_subscribers(envelope)
    route_to_network(envelope)
end

// Subscribe to a pattern
func subscribe[T](pattern: Pattern) ! NetworkError -> Subscription[T] do
    let (tx, rx) = channel()
    
    // Register with local router
    router.register(pattern, tx)
    
    // Announce subscription to network if needed
    if pattern.needs_network then
        announce_subscription(pattern)
    end
    
    return Subscription {
        pattern: pattern,
        receiver: rx
    }
end
```

### 3.3 Query/Response (REQ/REP)

```janus
// Query a specific path (REQ/REP pattern)
func query[Q, R](path: Path, request: Q, timeout: Duration) 
    ! NetworkError, TimeoutError -> R do
    
    let query_id = generate_id()
    let envelope = Envelope {
        path: path,
        payload: request,
        query_id: query_id,
        reply_path: Path.derived(query_id)
    }
    
    // Send query
    route_to_network(envelope)
    
    // Wait for single response
    let reply = await_reply(query_id, timeout)
    return reply.payload
end

// Register a queryable handler
func respond[Q, R](pattern: Pattern, handler: fn(Q) ! R) 
    ! NetworkError do
    
    router.register_queryable(pattern, handler)
end
```

### 3.4 Survey Pattern

```janus
// Survey multiple responders (SURVEY pattern)
func survey[Q, R](pattern: Pattern, request: Q, timeout: Duration)
    ! NetworkError -> QueryHandle[R] do
    
    let query_id = generate_id()
    let envelope = Envelope {
        path: pattern.to_path(),  // Broadcast to all matching
        payload: request,
        query_id: query_id,
        reply_path: Path.derived(query_id),
        expect_multiple: true
    }
    
    route_to_network(envelope)
    
    return QueryHandle {
        responses: Vec.new(),
        timeout: timeout,
        query_id: query_id
    }
end

// Usage
let handle = survey(Health.+, PingRequest {}, Timeout.ms(500))
while let Some(response) = handle.next() do
    process(response)
end
let all_responses = handle.all()  // Collect remaining within timeout
```

---

## 4. TRANSPORT LAYER

### 4.1 ns-service: The Runtime

`ns-service` is the runtime implementation of ns-msg for Janus `:service`:

```janus
// Service configuration
service MessageService {
    // Transport backends
    transport: [UTCP, QUIC, Memory]
    
    // Storage options
    persistence: PersistenceConfig {
        backend: RocksDB
        retention: Duration.days(7)
    }
    
    // Federation
    federation: FederationConfig {
        mode: PeerToPeer
        bootstrap_nodes: ["node1.libertaria.app", "node2.libertaria.app"]
    }
}

// Runtime handle
struct MessageRuntime {
    config: MessageService
    router: MessageRouter
    transports: Vec[Transport]
    
    func start(self) ! InitializationError do
        // Initialize transports
        // Start router
        // Join federation if configured
    end
    
    func stop(self) ! do
        // Graceful shutdown
    end
}
```

### 4.2 Wire Protocol

ns-msg compiles to LWF (Libertaria Wire Format):

```
LWF Frame Structure:
┌─────────────────────────────────────────────────────┐
│ Header (72 bytes)                                   │
│ ├── Version: 1 byte                                 │
│ ├── Frame Type: NS_MSG (0x05)                       │
│ ├── Session ID: 32 bytes                            │
│ ├── Sequence: 8 bytes                               │
│ └── Timestamp: 8 bytes                              │
├─────────────────────────────────────────────────────┤
│ NS-Msg Header                                       │
│ ├── Operation: 1 byte (PUB/SUB/QUERY/RESPONSE)      │
│ ├── Path Length: 2 bytes                            │
│ ├── Payload Length: 4 bytes                         │
│ └── Query ID: 16 bytes (optional)                   │
├─────────────────────────────────────────────────────┤
│ Path (variable)                                     │
│ ├── Segment count: 1 byte                           │
│ ├── Segments: [length + bytes]...                   │
├─────────────────────────────────────────────────────┤
│ Payload (variable, CBOR encoded)                    │
├─────────────────────────────────────────────────────┤
│ MAC (16 bytes, XChaCha20-Poly1305)                  │
└─────────────────────────────────────────────────────┘
```

### 4.3 Transport Selection

```janus
enum Transport {
    // In-process (zero-copy)
    Memory {
        channels: HashMap[Path, Channel]
    }
    
    // Local node (IPC)
    IPC {
        socket_path: String
    }
    
    // Network: L0 (UTCP)
    UTCP {
        endpoint: SocketAddr
        encryption: XChaCha20
    }
    
    // Network: L0 promoted (QUIC)
    QUIC {
        endpoint: SocketAddr
        zero_rtt: bool
    }
}

func select_transport(path: Path, target: NodeId) -> Transport do
    if target.is_local then
        return Transport.Memory
    else if target.is_same_node then
        return Transport.IPC
    else if can_zero_rtt(target) then
        return Transport.QUIC
    else
        return Transport.UTCP
    end
end
```

---

## 5. INTEGRATION WITH LIBERTARIA

### 5.1 Namespace Mapping

```janus
// Libertaria namespaces as Janus types
namespace Libertaria {
    namespace Membrane {
        path: "$MEMBRANE/{signal}"
        
        enum Signal {
            DefconCurrent
            DefconHistory
            PatternAlert(PatternId)
            StatsThroughput
        }
    }
    
    namespace Sensor {
        path: "$SENSOR/{geohash}/{metric}"
        
        struct Reading {
            value: f64
            unit: Unit
            timestamp: u64
            geohash: Geohash
        }
    }
    
    namespace Feed {
        path: "$FEED/{chapter}/{scope}/{id}"
        
        enum Scope {
            World
            Channel(ChannelId)
            Group(GroupId)
            DM(ThreadId)  // E2E encrypted
        }
        
        struct Post {
            author: DID
            content: Content
            entropy: EntropyStamp
            signatures: Vec[Signature]
        }
    }
    
    namespace Query {
        path: "$QUERY/{service}/{operation}"
        
        namespace QVL {
            func trust_distance(did: DID) ! TrustResponse
            func reputation(did: DID) ! ReputationResponse
        }
        
        namespace Economy {
            func velocity(token: Token) ! f64
        }
    }
}
```

### 5.2 Effect Composition

```janus
// Membrane Agent with full effect tracking
func membrane_agent() 
    ! NS.publish, NS.subscribe, NS.query, NS.respond,
      Crypto.verify, Time.now, Log.info,
      NetworkError, TimeoutError
    do
    
    // Subscribe to sensors
    let sensor_sub = subscribe(Sensor.".".pm25)
    
    // Respond to queries
    respond(Query.QVL.trust_distance, handle_trust_query)
    
    // Main loop
    loop do
        select do
            case reading = sensor_sub.next() ->
                if reading.value > 50.0 then
                    publish(Membrane.PatternAlert.air_quality, Alert {
                        severity: High,
                        location: reading.geohash
                    })
                end
            
            case query = handle_query() ->
                process_query(query)
        end
    end
end
```

---

## 6. IMPLEMENTATION ROADMAP

### Phase 1: Core Types (v0.5.0)
- [ ] Namespace type system
- [ ] Path/Pattern types with validation
- [ ] Envelope encoding/decoding (CBOR)

### Phase 2: In-Process (v0.6.0)
- [ ] Memory transport
- [ ] Local router
- [ ] Subscribe/publish loopback

### Phase 3: Network (v0.7.0)
- [ ] UTCP transport binding
- [ ] LWF frame integration
- [ ] Encryption (XChaCha20)

### Phase 4: Advanced Patterns (v0.8.0)
- [ ] Query/response
- [ ] Survey pattern
- [ ] Federation (ns-service)

### Phase 5: Persistence (v1.0.0)
- [ ] ns-msg-db external lib
- [ ] Historical queries
- [ ] Storage backends (RocksDB, SQLite)

---

## 7. RELATIONSHIP TO ZENOH

ns-msg is **inspired by** Zenoh but **native to Janus**:

| Zenoh | ns-msg | Difference |
|-------|--------|------------|
| Key-expression | Namespace types | Compile-time validated |
| `z_put()` | `publish()` | Effect-tracked |
| `z_get()` | `query()` | Type-safe request/response |
| `z_subscribe()` | `subscribe()` | Returns typed Stream |
| C API | Native Janus | No FFI boundary |
| Runtime library | Compiled | Zero-cost abstraction |

---

## 8. CONCLUSION

> **ns-msg: Distributed communication as first-class citizen.**

Just as Janus `:core` makes systems programming safe and explicit, ns-msg makes distributed systems programming safe and explicit. Everything is a namespace query. The pattern is in the path. The effects are visible.

**One language. One semantic. Sovereign communication.**

---

**End of RFC-0500 v0.1.0**

*The submarine speaks in namespaces.* 🜏


---

# RFC-0500 v0.2.0 AMENDMENT: LTP Profile & Wire Specification

**Version:** 0.2.0  
**Status:** DRAFT  
**Date:** 2026-02-15  
**Amends:** RFC-0500 v0.1.0  
**Author:** Markus Maiwald  
**Co-Author:** Claude (Anthropic)

---

## Summary of Changes

This amendment extends RFC-0500 with production-ready specifications for **LTP (Libertaria Telemetry Protocol)** — a profile of ns-msg for IoT/telemetry use cases. The core insight: **LTP is not a separate protocol; it is ns-msg with namespace conventions and retained values.**

| Feature | v0.1.0 | v0.2.0 (This Amendment) |
|---------|--------|---------------------------|
| Retained values | ❌ Not specified | ✅ Lamport-stamped (§3.5) |
| Subscription propagation | ❌ Mentioned only | ✅ SUB_ANNOUNCE spec (§4.4) |
| Will-Message integration | ❌ Not mentioned | ✅ Documented integration (§5.3) |
| Wire format | ❌ Conceptual only | ✅ Byte-level spec (§4.2) |
| LTP namespaces | ❌ Not defined | ✅ $LTP/* conventions (§6) |

---

## 3.5 RETAINED VALUES (NEW)

### 3.5.1 Motivation

MQTT's `retain` flag is essential for IoT: a sensor that publishes every 5 minutes should not require subscribers to wait 5 minutes for the first reading. The last known value must be available immediately.

ns-msg v0.2.0 adds retained values with **Lamport clock ordering** for causal consistency without consensus.

### 3.5.2 PublishOptions Extension

```zig
pub const PublishOptions = struct {
    /// Store this value as the retained value for the path?
    retain: bool = false,
    
    /// Delivery priority
    priority: Priority = .NORMAL,
    
    /// Lamport clock for causal ordering
    /// Automatically incremented by the publisher
    lamport_clock: u64 = 0,
    
    /// Time-to-live for retained value (0 = infinite)
    /// After TTL expires, retained value is deleted
    ttl_seconds: u32 = 0,
};
```

### 3.5.3 RetainedValue Storage

The local router maintains a `RetainedValue` cache:

```zig
pub const RetainedValue = struct {
    /// The concrete path (no wildcards)
    path: Path,
    
    /// Last envelope published with retain=true
    envelope: Envelope,
    
    /// Lamport clock at time of publication
    lamport_clock: u64,
    
    /// When this retained value expires (0 = never)
    expires_at: u64,
    
    /// Number of subscribers who have received this value
    /// (for garbage collection tracking)
    delivery_count: u32,
};

pub const RetainedValueCache = struct {
    /// Path → RetainedValue
    values: HashMap(Path, RetainedValue),
    
    /// Maximum retained values per namespace
    max_per_namespace: usize = 1000,
    
    /// Eviction policy: LRU when limit reached
    pub fn getOrEvict(self: *RetainedValueCache, path: Path) ?RetainedValue;
};
```

### 3.5.4 Causal Ordering with Lamport Clocks

When a retained value is updated, the router compares Lamport clocks:

```zig
fn updateRetained(path: Path, new_envelope: Envelope, new_clock: u64) !void {
    if (cache.get(path)) |existing| {
        // Only update if new clock is greater
        if (new_clock <= existing.lamport_clock) {
            return error.StaleValue;  // Ignore out-of-order update
        }
    }
    
    // Store new retained value
    cache.put(path, RetainedValue{
        .path = path,
        .envelope = new_envelope,
        .lamport_clock = new_clock,
        .expires_at = if (new_envelope.ttl_seconds > 0) 
            now() + new_envelope.ttl_seconds 
        else 
            0,
    });
}
```

**Why Lamport clocks:** They provide partial ordering without consensus. If sensor A and sensor B both publish to `sensor/berlin/temperature`, the router doesn't need to agree on "which is correct" — it just keeps the one with the highest Lamport clock.

### 3.5.5 Subscriber Initialization

When a subscriber calls `subscribe(pattern)`:

1. Router registers the subscription for future publishes
2. Router queries `RetainedValueCache` for all paths matching the pattern
3. Router immediately delivers matching retained values to the subscriber
4. Subscriber receives "latest known" values before any live data

```zig
fn subscribeWithRetained(pattern: Pattern) !Subscription {
    // Register for future messages
    var sub = try router.subscribe(pattern);
    
    // Deliver retained values immediately
    for (cache.values) |retained| {
        if (pattern.matches(retained.path)) {
            try sub.deliver(retained.envelope);
        }
    }
    
    return sub;
}
```

### 3.5.6 Implementation Notes

**Memory-constrained devices (Kenya profile):**
- Max 100 retained values per namespace
- Max 1KB payload per retained value
- TTL strongly recommended (prevents unbounded growth)

**Relay-scale deployment:**
- Retained values replicated across relay cluster
- Lamport clock synchronization via relay gossip
- Optional: consensus for contested updates (rare case)

---

## 4.2 WIRE FORMAT SPECIFICATION (UPGRADE)

### 4.2.1 Byte-Level LWF Header for ns-msg

ns-msg uses LWF Standard frames (1350 bytes max) with the following header layout:

```
LWF Header (88 bytes):
  [0-3]     Magic: "LWF\x00" (4 bytes)
  [4-27]    Destination Hint: 24 bytes (first 24 of target DID or topic hash)
  [28-51]   Source Hint: 24 bytes (first 24 of author DID)
  [52-67]   Session ID: 16 bytes (Noise session identifier)
  [68-71]   Sequence Number: u32 (big-endian, monotonic per session)
  [72-73]   Service Type: u16 (big-endian)
              0x0100 = NS_PUBLISH
              0x0101 = NS_SUBSCRIBE
              0x0102 = NS_QUERY
              0x0103 = NS_RESPONSE
              0x0104 = NS_SUB_ANNOUNCE
              0x0105 = NS_RETAINED_REQ
  [74-75]   Payload Length: u16 (big-endian, max 1182 for Standard frame)
  [76]      Frame Class: u8 (0x02 = Standard)
  [77]      Version: u8 (0x01 = ns-msg v1)
  [78]      Flags: u8
              bit 0: RETAIN (1 = this is a retained value)
              bit 1: ACK_REQ (1 = receipt requested)
              bit 2-7: Reserved (must be 0)
  [79]      Entropy Difficulty: u8 (min 10 for relay acceptance)
  [80-87]   Timestamp: u64 (big-endian, Sovereign Time)

Payload (variable, max 1182 bytes):
  CBOR-encoded message (see schemas below)

Trailer (68 bytes):
  [0-63]    Ed25519 Signature (author's signing key)
  [64-67]   CRC32C checksum (big-endian)
```

**Endianness:** All multi-byte integers are **big-endian** (network byte order).

### 4.2.2 CBOR Schema: NsPublish

```cbor
{
  0: "pub",              // Message type (text, 3 bytes)
  1: h'...',             // Path segments (array of byte strings)
  2: h'...',             // Payload (any CBOR, encrypted for topic)
  3: 1234567890,         // Lamport clock (unsigned)
  4: 3600,               // TTL seconds (unsigned, 0 = infinite)
  5: {                   // Metadata (optional map)
    0: "sensor/reading",  // Content type
    1: 1708000000,        // Origin timestamp
  }
}
```

### 4.2.3 CBOR Schema: NsSubscribe

```cbor
{
  0: "sub",              // Message type
  1: h'...',             // Pattern segments (array)
  2: true,               // Request retained values? (bool)
  3: 3600,               // Subscription TTL (seconds)
}
```

### 4.2.4 CBOR Schema: NsQuery

```cbor
{
  0: "qry",              // Message type
  1: h'...',             // Path segments (concrete, no wildcards)
  2: h'...',             // Query payload (CBOR, encrypted)
  3: 5000,               // Timeout milliseconds
  4: h'...',             // Correlation ID (16 bytes)
}
```

### 4.2.5 CBOR Schema: NsResponse

```cbor
{
  0: "res",              // Message type
  1: h'...',             // Correlation ID (matches query)
  2: h'...',             // Response payload (CBOR, encrypted)
  3: 200,                // Status code (200 = OK, 404 = not found, etc.)
}
```

### 4.2.6 Frame Size Limits

| Frame Class | Max Payload | Use Case |
|-------------|-------------|----------|
| Micro (0x00) | 40 bytes | Sensor readings, keepalives |
| Mini (0x01) | 422 bytes | Small telemetry batches |
| Standard (0x02) | 1,182 bytes | Most ns-msg traffic |
| Big (0x03) | 3,918 bytes | Large sensor dumps |
| Jumbo (0x04) | 8,812 bytes | Firmware updates, logs |

**Kenya devices:** Use Micro/Mini only. Standard requires 2KB RAM for frame buffer.

---

## 4.4 SUBSCRIPTION PROPAGATION (NEW)

### 4.4.1 The Scaling Problem

In a mesh of 100 solar panels, each panel publishes to `sensor/+/power`. Without subscription propagation, every relay must forward every publish to every peer (100 × 100 = 10,000 forwards per cycle).

With subscription propagation, relays only forward to peers that have expressed interest. Complexity drops to O(subscriptions) instead of O(nodes²).

### 4.4.2 SUB_ANNOUNCE Service Type

**Service Type:** `0x0104` (NS_SUB_ANNOUNCE)

**Purpose:** Gossip subscription patterns across the mesh.

**CBOR Schema:**

```cbor
{
  0: "ann",              // Message type
  1: h'...',             // Pattern segments (array)
  2: 3600,               // Subscription TTL (seconds)
  3: [                   // Interested peers (array of DID hints)
    h'abcd...',           // First 8 bytes of each interested DID
    h'ef01...',
  ],
  4: 1234567890,         // Lamport clock (for ordering updates)
}
```

### 4.4.3 Gossip Mechanics

**When a peer subscribes:**
1. Local router stores subscription
2. Router broadcasts SUB_ANNOUNCE to all mesh neighbors
3. Neighbors update their "subscription routing table"
4. If neighbor has no local interest, it forwards SUB_ANNOUNCE further

**Subscription routing table:**

```zig
pub const SubscriptionRoute = struct {
    /// Pattern being subscribed
    pattern: Pattern,
    
    /// Peers that have expressed interest
    interested_peers: Vec[PeerID],
    
    /// When this route entry expires
    expires_at: u64,
    
    /// Lamport clock of last update
    lamport_clock: u64,
};
```

### 4.4.4 Forwarding Logic

```zig
fn onPublishReceived(envelope: Envelope) !void {
    // Check local subscribers
    for (local_subscriptions) |sub| {
        if (sub.pattern.matches(envelope.path)) {
            try sub.deliver(envelope);
        }
    }
    
    // Check mesh forwarding table
    for (subscription_routes) |route| {
        if (route.pattern.matches(envelope.path)) {
            for (route.interested_peers) |peer| {
                try forwardToPeer(peer, envelope);
            }
        }
    }
}
```

### 4.4.5 TTL and Expiration

- SUB_ANNOUNCE carries TTL (default: 3600 seconds)
- Routers expire subscription routes after TTL
- Subscribers must re-announce periodically to maintain routes
- **Conservative default:** Re-announce every 15 minutes for 1-hour TTL

### 4.4.6 Deduplication

Routers track `(pattern, peer, lamport_clock)` to avoid forwarding duplicate SUB_ANNOUNCE. If a router receives the same pattern from the same peer with a lower or equal Lamport clock, it ignores the message.

---

## 5.3 WILL-MESSAGE INTEGRATION (NEW)

### 5.3.1 Architecture

RFC-0010 Amendment (Will-Message) delivers to ns-msg topics via `WillTarget::topic`. The integration point is clean: **the ns-msg router does not know it's processing a dead man's message.**

```
┌─────────────────────────────────────────────────────────────┐
│  Will-Message Layer (RFC-0010 Part IV)                       │
│  - Detects session death                                     │
│  - Validates Will signature                                  │
│  - Produces ExecutionProof                                   │
└──────────────────────┬──────────────────────────────────────┘
                       │ WILL_EXECUTE frame
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  ns-msg Router (this RFC)                                    │
│  - Receives Will as standard publish                         │
│  - Routes to subscribers                                     │
│  - No special handling required                              │
└──────────────────────┬──────────────────────────────────────┘
                       │ Standard publish
                       ▼
┌─────────────────────────────────────────────────────────────┐
│  Subscribers                                                 │
│  - Receive Will envelope                                     │
│  - Validate ExecutionProof                                   │
│  - Execute action (contract invocation, etc.)                │
└─────────────────────────────────────────────────────────────┘
```

### 5.3.2 Will Delivery as Retained Publish

When a Will executes, the relay publishes it with `retain = true`. This ensures:
1. Subscribers receive the Will even if they join after execution
2. The "death certificate" is available for audit
3. Contract agents can verify execution at their leisure

### 5.3.3 Contract Agent Handling

Contract agents (smart contract endpoints) subscribe to their own DID path:

```janus
// Contract agent subscribes to invocations targeting itself
let invocations = subscribe(Query.Contract."contract-did-here".*);

for msg in invocations {
    // Check if this is a Will-execution
    if msg.metadata.will_execution_proof {
        validateExecutionProof(msg.metadata.will_execution_proof);
        checkIdempotencyKey(msg.payload.idempotency_key);
    }
    
    // Execute contract method
    execute(msg.payload.method, msg.payload.args);
}
```

### 5.3.4 Integration Test Vector

```
Scenario: Escrow release on device death

1. Alice registers Will targeting escrow-contract DID
2. Alice's device goes offline (keepalive timeout)
3. Relay produces ExecutionProof
4. Relay publishes Will to $LTP/contract/escrow-agent/invoke
5. Escrow agent receives publish (with retain=true)
6. Agent validates Alice's signature + VC + ExecutionProof
7. Agent checks idempotency key (not seen before)
8. Agent releases funds to Bob
9. Agent publishes receipt to $LTP/contract/escrow-agent/receipt
```

---

## 6. LTP NAMESPACE CONVENTIONS (NEW)

### 6.1 The $LTP Prefix

**LTP (Libertaria Telemetry Protocol)** is a profile of ns-msg using standardized topic hierarchies under the `$LTP/` prefix. The `$` denotes a system namespace (user namespaces cannot start with `$`).

### 6.2 Topic Hierarchy

```
$LTP/
├── sensor/
│   ├── {geohash}/
│   │   ├── temperature     # °C, f64
│   │   ├── humidity        # %RH, f64
│   │   ├── pressure        # hPa, f64
│   │   ├── pm25            # µg/m³, f64
│   │   ├── pm10            # µg/m³, f64
│   │   ├── co2             # ppm, u32
│   │   ├── power           # Watts, f64 (solar/wind)
│   │   ├── energy          # kWh, f64 (cumulative)
│   │   └── status          # Device health, string enum
│   └── # Broadcast all sensors
├── weather/
│   ├── {geohash}/
│   │   ├── forecast        # JSON, 24h prediction
│   │   ├── alert           # Severe weather warning
│   │   └── radar           # Precipitation image (CBOR blob)
├── energy/
│   ├── grid/
│   │   ├── frequency       # Hz, f64
│   │   ├── voltage         # V, f64
│   │   └── load            # MW, f64
│   └── market/
│       ├── price           # €/MWh, f64
│       └── bid             # Bid/ask, structured
├── pager/                  # Emergency broadcast
│   ├── alert               # Critical alert (all devices)
│   ├── test                # Monthly test signal
│   └── all-clear           # End of emergency
├── device/
│   ├── {did}/
│   │   ├── will            # Will-Message execution
│   │   ├── status          # Online/offline
│   │   └── config          # Device configuration
└── contract/
    ├── {did}/
    │   ├── invoke          # Contract method invocation
    │   ├── receipt         # Execution receipt
    │   └── event           # Contract events
```

### 6.3 Geohash Precision

| Precision | Characters | Area (approx) | Use Case |
|-----------|------------|---------------|----------|
| 1 | 1 | 5,000 km | Continent |
| 2 | 2 | 1,000 km | Region |
| 3 | 3 | 100 km | State/Province |
| 4 | 4 | 20 km | City |
| 5 | 5 | 5 km | District |
| 6 | 6 | 1 km | Neighborhood |
| 7 | 7 | 100 m | Block |
| 8 | 8 | 20 m | Building |

**Default:** 6 characters (~1km²) for solar/weather sensors.

### 6.4 Standard Payload Schemas

**Sensor Reading (CBOR):**

```cbor
{
  0: 23.5,               // value (f64)
  1: "°C",               // unit (text)
  2: 1708000000,         // timestamp (u64, Unix seconds)
  3: 0.95,               // confidence 0-1 (f64, optional)
  4: h'...',             // sensor calibration hash (optional)
}
```

**Device Status (CBOR):**

```cbor
{
  0: "online",           // status: "online" | "degraded" | "offline"
  1: 95,                 // battery % (u8, 0-100)
  2: -45,                // RSSI dBm (i8)
  3: 1708000000,         // last_seen timestamp
  4: ["temp_sensor"],    // active sensors (array of text)
}
```

### 6.5 Example LTP Session

```janus
// Solar panel monitoring station
use ns_msg
use ltp  // LTP profile extensions

func solar_monitor(device_id: DID, location: Geohash) !void {
    // Publish power output every 30 seconds
    let power_topic = $LTP.sensor.{location}.power
    
    loop {
        let reading = sensor.read_power();
        
        publish(power_topic, SensorReading {
            value: reading.watts,
            unit: "W",
            timestamp: now(),
        }, .{
            retain = true,           // Keep last known value
            lamport_clock = clock.next(),
            ttl_seconds = 300,       // 5 minute freshness
        })
        
        sleep(Duration.seconds(30))
    }
}

// Grid operator receiving aggregated data
func grid_operator() !void {
    // Subscribe to all power sensors in Berlin (geohash u33)
    let sub = subscribe($LTP.sensor.u33.*.power)
    
    // Immediately receive all retained values
    for retained in sub.retained_values {
        update_grid_map(retained.path.geohash, retained.value)
    }
    
    // Then process live updates
    for reading in sub {
        update_grid_map(reading.path.geohash, reading.payload.value)
    }
}
```

---

## 7. PRODUCTION READINESS CHECKLIST

### 7.1 Implementation Status

| Component | Status | Notes |
|-----------|--------|-------|
| Path/Pattern types | ✅ Implemented | `src/service/ns_msg/types.zig` |
| Envelope encoding | ✅ Implemented | CBOR via `src/service/ns_msg/cbor.zig` |
| Local router | ✅ Implemented | `src/service/ns_msg/router.zig` |
| LWF integration | ✅ Implemented | `src/service/ns_msg/lwf.zig` |
| Retained values | ⏳ Missing | ~50 lines in router |
| Subscription propagation | ⏳ Missing | SUB_ANNOUNCE service type |
| Will-Message integration | ⏳ Missing | Documented, needs test |
| LTP namespace validation | ⏳ Missing | `$LTP/*` prefix checking |

### 7.2 Test Coverage

| Test Suite | Status | Target |
|------------|--------|--------|
| LWF frame BDD | 12/20 passing | 20/20 for v0.2.0 |
| Router unit tests | 16/16 passing | ✅ Good |
| Integration tests | Basic | Needs Will-Message test |
| Fuzz tests | ⏳ Missing | Property-based for retained values |

### 7.3 Open Questions

1. **Retained value synchronization across relay cluster:** Strong consistency or eventual?
2. **Subscription propagation in partition-tolerant networks:** How to handle netsplits?
3. **LTP geohash validation:** Should the router validate geohash syntax?

---

## 8. CHANGELOG

### v0.2.0 (2026-02-15)

- **Retained values** with Lamport clock ordering (§3.5)
- **Wire format specification** byte-level (§4.2 upgrade)
- **Subscription propagation** via SUB_ANNOUNCE (§4.4)
- **Will-Message integration** documented (§5.3)
- **LTP profile** namespace conventions (§6)
- Ready for IoT/telemetry production use

### v0.1.0 (2026-02-09)

- Genesis specification
- Core types: Path, Pattern, Envelope
- Effects: publish, subscribe, query, respond
- Language integration for Janus
- Relationship to Zenoh documented

---

> **LTP is not a protocol. It is a promise:**  
> **Your sensor data will find its way home.**  > **Your dead man's switch will fire.**  > **Your namespace is compile-time checked.**

---

**END RFC-0500 v0.2.0**  
**ns-msg: The namespace is the message.**
