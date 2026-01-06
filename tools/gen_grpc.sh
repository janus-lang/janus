#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")"/.. && pwd)
PROTO_DIR="$ROOT_DIR/protocol"
OUT_DIR="$PROTO_DIR/gen"

mkdir -p "$OUT_DIR"

echo "[gen_grpc] Generating protobuf C++ sources..."
protoc --version
protoc -I"$PROTO_DIR" --cpp_out="$OUT_DIR" "$PROTO_DIR/oracle.proto"

if command -v grpc_cpp_plugin >/dev/null 2>&1; then
  echo "[gen_grpc] Generating gRPC C++ service stubs..."
  protoc -I"$PROTO_DIR" --grpc_out="$OUT_DIR" --plugin=protoc-gen-grpc="$(command -v grpc_cpp_plugin)" "$PROTO_DIR/oracle.proto"
else
  echo "[gen_grpc] WARNING: grpc_cpp_plugin not found. Skipping gRPC service stub generation."
  echo "Install gRPC C++ plugin to generate oracle.grpc.pb.[h|cc] and enable full integration."
fi

cat >"$OUT_DIR/README.md" <<'EOF'
This directory contains generated C++ protobuf/gRPC code for Oracle service.

Regenerate with:

  tools/gen_grpc.sh

Requires:
  - protoc (Protocol Buffers compiler)
  - grpc_cpp_plugin (for gRPC service stubs)

Outputs:
  - oracle.pb.h / oracle.pb.cc (protobuf messages)
  - oracle.grpc.pb.h / oracle.grpc.pb.cc (gRPC service stubs, when plugin available)

EOF

echo "[gen_grpc] Done. Outputs in $OUT_DIR"
