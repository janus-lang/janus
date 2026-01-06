<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC — Oracle & Classical Dual Architecture

**Version:** 0.1.0 (2025-08-22)
**Scope:** CLI UX layer, AI orchestration, privacy enforcement,ty rules over ASTDB/Query
**Depends on:** SPEC-astdb-query, SPEC-query-engine, SPEC-profiles, development_coding_standards

## 0. Rationale

Janus must serve two personas with identical power:
- **Oracle**: conversational, AI-assisted, live introspection, constructive cynicism
- **Classical**: explicit, scriptable, byte-stable CLI outputs, automation-friendly

Both modes are **facades** over the same libjanus core (no second semantics). Outputs are deterministic and suitable for CI.

## 1. Operating Modes

### 1.1 Mode Resolution
Order of precedence (highest first):
1. `--mode={oracle|classical}` command line flag
2. `JANUS_MODE` environment variable
3. `janus.kdl` or `janus.json` configuration file `[ui.mode]`
4. Default: `classical` (for automation compatibility)

### 1.2 Parity Contract (OX-7)
For any command that has an Oracle analogue, **stdout/stderr and exit codes** of Classical MUST be byte-for-byte identical to the Oracle command run with `--oracle-output=classical`.

## 2. AI Provider Fabric

### 2.1 Provider Matrix
Supported drivers:
- **Local**: `ollama`, `lmstudio`, `gpt4all`, `localai`
- **Self-hosted**: `vllm`, `tgi`, `triton`, `http` (generic OpenAI-compatible)
- **Cloud**: `openai`, `anthropic`, `google`, `xai`

### 2.2 Cascade & Policy (OX-8)
A provider cascade is a priority-ordered list. On failure (network, quota, policy), the next provider is attempted **without changing the request semantics**.

### 2.3 Privacy Modes (OX-9)
- **`strict`**: **Never** send user code, ASTs, CIDs, or identifiers off box. Only high-level, anonymized summaries flow to AI. Hard-fail otherwise.
- **`balanced`**: Allow redacted spans and schema excerpts; never full sources. PII scrubbing on.
- **`local_only`**: Disables all non-local providers; cascade must resolve locally or fail.

Enforcement is at two layers:
1. **Request Builder** (client): validates policy before emit
2. **Daemon Gate** (server): rejects disallowed payloads with diagnostic `EOR-401 PrivacyPolicyDenied`

## 3. Commands & Oracle Equivalents

| Classical CLI | Oracle Equivalent | Output Contract |
|---|---|---|
| `janus query --expr "<Q>"` | `janus oracle query "<Q>"` | OX-7 |
| `janus diff --from A --to B` | `janus oracle diff A..B` | OX-7 |
| `janus build --check-no-work` | `janus oracle introspect build-invariance` | OX-7 |
| `janus stats --hover-latency` | `janus oracle introspect telemetry` | OX-7 |
| `janus snapshot save` | `janus oracle snapshot save` | OX-7 |

> `--suggest-oracle` may be added to any classical command to emit a one-line hint for the equivalent Oracle verb. Never alters output unless `--suggest-oracle` is present.

## 4. Configuration

### 4.1 KDL Configuration (Human-Readable)
```kdl
// janus.kdl
ui {
    mode "classical"  // or "oracle"
}

ai {
    privacy-mode "strict"  // strict | balanced | local_only

    // Single provider
    provider "ollama"
    model "codellama:13b-instruct"

    // OR cascade
    provider name="local" {
        type "ollama"
        model "qwen2.5-coder:14b"
        priority 1
    }

    provider name="cloud" {
        type "openai"
        model "gpt-4"
        priority 2
    }

    timeout-ms 15000
    max-output-tokens 1024
}
```

### 4.2 JSON Configuration (Machine-Readable)
```json
{
  "ui": {
    "mode": "classical"
  },
  "ai": {
    "privacy_mode": "strict",
    "providers": [
      {
        "name": "local",
        "type": "ollama",
        "model": "qwen2.5-coder:14b",
        "priority": 1
      },
      {
        "name": "cloud",
        "type": "openai",
        "model": "gpt-4",
        "priority": 2
      }
    ],
    "timeout_ms": 15000,
    "max_output_tokens": 1024
  }
}
```

### 4.3 Environment Overrides
- `JANUS_MODE`, `JANUS_AI_PRIVACY`, `JANUS_AI_PROVIDER`, `JANUS_AI_MODEL`

## 5. RPC / Daemon Surface (Versioned)

