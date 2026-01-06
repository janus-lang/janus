<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Oracle vs Classical: Two Paths to the Same Truth

Janus provides two complementary interfaces to its revolutionary ASTDB system:
- **Oracle**: Unified, conversational, AI-enhanced
- **Classical**: Traditional, explicit, familiar

Both provide identical functionality and performance - choose based on your preference and workflow.

## 🎯 Query Operations

### Oracle Approach (Unified & Conversational)
```bash
# Natural language query
janus oracle converse "show me all functions that write to the database"

# Formal predicate query
janus oracle query "func where effects.contains('db.write')"

# Complex query with poetic output
janus oracle query "(func or var) and child_count > 3" --format poetic
```

### Classical Approach (Traditional & Explicit)
```bash
# Direct query command
janus query "func where effects.contains('db.write')"

# Complex query with table output
janus query "(func or var) and child_count > 3" --format table

# With migration hint
janus query "func" --suggest-oracle
```

## 🔍 Semantic Diff Analysis

### Oracle Approach
```bash
# Unified diff with semantic focus
janus oracle diff HEAD~1 HEAD

# Live monitoring of changes
janus oracle subscribe "func where name.matches('transfer|payment')" --notify stdout
```

### Classical Approach
```bash
# Traditional diff command
janus diff HEAD~1 HEAD --format json

# Semantic-only changes
janus diff src/old.jan src/new.jan --semantic-only
```

## 🏗️ Build Validation

### Oracle Approach
```bash
# Self-reflection on build performance
janus oracle introspect build-invariance

# Performance telemetry
janus oracle introspect telemetry --format table
```

### Classical Approach
```bash
# Traditional build validation
janus build --check-no-work --deterministic

# Performance statistics
janus stats --format table --top 10
```

## 🤖 AI Integration Examples

### Oracle with Local AI (Privacy-First)
```bash
# Configure Ollama for local AI
export JANUS_AI_PROVIDER=ollama
export JANUS_AI_MODEL=codellama:13b-instruct

# Natural language queries with local AI
janus oracle converse "find functions that might have security issues"
```

### Oracle with Cloud AI (Feature-Rich)
```bash
# Configure multiple providers with fallback
cat ~/.janus/oracle.toml
[ai]
providers = [
  { name = "local", provider = "ollama", model = "codellama:13b", priority = 1 },
  { name = "openai", provider = "openai", model = "gpt-4", priority = 2 },
  { name = "claude", provider = "anthropic", model = "claude-3-sonnet", priority = 3 },
]

# AI-enhanced analysis with fallback
janus oracle converse "analyze the complexity of my codebase"
```

### Classical with AI Hints
```bash
# Traditional command with AI suggestions
janus query "func where child_count > 5" --ai-suggest
# Output includes: "💡 Natural language: 'show me complex functions'"
```

## 🔒 Privacy Modes Comparison

### Oracle Privacy Modes
```bash
# Strict privacy (no code sent to AI)
janus oracle converse "find database functions" --privacy-mode strict

# Local-only AI
janus oracle converse "analyze performance" --local-only

# Balanced mode (anonymized data only)
janus oracle converse "show risky patterns" --privacy-mode balanced
```

### Classical Privacy
```bash
# Classical commands never send data to AI by default
janus query "func where effects.contains('db.write')"  # Always private

# Explicit AI integration when desired
janus query "func" --ai-enhance --privacy-mode strict
```

## 📊 Output Format Comparison

### Oracle Formats
```bash
# Machine-readable JSONL (default)
janus oracle query "func" --format jsonl

# Human-readable table
janus oracle query "func" --format table

# Philosophical poetic mode
janus oracle query "func where child_count > 5" --format poetic
```

### Classical Formats
```bash
# JSON output (traditional)
janus query "func" --format json

# Table output (traditional)
janus query "func" --format table

# CSV for spreadsheet integration
janus query "func" --format csv
```

## 🚀 CI/CD Integration Examples

### Oracle in CI
```yaml
# .github/workflows/oracle-ci.yml
- name: Validate Build Invariants
  run: janus oracle introspect build-invariance --deterministic

- name: Security Analysis
  run: |
    janus oracle query effects.contains('db.write') and not requires_capability('CapAuditLog')" \
      --format json > security_report.json
```

### Classical in CI
```yaml
# .github/workflows/classical-ci.yml
- name: No-Work Rebuild Check
  run: janus build --check-no-work --deterministic

- name: Performance Monitoring
  run: janus stats --format json --export ci_metrics.json
```

## 🎭 Personality Comparison

### Oracle Personality (Constructive Cynicism)
```bash
$ janus oracle query "bad functions"
❌ Query failed: ambiguous predicate "bad functions"
💭 "Define 'bad' with precision, not prejudice. Try: 'func where child_count > 10'"

$ janus oracle query "func where effects.contains('pure')"
✅ Query executed successfully (2.1ms, 96% cache hit)
💭 "Ah, seeking the pure ones. These functions are honest about their intentions."
```

### Classical Personality (Professional & Direct)
```bash
$ janus query "bad functions"
Error: Invalid predicate syntax
Suggestion: Use specific criteria like 'func where child_count > 10'

$ janus query "func where effects.contains('pure')"
✅ Query completed successfully (2.1ms, 96% cache hit)
Found 23 pure functions
```

## 🔄 Migration Path

### From Classical to Oracle
```bash
# Start with familiar classical commands
janus query "func" --suggest-oracle

# Try Oracle equivalent
janus oracle query "func"

# Explore natural language
janus oracle converse "show me all functions"

# Add live monitoring
janus oracle subscribe "func" --notify stdout
```

### From Oracle to Classical
```bash
# Oracle users can always use classical commands
janus oracle query "func"  # Oracle style
janus query "func"         # Classical equivalent

# Both produce identical output
diff <(janus oracle query "func") <(janus query "func")  # No differences
```

## 🎯 When to Use Which?

### Use Oracle When:
- You want conversational, AI-enhanced interaction
- You prefer unified command structure
- You like constructive cynicism and philosophical guidance
- You want live monitoring and subscriptions
- You're exploring and experimenting with queries

### Use Classical When:
- You prefer explicit, traditional CLI patterns
- You're writing scripts and automation
- You want maximum compatibility with existing tools
- You prefer direct, professional output
- You're migrating from other CLI tools

## 🏆 The Best of Both Worlds

**The beauty of Janus is choice without compromise:**

- **Same Performance**: Both approaches use identical ASTDB and Query Engine
- **Same Features**: Every Oracle capability has a classical equivalent
- **Same Output**: Deterministic, bit-for-bit identical results
- **Same Security**: Privacy and capability hygiene in both modes
- **Seamless Mixing**: Use Oracle for exploration, classical for automation

**Choose your path, but know that both lead to the same revolutionary semantic truth.** 🔥
