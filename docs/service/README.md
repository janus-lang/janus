# Janus :service Profile

**Status:** Production Ready (2026-02-09)

## Overview

`:service` profile provides concurrent service primitives:
- **CBC-MN Scheduler** — Nursery-based structured concurrency
- **HTTP Client/Server** — Tri-signature (:min/:go/:full)
- **NS-Msg** — Namespace pub/sub with pattern matching (`app.*`, `sensor.+.reading`)

## Usage

```janus
use service

func chat_server() !void do
    var nursery = Nursery.init()
    defer nursery.deinit()
    
    const sub = ns_msg.subscribe("chat.room.general.*")
    defer sub.deinit()
    
    for msg in sub do
        // Handle message
    end
end
```

## Examples

- [chat_server.zig](../examples/service/chat_server.zig) — HTTP + NS-Msg pub/sub demo

## Tests

```
zig test std/service.zig
zig test src/service/ns_msg/router.zig
16/16 tests passing
```

## SPEC Compliance

- SPEC-017 Law 2 (do..end imperative)
- Explicit allocators
- No hidden costs
- Zig 0.15.2