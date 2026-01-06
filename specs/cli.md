<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC-cli.md

**Title:** Janus Oracle: The Semantic Conduit
**Version:** 0.1.0 (Finalized August 2025:** `janus oracle` (unified CLI), `janusd` (daemon RPC bridge)
**Depends on:** `SPEC-astdb-query`, `SPEC-query-engine`, `SPEC-profiles`, `development_coding_standards`, `AI API` (optional)
**Error ranges:** `OXxxxx` (Oracle Execution), `ORxxxx` (RPC), `ONxxxx` (Natural Language)

## 0. Purpose: From Tool to Oracle

The conventional CLI is a dead instrument. Janus demands a living conduit. This specification transforms the command line from a primitive tool into the **Janus Oracle**—a revolutionary interrogator for your codebase. It is a fluid, conversational interface where precise predicates, natural language probes, and live subscriptions unlock the deep semantic truth stored in the ASTDB.

This is not a collection of subcommands; it is a unified portal for a direct dialogue with your code's soul, designed for a seamless symbiosis between the developer, AI agents, and the system itself.

## 1. Design Principles: Doctrine Amplified

- **Unified Portal:** A single, potent entry point: `janus oracle`. The mode of interrogation (`query`, `diff`, `converse`, etc.) is a subordinate context, not a fragmented command.
- **AI Symbiosis:** Natively integrates an optional `AI` bridge to translate natural language into precise predicates. An error is not a failure; it's a cynical teaching moment.
- **Live Vigilance:** The `subscribe` mode turns static queries into vigilant sentinels, watching the codebase and reporting semantic shifts in real-time.
- **Self-Reflection:** The `introspect` mode allows the Oracle to query its own performance and state, turning telemetry into a strategic debrief.
- **Paradoxical Ergonomics:** Outputs are dual-natured. For machines and AI: pristine, deterministic `JSONL`. For humans: insightful tables or a "poetic" mode laced with constructive cynicism.
- **Determinism as Law:** All operations honor `--deterministic`. Identical inputs yield bit-for-bit identical outputs, ensuring reproducibility for CI and AI.
- **No Second Semantics:** The Oracle is a thin, intelligent client over the `janusd` RPC. All logic, all truth, resides in `libjanus`.

## 2. Dual Command Architecture: Oracle + Classical

### 2.1 The Unified Oracle (Revolutionary)
`janus oracle [mode] [query-or-subject] [options]`

If the mode is omitted, the Oracle will infer it from the query's structure (e.g., text resembling a predicate activates `query` mode; prose activates `converse` mode).

### 2.2 Classical Commands (Traditional)

For users who prefer explicit, traditional CLI patterns, all Oracle functionality is also available through classical subcommands:

```bash
# Classical query command (equivalent to oracle query)
janus query "<predicate>" [--format jsonl|table] [--profile :core|:service|:cluster|:sovereign]

# Classical diff command (equivalent to oracle diff)
janus diff <old> <new> [--format json|table] [--semantic-only]

# Classical build validation (equivalent to oracle introspect build-invariance)
janus build --check-no-work [--deterministic] [--strict]

# Classical stats command (equivalent to oracle introspect telemetry)
janus stats [--format json|table] [--top N]

# Classical snapshot management (equivalent to oracle snapshot)
janus snapshot save|show|list [args...]
```

**Compatibility Promise:**
- All classical commands produce identical output to Oracle equivalents
- Same performance targets and deterministic guarantees
- Same RPC protocol and caching behavior
- Classical users never forced to use Oracle interface

**Migration Path:**
- Classical commands include hints about Oracle equivalents
- `--suggest-oracle` flag shows Oracle syntax for any classical command
- Gradual adoption supported - mix classical and Oracle as preferred

## 3. Modes of Interrogation

### 3.1 `query` — Predicate Precision

The direct conduit to the ASTDB Query Engine. This is your scalpel for surgical semantic analysis.

**Invocation:**
`janus oracle query "<predicate>" [--format jsonl|table|poetic] ...`

**Functionality:**
- Executes a formal predicate against the codebase.
- Supports extensions for temporal analysis (`since: "24h"`) and capability chains (`requires: CapFsRead and not CapNet`).
- **Poetic Format:** Augments results with wry commentary. *"Behold, these I/O sinners who touch the disk without a proper writ. Guard your capabilities, lest they corrupt the pure."*

**Example:**
```bash
# Find all complex functions or actors
janus oracle query "(func or actor) and child_count > 3"

# Find functions that write to the DB without an audit capability
janus oracle query "effects.has('db.write') without CapAuditLog"
```

### 3.2 `diff` — Semantic Archaeology

Performs a precise semantic diff between two states of the codebase, revealing meaningful changes, not just textual noise.

**Invocation:**
`janus oracle diff <old> <new> [--format json|table] ...`
(where `<old>` and `<new>` can be file paths, commit hashes, or snapshot CIDs)

**Functionality:**
- Reports changes in semantics: literal values, type signatures, effects, etc.
- Lists all downstream queries and artifacts that are invalidated by the change.

**Example Output (JSON):**
```json
{
  "changed": [
    {"item": "main", "kind": "LiteralChange", "detail": {"from": "41", "to": "42"}}
  ],
  "unchanged": ["add"],
  "invalidated_queries": ["Q.IROf(main)", "Q.Dispatch(call@main:1)"]
}
```

### 3.3 `converse` — Natural Language Bridge

Engages the optional AI bridge to translate human prose into formal, executable predicates. This is intuition made manifest.

**Invocation:**
`janus oracle converse "show me all functions that could corrupt the database without logging" [--AI-key <key>] [--dry-run]`

**Functionality:**
- Sends the natural language phrase to an AI endpoint, receiving a translated predicate and a confidence score.
- `--dry-run` shows the translated predicate without executing it.
- If confidence is low or the API is unavailable, the Oracle falls back to heuristic parsing and responds with cynical guidance: *"Your words twist like a Gordian knot. Perhaps try precision?"*

### 3.4 `subscribe` — The Vigilant Sentinel

Turns a query into a persistent, live watch that reports changes as they happen.

**Invocation:**
`janus oracle subscribe "<predicate>" [--notify stdout|webhook|x]`

**Functionality:**
- Registers a query with `janusd`, which monitors the underlying code for semantic changes that affect the query results.
- On a change, emits a notification event containing the semantic diff.
- Can be used for CI vigilance (`subscribe "no-work violations"`) or focused development (`subscribe "changes in my_file.jan"`).

### 3.5 `introspect` — The Oracle Knows Itself

Queries the state and performance of the Janus toolchain itself.

**Invocations:**
- `janus oracle introspect telemetry [--format json|table]` — Retrieves performance metrics (latency, cache hits, memory usage).
- `janus oracle introspect build-invariance` — Executes the "no-work rebuild" check, critical for CI.

**Example `build-invariance` Output (JSON):**
```json
{
  "run1": {"parse": 145, "sema": 132, "ir": 87, "codegen": 12},
  "run2": {"parse": 0, "sema": 0, "ir": 0, "codegen": 0, "q_hits": 428, "q_misses": 0}
}
```

## 4. Configuration Format Doctrine

**Janus follows the sacred configuration doctrine:**
- **KDL for humans**: Readable, writable, beautiful configuration files
- **JSON for computers**: Machine-parseable, API-friendly, CI/automation use

**Configuration Hierarchy (highest to lowest priority):**
1. Command line flags (`--ai-provider ollama`)
2. Environment variables (`JANUS_AI_PROVIDER=ollama`)
3. Project config (`./janus.kdl` or `./janus.json`)
4. User config (`~/.janus/oracle.kdl` or `~/.janus/oracle.json`)
5. System defaults

**File Discovery:**
- KDL files preferred for interactive use
- JSON files preferred for programmatic/CI use
- Both formats supported simultaneously

## 5. Global Options: Dials of Destiny

- `--profile :core|:service|:cluster|:sovereign`: Sets the language profile for the operation.
- `--deterministic`: Enforces bit-for-bit identical output for identical inputs.
- `--format jsonl|table|poetic`: Sets the output format. `jsonl` is the default for non-interactive sessions.
- `--ai-provider <name>`: Override configured AI provider for this session.
- `--privacy-mode strict|balanced|local-only`: Override privacy mode for this session.
- `--notify <method>`: Sets the notification channel for `subscribe` mode (`stdout`, `webhook:<url>`, `x` for X/Twitter posts).
- `--color auto|infernal`: `infernal` uses a dark theme with cynical flair.

## 5. EARS Acceptance Criteria: Forged in Fire

- **[OX-1] Predicate Fidelity:** **WHEN** `oracle query` runs identical predicates twice in deterministic mode, **THEN** outputs **SHALL** match byte-for-byte, **SO THAT** AI agents can chain operations reliably.
- **[OX-2] Natural Insight:** **WHEN** `oracle converse` receives "find risky I/O funcs", **THEN** it **SHALL** yield the equivalent predicate with >0.8 confidence, **SO THAT** human intuition becomes a valid query language.
- **[OX-3] Vigilant Diff:** **WHEN** `oracle subscribe` detects a semantic change, **THEN** it **SHALL** notify with a precise semantic diff, **SO THAT** development becomes proactive, not reactive.
- **[OX-4] Invariance Gate:** **WHEN** `oracle introspect build-invariance` runs on identical inputs, **THEN** run2 counters for parse/sema/ir/codegen **SHALL** be zero, **SO THAT** CI can enforce incremental guarantees.
- **[OX-5] Cynical Grace:** **WHEN** an ambiguous query fails, **THEN** the Oracle **SHALL** respond with actionable refinement suggestions, **SO THAT** every error is an opportunity for mastery.
- **[OX-6] Performance Conduit:** **WHEN** handling queries on a 100k LOC project, **THEN** p95 latency **SHALL** be ≤ 10ms, **SO THAT** the dialogue with the codebase flows unhindered.
- **[OX-7] Classical Compatibility:** **WHEN** `janus query` and `janus oracle query` run identical predicates, **THEN** outputs **SHALL** be byte-for-byte identical, **SO THAT** traditional users have full feature parity.
- **[OX-8] AI Provider Flexibility:** **WHEN** multiple AI providers are configured, **THEN** the system **SHALL** cascade through them on failure, **SO THAT** translation remains available despite individual provider outages.
- **[OX-9] Privacy Guarantee:** **WHEN** `--privacy-mode strict` is enabled, **THEN** no actual code content **SHALL** be sent to external AI providers, **SO THAT** sensitive codebases remain secure.

## 6. Exit Codes: Ominous Omens

- `0`: Enlightenment achieved.
- `2`: `OX0101` — Query ambiguity or parse failure (suggestion provided).
- `3`: `OR0201` — RPC rupture; the daemon is absent or unresponsive.
- `4`: `ON0301` — Natural language translation failed (confidence too low).
- `5`: `OX0401` — `introspect build-invariance` check failed.

## 7. Output Formats: The Three Faces of Truth

### 7.1 `jsonl` — Machine Precision
The default format for non-interactive sessions. Each result is a single JSON object per line, enabling streaming and pipeline composition.

```jsonl
{"kind":"func","name":"transfer","cid":"blake3:a1b2c3...","span":{"file":"src/bank.jan","line":42,"col":5,"len":18},"effects":["db.write","audit.log"],"caps":["CapTransfer","CapAuditLog"]}
{"kind":"func","name":"validate","cid":"blake3:d4e5f6...","span":{"file":"src/bank.jan","line":15,"col":1,"len":12},"effects":["pure"],"caps":[]}
```

### 7.2 `table` — Human Clarity
Structured tabular output with intelligent column sizing and semantic highlighting.

```
┌──────────┬─────────────┬──────────────────┬─────────────────────────┐
│ Kind     │ Name        │ Effects          │ Capabilities            │
├──────────┼─────────────┼──────────────────┼─────────────────────────┤
│ func     │ transfer    │ db.write,        │ CapTransfer,            │
│          │             │ audit.log        │ CapAuditLog             │
│ func     │ validate    │ pure             │ none                    │
└──────────┴─────────────┴──────────────────┴─────────────────────────┘
```

### 7.3 `poetic` — Cynical Wisdom
Augments results with constructive cynicism and architectural insights.

```
🔍 Query Results: "(func or actor) and child_count > 3"

⚡ transfer (src/bank.jan:42)
   Effects: db.write, audit.log
   Capabilities: CapTransfer, CapAuditLog
   💭 "A complex beast with 7 children. At least it guards its capabilities properly."

⚠️  process_batch (src/batch.jan:128)
   Effects: db.write, io.fs.read
   Capabilities: CapBatchProcess
   💭 "This function juggles 12 operations. Consider breaking it down before it breaks you."

📊 Summary: 2 functions found, 1 architectural concern detected.
```

## 8. The AI Bridge: Natural Language to Predicate Translation

### 8.1 AI Provider Architecture

The Oracle supports multiple AI providers through a pluggable architecture:

**Supported Providers:**
- **Local Models**: Ollama, LM Studio, GPT4All, LocalAI
- **Cloud APIs**: OpenAI, Anthropic (Claude), Google (Gemini), xAI (Grok)
- **Self-Hosted**: vLLM, TGI (Text Generation Inference), Triton
- **Custom**: User-defined HTTP endpoints with OpenAI-compatible API

**Configuration Methods:**
```bash
# Environment variables (most secure)
export JANUS_AI_PROVIDER=ollama
export JANUS_AI_MODEL=codellama:13b
export JANUS_AI_ENDPOINT=http://localhost:11434

# Config file (~/.janus/oracle.kdl) - KDL for humans
ai {
    provider "anthropic"
    model "claude-3-sonnet"
    api-key-file "~/.config/janus/anthropic.key"
    max-tokens 1000
    temperature 0.1
    privacy-mode "strict"
}

# JSON for programmatic/CI use (~/.janus/oracle.json)
{
  "ai": {
    "provider": "anthropic",
    "model": "claude-4-sonnet",
    "api_key_file": "~/.config/janus/anthropic.key",
    "privacy_mode": "strict"
  }
}

# Command line (for testing)
janus oracle converse "find risky functions" --ai-provider ollama --ai-model codellama:13b
```

**Privacy-First Design:**
- **Code Never Sent**: Only query intent and context sent to AI, never actual code
- **Local-First**: Ollama and local models preferred for sensitive codebases
- **Configurable Privacy**: `--privacy-mode strict` disables all external AI calls

### 8.2 Translation Pipeline
1. **Natural Language Input**: "show me all functions that could corrupt the database without logging"
2. **Provider Selection**: Choose AI provider based on configuration and availability
3. **Context Preparation**: Send query intent with codebase schema (no actual code)
4. **AI Translation**: Converts to formal predicate with confidence score
5. **Validation**: Checks predicate syntax and semantic validity
6. **Execution**: Runs the translated query against ASTDB
7. **Explanation**: Shows both the translation and results

### 8.2 Example Translation Session
```bash
$ janus oracle converse "find risky database functions"

🤖 Translation (confidence: 0.92):
   "func where effects.contains('db.write') and not effects.contains('audit.log')"

🔍 Executing query...

⚠️  Found 3 potentially risky functions:
   - update_balance (no audit trail)
   - delete_user (no audit trail)
   - bulk_transfer (no audit trail)

💭 "These functions wield database power without accountability.
    Consider adding audit.log effects or CapAuditLog requirements."
```

### 8.3 AI Provider Configuration Examples

**Ollama (Local, Recommended for Privacy):**
```kdl
// ~/.janus/oracle.kdl - KDL for human configuration
ai {
    provider "ollama"
    endpoint "http://localhost:11434"
    model "codellama:13b-instruct"
    timeout 30
    privacy-mode "strict"  // Never send code content
}
```

**OpenAI (Cloud):**
```kdl
ai {
    provider "openai"
    model "gpt-4"
    api-key-file "~/.config/janus/openai.key"
    max-tokens 1000
    temperature 0.1
}
```

**Anthropic Claude (Cloud):**
```kdl
ai {
    provider "anthropic"
    model "claude-4-sonnet-20240229"
    api-key-file "~/.config/janus/anthropic.key"
    max-tokens 1000
}
```

**Custom Self-Hosted:**
```kdl
ai {
    provider "custom"
    endpoint "https://my-llm-server.company.com/v1/chat/completions"
    model "company-code-model-v2"
    headers {
        Authorization "Bearer ${COMPANY_AI_TOKEN}"
    }
}
```

**Multiple Providers with Fallback:**
```kdl
ai {
    privacy-mode "strict"
    fallback-strategy "cascade"  // Try local first, then cloud

    provider name="local" {
        type "ollama"
        model "codellama:13b"
        priority 1
    }

    provider name="cloud" {
        type "openai"
        model "gpt-5"
        priority 2
    }

    provider name="anthropic" {
        type "claude"
        model "claude-4-sonnet"
        priority 3
    }
}
```

**JSON for Programmatic/CI Use:**
```json
{
  "ai": {
    "privacy_mode": "strict",
    "fallback_strategy": "cascade",
    "providers": [
      {
        "name": "local",
        "type": "ollama",
        "model": "codellama:13b",
        "priority": 1,
        "endpoint": "http://localhost:11434"
      },
      {
        "name": "cloud",
        "type": "openai",
        "model": "gpt-5",
        "priority": 2,
        "api_key_file": "~/.config/janus/openai.key"
      }
    ]
  }
}
```

### 8.4 Privacy and Security Modes

**Strict Privacy Mode:**
```bash
janus oracle converse "find database functions" --privacy-mode strict
# Only sends: "find database functions" + codebase schema (function names, no code)
# Never sends: actual function bodies, variable names, literals
```

**Balanced Mode (Default):**
```bash
janus oracle converse "show risky I/O" --privacy-mode balanced
# Sends: query intent + anonymized function signatures + effect/capability info
# Never sends: function implementations, business logic, sensitive data
```

**Local-Only Mode:**
```bash
janus oracle converse "analyze complexity" --ai-provider ollama --local-only
# Forces use of local AI models only, fails if none available
# Guarantees no data leaves local machine
```

### 8.5 Fallback Strategies
When AI translation fails or confidence is low:
- **Heuristic parsing**: Attempts keyword-based predicate construction
- **Suggestion engine**: Offers similar successful queries from history
- **Provider cascade**: Falls back to next configured AI provider
- **Cynical guidance**: Provides constructive criticism with improvement hints

## 9. Live Subscription: The Vigilant Sentinel

### 9.1 Subscription Lifecycle
```bash
# Start watching for changes to critical functions
$ janus oracle subscribe "func where name.matches('transfer|payment|withdraw')" --notify stdout

🔔 Subscription active: watching 12 functions
📡 Monitoring semantic changes in real-time...

# When changes occur:
🚨 CHANGE DETECTED (2025-08-22 14:32:15Z)
   Function: transfer
   Change: LiteralChange {"from": "1000", "to": "10000"}
   Impact: 3 dependent functions invalidated
   CID: blake3:old123... → blake3:new456...
```

### 9.2 Notification Channels
- **stdout**: Direct terminal output for development
- **webhook**: HTTP POST to specified URL with JSON payload
    - **MCP**: Janus Control Plane for automated actions and other Agents
    - **slack**, **discord**, **telegram**, **X/Twitter**, etc for wider accountability
- **file**: Append to specified log file

## 10. Performance Telemetry: The Oracle Knows Itself

### 10.1 Telemetry Categories
```bash
$ janus oracle introspect telemetry

📊 Janus Oracle Performance Report
┌─────────────────────┬──────────┬──────────┬──────────┐
│ Metric              │ Current  │ P95      │ Target   │
├─────────────────────┼──────────┼──────────┼──────────┤
│ Query Latency       │ 3.2ms    │ 8.7ms    │ ≤10ms    │
│ Cache Hit Rate      │ 94.3%    │ -        │ ≥90%     │
│ Memory Peak         │ 128MB    │ 256MB    │ ≤512MB   │
│ CID Computation     │ 45µs     │ 89µs     │ ≤100µs   │
└─────────────────────┴──────────┴──────────┴──────────┘

🎯 All performance targets met
💾 Hot queries: Q.TypeOf (34%), Q.IROf (28%), Q.Dispatch (19%)
```

## 11. Security & Capability Hygiene

### 11.1 Capability Reporting
All capability and effect information reflects compiler truth, never CLI assumptions:

```bash
$ janus oracle query "func where requires_capability('CapDatabaseWrite')"

🔒 Security Analysis:
   - 5 functions require CapDatabaseWrite
   - 3 functions properly audit their operations
   - 2 functions lack audit trails ⚠️

💭 "Power without accountability is tyranny. Guard your capabilities wisely."
```

### 11.2 Path Sanitization
- All file paths are canonicalized and project-relative
- Absolute paths never leak into CIDs or outputs
- Deterministic mode ensures path ordering is stable

## 12. Integration Points

### 12.1 CI/CD Integration
```yaml
# .github/workflows/janus-oracle.yml
- name: Validate No-Work Rebuild
  run: janus oracle introspect build-invariance --deterministic

- name: Check for Risky Functions
  run: |
    janus oracle query "func where effects.contains('db.write') and not requires_capability('CapAuditLog')" \
      --format json | jq '.[] | select(.name)' && exit 1 || echo "All database functions properly secured"
```

### 12.2 IDE Integration
The Oracle's JSONL output integrates seamlessly with LSP for:
- **Hover information**: Query results on demand
- **Code actions**: Suggest capability additions based on effects
- **Diagnostics**: Real-time security and architectural warnings

### 12.3 AI Agent Integration
```python
# AI agent using Oracle for code analysis
import subprocess
import json

def analyze_security_risks(codebase_path):
    result = subprocess.run([
        'janus', 'oracle', 'query',
        'func where effects.contains("db.write") and not requires_capability("CapAuditLog")',
        '--format', 'jsonl', '--deterministic'
    ], capture_output=True, text=True)

    risks = [json.loads(line) for line in result.stdout.strip().split('\n') if line]
    return analyze_risk_patterns(risks)
```

## 13. The Oracle's Personality: Constructive Cynicism

The Oracle embodies the Janus philosophy through its responses:

### 13.1 Success with Wisdom
```
✅ Query executed successfully (3.2ms, 94% cache hit)
💭 "Your predicate was precise. The codebase yields its secrets willingly to those who ask the right questions."
```

### 13.2 Failure with Guidance
```
❌ Query failed: ambiguous predicate "functions that are bad"
💭 "Vague queries yield vague results. Try: 'func where child_count > 10 or effects.contains(\"io.fs.write\")'"
🎯 Similar successful queries:
   - "func where complexity > threshold"
   - "func where effects.risky()"
```

### 13.3 Performance Warnings
```
⚠️  Query completed but took 15.3ms (target: ≤10ms)
💭 "Your query was ambitious but costly. Consider adding constraints or indexing hints."
```

## 14. Classical Command Reference

For users who prefer traditional CLI patterns, all functionality is available through explicit subcommands:

### 14.1 Query Commands
```bash
# Basic queries
janus query "func"
janus query "(func or var) and child_count > 3" --format table

# Security analysis
janus query "func where effects.contains('db.write') and not requires_capability('CapAuditLog')"

# Performance analysis
janus query "func where compile_time > 100ms" --format json
```

### 14.2 Diff Commands
```bash
# File comparison
janus diff src/old.jan src/new.jan --format json

# Git commit comparison
janus diff HEAD~1 HEAD --semantic-only

# Snapshot comparison
janus diff snapshot:abc123 snapshot:def456 --format table
```

### 14.3 Build Commands
```bash
# No-work rebuild validation (critical for CI)
janus build --check-no-work --deterministic

# Build with performance monitoring
janus build --profile --report-slow-functions
```

### 14.4 Stats Commands
```bash
# Performance telemetry
janus stats --format table --top 10

# Cache analysis
janus stats --cache-only --format json

# Historical performance
janus stats --since "24h" --trend-analysis
```

### 14.5 Snapshot Commands
```bash
# Save current state
janus snapshot save --name "before-refactor"

# List snapshots
janus snapshot list --limit 10 --format table

# Show snapshot details
janus snapshot show blake3:abc123... --format json
```

### 14.6 Migration Hints
Classical commands can suggest Oracle equivalents:

```bash
$ janus query "func" --suggest-oracle
✅ Query executed successfully

💡 Oracle equivalent: janus oracle query "func"
💡 With natural language: janus oracle converse "show me all functions"
💡 With live monitoring: janus oracle subscribe "func" --notify stdout
```

This dual architecture ensures that both revolutionary Oracle users and traditional CLI users have full access to Janus's semantic power, without forcing anyone to change their preferred interaction style.

---

This Oracle is not just a tool—it's a philosophical extension of the Janus language itself, embodying its principles of honesty, precision, and constructive guidance. It transforms the command line from a primitive interface into a living dialogue with the semantic heart of your codebase, while respecting the preferences of users who value traditional, explicit command structures.
