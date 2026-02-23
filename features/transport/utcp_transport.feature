# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

Feature: UTCP Transport — Micro TCP Protocol for Janus
  As a Janus service developer
  I want a lightweight TCP-based control protocol
  So that AI agents can interact with janusd securely with minimal overhead

  Background:
    Given the UTCP protocol version is "0.1.1"
    And the transport uses line-delimited JSON over TCP
    And capability tokens follow the format "{resource}:{action}:{target}"

  # ============================================================================
  # Manual Discovery
  # ============================================================================

  Scenario: Client requests manual from janusd
    Given a janusd instance is running on localhost:7654
    When the client sends a "manual" request
    Then the response contains "manual_version" equal to "0.1.1"
    And the response contains "utcp_version" equal to "0.1"
    And the response contains an "auth" object with "auth_type" equal to "bearer"
    And the response contains a "tools" array with at least one tool

  Scenario: Manual contains tool definitions with capabilities
    Given a janusd instance is running on localhost:7654
    When the client requests the manual
    Then each tool in the "tools" array has:
      | field                 | type   |
      | name                  | string |
      | description           | string |
      | inputs                | object |
      | tool_call_template    | object |
      | x-janus-capabilities  | object |
    And each tool's "tool_call_template" has:
      | field                | type   |
      | call_template_type   | string |
      | url                  | string |
      | http_method          | string |
    And each tool's "x-janus-capabilities" has:
      | field    | type  |
      | required | array |
      | optional | array |

  # ============================================================================
  # Tool Invocation
  # ============================================================================

  Scenario: Client calls tool with required capabilities
    Given a janusd instance is running on localhost:7654
    And the client has the capability "fs.read:/workspace"
    When the client calls "compile" with:
      """
      {
        "source_file": "test.janus",
        "output_dir": "zig-out"
      }
      """
    And the client presents capabilities ["fs.read:/workspace", "fs.write:/workspace/zig-out"]
    Then the response "ok" field is true
    And the response contains a "result" object

  Scenario: Client calls tool without required capabilities
    Given a janusd instance is running on localhost:7654
    When the client calls "compile" with:
      """
      {
        "source_file": "test.janus",
        "output_dir": "zig-out"
      }
      """
    And the client presents capabilities []
    Then the response "ok" field is false
    And the response error code is "E1403_CAP_MISMATCH"
    And the response error contains "missing" array with "fs.read:${WORKSPACE}"

  # ============================================================================
  # Lease Registry Operations
  # ============================================================================

  Scenario: Client registers a lease for UTCP entry
    Given a janusd instance is running on localhost:7654
    And the client has the capability "registry.lease.register:test_group"
    When the client calls "registry.lease.register" with:
      """
      {
        "group": "test_group",
        "name": "test_entry",
        "ttl_seconds": 60
      }
      """
    Then the response "ok" field is true
    And the lease is stored with a valid BLAKE3 signature

  Scenario: Client extends lease via heartbeat
    Given a janusd instance is running on localhost:7654
    And the client has the capability "registry.lease.heartbeat:test_group"
    And a lease exists for group "test_group" entry "heartbeat_entry"
    When the client calls "registry.lease.heartbeat" with:
      """
      {
        "group": "test_group",
        "name": "heartbeat_entry",
        "ttl_seconds": 120
      }
      """
    Then the response "ok" field is true
    And the lease deadline is extended by 120 seconds

  Scenario: Heartbeat fails with invalid signature
    Given a janusd instance is running on localhost:7654
    And a lease exists with a corrupted signature
    When the client calls "registry.lease.heartbeat" with:
      """
      {
        "group": "corrupt_group",
        "name": "corrupt_entry",
        "ttl_seconds": 60
      }
      """
    Then the response "ok" field is false
    And the error indicates signature verification failed

  # ============================================================================
  # Registry State and Quotas
  # ============================================================================

  Scenario: Client queries registry state
    Given a janusd instance is running on localhost:7654
    When the client calls "registry.state" with no arguments
    Then the response "ok" field is true
    And the response contains "utcp_version" equal to "1.0.0"
    And the response contains "backpressure_metrics" object
    And the response contains "groups" object

  Scenario: Admin sets namespace quota
    Given a janusd instance is running on localhost:7654
    And the client has admin capability "registry.admin:*"
    When the client calls "registry.quota.set" with:
      """
      {
        "max_entries_per_group": 10
      }
      """
    Then the response "ok" field is true
    And subsequent registrations are limited to 10 entries per group

  Scenario: Quota enforcement prevents overflow
    Given a janusd instance is running on localhost:7654
    And the namespace quota is set to 2 entries per group
    And 2 entries already exist in group "quota_test_group"
    When the client attempts to register a 3rd entry
    Then the registration fails with error "NamespaceQuotaExceeded"

  # ============================================================================
  # Key Rotation (RSP-1)
  # ============================================================================

  Scenario: Admin rotates epoch key
    Given a janusd instance is running on localhost:7654
    And the client has admin capability "registry.admin:*"
    And an active lease exists signed with the old key
    When the client calls "registry.rotate" with:
      """
      {
        "key_hex": "new_epoch_key_hex_string"
      }
      """
    Then the response "ok" field is true
    And old leases are accepted during grace period
    And new leases use the new key

  # ============================================================================
  # Error Handling
  # ============================================================================

  Scenario: Malformed request returns structured error
    Given a janusd instance is running on localhost:7654
    When the client sends an invalid JSON payload
    Then the response "ok" field is false
    And the response contains "error" with "code" and "message" fields

  Scenario: Unknown tool returns error
    Given a janusd instance is running on localhost:7654
    When the client calls "unknown_tool" with empty arguments
    Then the response "ok" field is false
    And the error code indicates "UnknownTool" or similar
