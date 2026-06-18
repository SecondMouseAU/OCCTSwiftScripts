---
type: Policy
title: Open-source boundary
description: This repo is LGPL-2.1 and depends only on open-source Swift packages. Never propose anything that makes it depend on a closed-source project.
resource: /
tags: [policy, oss, licensing, boundary]
timestamp: 2026-06-18T00:00:00Z
---

# Policy

OCCTSwiftScripts is **LGPL-2.1** and depends only on open-source Swift packages (the OCCTSwift
family). **Never propose a verb, dependency, or change that would make this repo depend on a
closed-source project.** Downstream closed-source consumers (e.g. the OCCTStudio app) wire
their own proprietary pieces — constraint-solving (the former `solve-sketch`) was removed when
the swiftGCS dep was dropped for exactly this reason.

# Direction

Dependencies flow OSS-internal only. Downstream commercial consumers depend on *this* repo;
this repo never depends on *them* (see
[references/commercial-app-relationship](/docs/knowledge/references/commercial-app-relationship.md)).
