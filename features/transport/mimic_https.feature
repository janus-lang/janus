# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

Feature: MIMIC_HTTPS Transport — Censorship-Resistant L0 Transport
  As a Janus network developer
  I want to wrap LWF frames in HTTPS/WebSocket camouflage
  So that Libertaria traffic can bypass state-level DPI and censorship

  Background:
    Given the MIMIC_HTTPS protocol follows RFC-0015
    And the skin uses WebSocket over TLS 1.3
    And the default cover domain is "cdn.cloudflare.com"
    And the real endpoint is "relay.libertaria.network"
    And the WebSocket path is "/api/v1/stream"

  # ============================================================================
  # WebSocket Frame Encoding/Decoding
  # ============================================================================

  Scenario: Encode and decode WebSocket text frame
    Given a WebSocket frame with:
      | field    | value           |
      | fin      | true            |
      | opcode   | text            |
      | masked   | true            |
      | payload  | "Hello, World!" |
      | mask_key | 0x12345678      |
    When the frame is encoded to wire format
    And the frame is decoded from wire format
    Then the decoded payload equals "Hello, World!"
    And the decoded FIN flag is true
    And the decoded opcode is text

  Scenario: Encode and decode WebSocket binary frame
    Given a WebSocket frame with:
      | field    | value                |
      | fin      | true                 |
      | opcode   | binary               |
      | masked   | false                |
      | payload  | <binary 0x00-0xFF>   |
      | mask_key | 0x00000000           |
    When the frame is encoded to wire format
    And the frame is decoded from wire format
    Then the decoded payload matches the original binary data

  Scenario: WebSocket frame with small payload (<126 bytes)
    Given a payload of 100 bytes
    When the WebSocket frame is encoded
    Then the header length is 2 bytes (no extended length)
    And the payload length byte equals 100

  Scenario: WebSocket frame with medium payload (126-65535 bytes)
    Given a payload of 1000 bytes
    When the WebSocket frame is encoded
    Then the header uses 16-bit extended length (126 prefix)
    And the 2-byte length field equals 1000 (big-endian)

  Scenario: WebSocket frame with large payload (>65535 bytes)
    Given a payload of 100000 bytes
    When the WebSocket frame is encoded
    Then the header uses 64-bit extended length (127 prefix)
    And the 8-byte length field equals 100000 (big-endian)

  Scenario: WebSocket masking is applied correctly
    Given a payload "ABC"
    And a mask key [0x01, 0x02, 0x03, 0x04]
    When the masked frame is encoded
    Then the encoded payload equals [0x42, 0x42, 0x40] (XOR applied)
    And when decoded, the original payload is recovered

  # ============================================================================
  # Domain Fronting
  # ============================================================================

  Scenario: Build domain fronting HTTP request
    Given a domain fronting config:
      | field        | value                       |
      | cover_domain | cdn.cloudflare.com          |
      | real_host    | relay.libertaria.network    |
      | path         | /api/v1/stream              |
      | user_agent   | Mozilla/5.0 (Windows NT...) |
    When the HTTP request is built
    Then the request contains "Host: relay.libertaria.network"
    And the request contains "Upgrade: websocket"
    And the request contains "Sec-WebSocket-Version: 13"
    And the TLS SNI would contain "cdn.cloudflare.com" (not visible in HTTP)

  Scenario: WebSocket handshake generates valid key
    Given a client initiating WebSocket handshake
    When the Sec-WebSocket-Key is generated
    Then the key is 24 bytes (16 bytes nonce, base64 encoded)
    And the key is valid base64

  # ============================================================================
  # TLS Fingerprint Parroting
  # ============================================================================

  Scenario Outline: Generate TLS ClientHello for browser fingerprint
    Given a TLS fingerprint type "<browser>"
    And SNI "cover.example.com"
    When the ClientHello is generated
    Then the JA3 fingerprint matches known "<browser>" signature

    Examples:
      | browser    |
      | Chrome120  |
      | Firefox121 |
      | Safari17   |
      | Edge120    |

  # ============================================================================
  # LWF Frame Tunneling
  # ============================================================================

  Scenario: Tunnel LWF frame through WebSocket
    Given a valid LWF frame with payload "Secret message"
    And MIMIC_HTTPS is configured with domain fronting
    When the LWF frame is wrapped in a WebSocket binary frame
    And the WebSocket frame is encoded
    Then the encoded data can be decoded back to the original LWF frame

  Scenario: Full MIMIC_HTTPS session flow
    Given a client wants to connect to a Libertaria relay
    And the network has DPI that blocks unknown protocols
    When the client initiates MIMIC_HTTPS connection:
      """
      1. DNS query for cover domain (cdn.cloudflare.com)
      2. TCP connect to port 443
      3. TLS handshake with SNI = cover_domain
      4. HTTP GET with Host = real_endpoint
      5. WebSocket upgrade
      6. Send LWF frames as binary WebSocket messages
      """
    Then the DPI sees only HTTPS traffic to a CDN
    And the LWF frames are successfully tunneled

  # ============================================================================
  # Error Handling
  # ============================================================================

  Scenario: Reject truncated WebSocket frame
    Given a WebSocket frame encoding
    And the data is truncated mid-payload
    When attempting to decode
    Then the operation returns null (incomplete frame)

  Scenario: Reject WebSocket frame with invalid opcode
    Given a WebSocket frame with opcode 0x0F (reserved)
    When attempting to decode
    Then the frame is decoded but marked with unknown opcode

  Scenario: Handle incomplete WebSocket header
    Given only 1 byte of WebSocket frame data
    When attempting to decode
    Then the operation returns null (incomplete)

  # ============================================================================
  # ECH (Encrypted Client Hello) Support
  # ============================================================================

  Scenario: ECH config parsing
    Given an ECH config list from DNS HTTPS record:
      """
      base64: AD7+DQA65wAgACA... [truncated]
      """
    When the ECH config is parsed
    Then the config ID is extracted
    And the public key is available for HPKE encryption

  Scenario: Encrypt inner ClientHello with ECH
    Given an inner ClientHello with real SNI "relay.libertaria.network"
    And an outer ClientHello with cover SNI "cdn.cloudflare.com"
    And a valid ECH config with public key
    When ECH encryption is applied
    Then the inner ClientHello is encrypted with HPKE
    And only the cover SNI is visible to network observers

  # ============================================================================
  # Integration with Transport Skin Selector
  # ============================================================================

  Scenario: MIMIC_HTTPS skin is selected for censored networks
    Given a network environment with:
      | condition                    |
      | UDP blocked                  |
      | Raw LWF detected and blocked |
      | HTTPS to CDNs allowed        |
    When the transport skin selector probes available options
    Then MIMIC_HTTPS is selected as the active skin
    And RAW skin is marked as unavailable

  Scenario: Fallback from MIMIC_HTTPS to MIMIC_DNS
    Given MIMIC_HTTPS is the primary skin
    And HTTPS traffic is being throttled
    When the throttling is detected
    Then the secondary skin (MIMIC_DNS) is activated
    And session continuity is maintained via signal over DNS
