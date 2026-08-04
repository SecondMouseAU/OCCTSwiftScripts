---
type: policy
title: Open-source boundary
description: This repo is LGPL-2.1 and depends only on open-source Swift packages. Never propose anything that makes it depend on a closed-source project.
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts
tags: [policy, oss, licensing, boundary]
timestamp: 2026-08-04
---

# Open-source boundary

OCCTSwiftScripts is **LGPL-2.1** and depends only on open-source Swift packages (the OCCTSwift
family). **Never propose a verb, dependency, or change that would make this repo depend on a
closed-source project.**

Downstream closed-source consumers (for example the OCCTStudio app) wire their own proprietary
pieces. Constraint-solving (the former `solve-sketch` verb) was removed when the swiftGCS
dependency was dropped, for exactly this reason.

# Direction

Dependencies flow OSS-internal only. Downstream commercial consumers depend on *this* repo;
this repo never depends on *them*. See
[references/commercial-app-relationship](../references/commercial-app-relationship.md).

If a capability seems shared between this repo and a commercial consumer, it lands here under
LGPL-2.1 and the consumer calls it.
