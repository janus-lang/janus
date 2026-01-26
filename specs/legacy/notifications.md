<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-notifications.md

**Title:** Notifications & Control Plane (MCP)
**Version:** 0.1.0 (Aug25)
**Scope:** janus CLI, janusd, Oracle, CI/IDE integrations
**Depends on:** SPEC-cli, SPEC-query-engine, SPEC-id-epochs, privacy policy (Oracle)
**Error ranges:** NX**** (notify), WB**** (webhook), MC**** (MCP), IM**** (integrations)

## 0. Purpose

Emit **deterministic, structured events** from Janus (builds, queries, diffs, audits) to multiple channels (stdout, file, webhook, Slack/Discord/Telegram/X, MCP). Provide a **Control Plane (MCP)** for automated actions and agent orchestration. Honor privacy modes (`strict|balanced|local_only`) and deliver **at-least-once** with idempotency.

## 1. Event Model

### 1.1 Event envelope (canonical JSON; LF endings; stable key order)

```json
{
  "id": "evt_01H...",              // blake3 of (type,timestamp,payload_cid)
  "type": "build.no_work_ok",      // dot-namespaced
  "timestamp": "2025-08-23T12:34:56Z",
  "source": "janusd@host/tenant/project",
  "profile": ":sovereign",
  "deterministic": true,
  "privacy_mode": "strict",
  "payload_cid": "blake3:abcd...", // CAS of redacted payload
  "payload": { /* redacted or full, per mode */ },
  "related": [{ "cid": "blake3:...", "kind": "snapshot" }],
  "idempotency_key": "IK-01F...",  // stable across retries
  "sig": { "alg": "HMAC-SHA256", "kid": "key1", "mac": "base64..." }
}
```

### 1.2 Core event types (v1)

- `build.no_work_ok`, `build.changed`, `perf.regression`, `query.result`, `diff.semantic`,
- `using.leak_suspected`, `security.capability_violation`, `effects.conflict`, `oracle.privacy_denied`
- `mcp.audit.success`, `mcp.audit.failure`, `mcp.action.request`, `mcp.action.complete`

### 1.3 Determinism

- In `--deterministic`, same inputs → identical envelope (except `timestamp`, which may be suppressed with `--no-timestamps` for byte equality). CLI has `--oracle-output=classical` to mirror classical bytes.

## 2. Channels

- **stdout**: line-delimited JSON (JSONL).
- **file**: append JSONL to path (atomic line writes).
- **webhook**: HTTP POST; JSON body = envelope; success = 2xx.
- **slack/discord/telegram/x**: adaptors built on webhook transport (formatting shim only).
- **MCP**: in-process control plane bus for **publish/subscribe** and **actions** (see §4).

### 2.1 Delivery guarantees

- At-least-once with **idempotency_key**.
- Per-channel **retry policy**: exponential backoff with jitter (min 250ms, max 2m; 8 attempts).
- Ordering: **per aggregate** (`aggregate_id`= project/snapshot) ordering preserved; global ordering not guaranteed.
- Dead-letter queue (DLQ) per channel (CAS-backed) after max retries.

### 2.2 Security

- Webhooks: HMAC signing (`X-Janus-Signature`), optional mTLS; allow/deny lists.
- Redaction: privacy modes apply before emit:
  - `strict`: no source bytes, no symbol names, no dereferenceable CIDs; only summary counts and types.
  - `balanced`: spans redacted; stable pseudonyms for symbols.
  - `local_only`: disables external channels, MCP and stdout/file allowed.

## 3. Configuration

### 3.1 `janus.kdl` (KDL configuration)

```kdl
notify {
    enabled true
    privacy-mode "strict"  // strict|balanced|local_only
    default-channels "stdout" "file"

    file {
        path ".janus/events.jsonl"
    }

    webhook {
        url "https://hooks.example.com/janus"
        hmac-key-id "key1"
        hmac-secret-env "JANUS_WEBHOOK_HMAC"
        timeout-ms 4000
        retries 8
    }

    slack {
        webhook-url-env "JANUS_SLACK_WEBHOOK"
    }

    mcp {
        enabled true
        bus "inproc"  // inproc|ipc|tcp (future)
    }
}
```

### 3.2 CLI

```bash
janus notify test --channel stdout|file|webhook|mcp
janus query --expr "func" --notify --channels stdout,webhook
janus diff A..B --semantic --notify --channels mcp
janus build --check-no-work --notify --channels slack --redact=strict
```

## 4. MCP (Janus Control Plane) - The Fortress Architecture

### 4.1 Security Doctrine: No Roles, Only Capabilities

