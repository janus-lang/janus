#!/bin/sh
# Simple docs server using Python's built-in http.server
# Usage: ./serve.sh [port]
PORT="${1:-8080}"
cd "$(dirname "$0")"
python3 -m http.server "$PORT"
