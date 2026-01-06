<!--
SPDX-License-Identifier: LSL-1.0
Copyright (c) 2026 Self Sovereign Society Foundation
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

<!--
SPDX-License-Identifier: BSD-3-Clause
Copyright (c) 2025 Markus Maiwald
-->

This directory quarantines obsolete or experimental scaffolding that is no longer
part of the active build. Files are retained for reference and potential reuse,
but should not be imported by production modules or tests.

Criteria for moving files here:
- Deprecated stubs replaced by real implementations
- Legacy experiments superseded by unified modules
- Tests for retired components kept only for historical reference

If you need to revive any of these, move them back into an appropriate module
and wire them through the build system explicitly.
