<!--
---
title: Janus Writing Standards
description: Documentation conventions and hidden YAML front-matter requirements
author: Self Sovereign Society Foundation
date: 2025-08-29
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->

# Janus Writing Standards

## Hidden YAML-style Front-Matter (Mandatory)

All Markdown files must begin with a hidden YAML block inside an HTML comment. This embeds machine‑readable metadata without affecting renderers or linters.

Required fields: `title`, `description`, `author`, `date`, `license`, `version`.

Template (copy/paste):

```markdown
<!--
---
title: <Document Title>
description: <One-line purpose>
author: <Full Name>
date: YYYY-MM-DD
license: |
  
  // Copyright (c) 2026 Self Sovereign Society Foundation
  // The full text of the license can be found in the LICENSE file at the root of the repository.
version: 0.1
---
-->
```

## Conventions

- Date: ISO-8601 `YYYY-MM-DD`.
- Version: bump on material changes.
- License: use project SPDX; packages may differ (see `licensing.md`).
- Placement: the header is the first bytes of the file, followed by a blank line, then `# Title`.

## Linting

- HTML comments are allowed at file start.
- Do not add visible YAML triple-dash blocks (`---`) outside the comment.

## Enforcement

- Pre-commit hook `janus-front-matter` checks all `.md` files for the hidden header. See `.pre-commit-config.yaml` and `tools/check_front_matter.sh`.
