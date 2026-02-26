# L2 Session Manager

Sovereign agent session management with heartbeat timeout logic.

## Overview

The L2 Session Manager implements the Libertaria Protocol's session layer for agent-to-agent coordination. It provides:

- **State Machine**: handshake → active → degraded → closed
- **Heartbeat Monitoring**: Configurable intervals with grace periods
- **Automatic Recovery**: Degraded sessions recover on heartbeat
- **Timeout Enforcement**: Grace period expiration triggers session close

## Usage

```janus
use zig "l2_session/session"

// Create a session with custom heartbeat config
var config = HeartbeatConfig{
    .interval_ms = 30000,      // 30 second heartbeat interval
    .grace_period_ms = 10000,   // 10 second grace period
    .max_missed = 3,            // 3 missed beats before degradation
}

var session = try Session.init(allocator, session_id, config)
```

## The Four Modes of Coordination

This session layer enables the Libertaria Protocol's four coordination modes:

1. **Collaboration**: High-trust sessions with extended grace periods
2. **Cooperation**: Contract-bound sessions with strict timeouts
3. **Competition**: Short-lived sessions with cryptographic verification
4. **War**: Immediate session termination capabilities

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                 SessionManager                       │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐          │
│  │ Session  │  │ Session  │  │ Session  │          │
│  │ (active) │  │(degraded)│  │ (closed) │          │
│  └──────────┘  └──────────┘  └──────────┘          │
└─────────────────────────────────────────────────────┘
```

## License

LSL-1.0 (Libertaria Sovereign License)