The MCP operates under **Zero Trust** principles with cryptographically enforced capabilities. There are no "roles" - only precise, granular permissions issued as short-lived, signed tokens.

**Capability Examples:**
- `mcp.topic.subscribe:diff.semantic`
- `mcp.topic.publish:security.capability_violation`
- `mcp.action.invoke:refactor.apply`
- `mcp.action.read:rebuild.status`

### 4.2 Policy as Auditable Code

All permissions are defined in version-controlled `janus.policy.kdl`:

```kdl
// janus.policy.kdl - Single source of truth for MCP security

principal id="ci:pipeline" type="oidc" {
    issuer "https://gitlab.com"
    subject "project_path:your/project:ref_type:branch:ref:main"
    capabilities {
        "mcp.topic.subscribe:*"
        "mcp.action.invoke:rebuild"
        "mcp.action.invoke:test.run"
    }
}

principal id="agent:formatter" type="token" {
    capabilities {
        "mcp.action.invoke:format.file"
        "mcp.action.invoke:format.dry_run"
    }
}

principal id="user:markus" type="oidc" {
    issuer "https://accounts.google.com"
    subject "markus.maiwald@example.com"
    capabilities {
        "mcp.action.invoke:*"  // God mode, audited
    }
}
```

### 4.3 Simple Action API (Easy Win)

**Basic Flow:**
1. **Request:** Agent calls MCP action via simple JSON-RPC
2. **Validate:** Check basic API key against allowed actions list
3. **Execute:** Run action and return result
4. **Log:** Simple structured log entry

**JSON-RPC API:**
```json
{
  "jsonrpc": "2.0",
  "method": "mcp.action",
  "params": {
    "action": "format.file",
    "args": { "file_cid": "blake3:...", "dry_run": false },
    "api_key": "simple-key"
  },
  "id": 1
}
```

### 4.4 Simple Security (Ship It)

**API Key Validation:**
- Static API keys in `janus.kdl` config
- Each key has allowed actions list
- No JWT complexity, no expiry - just basic auth

**Example Config:**
```kdl
mcp {
    api-keys {
        "formatter-key" {
            actions "format.file" "format.check"
        }
        "ci-key" {
            actions "build" "test.run"
        }
    }
}
```

### 4.5 Basic Audit Log

Simple structured logging to file:
```json
{
  "timestamp": "2025-08-23T12:34:56Z",
  "action": "format.file",
  "api_key": "formatter-key",
  "success": true,
  "duration_ms": 150
}
```

## 5. Slack/Discord/Telegram/X Adaptors

- Wrap `webhook` transport; enforce redaction.
- Render a **compact summary** + link to CAS artifact (local viewer) instead of raw code.
- Rate-limit to 1 msg/sec per topic; batch multiple events into a summary every 5s window.

## 6. Errors

- **NX1001** InvalidChannel
- **NX1010** PrivacyViolation (blocked by policy)
- **WB2001** WebhookTimeout
- **WB2002** WebhookNon2xx (with response snippet)
- **MC3001** BusUnavailable
- **MC3002** InvalidToken
- **MC3003** InsufficientCapabilities
- **MC3004** ActionDenied (policy)
- **IM4001** IntegrationRateLimited

## 7. EARS Acceptance Criteria

**[N-1] Deterministic stdout**
*When* the same build runs twice with `--deterministic` and `--no-timestamps`, *then* stdout events are byte-identical **so that** CI diffs remain stable.

**[N-2] Webhook delivery**
*When* a 500 is returned by the webhook endpoint, *then* the notifier retries with backoff and includes the **same idempotency_key**, *and* delivery stops after max attempts with event in DLQ.

**[N-3] Privacy enforcement**
*When* privacy mode is `strict`, *then* no source bytes, symbol names, or dereferenceable CIDs appear in emitted payloads, and attempts produce **NX1010**.

**[N-4] MCP publish/subscribe**
*When* an agent subscribes to `diff.*` and a semantic diff occurs, *then* it receives exactly one event per diff with ordering preserved per snapshot.

**[N-5] Slack adapter parity**
*When* sending to Slack and webhook directly for the same event, *then* the message text contains the same summary facts, and links target the same CAS artifact.

**[N-6] Throughput**
*When* emitting 10k events/minute to file/stdout, *then* P99 enqueue latency ≤ 10ms and no events dropped (backpressure engages).

**[N-7] MCP API Key Auth**
*When* an agent with "formatter-key" attempts to trigger a rebuild, *then* the request is denied with **MC3003** and logged.

**[N-8] Basic Audit Log**
*When* any MCP action completes, *then* a structured log entry is written with action, key, success, and duration.
