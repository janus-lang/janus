#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

status=0

if [[ $# -eq 0 ]]; then
  # If no args, scan all tracked markdown files
  mapfile -t files < <(git ls-files "**/*.md")
else
  files=("$@")
fi

for f in "${files[@]}"; do
  # Only check markdown files
  [[ "${f##*.}" != "md" ]] && continue
  # Look for opening HTML comment with YAML triple-dash on next line
  if ! awk 'NR==1 && $0 ~ /^<!--$/ {getline; if ($0 ~ /^---$/) found=1} END {exit !found}' "$f"; then
    echo "✗ Missing hidden YAML front-matter in: $f" >&2
    status=1
  fi
done

exit $status
