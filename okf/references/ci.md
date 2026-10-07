---
type: reference
title: CI gates and required checks
resource: https://github.com/SecondMouseAU/OCCTSwiftScripts/tree/main/.github/workflows
tags: [reference, ci, testing, branch-protection]
description: What each CI job proves, which ones are meant to block a merge, and how to run them locally.
generated: { by: claude-code/sonnet-5, at: 2026-10-07 }
---

# CI gates and required checks

Every job below is meant to block a merge. None is `continue-on-error`. Pull requests run all of
them with no `paths:` filter, because a required check that a path filter skips never reports and
blocks the PR forever. `make ci` runs the ones that need no extra tooling locally.

| Check (job name) | Workflow | What a red result means |
|---|---|---|
| `tests` | `tests.yml` | A unit or in-process verb test failed (`swift test`) |
| `build-all` | `tests.yml` | Some target, including the deprecated standalone executables, no longer compiles |
| `lockfile` | `tests.yml` | `Package.resolved` is behind what SwiftPM resolves today |
| `integration` | `integration.yml` | A cookbook recipe regressed (`recipe-check.sh`), or `--serve` stopped answering one envelope per request and recovering from a failure (`serve-check.sh`) |
| `verbs` | `verbs.yml` | The verb inventory, README count, or `occtkit run` workspace identity drifted |
| `code-style` | `code-style.yml` | `swift-format` or SwiftLint failed |
| `policies` | `docs-consistency.yml` | `okf/policies/`, `okf/index.md`, and `CLAUDE.md` disagree |

`tests` and `integration` also run nightly, to catch an upstream release (OCCTSwift or its cohort)
breaking the build with no commit here.

## What is deliberately not covered

- **`render-preview`**: needs a Metal device. It is exempt in `RegistryCoverageTests` with that reason.
- **Linux and iOS**: the OCCTSwift dependency is a macOS xcframework.
- **`graph-validate` reporting an invalid shape**: no cheap invalid-shape fixture exists, so a verb that
  always reported `isValid: true` would pass.

## Test rules

New tests follow [prove-the-test-fails](../policies/prove-the-test-fails.md): run the test once with its
subject broken, see it fail, restore. `Scripts/serve-check.sh` is a detector, so it was proven the same
way (failure reported as ok, loop dying after a failure, error text dropped).

Known bugs are pinned with Swift Testing's `withKnownIssue` and a link to the issue (`graph-compact` and
`graph-dedup`, #128; `reconstruct` revolve, #129). The marker makes the suite go red when the bug is
fixed, which forces its removal.

## Branch protection

Applied to `main` on 2026-10-07: the seven checks in the table above are required to merge. Settings:
`strict: false` (a branch need not be up to date, which would re-run the macOS jobs on every merge),
`enforce_admins: false` (an owner can still push in an emergency, so a red gate is advice to an owner
and a hard stop to everyone else), no required reviews, force pushes and deletions off.

The WASM build workflow added in #126 reports a `build` check that is not required.

This is a repository setting, not a file in this repo. If it is ever reset, re-apply it with the
command below, and update the `contexts` list whenever a job is added or renamed: a required check
that no job reports blocks every PR.

```bash
gh api -X PUT repos/SecondMouseAU/OCCTSwiftScripts/branches/main/protection --input - <<'JSON'
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["tests", "build-all", "lockfile", "integration", "verbs", "code-style", "policies"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
```
