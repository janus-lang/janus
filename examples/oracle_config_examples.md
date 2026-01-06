<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# Janus Oracle Configuration Examples

**Following the sacred Janus doctrine: KDL for humans, JSON for computers.**

## 🎯 Configuration Hierarchy

1. **Command line flags** (highest priority)
2. **Environment variables**
3. **Project config** (`./janus.kdl` or `./janus.json`)
4. **User config** (`~/.janus/oracle.kdl` or `~/.janus/oracle.json`)
5. **System defaults** (lowest priority)

## 📝 KDL Configuration (For Humans)

### Basic Local Setup (Privacy-First)
```kdl
// ~/.janus/oracle.kdl
ai {
    provider "ollama"
    endpoint "http://localhost:11434"
    model "codellama:13b-instruct"
    privacy-mode "strict"  // Never send code content
    timeout 30
}

oracle {
    default-format "table"
    color "infernal"
    cynicism-level "constructive"
}
```

### Multi-Provider Cascade (Resilient)
```kdl
// ~/.janus/oracle.kdl
ai {
    privacy-mode "strict"
    fallback-strategy "cascade"
    confidence-threshold 0.8

    // Local first (privacy)
    provider name="local" {
        type "ollama"
        model "codellama:13b-instruct"
        endpoint "http://localhost:11434"
        priority 1
        timeout 30
    }

    // Cloud fallback (features)
    provider name="openai" {
        type "openai"
        model "gpt-4"
        api-key-file "~/.config/janus/openai.key"
        priority 2
        max-tokens 1000
        temperature 0.1
    }

    provider name="claude" {
        type "anthropic"
        model "claude-3-sonnet-20240229"
        api-key-file "~/.config/janus/claude.key"
        priority 3
        max-tokens 1000
    }

    provider name="gemini" {
        type "google"
        model "gemini-pro"
        api-key-file "~/.config/janus/google.key"
        priority 4
    }
}

oracle {
    default-format "poetic"
    subscription {
        default-notify "stdout"
        webhook-timeout 5000
    }
}

classical {
    default-format "jsonl"
    suggest-oracle true
    migration-hints true
}
```

### Enterprise Setup (Self-Hosted)
```kdl
// ~/.janus/oracle.kdl
ai {
    privacy-mode "local-only"  // Never leave corporate network

    provider name="corporate" {
        type "custom"
        endpoint "https://ai.company.com/v1/chat/completions"
        model "company-code-model-v2"
        priority 1
        headers {
            Authorization "Bearer ${COMPANY_AI_TOKEN}"
            X-Department "engineering"
        }
        timeout 60
    }

    provider name="local-backup" {
        type "ollama"
        endpoint "http://ai-server.internal:11434"
        model "codellama:34b"
        priority 2
    }
}

security {
    audit-log true
    log-file "/var/log/janus/oracle.log"
    redact-sensitive true
}
```

## 🤖 JSON Configuration (For Computers/CI)

### CI/Automation Setup
```json
{
  "ai": {
    "privacy_mode": "strict",
    "fallback_strategy": "cascade",
    "confidence_threshold": 0.8,
    "providers": [
      {
        "name": "local",
        "type": "ollama",
        "model": "codellama:13b-instruct",
        "endpoint": "http://localhost:11434",
        "priority": 1,
        "timeout": 30
      },
      {
        "name": "openai",
        "type": "openai",
        "model": "gpt-4",
        "api_key_file": "~/.config/janus/openai.key",
        "priority": 2,
        "max_tokens": 1000,
        "temperature": 0.1
      }
    ]
  },
  "oracle": {
    "default_format": "jsonl",
    "color": "never",
    "cynicism_level": "minimal"
  },
  "classical": {
    "default_format": "json",
    "suggest_oracle": false,
    "migration_hints": false
  }
}
```

### Docker/Container Setup
```json
{
  "ai": {
    "privacy_mode": "local-only",
    "providers": [
      {
        "name": "container",
        "type": "ollama",
        "endpoint": "http://ollama:11434",
        "model": "codellama:7b",
        "priority": 1
      }
    ]
  },
  "oracle": {
    "default_format": "jsonl",
    "color": "never"
  }
}
```

## 🔧 Environment Variable Overrides

```bash
# Override provider for this session
export JANUS_AI_PROVIDER=claude
export JANUS_AI_MODEL=claude-3-opus

# Privacy enforcement
export JANUS_PRIVACY_MODE=strict

# Disable AI entirely
export JANUS_AI_DISABLED=true

# Custom endpoint
export JANUS_AI_ENDPOINT=http://my-local-ai:8080
```

## 🎯 Command Line Overrides

```bash
# Override configured provider
janus oracle converse "find risky functions" --ai-provider ollama

# Override privacy mode
janus oracle converse "analyze complexity" --privacy-mode local-only

# Disable AI for this query
janus oracle query "func where effects.contains('db.write')" --no-ai

# Use specific model
janus oracle converse "show me patterns" --ai-model codellama:34b
```

## 🏢 Project-Specific Configuration

```kdl
// ./janus.kdl (project root)
project {
    name "secure-banking-app"
    profile "full"
}

ai {
    privacy-mode "strict"  // Banking code never leaves premises

    provider name="local-only" {
        type "ollama"
        model "codellama:13b-instruct"
        endpoint "http://localhost:11434"
        priority 1
    }
}

security {
    audit-queries true
    log-file "./logs/janus-queries.log"
    require-justification true
}

oracle {
    cynicism-level "high"  // Extra scrutiny for financial code
    default-format "table"
}
```

## 🔒 Security Best Practices

### API Key Management
```kdl
// Never put keys directly in config
ai {
    provider name="openai" {
        type "openai"
        api-key-file "~/.config/janus/openai.key"  // File with 0600 permissions
        // OR
        api-key-env "OPENAI_API_KEY"  // Environment variable
    }
}
```

### Privacy Modes Explained
```kdl
ai {
    // STRICT: Only query intent + metadata (function names, no code)
    privacy-mode "strict"

    // BALANCED: Anonymized code snippets (variables renamed, literals removed)
    // privacy-mode "balanced"

    // LOCAL-ONLY: Only use local models, fail if none available
    // privacy-mode "local-only"

    // OFF: Full code context sent (only for non-sensitive projects)
    // privacy-mode "off"
}
```

## 🎭 Format Examples

### Oracle Poetic Output
```kdl
oracle {
    default-format "poetic"
    cynicism-level "constructive"
    personality {
        success-messages true
        failure-guidance true
        performance-warnings true
    }
}
```

### Classical Professional Output
```kdl
classical {
    default-format "jsonl"
    suggest-oracle true
    migration-hints true
    professional-tone true
}
```

## 🔄 Migration Configuration

```kdl
// Gradual migration from classical to oracle
migration {
    suggest-oracle true
    show-equivalents true
    track-usage true

    // After 30 days, start suggesting oracle more aggressively
    suggestion-frequency "weekly"

    // Track which commands users prefer
    analytics {
        enabled true
        anonymous true
        local-only true
    }
}
```

**The beauty of KDL: Human-readable configuration that doesn't sacrifice power or precision. JSON remains available for automation and CI/CD pipelines where machine-parseable formats excel.** 🔥
