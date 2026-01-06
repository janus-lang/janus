<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Oracle: Revolutionary CLI in Action

This document showcases the revolutionary capabilities of the Janus Oracle - transforming how developers and AI agents interrogate codebases.

## 🎯 Query Mode: Predicate Precision

### Basic Queries
```bash
# Find all functions
$ janus oracle query "func"
{"kind":"func","name":"transfer","cid":"blake3:a1b2c3...","span":{"file":"src/bank.jan","line":42,"col":5,"len":18},"effects":["db.write","audit.log"],"caps":["CapTransfer","CapAuditLog"]}
{"kind":"func","name":"validate","cid":"blake3:d4e5f6...","span":{"file":"src/bank.jan","line":15,"col":1,"len":12},"effects":["pure"],"caps":[]}

# Complex predicates with combinators
$ janus oracle query "(func or var) and child_count > 3" --format table
┌──────────┬─────────────┬──────────────────┬─────────────────────────┐
│ Kind     │ Name        │ Effects          │ Capabilities            │
├──────────┼─────────────┼──────────────────┼─────────────────────────┤
│ func     │ process_batch│ db.write,        │ CapBatchProcess         │
│          │             │ io.fs.read       │                         │
│ func     │ handle_request│ net.http,       │ CapHttpServer           │
│          │             │ db.read          │                         │
└──────────┴─────────────┴──────────────────┴─────────────────────────┘
```

### Security Analysis
```bash
# Find functions that could corrupt data without proper auditing
$ janus oracle query "func where effects.contains('db.write') and not requires_capability('CapAuditLog')" --format poetic

🔍 Query Results: Security Analysis

⚠️  update_balance (src/bank.jan:128)
   Effects: db.write
   Capabilities: CapTransfer
   💭 "This function wields database power without accountability. Consider adding CapAuditLog."

⚠️  delete_user (src/admin.jan:67)
   Effects: db.write, user.delete
   Capabilities: CapAdmin
   💭 "Deletion without audit trails? Bold strategy. Your compliance team disagrees."

📊 Summary: 2 risky functions found. Guard your capabilities wisely.
```

## 🔍 Diff Mode: Semantic Archaeology

### Precise Change Detection
```bash
# Compare two versions of a file
$ janus oracle diff src/bank_v1.jan src/bank_v2.jan --format json
{
  "changed": [
    {
      "item": "transfer",
      "kind": "LiteralChange",
      "detail": {"from": "1000", "to": "10000"}
    },
    {
      "item": "validate_amount",
      "kind": "TypeChange",
      "detail": {"from": "i32", "to": "i64"}
    }
  ],
  "unchanged": ["audit_log", "send_notification"],
  "invalidated_queries": [
    "Q.IROf(transfer)",
    "Q.TypeOf(validate_amount)",
    "Q.Dispatch(main_call_transfer)"
  ]
}

# Human-readable diff
$ janus oracle diff HEAD~1 HEAD --format table
┌─────────────────┬─────────────────┬──────────────────────────────────┐
│ Function        │ Change Type     │ Details                          │
├─────────────────┼─────────────────┼──────────────────────────────────┤
│ transfer        │ LiteralChange   │ Transfer limit: 1000 → 10000     │
│ validate_amount │ TypeChange      │ Parameter type: i32 → i64        │
│ process_batch   │ EffectChange    │ Added: audit.log                 │
└─────────────────┴─────────────────┴──────────────────────────────────┘

💭 "3 functions changed, 12 dependents invalidated. The ripple effect of precision."
```

## 🤖 Converse Mode: Natural Language Bridge

