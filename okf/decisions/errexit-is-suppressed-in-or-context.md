---
type: decision
title: A shell function called as `f || status=1` must return failure explicitly
description: errexit is suppressed inside the left-hand side of a `||`, so a bare failing command in such a function does not abort it and the function returns the exit status of its last command instead.
tags: [decision, bash, scripts, ci, testing]
timestamp: 2026-08-05
---

# Decision

In a shell function that is invoked as the left-hand side of `||` or `&&`, every check must
propagate failure **explicitly**:

```bash
if ! python3 - "$@" <<'PY'
...
PY
then
    return 1
fi
```

Not:

```bash
python3 - "$@" <<'PY'   # a nonzero exit here does NOT abort the function
...
PY
```

# Why

`set -e` is disabled for any command in a context where its exit status is already being tested,
including the left-hand side of `||`. So in:

```bash
check_one "$dir" || status=1
```

a bare failing command inside `check_one` does not abort it. Execution continues, and the
function returns the status of whichever command happened to run last, which is usually a
successful `echo`.

# Why it mattered

`Scripts/recipe-check.sh` had exactly this shape. Its Python validation block printed every
failure it detected and then returned success, so the whole suite exited 0 while reporting
problems on screen. Every assertion in it was decorative.

It hid a real regression: `recipes/01-mounting-bracket` had drifted 2.27% in volume against its
committed reference after the OCCTSwift 1.15.0 to 1.17.0 repin
([#101](https://github.com/SecondMouseAU/OCCTSwiftScripts/issues/101)). The check was detecting
it and reporting a pass.

# The general rule

This is the same failure class the repo has now hit three times: a guard that cannot fail is
worse than no guard, because it reads as coverage. See
[single-source-verb-inventory](single-source-verb-inventory.md) for the dead-code variant, where
the mechanism existed and was never wired up.

When adding any check, verify it fails when it should. Break the thing deliberately, watch the
check go red, then restore. Put that evidence in the PR body.