```protobuf
// Oracle RPC Interface
method Oracle.RunQuery {
  params: {
    expr: string,                    // ASTDB query string
    output_format: enum { json, table, classical },
    privacy_mode: enum { strict, balanced, local_only },
    provider_hint?: string,          // optional provider key
  }
  result: {
    rows: []Row,                     // when output_format=json
    classical_bytes?: bytes,         // OX-7 mirror of classical CLI
    diag: []Diagnostic,
    timings: { total_ms: u32, cache_hits: u32 }
  }
  errors: [EOR-401, EOR-429, EOR-500]
}
```

All Oracle APIs have a **shadow classical encoding** so OX-7 can be validated bit-for-bit.

## 6. Diagnostics

- **EOR-401 PrivacyPolicyDenied** — payload violates privacy mode
- **EOR-404 ProviderUnavailable** — no provider reachable
- **EOR-408 ProviderTimeout** — upstream exceeded deadline
- **EOR-429 RateLimited** — upstream rate-limited; cascade exhausted
- **EOR-500 ProviderError** — upstream internal error

Diagnostics include stable ID, primary span (when applicable), remediation.

## 7. Performance Targets

- Oracle round-trip latency (local provider, warmed): ≤ 80 ms for short prompts
- Hover latency end-to-end (ASTDB + Oracle presentation): ≤ 10 ms @ 100k LOC
- Oracle facade overhead: ≤ 2 ms additional latency over classical equivalent

## 8. Security & Redaction

- Redaction rules are declarative and testable: identifiers → stable pseudonyms, strings → `"<redacted:N>"`, code blocks → CID references only
- Proof: Golden tests enforce **zero literal source leak** under `strict`

## 9. EARS Acceptance Criteria

**[OX-7] Classical Compatibility**
- *WHEN* a classical command has an Oracle equivalent
- *THEN* `--oracle-output=classical` yields **byte-identical stdout/stderr and exit code**

**[OX-8] AI Provider Flexibility**
- *WHEN* the first provider fails due to timeout or policy
- *THEN* the cascade MUST attempt the next provider with the same redacted payload
- *AND* the final result (if any) MUST annotate `provider_used` deterministically

**[OX-9] Privacy Guarantee**
- *WHEN* `privacy_mode=strict`
- *THEN* no request may contain source bytes, AST nodes, symbol names, or CIDs that can be dereferenced to source
- *AND* violations produce `EOR-401` without contacting any external provider

**[OX-10] Parity on Diffs**
- *WHEN* running `janus diff` vs `janus oracle diff`
- *THEN* semantic JSON and textual summaries MUST match, modulo Oracle's optional preface (suppressed by `--oracle-output=classical`)

**[OX-11] Determinism**
- *WHEN* `--deterministic` is set
- *THEN* Oracle post-processing MUST be deterministic (no timestamps, seeds pinned)

## 10. CLI Surface (Authoritative)

### 10.1 Classical
```bash
janus query --expr "<Q>" [--json|--table] [--suggest-oracle]
janus diff --from CID_A --to CID_B [--json] [--suggest-oracle]
janus build --check-no-work [--suggest-oracle]
janus stats --hover-latency [--suggest-oracle]
```

### 10.2 Oracle
```bash
janus oracle query "<Q>" [--oracle-output=classical|json|table]
janus oracle diff CID_A..CID_B [--oracle-output=classical|json]
janus oracle introspect build-invariance [--oracle-output=classical]
janus oracle introspect telemetry [--oracle-output=classical]
```

Help text in classical mode is **flat and neutral**; Oracle help may include coaching and suggestions but never changes machine outputs.

## 11. The Oracle's Personality vs Classical Professionalism

### Oracle Mode (Conversational)
```bash
$ janus oracle query "func where child_count > 5"
🔍 Found 3 complex functions:

⚡ process_batch (src/batch.jan:128)
   💭 "This function juggles 12 operations. Consider breaking it down."

✅ Query executed (3.2ms, 94% cache hit)
💭 "Your predicate was precise. The codebase yields its secrets willingly."
```

### Classical Mode (Professional)
```bash
$ janus query --expr "func where child_count > 5"
{"kind":"func","name":"process_batch","cid":"blake3:...","child_count":12}
{"kind":"func","name":"handle_request","cid":"blake3:...","child_count":8}
{"kind":"func","name":"validate_input","cid":"blake3:...","child_count":6}
```

**Same data, different presentation. User's choice, Janus's power.**
