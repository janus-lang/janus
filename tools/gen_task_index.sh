#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

out_file=".kiro/TASK-INDEX.md"
timestamp=$(date +"%Y-%m-%d_%H%M")

{
  cat <<'HDR'
<!--
---
title: Task Index
description: Aggregated open tasks across project specs
author: Markus Maiwald
date: REPLACED_BY_SCRIPT
license: |
  // SPDX-License-Identifier: LUL-1.0
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
tags: [tasks, index, specs]
---
-->

# Task Index (Generated)

HDR
  echo "Generated: ${timestamp}"
  echo

  shopt -s nullglob
  for f in .kiro/specs/*/*/tasks.md; do
    echo "## ${f}"
    echo
    # Print unchecked tasks
    awk '/^- \[ \]/{print "- "$0}' "$f" | sed 's/^- \[ \]/- [ ]/g' || true
    echo
  done
} | sed "s/date: REPLACED_BY_SCRIPT/date: ${timestamp}/" > "$out_file"

echo "Wrote $out_file"
