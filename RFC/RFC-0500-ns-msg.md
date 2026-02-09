# **RFC-0500: ns-msg — Namespace Messaging**

## First-Class Distributed Communication for Janus

**Version:** 0.1.0  
**Status:** DRAFT  
**Profile:** :service  
**Layer:** L0-L4 (Transport to Federation)  
**Class:** FOUNDATIONAL  
**Author:** Markus Maiwald  
**Date:** 2026-02-09  

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