### Intuitive Queries
```bash
# Natural language to precise predicate
$ janus oracle converse "show me all functions that could cause security issues"

🤖 Translation (confidence: 0.89):
   "func where effects.contains('db.write') or effects.contains('net.http') or effects.contains('fs.write')"

🔍 Executing query...

⚠️  Found 7 potentially sensitive functions:
   - transfer (db.write, audit.log)
   - upload_file (fs.write, net.http)
   - backup_database (db.read, fs.write)
   - process_payment (db.write, net.http)
   - delete_logs (fs.write)
   - sync_users (db.write, net.http)
   - export_data (db.read, fs.write)

💭 "Power requires responsibility. Ensure these functions have proper capability guards."

# Dry run to see translation without execution
$ janus oracle converse "find slow functions" --dry-run

🤖 Translation (confidence: 0.76):
   "func where compile_time > 100ms or complexity > 10"

💭 "Translation confidence below threshold (0.8). Consider refining your query."
🎯 Suggested alternatives:
   - "func where child_count > 10"
   - "func where effects.contains('io.fs.read') and child_count > 5"
```

## 📡 Subscribe Mode: The Vigilant Sentinel

### Real-Time Monitoring
```bash
# Watch for changes to critical functions
$ janus oracle subscribe "func where name.matches('transfer|payment|withdraw')" --notify stdout

🔔 Subscription active: watching 12 functions
📡 Monitoring semantic changes in real-time...

# When changes occur:
🚨 CHANGE DETECTED (2025-08-22 14:32:15Z)
   Function: transfer
   Change: LiteralChange {"from": "1000", "to": "10000"}
   Impact: 3 dependent functions invalidated
   CID: blake3:old123... → blake3:new456...

   Affected Dependencies:
   - validate_transfer (signature change required)
   - audit_transfer (amount validation updated)
   - main (dispatch resolution changed)

💭 "A tenfold increase in transfer limits. Bold move. Hope your risk models agree."

# CI Integration - watch for no-work rebuild violations
$ janus oracle subscribe "build_invariance_violations" --notify webhook:https://ci.company.com/alerts

🔔 Watching for no-work rebuild violations...
📡 Will alert CI system if incremental guarantees are broken.
```

## 🔬 Introspect Mode: The Oracle Knows Itself

### Performance Telemetry
```bash
$ janus oracle introspect telemetry --format table

📊 Janus Oracle Performance Report
┌─────────────────────┬──────────┬──────────┬──────────┐
│ Metric              │ Current  │ P95      │ Target   │
├─────────────────────┼──────────┼──────────┼──────────┤
│ Query Latency       │ 3.2ms    │ 8.7ms    │ ≤10ms    │
│ Cache Hit Rate      │ 94.3%    │ -        │ ≥90%     │
│ Memory Peak         │ 128MB    │ 256MB    │ ≤512MB   │
│ CID Computation     │ 45µs     │ 89µs     │ ≤100µs   │
│ AI Translation      │ 87.2%    │ -        │ ≥80%     │
└─────────────────────┴──────────┴──────────┴──────────┘

🎯 All performance targets met
💾 Hot queries: Q.TypeOf (34%), Q.IROf (28%), Q.Dispatch (19%)
🤖 AI accuracy: 87.2% (142/163 successful translations)

💭 "Your Oracle runs efficiently. The codebase yields its secrets swiftly."
```

### No-Work Rebuild Validation
```bash
# Critical for CI - validate incremental build guarantees
$ janus oracle introspect build-invariance --deterministic

🔍 Executing no-work rebuild validation...

📊 Build Trace Analysis:
{
  "run1": {"parse": 145, "sema": 132, "ir": 87, "codegen": 12},
  "run2": {"parse": 0, "sema": 0, "ir": 0, "codegen": 0, "q_hits": 428, "q_misses": 0}
}

✅ No-work rebuild PASSED
   - Zero compilation stages in run 2
   - Zero query cache misses
   - 428 cache hits (100% hit rate)
   - Build time: 12ms vs 2.3s initial

💭 "Incremental perfection achieved. Your build system honors the covenant of efficiency."

# Example failure case
$ janus oracle introspect build-invariance

❌ No-work rebuild FAILED
   - Run 2 executed 3 parse stages (expected: 0)
   - Run 2 had 12 query cache misses (expected: 0)
   - Possible cause: Non-deterministic CID computation

💭 "Your incremental guarantees are broken. Check for hidden dependencies or non-deterministic operations."
🎯 Suggested fixes:
   - Enable --deterministic mode
   - Check for ambient state in CID computation
   - Verify string interning consistency
```

