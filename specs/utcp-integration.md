<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — UTCP Integration (Preferred over legacy MCP)

Status: Draft (scope locked for initial implementation)
Owners: janusd, CLI/Client (`janus.utcp`), Security
Depends on: Runtime Implementation (`src/runtime/`), Build System (`build.zig`), Project Structure

Purpose
- Establish UTCP as the primary control protocol for Janus (daemon-first), deprecating MCP as the default path.
- Make capability security a first‑class, machine‑readable contract across manuals, clients, and janusd.

Implementation References
- **[Runtime Architecture](../src/runtime/)** - Daemon and capability system implementation
- **[Build System](../build.zig)** - Module definitions and compilation pipeline
- **[Project Structure](../src/)** - Repository layout and module organization

Scope
- Define the UTCP manual extension for sovereign capability declaration.
- Specify server-side validation in `janusd` and client expectations for `janus.utcp`.
- Provide error semantics and migration scaffolding from MCP.

Non-Goals
- Re-specifying existing MCP behavior (kept for compatibility only).
- Transport selection beyond a minimal UTCP framing draft (HTTP/WebSocket/TCP variants out of scope here).

—

Requirement 14 — Sovereign Capability Declaration

User Story: As an AI agent, I want the UTCP manual to explicitly declare the precise Janus capabilities required for each tool, so that I can request them and understand the security implications of my actions before I make a call.

Acceptance Criteria
1. WHEN a tool is defined in the manual THEN its object schema SHALL be extended with a custom `x-janus-capabilities` block.
2. WHEN capabilities are defined THEN this block SHALL contain `required` and `optional` lists of Janus capability tokens (e.g., `fs.read:/etc/app`, `net.http:POST:https://api.example.com`).
3. WHEN a tool is called THEN `janusd` SHALL validate that the capabilities presented by the client match those declared in the manual for that tool. A mismatch SHALL result in a specific, diagnosable authorization error.
4. WHEN the `janus.utcp` client consumes a manual THEN it SHALL be able to parse this block and attach the necessary capability tokens to its outgoing requests.

—

Manual Schema Extension (UTCP)
- Each tool definition gains `x-janus-capabilities`:

```
{
  "name": "build",
  "summary": "Builds the workspace",
  "params": { "profile": "string" },
  "x-janus-capabilities": {
    "required": [
      "fs.read:${WORKSPACE}",
      "fs.write:${WORKSPACE}/zig-out"
    ],
    "optional": [
      "net.http:POST:https://hooks.example.com/deploy"
    ]
  }
}
```

Notes
- Tokens are opaque strings to UTCP but meaningful to Janus security. They MAY include method/path scoping and variable expansion negotiated per session.
- Clients MUST echo tokens they intend to use per call; servers MUST audit accepted tokens.

Server Validation (janusd)
- Load/produce manual with `x-janus-capabilities` for all public tools.
- On call:
  - Resolve the tool entry; collect `required` and `optional` tokens.
  - Compare against the caller-presented capability tokens.
  - If any `required` token missing or mismatched, return `E1403_CAP_MISMATCH` with a deterministic explanation containing: tool, missing tokens, and presented set size.
  - On success, bind the accepted capability set to the request context and proceed to execution.

Client Behavior (janus.utcp)
- Parse manuals and surface capability prompts to the operator or agent runtime.
- Attach selected tokens to each request.
- On `E1403_CAP_MISMATCH`, auto-remediate by re‑requesting missing tokens if policy allows; otherwise surface the error.

Error Model
- Code: `E1403_CAP_MISMATCH`
- Class: Authorization
- Shape:
  - `code`: string (fixed)
  - `message`: string (human diagnostic)
  - `tool`: string
  - `missing`: string[]
  - `presented_count`: number

Minimal UTCP Frame (for bootstrap testing)
- Transport: line‑delimited JSON over TCP.
- Request:
  - `op`: `manual` | `call`
  - `tool`: string (for `call`)
  - `args`: object (arbitrary)
  - `caps`: string[] (capability tokens)
- Response:
  - `ok`: boolean
  - `result` | `error`: object

Backward Compatibility (MCP)
- MCP remains loadable under a compatibility shim. UTCP is preferred for new clients.
- Audit logs MUST annotate the transport: `x-janus-transport=utcp|mcp`.

Phased Tasks
1) Spec & scaffolding
    - Add this SPEC and example manual snippet; align with Janus doctrines and implementation patterns.
2) janusd UTCP bootstrap
   - Add `janusd` binary with TCP listener and line‑JSON framing; implement `manual` and `call` stubs.
   - Implement capability validation pipeline with `E1403_CAP_MISMATCH`.
3) Client library
   - `janus.utcp` module: manual parsing, token prompting, request composition.
4) Audit and policy
   - Record accepted tokens and outcomes; wire policy read from `janus.policy.kdl` without changing its format in this phase.
5) Migration plan
   - Document MCP → UTCP migration checklist; keep MCP endpoints functional until deprecation window closes.

Security Considerations
- Capability tokens are contractual; the server is the source of truth. Clients MUST NOT infer laxity from optional tokens.
- Tokens SHOULD be short‑lived per session; persistence strategies are out of scope for this SPEC.

Open Questions
- Negotiation of token variable expansion (e.g., `${WORKSPACE}`) and per‑session binding keys.
- Transport multiplexing (HTTP/WS) for broader interoperability.

Implementation Notes
- Follow logging and error routing practices consistent with std.log usage elsewhere.
- Avoid absolute paths; resolve relative to workspace utilities per Steering.

End of SPEC — UTCP Integration
