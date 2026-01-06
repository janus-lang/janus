<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





This directory contains generated C++ protobuf/gRPC code for Oracle service.

Regenerate with:

  tools/gen_grpc.sh

Requires:
  - protoc (Protocol Buffers compiler)
  - grpc_cpp_plugin (for gRPC service stubs)

Outputs:
  - oracle.pb.h / oracle.pb.cc (protobuf messages)
  - oracle.grpc.pb.h / oracle.grpc.pb.cc (gRPC service stubs, when plugin available)
