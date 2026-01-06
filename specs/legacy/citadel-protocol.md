<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# SPEC: Citadel Protocol

**Status:** Draft
**Author:** Self Sovereign Society Foundation
**Date:** 2025-09-06
**Version:** 0.1.1
**Epic:** The Citadel Architecture - Protocol Definition

## Overview

The Citadel Protocol is the lightweight, dependency-free communication contract between the `janus-core-daemon` (The Keep) and protocol-specific proxies (The Outer Wall). This protocol is the unbreakable foundation upon which the entire Citadel Architecture is built.

**Design Principles:**
- **Minimal Overhead:** Sub-millisecond serialization/deserialization
- **Cross-Platform:** Works identically on all target platforms
- **Versioned:** Forward and backward compatibility through version negotiation
- **Stateless Messages:** Each message is self-contained
- **Error Resilient:** Comprehensive error handling and recovery

## Transport Layer

### Communication Channels

The protocol supports two transport mechanisms:

1. **stdio (Primary):** Standard input/output streams for subprocess communication
2. **Unix Socket (Alternative):** Local domain socket for same-machine IPC

### Message Framing

All messages use length-prefixed framing to handle variable-length MessagePack payloads:

```
┌─────────────┬─────────────────────────────────────┐
│   Length    │           MessagePack Payload       │
│  (4 bytes)  │         (Length bytes)              │
│  Big Endian │                                     │
└─────────────┴─────────────────────────────────────┘
```

**Frame Structure:**
- **Length Field:** 4-byte big-endian unsigned integer indicating payload size
- **Payload:** MessagePack-encoded message (Request or Response)
- **Maximum Message Size:** 16MB (prevents memory exhaustion attacks)

## Protocol Negotiation

### Version Handshake

Every connection begins with a version negotiation handshake:

```
Client → Server: VersionRequest
Server → Client: VersionResponse
```

VersionRequest
```msgpack
{
  "type": "version_request",
  "client_version": {
    "major": 1,
    "minor": 0,
    "patch": 0
  },
  "supported_features": ["stdio", "unix_socket", "compression"]
}
```

#### VersionResponse
```msgpack
{
  "type": "version_response",
  "server_version": {
    "major": 1,
    "minor": 0,
    "patch": 0
  },
  "negotiated_version": {
    "major": 1,
    "minor": 0,
    "patch": 0
  },
  "enabled_features": ["stdio"],
  "status": "success" | "incompatible"
}
```

**Version Compatibility Rules:**
- **Major Version:** Must match exactly (breaking changes)
- **Minor Version:** Backward compatible (new features)
- **Patch Version:** Fully compatible (bug fixes)

## Core Message Types

### Request Message Structure

```msgpack
{
  "id": <uint32>,           // Unique request identifier
  "type": <string>,         // Request type identifier
  "timestamp": <uint64>,    // Unix timestamp in nanoseconds
  "payload": <object>       // Type-specific request data
}
```

### Response Message Structure

```msgpack
{
  "id": <uint32>,           // Matching request identifier
  "type": <string>,         // Response type identifier
  "timestamp": <uint64>,    // Unix timestamp in nanoseconds
  "status": <string>,       // "success" | "error"
  "payload": <object>,      // Type-specific response data
  "error": <object>         // Present only when status == "error"
}
```

## Oracle API Messages

### DocUpdate Operation

Updates document content and creates/updates the ASTDB snapshot.

#### DocUpdateRequest
```msgpack
{
  "id": 1001,
  "type": "doc_update",
  "timestamp": 1725634800000000000,
  "payload": {
    "uri": "file:///path/to/document.jan",
    "content": "func main() {\n    print(\"Hello, World!\");\n}",
    "version": 42                    // Optional: document version number
  }
}
```

#### DocUpdateResponse
```msgpack
{
  "id": 1001,
  "type": "doc_update_response",
  "timestamp": 1725634800001000000,
  "status": "success",
  "payload": {
    "success": true,
    "snapshot_id": "blake3:a1b2c3d4...",  // BLAKE3 hash of snapshot
    "parse_time_ns": 1250000,             // Parsing time in nanoseconds
    "token_count": 15,                    // Number of tokens parsed
    "node_count": 8                       // Number of AST nodes created
  }
}
```

