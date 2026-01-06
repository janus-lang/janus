#!/usr/bin/env python3
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env python3
#!/usr/bin/env python3
#!/usr/bin/env python3
"""
MessagePack Test Client for Janus Core Daemon

This client tests the Citadel Protocol using proper MessagePack serialization
to verify that the daemon correctly implements the protocol specification.
"""

import subprocess
import struct
import msgpack
import time
import sys

def send_framed_message(process, message_data):
    """Send a length-prefixed MessagePack message to the daemon."""
    # Length prefix (4 bytes, big-endian)
    length = len(message_data)
    length_bytes = struct.pack('>I', length)

    # Send length + payload
    process.stdin.write(length_bytes)
    process.stdin.write(message_data)
    process.stdin.flush()

def read_framed_message(process):
    """Read a length-prefixed MessagePack message from the daemon."""
    # Read 4-byte length prefix
    length_bytes = process.stdout.read(4)
    if len(length_bytes) != 4:
        raise Exception(f"Failed to read length prefix, got {len(length_bytes)} bytes")

    length = struct.unpack('>I', length_bytes)[0]

    # Read payload
    payload = process.stdout.read(length)
    if len(payload) != length:
        raise Exception(f"Failed to read payload, expected {length} bytes, got {len(payload)}")

    return payload

def test_ping_msgpack():
    """Test ping request using proper MessagePack serialization."""
    print("🧪 Testing Janus Core Daemon with MessagePack Protocol")

    # Start the daemon
    daemon_cmd = ["./zig-out/bin/janus-core-daemon", "--log-level", "debug"]
    process = subprocess.Popen(
        daemon_cmd,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )

    try:
        # Create ping request using MessagePack
        ping_request = {
            "id": 1,
            "type": "ping",
            "timestamp": int(time.time() * 1_000_000_000),  # nanoseconds
            "payload": {
                "echo_data": "msgpack_test_123"
            }
        }

        print("📡 Sending MessagePack ping request...")

        # Serialize with MessagePack
        msgpack_data = msgpack.packb(ping_request)
        print(f"📦 MessagePack payload size: {len(msgpack_data)} bytes")

        # Send framed message
        send_framed_message(process, msgpack_data)

        # Read response
        print("📨 Reading response...")
        response_data = read_framed_message(process)

        # Try to parse as MessagePack first
        try:
            response = msgpack.unpackb(response_data, raw=False)
            print("✅ Received valid MessagePack response!")
            protocol_type = "MessagePack"
        except msgpack.exceptions.ExtraData:
            # Fall back to JSON if MessagePack fails
            response = msgpack.loads(response_data.decode('utf-8'))
            print("⚠️  Received JSON response (not MessagePack)")
            protocol_type = "JSON"

        print(f"📨 Response ({protocol_type}): {response}")

        # Validate response
        if response.get("id") != 1:
            print(f"❌ Wrong response ID: expected 1, got {response.get('id')}")
            return False

        if response.get("type") != "ping_response":
            print(f"❌ Wrong response type: expected 'ping_response', got '{response.get('type')}'")
            return False

        if response.get("status") != "success":
            print(f"❌ Wrong response status: expected 'success', got '{response.get('status')}'")
            return False

        payload = response.get("payload", {})
        echo_data = payload.get("echo_data")

        if echo_data != "msgpack_test_123":
            print(f"❌ Wrong echo data: expected 'msgpack_test_123', got '{echo_data}'")
            return False

        if protocol_type == "MessagePack":
            print("✅ MessagePack protocol test PASSED!")
        else:
            print("⚠️  JSON fallback test passed, but MessagePack implementation needed")

        # Send shutdown
        shutdown_request = {
            "id": 2,
            "type": "shutdown",
            "timestamp": int(time.time() * 1_000_000_000),
            "payload": {
                "reason": "test_complete",
                "timeout_ms": 1000
            }
        }

        shutdown_data = msgpack.packb(shutdown_request)
        send_framed_message(process, shutdown_data)

        # Wait for daemon to exit
        process.wait(timeout=5)

        return protocol_type == "MessagePack"

    except Exception as e:
        print(f"❌ Test failed: {e}")
        process.terminate()
        return False
    finally:
        if process.poll() is None:
            process.terminate()

if __name__ == "__main__":
    success = test_ping_msgpack()
    if success:
        print("🎉 MessagePack protocol implementation verified!")
        sys.exit(0)
    else:
        print("💥 MessagePack protocol implementation required!")
        sys.exit(1)
