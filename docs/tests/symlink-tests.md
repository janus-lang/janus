<!--
SPDX-License-Identifier: LUL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->





Symlink Tests: Environment and CI Toggle

Overview
- The symlink parity tests validate file and directory symlink behavior across MemoryFS and PhysicalFS.
- On platforms without symlink support or with restricted permissions (e.g., Windows without Developer Mode), tests skip gracefully.

Windows Setup
- Enable Windows Developer Mode to allow creating symbolic links without elevated privileges:
  - Settings → Privacy & Security → For Developers → Developer Mode.
  - Alternatively, run the test process with administrative privileges.

CI Toggle
- To explicitly enable PhysicalFS symlink tests in CI, set the environment variable:
  - `JANUS_ENABLE_SYMLINK_TESTS=1`
- When this variable is not set, the PhysicalFS symlink tests skip early with a notice.

Test Behavior
- MemoryFS tests always run (pure in‑memory model).
- PhysicalFS tests:
  - First check `JANUS_ENABLE_SYMLINK_TESTS`. If absent, skip.
  - Attempt to create symlinks. If the runtime reports OperationNotSupported/AccessDenied, tests skip gracefully.

Files
- Tests: `tests/std/fs_physical_symlink_parity_test.jan`, `tests/std/fs_memory_symlink_*`
- Runtime glue: `std/runtime.zig` (symlink creation helpers, env var query)