### HoverAt Operation

Retrieves hover information for a specific position in a document.

#### HoverAtRequest
```msgpack
{
  "id": 1002,
  "type": "hover_at",
  "timestamp": 1725634800002000000,
  "payload": {
    "uri": "file:///path/to/document.jan",
    "position": {
      "line": 1,        // 0-based line number
      "character": 5    // 0-based character offset
    }
  }
}
```

#### HoverAtResponse
```msgpack
{
  "id": 1002,
  "type": "hover_at_response",
  "timestamp": 1725634800003000000,
  "status": "success",
  "payload": {
    "hover_info": {
      "markdown": "**Type:** `string`\n\nA string literal value.",
      "range": {
        "start": {"line": 1, "character": 4},
        "end": {"line": 1, "character": 19}
      }
    }
  }
}
```

**Note:** If no hover information is available, `hover_info` will be `null`.

### DefinitionAt Operation

Finds the definition location for a symbol at a specific position.

#### DefinitionAtRequest
```msgpack
{
  "id": 1003,
  "type": "definition_at",
  "timestamp": 1725634800004000000,
  "payload": {
    "uri": "file:///path/to/document.jan",
    "position": {
      "line": 2,
      "character": 8
    }
  }
}
```

#### DefinitionAtResponse
```msgpack
{
  "id": 1003,
  "type": "definition_at_response",
  "timestamp": 1725634800005000000,
  "status": "success",
  "payload": {
    "definition": {
      "uri": "file:///path/to/document.jan",
      "range": {
        "start": {"line": 0, "character": 5},
        "end": {"line": 0, "character": 9}
      }
    }
  }
}
```

**Note:** If no definition is found, `definition` will be `null`.

### ReferencesAt Operation

Finds all references to a symbol at a specific position.

#### ReferencesAtRequest
```msgpack
{
  "id": 1004,
  "type": "references_at",
  "timestamp": 1725634800006000000,
  "payload": {
    "uri": "file:///path/to/document.jan",
    "position": {
      "line": 0,
      "character": 5
    },
    "include_declaration": true
  }
}
```

#### ReferencesAtResponse
```msgpack
{
  "id": 1004,
  "type": "references_at_response",
  "timestamp": 1725634800007000000,
  "status": "success",
  "payload": {
    "references": [
      {
        "uri": "file:///path/to/document.jan",
        "range": {
          "start": {"line": 0, "character": 5},
          "end": {"line": 0, "character": 9}
        },
        "is_declaration": true
      },
      {
        "uri": "file:///path/to/document.jan",
        "range": {
          "start": {"line": 2, "character": 4},
          "end": {"line": 2, "character": 8}
        },
        "is_declaration": false
      }
    ]
  }
}
```

## Administrative Messages

### Shutdown Operation

Gracefully shuts down the core daemon.

#### ShutdownRequest
```msgpack
{
  "id": 9999,
  "type": "shutdown",
  "timestamp": 1725634800008000000,
  "payload": {
    "reason": "proxy_terminating",
    "timeout_ms": 5000
  }
}
```

#### ShutdownResponse
```msgpack
{
  "id": 9999,
  "type": "shutdown_response",
  "timestamp": 1725634800009000000,
  "status": "success",
  "payload": {
    "message": "Daemon shutting down gracefully"
  }
}
```

### Ping Operation

Health check and latency measurement.

#### PingRequest
```msgpack
{
  "id": 8888,
  "type": "ping",
  "timestamp": 1725634800010000000,
  "payload": {
    "echo_data": "test_payload_123"
  }
}
```

#### PingResponse
```msgpack
{
  "id": 8888,
  "type": "ping_response",
  "timestamp": 1725634800010500000,
  "status": "success",
  "payload": {
    "echo_data": "test_payload_123",
    "server_timestamp": 1725634800010500000
  }
}
```

## Error Handling

### Error Response Structure

When `status` is `"error"`, the response includes an `error` object:

