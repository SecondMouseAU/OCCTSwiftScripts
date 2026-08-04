---
type: reference
title: Open Knowledge Format (OKF)
description: The vendor-neutral markdown plus YAML-frontmatter format this knowledge bundle conforms to, from Google's Knowledge Catalog.
resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf
tags: [reference, okf, knowledge, format, meta]
timestamp: 2026-08-04
---

# Open Knowledge Format

**OKF** is a vendor-neutral format for representing knowledge as plain markdown files with YAML
frontmatter, from Google Cloud's **Knowledge Catalog** repo (community-maintained, Apache 2.0).
This bundle conforms to OKF v0.1.

# Schema

**Frontmatter.** `type` is the only REQUIRED field. Recommended: `title`, `description` (a single
sentence), `resource` (a URI or path), `tags` (a list), `timestamp` (ISO 8601). Producers may add
custom keys; consumers preserve unknown fields.

**Concept ID** is the file path within the bundle, minus `.md`.

**Cross-links** are bundle-relative (`[x](/path.md)`) or relative (`[x](./other.md)`), written
as ordinary markdown links. Broken links are tolerated.

**Reserved files** (no frontmatter): `index.md` (a directory listing) and `log.md` (date-grouped
history, `## YYYY-MM-DD` followed by `* **Creation**:` or `* **Update**:` entries).

**Conventional body headings**: `# Schema`, `# Examples`, `# Citations`.

# How we use it

`okf/` is this repo's single knowledge bundle. It complements `CLAUDE.md`, which stays the
detailed implementation quick reference. `type` values in use: `repo`, `component`, `policy`,
`reference`, `decision`. Use lowercase `type` values, and date-only timestamps.

The ecosystem-wide conventions are in
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md);
`ecosystem.yml` at the repo root is this bundle's catalog entry.

# Citations

[1] [knowledge-catalog/okf](https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf)
