#!/usr/bin/env bash
# SPDX-License-Identifier: LUL-1.0
# Copyright (c) 2026 Self Sovereign Society Foundation

#!/usr/bin/env bash
#!/usr/bin/env bash
set -euo pipefail

# Forbidden top-level paths (regex, anchored at start)
FORBIDDEN_REGEX='^(\.kiro/|\.zig-cache/|\.zig-global-cache/|zig-out/|test_golden_snapshots/)'

green() { echo -e "\033[32m$*\033[0m"; }
red()   { echo -e "\033[31m$*\033[0m"; }

echo "🔒 Checking for forbidden paths..."

# Determine changed files if CI provides a diff base; else scan full repo
FILES=""
if [[ -n "${GITHUB_BASE_REF:-}" && -n "${GITHUB_SHA:-}" ]]; then
  # GitHub PR context
  git fetch --depth=100 origin "${GITHUB_BASE_REF}" >/dev/null 2>&1 || true
  BASE=$(git merge-base "origin/${GITHUB_BASE_REF}" "${GITHUB_SHA}")
  FILES=$(git diff --name-only "$BASE" "${GITHUB_SHA}")
elif [[ -n "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME:-}" && -n "${CI_COMMIT_SHA:-}" ]]; then
  # Gitea/Forgejo PR-like context
  git fetch --depth=100 origin "${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}" >/dev/null 2>&1 || true
  BASE=$(git merge-base "origin/${CI_MERGE_REQUEST_TARGET_BRANCH_NAME}" "${CI_COMMIT_SHA}")
  FILES=$(git diff --name-only "$BASE" "${CI_COMMIT_SHA}")
else
  FILES=$(git ls-files)
fi

if [[ -z "$FILES" ]]; then
  green "✅ No files to check."
  exit 0
fi

VIOLATIONS=$(echo "$FILES" | grep -E "$FORBIDDEN_REGEX" || true)

if [[ -n "$VIOLATIONS" ]]; then
  red "❌ Forbidden paths detected in the diff/repo:"
  echo "$VIOLATIONS" | sed 's/^/  - /'
  echo
  echo "These paths must not be tracked or in PRs."
  echo "Add them to .gitignore and remove from history/index if present."
  exit 1
fi

green "✅ No forbidden paths detected."
exit 0