```msgpack
{
  "id": 1001,
  "type": "doc_update_response",
  "timestamp": 1725634800011000000,
  "status": "error",
  "payload": null,
  "error": {
    "code": "PARSE_ERROR",
    "message": "Syntax error at line 2, column 15: expected ';' after statement",
    "details": {
      "line": 2,
      "column": 15,
      "expected": ";",
      "found": "}"
    }
  }
}
```

### Standard Error Codes

| Code | Description | Retry Safe |
|------|-------------|------------|
| `INVALID_REQUEST` | Malformed or invalid request message | No |
| `DOCUMENT_NOT_FOUND` | Requested document URI not found | No |
| `PARSE_ERROR` | Syntax error in document content | No |
| `INTERNAL_ERROR` | Unexpected server error | Yes |
| `TIMEOUT` | Operation exceeded time limit | Yes |
| `OUT_OF_MEMORY` | Insufficient memory to complete operation | Yes |
| `PROTOCOL_VERSION_MISMATCH` | Incompatible protocol versions | No |
| `FEATURE_NOT_SUPPORTED` | Requested feature not available | No |

### Error Recovery

- **Transient Errors:** Clients should retry with exponential backoff
- **Permanent Errors:** Clients should not retry without fixing the request
- **Connection Errors:** Clients should re-establish connection and re-negotiate protocol version

## Performance Characteristics

### Latency Targets

| Operation | Target Latency | Maximum Latency |
|-----------|----------------|-----------------|
| DocUpdate | < 5ms | < 50ms |
| HoverAt | < 1ms | < 10ms |
| DefinitionAt | < 2ms | < 20ms |
| ReferencesAt | < 5ms | < 50ms |
| Ping | < 0.1ms | < 1ms |

### Throughput Targets

- **Concurrent Requests:** Support up to 100 concurrent operations
- **Message Rate:** Handle 1000+ messages per second
- **Memory Usage:** Stable memory usage under sustained load

### Protocol Overhead

- **Serialization:** MessagePack adds ~5-10% overhead vs raw binary
- **Framing:** 4-byte length prefix adds negligible overhead
- **Total Overhead:** Target <100μs per message for serialization/deserialization

## Security Considerations

### Input Validation

- **Message Size Limits:** Maximum 16MB per message
- **URI Validation:** Reject malformed or suspicious URIs
- **Content Sanitization:** Validate document content encoding (UTF-8)
- **Request Rate Limiting:** Prevent DoS through excessive requests

### Process Isolation

- **Subprocess Sandboxing:** Core daemon runs in isolated process
- **Resource Limits:** Memory and CPU limits enforced by OS
- **Capability Restrictions:** Minimal file system and network access

### Error Information Disclosure

- **Internal Paths:** Never expose internal file system paths
- **Stack Traces:** Sanitize error messages in production
- **Timing Attacks:** Consistent response times for similar operations

## Implementation Notes

### MessagePack Schema Validation

All messages must be validated against their schemas before processing:

```zig
const RequestSchema = struct {
    id: u32,
    type: []const u8,
    timestamp: u64,
    payload: std.json.Value,
};

fn validateRequest(data: []const u8) !RequestSchema {
    // Parse MessagePack and validate structure
    // Return validated request or error
}
```

### Backward Compatibility

- **Field Addition:** New optional fields can be added to existing messages
- **Field Removal:** Deprecated fields must be supported for one major version
- **Type Changes:** Field type changes require major version increment

### Future Extensions

The protocol is designed to support future enhancements:

- **Compression:** Optional gzip/lz4 compression for large payloads
- **Streaming:** Support for streaming responses (e.g., incremental parsing)
- **Multiplexing:** Multiple concurrent request streams over single connection
- **Authentication:** Optional authentication and authorization mechanisms

## Conclusion

The Citadel Protocol provides a robust, efficient, and extensible foundation for the Citadel Architecture. By establishing this contract first, we ensure that all components can be developed and tested independently while maintaining perfect interoperability.

**The Protocol is Law. The Protocol is Unbreakable. The Protocol is the Foundation upon which the Citadel stands.**
