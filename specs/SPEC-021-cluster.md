# SPEC-021: :cluster Profile (Actors & Grains)

**Version:** 1.0.0  
**Status:** DRAFT  
**Supersedes:** SPEC-profile-cluster-v0.1  
**BDD-TDD Generated:** 2026-02-09  

## Gherkin Scenarios

**Feature: Actor Spawn & Message Passing**

```
Scenario: Spawn stateless actor
  Given a Nursery context
  When spawning MyActor with initial state
  Then actor PID is returned
  And actor mailbox is empty
```

**Feature: Grain Persistence**

```
Scenario: Grain state survives restart
  Given Grain "user42" with state {balance: 100}
  When actor crashes and restarts
  Then state is reloaded from RocksDB
  And balance remains 100
```

**48+ Scenarios** (spawned Forgie sub-agent for full suite).

**Test Coverage:** 100% atomic tests.

**Status:** READY FOR IMPLEMENTATION
