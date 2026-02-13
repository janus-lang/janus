# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

Feature: LWF Frame — Libertaria Wire Frame Protocol
  As a Janus network developer
  I want a lightweight, efficient wire protocol for message framing
  So that L0 transport can reliably encode and decode messages with minimal overhead

  Background:
    Given the LWF protocol version is "0.1.0"
    And the LWF magic bytes are "LWF\\0"
    And the fixed header size is 88 bytes
    And the fixed trailer size is 36 bytes

  # ============================================================================
  # Frame Structure Validation
  # ============================================================================

  Scenario: Encode and decode LWF frame with minimal payload
    Given a frame class "Micro" (max 128 bytes)
    And a payload of "Hello"
    When the frame is encoded
    Then the encoded frame size is 129 bytes (88 header + 5 payload + 36 trailer)
    And the header magic equals "LWF\\0"
    And the header payload_len equals 5
    And the header frame_class equals 0x00 (Micro)
    And the trailer checksum is valid

  Scenario: Encode frame with all header fields set
    Given a header with:
      | field              | value                          |
      | dest_hint          | 24-byte destination hint       |
      | source_hint        | 24-byte source hint            |
      | session_id         | 16-byte session identifier     |
      | sequence           | 42                             |
      | service_type       | 0x0501                         |
      | frame_class        | Standard                       |
      | version            | 1                              |
      | flags              | 0                              |
      | entropy_difficulty | 8                              |
      | timestamp          | 1700000000000                  |
    And a payload of 100 bytes
    When the frame is encoded
    And the frame is decoded
    Then all header fields match the original values

  # ============================================================================
  # Frame Classes and Size Limits
  # ============================================================================

  Scenario Outline: Frame class size limits
    Given a frame class "<class>"
    When querying max frame size
    Then the max frame size is <max_size> bytes
    And the max payload size is <max_payload> bytes

    Examples:
      | class    | max_size | max_payload |
      | Micro    | 128      | 4           |
      | Mini     | 512      | 388         |
      | Standard | 1350     | 1226        |
      | Big      | 4096     | 3972        |
      | Jumbo    | 9000     | 8876        |

  Scenario: Reject payload exceeding frame class limit
    Given a frame class "Micro"
    And a payload of 10 bytes (exceeds 4-byte limit)
    When attempting to encode the frame
    Then the operation fails with error "PayloadTooLarge"

  # ============================================================================
  # Integrity and Verification
  # ============================================================================

  Scenario: Frame with valid CRC32C checksum passes verification
    Given a valid encoded frame
    When the frame is decoded with checksum verification
    Then the decoded payload matches the original

  Scenario: Frame with corrupted checksum fails verification
    Given a valid encoded frame
    And the trailer checksum byte at offset 0 is corrupted
    When attempting to decode the frame
    Then the operation fails with error "ChecksumMismatch"

  Scenario: Frame with truncated data fails decoding
    Given a valid encoded frame
    And the frame is truncated by 10 bytes
    When attempting to decode the frame
    Then the operation fails with error "InvalidLength"

  # ============================================================================
  # Signed Frames
  # ============================================================================

  Scenario: Encode and verify signed frame
    Given a valid Ed25519 signing keypair
    And a payload of "Signed message"
    When the frame is encoded with signing
    Then the trailer contains a 32-byte signature
    And the header flags do NOT have FlagUnsigned set
    And the signature verifies against the header + payload

  Scenario: Reject unsigned frame when signed required
    Given an unsigned frame (FlagUnsigned set)
    When decoding with VerifyMode.RequireSigned
    Then the operation fails with error "UnsignedFrame"

  Scenario: Accept unsigned frame when allowed
    Given an unsigned frame (FlagUnsigned set)
    When decoding with VerifyMode.AllowUnsigned
    Then the frame decodes successfully

  Scenario: Reject frame with invalid signature
    Given a signed frame
    And the signature is corrupted
    When attempting to decode with verification
    Then the operation fails with signature verification error

  # ============================================================================
  # Session and Sequence Management
  # ============================================================================

  Scenario: Sequence number increments correctly
    Given a session with sequence number 100
    When encoding 3 frames in sequence
    Then the frames have sequence numbers 100, 101, 102

  Scenario: Read payload length from raw header bytes
    Given raw header bytes with payload_len at offset 74-76
    When calling readPayloadLen
    Then the correct payload length is returned

  # ============================================================================
  # Error Handling
  # ============================================================================

  Scenario: Reject frame with invalid magic bytes
    Given header bytes with magic "XXYZ" instead of "LWF\\0"
    When attempting to decode the header
    Then the operation fails with error "InvalidMagic"

  Scenario: Reject header decode with insufficient bytes
    Given only 50 bytes of header data
    When attempting to decode the header
    Then the operation fails with error "InvalidLength"

  Scenario: Missing verify key for signed frame
    Given a signed frame
    And no verify key is provided
    When attempting to decode
    Then the operation fails with error "MissingVerifyKey"
