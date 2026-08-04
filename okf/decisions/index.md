# Decisions

Recorded engineering decisions and their rationale. Add an entry here when a choice needs its
reasoning preserved beyond the commit message, so the next person does not re-litigate it.

Decisions to date are captured in `CLAUDE.md` and the git log; this directory holds the ones
that need standalone rationale.

* [Single-source verb inventory](single-source-verb-inventory.md): `Registry.all` is the only
  verb list; `occtkit --verbs` feeds the Makefile and the docs point at the reference page.
* [SwiftPM path dependency identity](swiftpm-path-dependency-identity.md): a path dep's
  identity is the directory basename, so generated manifests derive declaration and identity from
  one value.
* [Wire sweep factories are not symmetric](wire-sweep-factories-are-not-symmetric.md): `extrude`
  faces a wire for you, `revolve` and `sweep` do not. Assert `solidCount >= 1`.
* [errexit is suppressed in `||` context](errexit-is-suppressed-in-or-context.md): a function
  called as `f || status=1` must `return 1` explicitly or its checks are decorative.
