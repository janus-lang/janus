<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC: The Citadel Architecture

**Status:** Draft
**Author:** Self Sovereign Society Foundation
**Date:** 2025-09-06
**Version:** 0.1.0
**Epic:** The Citadel Architecture

## Problem Statement

The current `janusd` daemon is a monolithic binary that tightly couples the pure, dependency-light compiler core (`libjanus`) with a heavy, C++-based transport layer (gRPC). This architectural violation has led to:

1. **Cross-compilation failure**: gRPC dependencies prevent building for all target platforms
2. **Architectural impurity**: The core compiler is beholden to transport protocol complexities
3. **Deployment inflexibility**: Cannot deploy core functionality without heavy dependencies
4. **Future brittleness**: Adding new transport protocols requires touching the core

This violates our doctrine: **The Citadel should not be tied to the material of the outer wall.**

## Solution: The Citadel Architecture

We will refactor our daemon into a **Citadel Architecture** with three distinct components:

```
┌─────────────────────────────────────────────────────────────┐
│                    The Outer Wall                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              janus-grpc-proxy                       │    │
│  │  • gRPC Server (C++ dependencies)                   │    │
│  │  • Stateless protocol translation                   │    │
│  │  • Platform-specific deployment                     │    │
│  └─────────────────────────────────────────────────────┘    │
│                           │                                 │
│                    stdio/socket                             │
│                           │                                 │
│  ┌─────────────────────────────────────────────────────┐    │
│  │               The Keep                              │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │         janus-core-daemon                   │    │    │
│  │  │  • Links only against libjanus              │    │    │
│  │  │  • Lightweight protocol (MessagePack)       │    │    │
│  │  │  • Cross-compiles to all targets            │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  │                     │                               │    │
│  │              Direct API calls                       │    │
│  │                     │                               │    │
│  │  ┌─────────────────────────────────────────────┐    │    │
│  │  │              The Citadel                    │    │    │
│  │  │  ┌─────────────────────────────────────┐    │    │    │
│  │  │  │            libjanus                 │    │    │    │
│  │  │  │  • Pure, dependency-free library    │    │    │    │
│  │  │  │  • Zero knowledge of transport      │    │    │    │
│  │  │  │  • Core compiler functionality      │    │    │    │
│  │  │  └─────────────────────────────────────┘    │    │    │
│  │  └─────────────────────────────────────────────┘    │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

### Component 1: `libjanus` (The Citadel)

**Status:** ✅ Already exists and is pure
**Dependencies:** None (zero external dependencies)
**Responsibility:** Core compiler functionality

This remains unchanged. It is already our pure, dependency-free library with zero knowledge of transport protocols.

### Component 2: `janus-core-daemon` (The Keep)

**Status:** 🔄 New component to be created
**Dependencies:** Only `libjanus`
**Communication:** stdio or Unix socket
**Protocol:** MessagePack or similar lightweight format

A new, lightweight daemon binary that:
- Links *only* against `libjanus`
- Exposes compiler functionality over a simple communication channel
- Speaks a lightweight, dependency-free protocol
- Cross-compiles trivially to all target platforms

### Component 3: `janus-grpc-proxy` (The Outer Wall)

**Status:** 🔄 Refactor from current `janusd`
**Dependencies:** gRPC, protobuf, etc.
**Communication:** gRPC (external), stdio/socket (internal)

A separate binary that:
- Does **not** link against `libjanus`
- Is a simple, stateless proxy
- Receives gRPC requests and translates them
- Forwards requests to `janus-core-daemon` over simple protocol
- Can be compiled natively only where needed

## Strategic Benefits

### 1. Cross-Compilation Solved
- Cross-compile the lean `janus-core-daemon` for all platforms
- Compile `janus-grpc-proxy` natively only on platforms where needed
- Or rewrite the proxy in another language (Go, Rust, etc.)

### 2. Architectural Purity
- Core compiler fully decoupled from transport layer
- Clean separation of concerns
- No protocol knowledge leaks into the core

### 3. Future-Proof Extensibility
- Add new proxies (`janus-jsonrpc-proxy`, `janus-capnproto-proxy`) without touching core
- Support multiple protocols simultaneously
- Easy to add new transport mechanisms

### 4. Deployment Flexibility
- Deploy core daemon on resource-constrained environments
- Deploy proxy only where heavy protocols are needed
- Mix and match components as needed

## Implementation Plan

### Phase 1: Core Daemon Creation
1. Create `daemon/janus_core_daemon.zig`
2. Implement lightweight protocol (MessagePack over stdio)
3. Expose core `libjanus` functionality
4. Ensure cross-compilation works for all targets

### Phase 2: Protocol Definition
1. Define lightweight protocol specification
2. Implement protocol serialization/deserialization
3. Create protocol test suite
4. Document protocol for future proxy implementations

### Phase 3: Proxy Refactoring
1. Refactor current `janusd` into `janus-grpc-proxy`
2. Remove direct `libjanus` dependencies
3. Implement proxy communication with core daemon
4. Maintain API compatibility

### Phase 4: Integration & Testing
1. End-to-end testing of the full stack
2. Performance benchmarking
3. Cross-platform deployment testing
4. Documentation updates

## Success Criteria

1. ✅ **Green Cross-Compilation**: `janus-core-daemon` builds for all target platforms
2. ✅ **Zero Core Dependencies**: Core daemon has no external dependencies beyond `libjanus`
3. ✅ **Protocol Isolation**: Core has zero knowledge of gRPC or any transport protocol
4. ✅ **API Compatibility**: Existing gRPC API continues to work unchanged
5. ✅ **Performance Parity**: No significant performance regression
6. ✅ **Deployment Flexibility**: Can deploy components independently

## Risk Mitigation

### Risk: Performance Overhead
**Mitigation:** Use efficient serialization (MessagePack) and local communication (Unix sockets)

### Risk: Protocol Complexity
**Mitigation:** Keep protocol minimal and well-documented; use existing serialization libraries

### Risk: Deployment Complexity
**Mitigation:** Provide deployment scripts and clear documentation; maintain backward compatibility

## Future Extensions

Once the Citadel Architecture is established:

1. **Multiple Protocols**: Add JSON-RPC, Cap'n Proto, or other protocol proxies
2. **Language Bindings**: Implement proxies in other languages (Go, Rust, Python)
3. **Distributed Deployment**: Deploy core daemon and proxies on different machines
4. **Load Balancing**: Multiple proxy instances connecting to core daemon pools

## Conclusion

The Citadel Architecture solves our immediate cross-compilation crisis while establishing a robust, extensible foundation for future growth. It embodies our architectural principles:

- **Separation of Concerns**: Core logic isolated from transport
- **Dependency Minimization**: Each component has minimal, appropriate dependencies
- **Cross-Platform Support**: Core functionality available everywhere
- **Future-Proof Design**: Easy to extend without breaking existing functionality

This is not just a fix—it's a strategic architectural upgrade that will serve us for years to come.
