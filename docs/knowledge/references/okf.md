---
type: Reference
title: Open Knowledge Framework (OKF)
description: The vendor-neutral markdown+YAML-frontmatter format this knowledge bundle conforms to, from Google's Knowledge Catalog.
resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf
tags: [reference, okf, knowledge, format, meta]
timestamp: 2026-06-18T00:00:00Z
---

**OKF (Open Knowledge Format / Framework)** is a universal, vendor-neutral format for
representing knowledge as plain markdown files with YAML frontmatter, from Google Cloud's
**Knowledge Catalog** repo (community-maintained, Apache 2.0). This bundle conforms to OKF v0.1.

# Schema

**Frontmatter** — `type` is the only REQUIRED field. Recommended: `title`, `description`
(single sentence), `resource` (a URI/path), `tags` (list), `timestamp` (ISO 8601). Producers
may add custom keys; consumers preserve unknown fields.

**Concept ID** = the file path within the bundle minus `.md`.

**Cross-links** — bundle-relative `[x](/path.md)` or relative `[x](./other.md)`. Broken links
tolerated.

**Reserved files** (no frontmatter): `index.md` (directory listing) and `log.md` (date-grouped
history — `## YYYY-MM-DD` + `* **Creation**:` / `* **Update**:`).

**Conventional body headings**: `# Schema`, `# Examples`, `# Citations`.

# How we use it

`docs/knowledge/` is the OKF bundle — durable, in-repo project knowledge. It complements
`CLAUDE.md` (the detailed quick reference) and the agent-private Claude memory. `type` values
in use: `Project`, `Architecture`, `Strategy`, `Policy`, `Decision`, `Reference`, `Playbook`.

# Citations

[1] [knowledge-catalog/okf](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
