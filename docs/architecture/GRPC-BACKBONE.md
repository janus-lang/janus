<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





# gRPC Backbone: Architecture, Build, and Operations

This document captures the final state of the Oracle transport. It is the handoff guide for future maintainers.

## What Changed

- Single transport: gRPC is the only transport. All JSON/TCP code paths are removed.
- Foreign ABI quarantine: All C++ (gRPC C++ + Protobuf) is contained in a self‑built shared library shim `protocol/gen/liboracle_shim.so` exposing a pure C API in `protocol/c_shim/oracle_c_api.h`.
- Zig sees only a C ABI: `protocol/grpc_bindings.zig` unconditionally imports the C shim header and exposes it as `@import("grpc_bindings").c`.

## Key Files

- `protocol/oracle.proto` — Protocol definition
- `protocol/gen/` — Generated files (via `tools/gen_grpc.sh`):
  - `oracle.pb.{h,cc}`
  - `oracle.grpc.pb.{h,cc}`
  - `liboracle_shim.so` (built by `build.zig`)
- `protocol/c_shim/oracle_c_api.h` — C API (client + server callbacks)
- `protocol/c_shim/oracle_c_api.cc` — C++ implementation bridging to generated stubs
- `protocol/grpc_bindings.zig` — C import of the shim header
- `lsp/oracle_grpc_client.zig` — Pure gRPC client facade used by the LSP
- `daemon/oracle_grpc_server.zig` — gRPC server bridging to daemon logic
- `daemon/janusd.zig` — Minimal daemon starting the gRPC server (JSON removed)
- `tools/gen_grpc.sh` — Protobuf/gRPC code generator
- `tools/grpc_smoke_test.zig` — Smoke client exercising all RPCs

## Build & Link Flow

`build.zig` compiles and links in three layers:

1) Generate or use existing `protocol/gen/*.pb.cc` and `*.grpc.pb.cc`.
2) Build a shared shim library via system `g++`:
   - `protocol/gen/liboracle_shim.so` with `-lgrpc++ -lgrpc -lprotobuf -lpthread`
3) Link Zig executables to the shim and set `rpath` to `protocol/gen` for runtime resolution.

### libstdc++ selection

- The build exposes `-Dlibstdcxx_dir=/path/to/lib` to force both link and rpath to a specific libstdc++ directory when necessary.
- Example: `zig build -Dwith_lsp=true -Dlibstdcxx_dir=$(dirname $(g++ -print-file-name=libstdc++.so))`

## Live‑Fire Proof (Automated)

- One command: `zig build smoke -Dwith_lsp=true`
- The smoke step:
  - Builds `janusd`, `oracle-smoke`, and the shim
  - Starts `janusd` on 127.0.0.1:7777
  - Runs `oracle-smoke 127.0.0.1 7777`
  - Captures `smoke-logs/janusd.log` and `smoke-logs/smoke.log`, and prints both

## Maintenance

- Regenerate stubs after changing `protocol/oracle.proto`:
  - `bash tools/gen_grpc.sh`
- If system toolchains change, validate with:
  - `zig build -Dwith_lsp=true`
  - `zig build smoke -Dwith_lsp=true`
- Keep `protocol/c_shim/oracle_c_api.h` the single source of contract. All Zig interop depends on it.

## Safety Notes

- HoverAt server path returns a pointer copied synchronously by the shim. If turning the response into a heap allocation, expose a `free` in the C API and copy in Zig.
- ReferencesAt streams results via a sink callback to avoid monolithic allocations.

## Next Enhancements

- CI: add a job that runs `zig build` and `zig build smoke` on Linux/macOS.
- Timeouts and retries on the client.
- Detailed error propagation on server exceptions.