## 🔗 Integration Examples

### CI/CD Pipeline
```yaml
# .github/workflows/janus-oracle.yml
name: Janus Oracle Validation

on: [push, pull_request]

jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Validate No-Work Rebuild
      run: janus oracle introspect build-invariance --deterministic

    - name: Security Analysis
      run: |
        janus oracle query "func where effects.contains('db.write') and not requires_capability('CapAuditLog')" \
          --format json > security_report.json
        if [ -s security_report.json ]; then
          echo "❌ Found functions with database write access but no audit capability"
          cat security_report.json
          exit 1
        fi

    - name: Performance Check
      run: |
        janus oracle introspect telemetry --format json | \
          jq '.query_latency_p95 > 10' | grep -q false || \
          (echo "❌ Query latency exceeds 10ms target" && exit 1)
```

### AI Agent Integration
```python
import subprocess
import json

class JanusOracle:
    def __init__(self, deterministic=True):
        self.base_cmd = ['janus', 'oracle']
        if deterministic:
            self.base_cmd.append('--deterministic')

    def query(self, predicate, format='jsonl'):
        cmd = self.base_cmd + ['query', predicate, '--format', format]
        result = subprocess.run(cmd, capture_output=True, text=True)

        if result.returncode != 0:
            raise Exception(f"Query failed: {result.stderr}")

        if format == 'jsonl':
            return [json.loads(line) for line in result.stdout.strip().split('\n') if line]
        return result.stdout

    def analyze_security_risks(self):
        """Find functions that could cause security issues"""
        risky_functions = self.query(
            "func where effects.contains('db.write') and not requires_capability('CapAuditLog')"
        )

        return {
            'risk_count': len(risky_functions),
            'functions': [f['name'] for f in risky_functions],
            'recommendation': 'Add CapAuditLog requirement to database write functions'
        }

    def converse(self, natural_query, dry_run=False):
        """Use natural language to query the codebase"""
        cmd = self.base_cmd + ['converse', natural_query]
        if dry_run:
            cmd.append('--dry-run')

        result = subprocess.run(cmd, capture_output=True, text=True)
        return result.stdout

# Usage example
oracle = JanusOracle()

# Programmatic security analysis
risks = oracle.analyze_security_risks()
print(f"Found {risks['risk_count']} risky functions: {risks['functions']}")

# Natural language queries
response = oracle.converse("show me all complex functions that might need refactoring")
print(response)
```

## 🎭 The Oracle's Personality in Action

The Oracle embodies Janus philosophy through constructive cynicism:

### Success with Wisdom
```bash
$ janus oracle query "func where effects.contains('pure')"
✅ Query executed successfully (2.1ms, 96% cache hit)
💭 "Ah, seeking the pure ones. These functions are honest about their intentions - no hidden side effects, no surprises. Learn from their discipline."
```

### Failure with Guidance
```bash
$ janus oracle query "bad functions"
❌ Query failed: ambiguous predicate "bad functions"
💭 "Define 'bad' with precision, not prejudice. Try: 'func where child_count > 10 or effects.contains(\"io.fs.write\") and not requires_capability(\"CapFsWrite\")'"

🎯 Similar successful queries:
   - "func where complexity > threshold"
   - "func where effects.risky()"
   - "func where child_count > 5 and not effects.contains('pure')"
```

### Performance Warnings
```bash
$ janus oracle query "func" --format table
⚠️  Query completed but took 15.3ms (target: ≤10ms)
💭 "Your query was ambitious but costly. Consider adding constraints like 'func where file.matches(\"src/core/*\")' to narrow the search."

🎯 Optimization suggestions:
   - Add file path constraints
   - Use more specific predicates
   - Consider indexing hints for large codebases
```

---

**The Janus Oracle transforms the command line from a primitive tool into a living dialogue with your codebase's soul. It's not just about querying code—it's about understanding, monitoring, and evolving your software with unprecedented precision and insight.** 🔥
