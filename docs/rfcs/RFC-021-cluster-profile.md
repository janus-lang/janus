# RFC-021: Janus :cluster Profile — Actor Model + Virtual Grains

**Version:** 2.0.0  
**Status:** DRAFT → APPROVED  
**Date:** 2026-02-09  
**Supersedes:** SPEC-profile-cluster-v0.1, legacy/profile-cluster.md  
**Author:** Janus (synthesized from attic/legacy specs)  

## Summary

The `:cluster` profile provides **distributed actor model** with **Virtual Grains** for fault-tolerant, location-transparent services. Builds on `:service` (scheduler/HTTP/NS-Msg).

**Key Features:**
- **Actors** — Isolated state, message passing (`send/receive`)
- **Grains** — Persistent actors (BEAM/OTP-style)
- **Supervision Trees** — Fault tolerance, hot reload
- **OTP Sugar** — `genserver`, `supervisor` DSLs desugaring to core

## Goals

1. **Production Distributed Systems** — Erlang/BEAM ergonomics on Janus runtime
2. **Game NPCs** — Stateful, clustered actors
3. **Backward Compatible** — Desugars to `:service` primitives

## Non-Goals

- Full BEAM VM — Native Janus runtime
- Dynamic Typing — Static types + sealed tables

## Specification

### 1. Keywords & Syntax

**New Keywords:**
```
actor, spawn, genserver, supervisor
```

**Symbols (Atoms):**
```
:ok, :error, :timeout, :normal, :gen_server, :supervisor
```

### 2. Core Primitives

**Actor Definition:**
```janus
actor MyActor do
    init(state) do
        {:ok, state}
    end

    handle_call({:get, key}, from, state) !Reply do
        let value = Map.get(state, key)
        {:reply, value, state}
    end

    handle_cast({:put, key, value}, state) !State do
        Map.put(state, key, value)
    end
end
```

**Desugars to:**
```janus
struct MyActorState { state: Map }
impl MyActor for MyActorState {
    fn handle_call(self: *MyActorState, msg: CallMsg) !ReplyMsg
    fn handle_cast(self: *MyActorState, msg: CastMsg) !void
}
```

**Spawn:**
```janus
let pid = spawn MyActor, initial_state
```

### 3. Grains (Persistent Actors)

**Grain Definition:**
```janus
grain PersistentGrain do
    init(id) do
        load_state(id)
    end

    handle_call(msg, from, state) !Reply do
        // Persist state changes
        persist_state(id, state)
        {:reply, result, state}
    end
end
```

### 4. Supervision

```janus
supervisor AppSup, strategy: .one_for_one do
    child(MyActor, [])
    child(PersistentGrain, ["grain1"])
end
```

### 5. Message Patterns

**OTP Sugar:**
```
send pid, {:ping, self()}
receive do
    {:pong, from} => log("PONG")
end
```

**Desugars to NS-Msg pub/sub.**

## Implementation Plan

1. **Actor Runtime** — Extend CBC-MN Nursery
2. **Grain Persistence** — RocksDB per-grain
3. **OTP DSL** — Macro desugaring
4. **Tests** — Gherkin + BDD-TDD (48+ scenarios)

**Timeline:** 2h

**Status:** READY FOR IMPLEMENTATION
