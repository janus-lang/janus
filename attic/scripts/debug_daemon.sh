#!/bin/bash
echo "Starting daemon with debug logging..."
timeout 10 ./zig-out/bin/janus-core-daemon --log-level debug &
DAEMON_PID=$!
sleep 1

echo "Sending test request..."
timeout 5 ./zig-out/bin/test-doc-update

echo "Killing daemon..."
kill $DAEMON_PID 2>/dev/null
wait $DAEMON_PID 2>/dev/null