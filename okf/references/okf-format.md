---
type: reference
title: Open Knowledge Format (OKF)
description: The vendor-neutral markdown plus YAML-frontmatter format this knowledge bundle conforms to, from Google's Knowledge Catalog.
resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf
tags: [reference, okf, knowledge, format, meta]
generated: { by: claude-code/opus-5, at: 2026-08-04 }
sources:
  - id: "1"
    resource: https://github.com/GoogleCloudPlatform/knowledge-catalog/tree/main/okf
    title: knowledge-catalog/okf
---

# Open Knowledge Format

**OKF** is a vendor-neutral format for representing knowledge as plain markdown files with YAML
frontmatter, from Google Cloud's **Knowledge Catalog** repo (community-maintained, Apache 2.0).
This bundle targets OKF v0.2 (`okf_version: "0.2"` in `okf/index.md` and `ecosystem.yml`), which
still reads v0.1.

# Schema

**Frontmatter.** `type` is the only REQUIRED field. Recommended: `title`, `description` (a single
sentence), `resource` (a URI or path), `tags` (a list), `generated: { by, at }` (v0.1's `timestamp`, replaced in 0.2; derive `by` from git with
`okf migrate`, never retype it), and optionally `sources`, `verified`, `status` (`draft`/`stable`/`deprecated`),
and `stale_after`. Producers may add
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
`reference`, `decision`. Use lowercase `type` values. Run `okf validate --strict` before committing a bundle change.

The ecosystem-wide conventions are in
[OKF-STANDARD.md](https://github.com/SecondMouseAU/ecosystem/blob/main/OKF-STANDARD.md);
`ecosystem.yml` at the repo root is this bundle's catalog entry.

